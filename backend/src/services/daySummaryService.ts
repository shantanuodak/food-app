import { pool } from '../db.js';
import { ApiError } from '../utils/errors.js';

type DayTotals = {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
};

type DaySummary = {
  date: string;
  timezone: string;
  totals: DayTotals;
  targets: DayTotals;
  remaining: DayTotals;
};

function toNumber(value: unknown): number {
  if (value === null || value === undefined) {
    return 0;
  }
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
  const timezone = (value || '').trim();
  return timezone || 'UTC';
}

function validateDate(date: string): void {
  const dt = new Date(`${date}T00:00:00.000Z`);
  if (Number.isNaN(dt.valueOf())) {
    throw new ApiError(400, 'INVALID_INPUT', 'Invalid date. Use YYYY-MM-DD');
  }
}

export async function getDaySummary(userId: string, date: string, timezoneOverride?: string): Promise<DaySummary> {
  validateDate(date);

  const targetResult = await pool.query<{
    calorie_target: string;
    macro_target_protein: string;
    macro_target_carbs: string;
    macro_target_fat: string;
    timezone: string | null;
  }>(
    `
    SELECT calorie_target, macro_target_protein, macro_target_carbs, macro_target_fat, timezone
    FROM onboarding_profiles
    WHERE user_id = $1
    `,
    [userId]
  );

  if (!targetResult.rows[0]) {
    throw new ApiError(404, 'PROFILE_NOT_FOUND', 'Onboarding profile not found');
  }
  const profileTimezone = normalizeTimezone(targetResult.rows[0].timezone);
  const effectiveTimezone = normalizeTimezone(timezoneOverride || profileTimezone);
  if (!isValidTimezone(effectiveTimezone)) {
    throw new ApiError(400, 'INVALID_INPUT', 'Invalid timezone');
  }

  const totalsResult = await pool.query<{
    total_calories: string;
    total_protein: string;
    total_carbs: string;
    total_fat: string;
  }>(
    `
    SELECT
      COALESCE(SUM(total_calories), 0) AS total_calories,
      COALESCE(SUM(total_protein_g), 0) AS total_protein,
      COALESCE(SUM(total_carbs_g), 0) AS total_carbs,
      COALESCE(SUM(total_fat_g), 0) AS total_fat
    FROM food_logs
    WHERE user_id = $1
      AND (logged_at AT TIME ZONE $2)::date = $3::date
    `,
    [userId, effectiveTimezone, date]
  );

  const targets: DayTotals = {
    calories: round(toNumber(targetResult.rows[0].calorie_target)),
    protein: round(toNumber(targetResult.rows[0].macro_target_protein)),
    carbs: round(toNumber(targetResult.rows[0].macro_target_carbs)),
    fat: round(toNumber(targetResult.rows[0].macro_target_fat))
  };

  const totals: DayTotals = {
    calories: round(toNumber(totalsResult.rows[0]?.total_calories)),
    protein: round(toNumber(totalsResult.rows[0]?.total_protein)),
    carbs: round(toNumber(totalsResult.rows[0]?.total_carbs)),
    fat: round(toNumber(totalsResult.rows[0]?.total_fat))
  };

  return {
    date,
    timezone: effectiveTimezone,
    totals,
    targets,
    remaining: {
      calories: round(targets.calories - totals.calories),
      protein: round(targets.protein - totals.protein),
      carbs: round(targets.carbs - totals.carbs),
      fat: round(targets.fat - totals.fat)
    }
  };
}
