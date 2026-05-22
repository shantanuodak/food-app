import { pool } from '../db.js';
import { isAdminEmail } from './adminFeatureFlagsService.js';
import type { PoolClient } from 'pg';

type UserIdentity = {
  authProvider?: string | null;
  email?: string | null;
  displayName?: string | null;
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

function normalizeDisplayName(value: string | null | undefined): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }
  // PATCH /v1/users/me caps at 80; mirror the cap here defensively in
  // case a caller bypasses the route validator.
  return trimmed.slice(0, 80);
}

export async function ensureUserExists(userId: string, identity?: UserIdentity, client?: PoolClient): Promise<void> {
  const db = client || pool;
  const provider = normalizeProvider(identity?.authProvider);
  const email = normalizeEmail(userId, provider, identity?.email);
  const isAdmin = isAdminEmail(email);
  const displayName = normalizeDisplayName(identity?.displayName);
  // V3.1 Phase 0 (2026-05-20): when an existing row has a synthetic
  // `<UUID>@dev.local` email (created earlier by an identity-less
  // ensureUserExists call, e.g. from aiCostService.ts), allow a later
  // identity-aware call to overwrite it with the real email. Without this
  // CASE, real Supabase-authenticated users could get stuck with synthetic
  // emails because the COALESCE branch preserves any non-empty value.
  //
  // Bug 2 (2026-05-22): same non-destructive shape for display_name —
  // only overwrite when the incoming value is non-empty AND the existing
  // row is empty/NULL. PATCH /v1/users/me is the only place that should
  // be flipping an already-set display_name; an identity-aware
  // ensureUserExists call (e.g. from the onboarding submit flow) must
  // never silently wipe a name the user just typed.
  await db.query(
    `
    INSERT INTO users (id, email, auth_provider, is_admin, display_name)
    VALUES ($1, $2, $3, $4, $5)
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
      is_admin = EXCLUDED.is_admin,
      display_name = COALESCE(NULLIF(users.display_name, ''), EXCLUDED.display_name)
    `,
    [userId, email, provider, isAdmin, displayName]
  );
}

export async function updateUserDisplayName(userId: string, rawName: string): Promise<string | null> {
  const normalized = normalizeDisplayName(rawName);
  // Empty after trim is allowed and clears the field — UI falls back to
  // the email prefix.
  await pool.query(
    `
    UPDATE users
    SET display_name = $2
    WHERE id = $1
    `,
    [userId, normalized]
  );
  return normalized;
}

export async function getUserDisplayName(userId: string): Promise<string | null> {
  const result = await pool.query<{ display_name: string | null }>(
    'SELECT display_name FROM users WHERE id = $1',
    [userId]
  );
  const value = result.rows[0]?.display_name;
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
