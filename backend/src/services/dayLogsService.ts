import { pool } from '../db.js';
import { ApiError } from '../utils/errors.js';
import { getDietAndAllergies } from './onboardingService.js';
import { detectDietaryConflicts, type DietaryFlag } from './dietaryConflictService.js';

type DayLogItem = {
  id: string;
  foodName: string;
  quantity: number;
  amount: number;
  unit: string;
  unitNormalized: string;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  nutritionSourceId: string;
  sourceFamily: string | null;
  matchConfidence: number;
};

type DayLogEntry = {
  id: string;
  loggedAt: string;
  rawText: string;
  inputKind: string;
  confidence: number;
  totals: {
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
  };
  items: DayLogItem[];
  /**
   * Diet preference / allergy violations recomputed against the current
   * onboarding profile each time the day is fetched. Re-running on read
   * (rather than persisting at save time) means iOS picks up newly added
   * allergies for past meals without a backfill.
   */
  dietaryFlags?: DietaryFlag[];
};

type DayLogsResponse = {
  date: string;
  timezone: string;
  logs: DayLogEntry[];
};

function toNumber(value: unknown): number {
  if (value === null || value === undefined) return 0;
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function round(value: number): number {
  return Math.round(value * 10) / 10;
}

function isValidTimezone(value: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

function normalizeTimezone(value: string | null | undefined): string {
  const tz = (value || '').trim();
  return tz || 'UTC';
}

function validateDate(date: string): void {
  const dt = new Date(`${date}T00:00:00.000Z`);
  if (Number.isNaN(dt.valueOf())) {
    throw new ApiError(400, 'INVALID_INPUT', 'Invalid date. Use YYYY-MM-DD');
  }
}

export async function getDayLogsRange(
  userId: string,
  from: string,
  to: string,
  timezoneOverride?: string
): Promise<DayLogsResponse[]> {
  validateDate(from);
  validateDate(to);

  const profileResult = await pool.query<{ timezone: string | null }>(
    `SELECT timezone FROM onboarding_profiles WHERE user_id = $1`,
    [userId]
  );

  const profileTimezone = normalizeTimezone(profileResult.rows[0]?.timezone);
  const effectiveTimezone = normalizeTimezone(timezoneOverride || profileTimezone);
  if (!isValidTimezone(effectiveTimezone)) {
    throw new ApiError(400, 'INVALID_INPUT', 'Invalid timezone');
  }

  const logsResult = await pool.query<{
    id: string;
    logged_at: Date;
    raw_text: string;
    input_kind: string;
    parse_confidence: string;
    total_calories: string;
    total_protein_g: string;
    total_carbs_g: string;
    total_fat_g: string;
    day_date: string;
  }>(
    `SELECT id, logged_at, raw_text, input_kind, parse_confidence,
            total_calories, total_protein_g, total_carbs_g, total_fat_g,
            (logged_at AT TIME ZONE $2)::date::text AS day_date
     FROM food_logs
     WHERE user_id = $1
       AND (logged_at AT TIME ZONE $2)::date >= $3::date
       AND (logged_at AT TIME ZONE $2)::date <= $4::date
     ORDER BY logged_at ASC`,
    [userId, effectiveTimezone, from, to]
  );

  if (logsResult.rows.length === 0) {
    const results: DayLogsResponse[] = [];
    const startDate = new Date(`${from}T00:00:00.000Z`);
    const endDate = new Date(`${to}T00:00:00.000Z`);
    for (let d = new Date(startDate); d <= endDate; d.setUTCDate(d.getUTCDate() + 1)) {
      results.push({ date: d.toISOString().slice(0, 10), timezone: effectiveTimezone, logs: [] });
    }
    return results;
  }

  const logIds = logsResult.rows.map((r) => r.id);

  const itemsResult = await pool.query<{
    id: string;
    food_log_id: string;
    food_name: string;
    quantity: string;
    amount: string | null;
    unit: string;
    unit_normalized: string | null;
    grams: string;
    calories: string;
    protein_g: string;
    carbs_g: string;
    fat_g: string;
    nutrition_source_id: string;
    source_family: string | null;
    match_confidence: string;
  }>(
    `SELECT id, food_log_id, food_name, quantity, amount, unit, unit_normalized,
            grams, calories, protein_g, carbs_g, fat_g,
            nutrition_source_id, source_family, match_confidence
     FROM food_log_items
     WHERE food_log_id = ANY($1)
     ORDER BY food_log_id, id`,
    [logIds]
  );

  const itemsByLogId = new Map<string, DayLogItem[]>();
  for (const item of itemsResult.rows) {
    if (!itemsByLogId.has(item.food_log_id)) {
      itemsByLogId.set(item.food_log_id, []);
    }
    itemsByLogId.get(item.food_log_id)!.push({
      id: item.id,
      foodName: item.food_name,
      quantity: toNumber(item.quantity),
      amount: toNumber(item.amount ?? item.quantity),
      unit: item.unit,
      unitNormalized: item.unit_normalized ?? item.unit,
      grams: round(toNumber(item.grams)),
      calories: round(toNumber(item.calories)),
      protein: round(toNumber(item.protein_g)),
      carbs: round(toNumber(item.carbs_g)),
      fat: round(toNumber(item.fat_g)),
      nutritionSourceId: item.nutrition_source_id,
      sourceFamily: item.source_family,
      matchConfidence: toNumber(item.match_confidence)
    });
  }

  // Soft-fail: never let dietary lookup break a day-logs range fetch.
  let dietaryProfile: { dietPreference: string | null; allergies: string[] } = {
    dietPreference: null,
    allergies: []
  };
  try {
    dietaryProfile = await getDietAndAllergies(userId);
  } catch (err) {
    console.warn('[dietary] day-logs-range profile fetch failed; returning no flags', err);
  }
  const hasProfile = dietaryProfile.dietPreference !== null || dietaryProfile.allergies.length > 0;

  // Group logs by day
  const logsByDay = new Map<string, DayLogEntry[]>();
  for (const log of logsResult.rows) {
    const dayDate = log.day_date;
    if (!logsByDay.has(dayDate)) {
      logsByDay.set(dayDate, []);
    }
    const items = itemsByLogId.get(log.id) ?? [];
    const flags = hasProfile
      ? detectDietaryConflicts({
          itemNames: items.map((item) => item.foodName),
          dietPreference: dietaryProfile.dietPreference,
          allergies: dietaryProfile.allergies
        })
      : [];
    logsByDay.get(dayDate)!.push({
      id: log.id,
      loggedAt: log.logged_at instanceof Date ? log.logged_at.toISOString() : String(log.logged_at),
      rawText: log.raw_text,
      inputKind: log.input_kind || 'text',
      confidence: round(toNumber(log.parse_confidence)),
      totals: {
        calories: round(toNumber(log.total_calories)),
        protein: round(toNumber(log.total_protein_g)),
        carbs: round(toNumber(log.total_carbs_g)),
        fat: round(toNumber(log.total_fat_g))
      },
      items,
      dietaryFlags: flags
    });
  }

  // Build response for every day in range
  const results: DayLogsResponse[] = [];
  const startDate = new Date(`${from}T00:00:00.000Z`);
  const endDate = new Date(`${to}T00:00:00.000Z`);
  for (let d = new Date(startDate); d <= endDate; d.setUTCDate(d.getUTCDate() + 1)) {
    const dateStr = d.toISOString().slice(0, 10);
    results.push({
      date: dateStr,
      timezone: effectiveTimezone,
      logs: logsByDay.get(dateStr) ?? []
    });
  }

  return results;
}

export async function getDayLogs(userId: string, date: string, timezoneOverride?: string): Promise<DayLogsResponse> {
  validateDate(date);

  const profileResult = await pool.query<{ timezone: string | null }>(
    `SELECT timezone FROM onboarding_profiles WHERE user_id = $1`,
    [userId]
  );

  const profileTimezone = normalizeTimezone(profileResult.rows[0]?.timezone);
  const effectiveTimezone = normalizeTimezone(timezoneOverride || profileTimezone);
  if (!isValidTimezone(effectiveTimezone)) {
    throw new ApiError(400, 'INVALID_INPUT', 'Invalid timezone');
  }

  const logsResult = await pool.query<{
    id: string;
    logged_at: Date;
    raw_text: string;
    input_kind: string;
    parse_confidence: string;
    total_calories: string;
    total_protein_g: string;
    total_carbs_g: string;
    total_fat_g: string;
  }>(
    `
    SELECT id, logged_at, raw_text, input_kind, parse_confidence,
           total_calories, total_protein_g, total_carbs_g, total_fat_g
    FROM food_logs
    WHERE user_id = $1
      AND (logged_at AT TIME ZONE $2)::date = $3::date
    ORDER BY logged_at ASC
    `,
    [userId, effectiveTimezone, date]
  );

  if (logsResult.rows.length === 0) {
    return { date, timezone: effectiveTimezone, logs: [] };
  }

  const logIds = logsResult.rows.map((r) => r.id);

  const itemsResult = await pool.query<{
    id: string;
    food_log_id: string;
    food_name: string;
    quantity: string;
    amount: string | null;
    unit: string;
    unit_normalized: string | null;
    grams: string;
    calories: string;
    protein_g: string;
    carbs_g: string;
    fat_g: string;
    nutrition_source_id: string;
    source_family: string | null;
    match_confidence: string;
  }>(
    `
    SELECT id, food_log_id, food_name, quantity, amount, unit, unit_normalized,
           grams, calories, protein_g, carbs_g, fat_g,
           nutrition_source_id, source_family, match_confidence
    FROM food_log_items
    WHERE food_log_id = ANY($1)
    ORDER BY food_log_id, id
    `,
    [logIds]
  );

  const itemsByLogId = new Map<string, DayLogItem[]>();
  for (const item of itemsResult.rows) {
    if (!itemsByLogId.has(item.food_log_id)) {
      itemsByLogId.set(item.food_log_id, []);
    }
    itemsByLogId.get(item.food_log_id)!.push({
      id: item.id,
      foodName: item.food_name,
      quantity: toNumber(item.quantity),
      amount: toNumber(item.amount ?? item.quantity),
      unit: item.unit,
      unitNormalized: item.unit_normalized ?? item.unit,
      grams: round(toNumber(item.grams)),
      calories: round(toNumber(item.calories)),
      protein: round(toNumber(item.protein_g)),
      carbs: round(toNumber(item.carbs_g)),
      fat: round(toNumber(item.fat_g)),
      nutritionSourceId: item.nutrition_source_id,
      sourceFamily: item.source_family,
      matchConfidence: toNumber(item.match_confidence)
    });
  }

  // Soft-fail: never let dietary lookup break a day-logs fetch.
  let dietaryProfile: { dietPreference: string | null; allergies: string[] } = {
    dietPreference: null,
    allergies: []
  };
  try {
    dietaryProfile = await getDietAndAllergies(userId);
  } catch (err) {
    console.warn('[dietary] day-logs profile fetch failed; returning no flags', err);
  }
  const hasProfile = dietaryProfile.dietPreference !== null || dietaryProfile.allergies.length > 0;

  const logs: DayLogEntry[] = logsResult.rows.map((log) => {
    const items = itemsByLogId.get(log.id) ?? [];
    const flags = hasProfile
      ? detectDietaryConflicts({
          itemNames: items.map((item) => item.foodName),
          dietPreference: dietaryProfile.dietPreference,
          allergies: dietaryProfile.allergies
        })
      : [];

    return {
      id: log.id,
      loggedAt: log.logged_at instanceof Date ? log.logged_at.toISOString() : String(log.logged_at),
      rawText: log.raw_text,
      inputKind: log.input_kind || 'text',
      confidence: round(toNumber(log.parse_confidence)),
      totals: {
        calories: round(toNumber(log.total_calories)),
        protein: round(toNumber(log.total_protein_g)),
        carbs: round(toNumber(log.total_carbs_g)),
        fat: round(toNumber(log.total_fat_g))
      },
      items,
      dietaryFlags: flags
    };
  });

  return { date, timezone: effectiveTimezone, logs };
}
