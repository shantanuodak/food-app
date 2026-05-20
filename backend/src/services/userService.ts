import { pool } from '../db.js';
import { isAdminEmail } from './adminFeatureFlagsService.js';
import type { PoolClient } from 'pg';

type UserIdentity = {
  authProvider?: string | null;
  email?: string | null;
};

function normalizeProvider(value: string | null | undefined): string {
  const provider = (value || 'dev').trim().toLowerCase();
  return provider || 'dev';
}

function normalizeEmail(userId: string, provider: string, email: string | null | undefined): string {
  const candidate = (email || '').trim().toLowerCase();
  if (candidate) {
    return candidate;
  }
  return `${userId}@${provider}.local`;
}

export async function ensureUserExists(userId: string, identity?: UserIdentity, client?: PoolClient): Promise<void> {
  const db = client || pool;
  const provider = normalizeProvider(identity?.authProvider);
  const email = normalizeEmail(userId, provider, identity?.email);
  const isAdmin = isAdminEmail(email);
  // V3.1 Phase 0 (2026-05-20): when an existing row has a synthetic
  // `<UUID>@dev.local` email (created earlier by an identity-less
  // ensureUserExists call, e.g. from aiCostService.ts), allow a later
  // identity-aware call to overwrite it with the real email. Without this
  // CASE, real Supabase-authenticated users could get stuck with synthetic
  // emails because the COALESCE branch preserves any non-empty value.
  await db.query(
    `
    INSERT INTO users (id, email, auth_provider, is_admin)
    VALUES ($1, $2, $3, $4)
    ON CONFLICT (id) DO UPDATE
    SET
      email = CASE
        WHEN users.email LIKE '%@dev.local' AND EXCLUDED.email NOT LIKE '%@dev.local'
          THEN EXCLUDED.email
        ELSE COALESCE(NULLIF(users.email, ''), EXCLUDED.email)
      END,
      auth_provider = CASE
        WHEN users.auth_provider = 'dev' AND EXCLUDED.auth_provider <> 'dev' THEN EXCLUDED.auth_provider
        ELSE users.auth_provider
      END,
      is_admin = EXCLUDED.is_admin
    `,
    [userId, email, provider, isAdmin]
  );
}
