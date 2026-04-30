import { pool } from '../db.js';
import { ApiError } from '../utils/errors.js';

export type StreakRange = 30 | 365;

export type StreakDay = {
  date: string;
  logsCount: number;
  foodsCount: number;
  level: number;
};

export type StreakStatus = 'completed_today' | 'at_risk_today' | 'broken';

export type StreakResponse = {
  from: string;
  to: string;
  timezone: string;
  range: StreakRange;
  currentDays: number;
  longestDays: number;
  todayHasLog: boolean;
  status: StreakStatus;
  lastLoggedDate: string | null;
  days: StreakDay[];
};

function toNumber(value: unknown): number {
  if (value === null || value === undefined) {
    return 0;
  }
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
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

function todayInTimezone(timezone: string): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).formatToParts(new Date());
  const year = parts.find((part) => part.type === 'year')?.value;
  const month = parts.find((part) => part.type === 'month')?.value;
  const day = parts.find((part) => part.type === 'day')?.value;
  if (!year || !month || !day) {
    throw new ApiError(500, 'INTERNAL_ERROR', 'Unable to resolve local date');
  }
  return `${year}-${month}-${day}`;
}

function levelForFoods(foodsCount: number): number {
  if (foodsCount <= 0) return 0;
  if (foodsCount <= 3) return 1;
  if (foodsCount <= 6) return 2;
  return 3;
}

function computeLongestStreak(days: StreakDay[]): number {
  let longest = 0;
  let running = 0;

  for (const day of days) {
    if (day.logsCount > 0) {
      running += 1;
      longest = Math.max(longest, running);
    } else {
      running = 0;
    }
  }

  return longest;
}

function computeCurrentStreak(days: StreakDay[]): { currentDays: number; status: StreakStatus } {
  if (days.length === 0) {
    return { currentDays: 0, status: 'broken' };
  }

  const todayIndex = days.length - 1;
  const todayHasLog = days[todayIndex]?.logsCount > 0;
  let streakEndIndex = todayIndex;
  let status: StreakStatus = 'completed_today';

  if (!todayHasLog) {
    streakEndIndex = todayIndex - 1;
    status = days[streakEndIndex]?.logsCount > 0 ? 'at_risk_today' : 'broken';
  }

  if (streakEndIndex < 0 || status === 'broken') {
    return { currentDays: 0, status };
  }

  let currentDays = 0;
  for (let i = streakEndIndex; i >= 0; i -= 1) {
    if (days[i]?.logsCount <= 0) {
      break;
    }
    currentDays += 1;
  }

  return { currentDays, status };
}

export async function getFoodLogStreaks(
  userId: string,
  range: StreakRange,
  timezoneOverride?: string,
  toOverride?: string
): Promise<StreakResponse> {
  const profileResult = await pool.query<{ timezone: string | null }>(
    `
    SELECT timezone
    FROM onboarding_profiles
    WHERE user_id = $1
    `,
    [userId]
  );

  const effectiveTimezone = normalizeTimezone(timezoneOverride || profileResult.rows[0]?.timezone || 'UTC');
  if (!isValidTimezone(effectiveTimezone)) {
    throw new ApiError(400, 'INVALID_INPUT', 'Invalid timezone');
  }

  const to = toOverride || todayInTimezone(effectiveTimezone);
  validateDate(to);

  // Use a full year internally so the 30-day drawer can still show a real
  // current streak if it started before the visible 30-day window.
  const lookbackDays = Math.max(range, 365);

  const rows = await pool.query<{
    date: string;
    logs_count: string | number;
    foods_count: string | number;
  }>(
    `
    WITH date_series AS (
      SELECT generate_series(
        ($3::date - (($4::int - 1) * interval '1 day'))::date,
        $3::date,
        interval '1 day'
      )::date AS day
    )
    SELECT
      ds.day::text AS date,
      COUNT(DISTINCT fl.id)::int AS logs_count,
      GREATEST(COUNT(DISTINCT fl.id), COUNT(fli.id))::int AS foods_count
    FROM date_series ds
    LEFT JOIN food_logs fl
      ON fl.user_id = $1
      AND (fl.logged_at AT TIME ZONE $2)::date = ds.day
    LEFT JOIN food_log_items fli
      ON fli.food_log_id = fl.id
    GROUP BY ds.day
    ORDER BY ds.day ASC
    `,
    [userId, effectiveTimezone, to, lookbackDays]
  );

  const allDays: StreakDay[] = rows.rows.map((row) => {
    const logsCount = Math.max(0, Math.floor(toNumber(row.logs_count)));
    const foodsCount = Math.max(0, Math.floor(toNumber(row.foods_count)));
    return {
      date: row.date,
      logsCount,
      foodsCount,
      level: levelForFoods(foodsCount)
    };
  });

  const visibleDays = allDays.slice(-range);
  const current = computeCurrentStreak(allDays);
  const lastLoggedDate = [...allDays].reverse().find((day) => day.logsCount > 0)?.date ?? null;

  return {
    from: visibleDays[0]?.date ?? to,
    to,
    timezone: effectiveTimezone,
    range,
    currentDays: current.currentDays,
    longestDays: computeLongestStreak(allDays),
    todayHasLog: allDays[allDays.length - 1]?.logsCount > 0,
    status: current.status,
    lastLoggedDate,
    days: visibleDays
  };
}
