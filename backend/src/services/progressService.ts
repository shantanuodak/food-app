import { pool } from '../db.js';
import { ApiError } from '../utils/errors.js';

type DayTotals = {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
};

type ProgressMetricDelta = {
  currentAvg: number;
  previousAvg: number;
  delta: number;
  deltaPct: number | null;
};

type ProgressAdherence = {
  caloriesPct: number;
  proteinPct: number;
  carbsPct: number;
  fatPct: number;
};

type ProgressDayPoint = {
  date: string;
  totals: DayTotals;
  targets: DayTotals;
  remaining: DayTotals;
  hasLogs: boolean;
  logsCount: number;
  adherence: ProgressAdherence;
};

type ProgressStreaks = {
  currentDays: number;
  longestDays: number;
};

type ProgressWeeklyDelta = {
  calories: ProgressMetricDelta;
  protein: ProgressMetricDelta;
  carbs: ProgressMetricDelta;
  fat: ProgressMetricDelta;
};

export type ProgressSummaryResponse = {
  from: string;
  to: string;
  timezone: string;
  days: ProgressDayPoint[];
  streaks: ProgressStreaks;
  weeklyDelta: ProgressWeeklyDelta;
};

function toNumber(value: unknown): number {
  if (value === null || value === undefined) {
    return 0;
  }
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function roundOneDecimal(value: number): number {
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

function daysBetween(from: string, to: string): number {
  const start = new Date(`${from}T00:00:00.000Z`);
  const end = new Date(`${to}T00:00:00.000Z`);
  return Math.floor((end.getTime() - start.getTime()) / 86_400_000) + 1;
}

function adherencePercent(consumed: number, target: number): number {
  if (target <= 0) {
    return 0;
  }
  return roundOneDecimal((consumed / target) * 100);
}

function computeStreaks(days: ProgressDayPoint[]): ProgressStreaks {
  let longestDays = 0;
  let running = 0;
  for (const day of days) {
    if (day.hasLogs) {
      running += 1;
      longestDays = Math.max(longestDays, running);
    } else {
      running = 0;
    }
  }

  let currentDays = 0;
  for (let i = days.length - 1; i >= 0; i -= 1) {
    if (!days[i]?.hasLogs) {
      break;
    }
    currentDays += 1;
  }

  return { currentDays, longestDays };
}

function metricAverage(days: ProgressDayPoint[], metric: keyof DayTotals): number {
  if (days.length === 0) {
    return 0;
  }
  const sum = days.reduce((acc, day) => acc + day.totals[metric], 0);
  return roundOneDecimal(sum / days.length);
}

function metricDelta(currentAvg: number, previousAvg: number): ProgressMetricDelta {
  const delta = roundOneDecimal(currentAvg - previousAvg);
  return {
    currentAvg,
    previousAvg,
    delta,
    deltaPct: previousAvg > 0 ? roundOneDecimal((delta / previousAvg) * 100) : null
  };
}

function computeWeeklyDelta(days: ProgressDayPoint[]): ProgressWeeklyDelta {
  const count = days.length;
  const currentWindow = days.slice(Math.max(0, count - 7), count);
  const previousWindow = days.slice(Math.max(0, count - 14), Math.max(0, count - 7));

  const currentCalories = metricAverage(currentWindow, 'calories');
  const previousCalories = metricAverage(previousWindow, 'calories');

  const currentProtein = metricAverage(currentWindow, 'protein');
  const previousProtein = metricAverage(previousWindow, 'protein');

  const currentCarbs = metricAverage(currentWindow, 'carbs');
  const previousCarbs = metricAverage(previousWindow, 'carbs');

  const currentFat = metricAverage(currentWindow, 'fat');
  const previousFat = metricAverage(previousWindow, 'fat');

  return {
    calories: metricDelta(currentCalories, previousCalories),
    protein: metricDelta(currentProtein, previousProtein),
    carbs: metricDelta(currentCarbs, previousCarbs),
    fat: metricDelta(currentFat, previousFat)
  };
}

export async function getProgressSummary(
  userId: string,
  from: string,
  to: string,
  timezoneOverride?: string
): Promise<ProgressSummaryResponse> {
  validateDate(from);
  validateDate(to);
  if (from > to) {
    throw new ApiError(400, 'INVALID_INPUT', '`from` must be earlier than or equal to `to`');
  }

  const dayCount = daysBetween(from, to);
  if (dayCount > 180) {
    throw new ApiError(400, 'INVALID_INPUT', 'Progress range cannot exceed 180 days');
  }

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

  const targets: DayTotals = {
    calories: roundOneDecimal(toNumber(targetResult.rows[0].calorie_target)),
    protein: roundOneDecimal(toNumber(targetResult.rows[0].macro_target_protein)),
    carbs: roundOneDecimal(toNumber(targetResult.rows[0].macro_target_carbs)),
    fat: roundOneDecimal(toNumber(targetResult.rows[0].macro_target_fat))
  };

  const rows = await pool.query<{
    day: string;
    total_calories: string;
    total_protein: string;
    total_carbs: string;
    total_fat: string;
    logs_count: string;
  }>(
    `
    WITH date_series AS (
      SELECT generate_series($3::date, $4::date, interval '1 day')::date AS day
    )
    SELECT
      ds.day::text AS day,
      COALESCE(SUM(fl.total_calories), 0) AS total_calories,
      COALESCE(SUM(fl.total_protein_g), 0) AS total_protein,
      COALESCE(SUM(fl.total_carbs_g), 0) AS total_carbs,
      COALESCE(SUM(fl.total_fat_g), 0) AS total_fat,
      COUNT(fl.id)::text AS logs_count
    FROM date_series ds
    LEFT JOIN food_logs fl
      ON fl.user_id = $1
      AND (fl.logged_at AT TIME ZONE $2)::date = ds.day
    GROUP BY ds.day
    ORDER BY ds.day ASC
    `,
    [userId, effectiveTimezone, from, to]
  );

  const days: ProgressDayPoint[] = rows.rows.map((row) => {
    const totals: DayTotals = {
      calories: roundOneDecimal(toNumber(row.total_calories)),
      protein: roundOneDecimal(toNumber(row.total_protein)),
      carbs: roundOneDecimal(toNumber(row.total_carbs)),
      fat: roundOneDecimal(toNumber(row.total_fat))
    };
    const logsCount = Math.max(0, Math.floor(toNumber(row.logs_count)));
    return {
      date: row.day,
      totals,
      targets,
      remaining: {
        calories: roundOneDecimal(targets.calories - totals.calories),
        protein: roundOneDecimal(targets.protein - totals.protein),
        carbs: roundOneDecimal(targets.carbs - totals.carbs),
        fat: roundOneDecimal(targets.fat - totals.fat)
      },
      hasLogs: logsCount > 0,
      logsCount,
      adherence: {
        caloriesPct: adherencePercent(totals.calories, targets.calories),
        proteinPct: adherencePercent(totals.protein, targets.protein),
        carbsPct: adherencePercent(totals.carbs, targets.carbs),
        fatPct: adherencePercent(totals.fat, targets.fat)
      }
    };
  });

  return {
    from,
    to,
    timezone: effectiveTimezone,
    days,
    streaks: computeStreaks(days),
    weeklyDelta: computeWeeklyDelta(days)
  };
}
