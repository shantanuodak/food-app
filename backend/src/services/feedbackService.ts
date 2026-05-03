import { pool } from '../db.js';

/**
 * In-app feedback submitted by users from the profile screen. Not bug
 * tickets — product comments, ideas, complaints. Surfaced to the team via
 * the testing dashboard's Feedback tab. See migration 0021_user_feedback.sql.
 */

export type FeedbackInput = {
  userId: string | null;
  userEmail: string | null;
  message: string;
  appVersion: string | null;
  buildNumber: string | null;
  deviceModel: string | null;
  osVersion: string | null;
  locale: string | null;
};

export type FeedbackRow = {
  id: string;
  userId: string | null;
  userEmail: string | null;
  message: string;
  appVersion: string | null;
  buildNumber: string | null;
  deviceModel: string | null;
  osVersion: string | null;
  locale: string | null;
  createdAt: string;
};

export async function saveFeedback(input: FeedbackInput): Promise<FeedbackRow> {
  const result = await pool.query<{
    id: string;
    user_id: string | null;
    user_email: string | null;
    message: string;
    app_version: string | null;
    build_number: string | null;
    device_model: string | null;
    os_version: string | null;
    locale: string | null;
    created_at: Date;
  }>(
    `
    INSERT INTO user_feedback (
      user_id, user_email, message,
      app_version, build_number, device_model, os_version, locale
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
    RETURNING id, user_id, user_email, message,
              app_version, build_number, device_model, os_version, locale, created_at
    `,
    [
      input.userId,
      input.userEmail,
      input.message,
      input.appVersion,
      input.buildNumber,
      input.deviceModel,
      input.osVersion,
      input.locale,
    ]
  );

  const row = result.rows[0]!;
  return {
    id: row.id,
    userId: row.user_id,
    userEmail: row.user_email,
    message: row.message,
    appVersion: row.app_version,
    buildNumber: row.build_number,
    deviceModel: row.device_model,
    osVersion: row.os_version,
    locale: row.locale,
    createdAt: row.created_at.toISOString(),
  };
}

/**
 * Newest-first list for the dashboard. `limit` is clamped to [1, 200] to
 * keep the dashboard payload bounded — pagination can come later if the
 * volume warrants.
 */
export async function listRecentFeedback(limit: number = 100): Promise<FeedbackRow[]> {
  const clamped = Math.max(1, Math.min(200, Math.floor(limit)));
  const result = await pool.query<{
    id: string;
    user_id: string | null;
    user_email: string | null;
    message: string;
    app_version: string | null;
    build_number: string | null;
    device_model: string | null;
    os_version: string | null;
    locale: string | null;
    created_at: Date;
  }>(
    `
    SELECT id, user_id, user_email, message,
           app_version, build_number, device_model, os_version, locale, created_at
    FROM user_feedback
    ORDER BY created_at DESC
    LIMIT $1
    `,
    [clamped]
  );

  return result.rows.map((row) => ({
    id: row.id,
    userId: row.user_id,
    userEmail: row.user_email,
    message: row.message,
    appVersion: row.app_version,
    buildNumber: row.build_number,
    deviceModel: row.device_model,
    osVersion: row.os_version,
    locale: row.locale,
    createdAt: row.created_at.toISOString(),
  }));
}
