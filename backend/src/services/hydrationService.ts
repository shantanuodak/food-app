import { pool } from '../db.js';
import { ApiError } from '../utils/errors.js';
import { ensureUserExists } from './userService.js';

export type HydrationSource = 'text' | 'voice' | 'quick_add' | 'manual';

export type AuthIdentity = {
  authProvider?: string | null;
  userEmail?: string | null;
};

export type HydrationPreference = {
  dailyGoalMl: number;
  createdAt: string;
  updatedAt: string;
};

export type HydrationLog = {
  id: string;
  loggedAt: string;
  rawText: string;
  amountMl: number;
  inputAmount: number | null;
  inputUnit: string | null;
  source: HydrationSource;
  confidence: number;
  createdAt: string;
  updatedAt: string;
};

export type HydrationDaySummary = {
  date: string;
  timezone: string;
  totalMl: number;
  goalMl: number | null;
  remainingMl: number | null;
  percent: number | null;
  hasLogs: boolean;
  logsCount: number;
};

export type HydrationProgressResponse = {
  from: string;
  to: string;
  timezone: string;
  goalMl: number | null;
  days: HydrationDaySummary[];
  weeklyDelta: HydrationWeeklyDelta;
};

export type HydrationWeeklyDelta = {
  currentAvgMl: number;
  previousAvgMl: number;
  deltaMl: number;
  deltaPct: number | null;
};

type HydrationLogRow = {
  id: string;
  logged_at: string;
  raw_text: string;
  amount_ml: string;
  input_amount: string | null;
  input_unit: string | null;
  source: HydrationSource;
  confidence: string;
  created_at: string;
  updated_at: string;
};

function toNumber(value: unknown): number {
  if (value === null || value === undefined) {
    return 0;
  }
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function roundMl(value: number): number {
  return Math.round(value);
}

function roundOneDecimal(value: number): number {
  return Math.round(value * 10) / 10;
}

function normalizeTimezone(value: string | null | undefined): string {
  const timezone = (value || '').trim();
  return timezone || 'UTC';
}

function isValidTimezone(value: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

function validateDate(date: string): void {
  const dt = new Date(`${date}T00:00:00.000Z`);
  if (Number.isNaN(dt.valueOf())) {
    throw new ApiError(400, 'INVALID_INPUT', 'Invalid date. Use YYYY-MM-DD');
  }
}

function daysBetween(from: string, to: string): number {
  const start = new Date(`${from}T00:00:00.000Z`);
  const end = new Date(`${to}T00:00:00.000Z`);
  return Math.floor((end.getTime() - start.getTime()) / 86_400_000) + 1;
}

async function resolveTimezone(userId: string, timezoneOverride?: string): Promise<string> {
  if (timezoneOverride?.trim()) {
    const override = normalizeTimezone(timezoneOverride);
    if (!isValidTimezone(override)) {
      throw new ApiError(400, 'INVALID_INPUT', 'Invalid timezone');
    }
    return override;
  }

  const result = await pool.query<{ timezone: string | null }>(
    'SELECT timezone FROM onboarding_profiles WHERE user_id = $1',
    [userId]
  );
  const timezone = normalizeTimezone(result.rows[0]?.timezone);
  if (!isValidTimezone(timezone)) {
    throw new ApiError(400, 'INVALID_INPUT', 'Invalid timezone');
  }
  return timezone;
}

function mapPreference(row: { daily_goal_ml: string | number; created_at: string; updated_at: string }): HydrationPreference {
  return {
    dailyGoalMl: Math.round(toNumber(row.daily_goal_ml)),
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function mapLog(row: HydrationLogRow): HydrationLog {
  return {
    id: row.id,
    loggedAt: row.logged_at,
    rawText: row.raw_text,
    amountMl: roundMl(toNumber(row.amount_ml)),
    inputAmount: row.input_amount === null ? null : toNumber(row.input_amount),
    inputUnit: row.input_unit,
    source: row.source,
    confidence: toNumber(row.confidence),
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export async function getHydrationGoal(userId: string): Promise<HydrationPreference | null> {
  const result = await pool.query<{ daily_goal_ml: string; created_at: string; updated_at: string }>(
    `
    SELECT daily_goal_ml, created_at, updated_at
    FROM hydration_preferences
    WHERE user_id = $1
    `,
    [userId]
  );
  return result.rows[0] ? mapPreference(result.rows[0]) : null;
}

export async function upsertHydrationGoal(
  userId: string,
  dailyGoalMl: number,
  auth?: AuthIdentity
): Promise<HydrationPreference> {
  await ensureUserExists(userId, { authProvider: auth?.authProvider, email: auth?.userEmail });
  const result = await pool.query<{ daily_goal_ml: string; created_at: string; updated_at: string }>(
    `
    INSERT INTO hydration_preferences (user_id, daily_goal_ml)
    VALUES ($1, $2)
    ON CONFLICT (user_id) DO UPDATE
    SET daily_goal_ml = EXCLUDED.daily_goal_ml,
        updated_at = NOW()
    RETURNING daily_goal_ml, created_at, updated_at
    `,
    [userId, Math.round(dailyGoalMl)]
  );
  return mapPreference(result.rows[0]);
}

export async function deleteHydrationGoal(userId: string): Promise<{ status: 'deleted' | 'not_found' }> {
  const result = await pool.query('DELETE FROM hydration_preferences WHERE user_id = $1', [userId]);
  return { status: (result.rowCount || 0) > 0 ? 'deleted' : 'not_found' };
}

export async function saveHydrationLog(input: {
  userId: string;
  auth?: AuthIdentity;
  loggedAt: string;
  rawText: string;
  amountMl: number;
  inputAmount?: number | null;
  inputUnit?: string | null;
  source: HydrationSource;
  confidence: number;
}): Promise<HydrationLog> {
  await ensureUserExists(input.userId, { authProvider: input.auth?.authProvider, email: input.auth?.userEmail });
  const result = await pool.query<HydrationLogRow>(
    `
    INSERT INTO hydration_logs (
      user_id, logged_at, raw_text, amount_ml, input_amount, input_unit, source, confidence
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
    RETURNING id, logged_at, raw_text, amount_ml, input_amount, input_unit, source, confidence, created_at, updated_at
    `,
    [
      input.userId,
      input.loggedAt,
      input.rawText,
      roundMl(input.amountMl),
      input.inputAmount ?? null,
      input.inputUnit ?? null,
      input.source,
      input.confidence
    ]
  );
  return mapLog(result.rows[0]);
}

export async function updateHydrationLog(input: {
  userId: string;
  logId: string;
  loggedAt?: string;
  rawText?: string;
  amountMl: number;
  inputAmount?: number | null;
  inputUnit?: string | null;
  source?: HydrationSource;
  confidence?: number;
}): Promise<HydrationLog> {
  const result = await pool.query<HydrationLogRow>(
    `
    UPDATE hydration_logs
    SET logged_at = COALESCE($3, logged_at),
        raw_text = COALESCE($4, raw_text),
        amount_ml = $5,
        input_amount = $6,
        input_unit = $7,
        source = COALESCE($8, source),
        confidence = COALESCE($9, confidence),
        updated_at = NOW()
    WHERE id = $1
      AND user_id = $2
    RETURNING id, logged_at, raw_text, amount_ml, input_amount, input_unit, source, confidence, created_at, updated_at
    `,
    [
      input.logId,
      input.userId,
      input.loggedAt ?? null,
      input.rawText ?? null,
      roundMl(input.amountMl),
      input.inputAmount ?? null,
      input.inputUnit ?? null,
      input.source ?? null,
      input.confidence ?? null
    ]
  );
  if (!result.rows[0]) {
    throw new ApiError(404, 'HYDRATION_LOG_NOT_FOUND', 'Hydration log not found');
  }
  return mapLog(result.rows[0]);
}

export async function deleteHydrationLog(userId: string, logId: string): Promise<{ logId: string; status: 'deleted' }> {
  const result = await pool.query('DELETE FROM hydration_logs WHERE id = $1 AND user_id = $2', [logId, userId]);
  if ((result.rowCount || 0) === 0) {
    throw new ApiError(404, 'HYDRATION_LOG_NOT_FOUND', 'Hydration log not found');
  }
  return { logId, status: 'deleted' };
}

export async function getHydrationDayLogs(
  userId: string,
  date: string,
  timezoneOverride?: string
): Promise<{ date: string; timezone: string; logs: HydrationLog[] }> {
  validateDate(date);
  const timezone = await resolveTimezone(userId, timezoneOverride);
  const result = await pool.query<HydrationLogRow>(
    `
    SELECT id, logged_at, raw_text, amount_ml, input_amount, input_unit, source, confidence, created_at, updated_at
    FROM hydration_logs
    WHERE user_id = $1
      AND (logged_at AT TIME ZONE $2)::date = $3::date
    ORDER BY logged_at ASC, created_at ASC, id ASC
    `,
    [userId, timezone, date]
  );
  return {
    date,
    timezone,
    logs: result.rows.map(mapLog)
  };
}

export async function getHydrationDayLogsRange(
  userId: string,
  from: string,
  to: string,
  timezoneOverride?: string
): Promise<{ date: string; timezone: string; logs: HydrationLog[] }[]> {
  validateDate(from);
  validateDate(to);
  const timezone = await resolveTimezone(userId, timezoneOverride);

  const result = await pool.query<HydrationLogRow & { day_date: string }>(
    `
    SELECT id, logged_at, raw_text, amount_ml, input_amount, input_unit, source, confidence, created_at, updated_at,
           (logged_at AT TIME ZONE $2)::date::text AS day_date
    FROM hydration_logs
    WHERE user_id = $1
      AND (logged_at AT TIME ZONE $2)::date >= $3::date
      AND (logged_at AT TIME ZONE $2)::date <= $4::date
    ORDER BY logged_at ASC, created_at ASC, id ASC
    `,
    [userId, timezone, from, to]
  );

  const logsByDay = new Map<string, HydrationLog[]>();
  for (const row of result.rows) {
    if (!logsByDay.has(row.day_date)) {
      logsByDay.set(row.day_date, []);
    }
    logsByDay.get(row.day_date)!.push(mapLog(row));
  }

  // Emit one entry per calendar day in [from, to], including empty days, so
  // the client can warm its cache for the whole window in a single response.
  const results: { date: string; timezone: string; logs: HydrationLog[] }[] = [];
  const startDate = new Date(`${from}T00:00:00.000Z`);
  const endDate = new Date(`${to}T00:00:00.000Z`);
  for (let d = new Date(startDate); d <= endDate; d.setUTCDate(d.getUTCDate() + 1)) {
    const dateStr = d.toISOString().slice(0, 10);
    results.push({ date: dateStr, timezone, logs: logsByDay.get(dateStr) ?? [] });
  }
  return results;
}

export async function getHydrationDaySummary(
  userId: string,
  date: string,
  timezoneOverride?: string
): Promise<HydrationDaySummary> {
  return (await getHydrationProgress(userId, date, date, timezoneOverride)).days[0];
}

export async function getHydrationProgress(
  userId: string,
  from: string,
  to: string,
  timezoneOverride?: string
): Promise<HydrationProgressResponse> {
  validateDate(from);
  validateDate(to);
  if (from > to) {
    throw new ApiError(400, 'INVALID_INPUT', '`from` must be earlier than or equal to `to`');
  }
  const dayCount = daysBetween(from, to);
  if (dayCount > 366) {
    throw new ApiError(400, 'INVALID_INPUT', 'Hydration progress range cannot exceed 366 days');
  }

  const timezone = await resolveTimezone(userId, timezoneOverride);
  const goal = await getHydrationGoal(userId);
  const goalMl = goal?.dailyGoalMl ?? null;

  const rows = await pool.query<{
    day: string;
    total_ml: string;
    logs_count: string;
  }>(
    `
    WITH date_series AS (
      SELECT generate_series($3::date, $4::date, interval '1 day')::date AS day
    )
    SELECT
      ds.day::text AS day,
      COALESCE(SUM(hl.amount_ml), 0) AS total_ml,
      COUNT(hl.id)::text AS logs_count
    FROM date_series ds
    LEFT JOIN hydration_logs hl
      ON hl.user_id = $1
      AND (hl.logged_at AT TIME ZONE $2)::date = ds.day
    GROUP BY ds.day
    ORDER BY ds.day ASC
    `,
    [userId, timezone, from, to]
  );

  const days = rows.rows.map((row): HydrationDaySummary => {
    const totalMl = roundMl(toNumber(row.total_ml));
    const logsCount = Math.max(0, Math.floor(toNumber(row.logs_count)));
    return {
      date: row.day,
      timezone,
      totalMl,
      goalMl,
      remainingMl: goalMl === null ? null : roundMl(goalMl - totalMl),
      percent: goalMl === null || goalMl <= 0 ? null : roundOneDecimal((totalMl / goalMl) * 100),
      hasLogs: logsCount > 0,
      logsCount
    };
  });

  return {
    from,
    to,
    timezone,
    goalMl,
    days,
    weeklyDelta: computeWeeklyDelta(days)
  };
}

function computeWeeklyDelta(days: HydrationDaySummary[]): HydrationWeeklyDelta {
  const count = days.length;
  const currentWindow = days.slice(Math.max(0, count - 7), count);
  const previousWindow = days.slice(Math.max(0, count - 14), Math.max(0, count - 7));
  const currentAvgMl = averageMl(currentWindow);
  const previousAvgMl = averageMl(previousWindow);
  const deltaMl = roundMl(currentAvgMl - previousAvgMl);
  return {
    currentAvgMl,
    previousAvgMl,
    deltaMl,
    deltaPct: previousAvgMl > 0 ? roundOneDecimal((deltaMl / previousAvgMl) * 100) : null
  };
}

function averageMl(days: HydrationDaySummary[]): number {
  if (days.length === 0) {
    return 0;
  }
  return roundMl(days.reduce((sum, day) => sum + day.totalMl, 0) / days.length);
}
