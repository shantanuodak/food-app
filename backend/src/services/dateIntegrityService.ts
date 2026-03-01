import { pool } from '../db.js';
import { ApiError } from '../utils/errors.js';

function normalizeTimezone(value: string | null | undefined): string {
  const normalized = (value || '').trim();
  return normalized || 'UTC';
}

function isValidTimezone(value: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

function dateKeyInTimezone(date: Date, timezone: string): string {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  });
  return formatter.format(date);
}

export async function getUserTimezoneOrUtc(userId: string): Promise<string> {
  const result = await pool.query<{ timezone: string | null }>(
    `
    SELECT timezone
    FROM onboarding_profiles
    WHERE user_id = $1
    `,
    [userId]
  );

  const timezone = normalizeTimezone(result.rows[0]?.timezone);
  return isValidTimezone(timezone) ? timezone : 'UTC';
}

export async function assertLoggedAtNotInFutureForUser(userId: string, loggedAt: Date): Promise<void> {
  if (Number.isNaN(loggedAt.valueOf())) {
    throw new ApiError(400, 'INVALID_INPUT', 'Invalid loggedAt timestamp');
  }

  const timezone = await getUserTimezoneOrUtc(userId);
  const loggedAtDateKey = dateKeyInTimezone(loggedAt, timezone);
  const todayDateKey = dateKeyInTimezone(new Date(), timezone);
  if (loggedAtDateKey > todayDateKey) {
    throw new ApiError(422, 'FUTURE_DATE_NOT_ALLOWED', `loggedAt cannot be in the future (${timezone}).`);
  }
}
