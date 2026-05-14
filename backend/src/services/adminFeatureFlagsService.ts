import { pool } from '../db.js';
import type { PoolClient } from 'pg';
import { config } from '../config.js';

export type AdminFeatureFlags = {
  geminiEnabled: boolean;
};

function normalizeEmail(email: string | null | undefined): string {
  return (email || '').trim().toLowerCase();
}

export function isAdminEmail(email: string | null | undefined): boolean {
  const normalized = normalizeEmail(email);
  if (!normalized) {
    return false;
  }
  return config.adminEmails.includes(normalized);
}

export function defaultAdminFeatureFlags(): AdminFeatureFlags {
  const geminiEnabled = Boolean(config.geminiApiKey);
  return { geminiEnabled };
}

export async function getAdminFeatureFlagsForUser(
  userId: string,
  client?: PoolClient
): Promise<AdminFeatureFlags | null> {
  const db = client || pool;
  const result = await db.query(
    `
    SELECT gemini_enabled
    FROM admin_feature_flags
    WHERE user_id = $1
    `,
    [userId]
  );
  if (result.rowCount === 0) {
    return null;
  }
  const row = result.rows[0];
  return {
    geminiEnabled: Boolean(row.gemini_enabled)
  };
}

export async function getEffectiveFeatureFlags(
  userId: string,
  client?: PoolClient
): Promise<AdminFeatureFlags> {
  const override = await getAdminFeatureFlagsForUser(userId, client);
  if (override) {
    return override;
  }
  return defaultAdminFeatureFlags();
}

export async function upsertAdminFeatureFlags(
  userId: string,
  flags: AdminFeatureFlags,
  client?: PoolClient
): Promise<AdminFeatureFlags> {
  const db = client || pool;
  // Note: fatsecret_enabled column is NOT NULL in the legacy schema, so we hardcode false.
  // The column is no longer read or surfaced anywhere in the application.
  const result = await db.query(
    `
    INSERT INTO admin_feature_flags (user_id, gemini_enabled, fatsecret_enabled)
    VALUES ($1, $2, false)
    ON CONFLICT (user_id) DO UPDATE
    SET
      gemini_enabled = EXCLUDED.gemini_enabled,
      updated_at = NOW()
    RETURNING gemini_enabled
    `,
    [userId, flags.geminiEnabled]
  );
  const row = result.rows[0];
  return {
    geminiEnabled: Boolean(row.gemini_enabled)
  };
}
