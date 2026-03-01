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
  await db.query(
    `
    INSERT INTO users (id, email, auth_provider, is_admin)
    VALUES ($1, $2, $3, $4)
    ON CONFLICT (id) DO UPDATE
    SET
      email = COALESCE(NULLIF(users.email, ''), EXCLUDED.email),
      auth_provider = CASE
        WHEN users.auth_provider = 'dev' AND EXCLUDED.auth_provider <> 'dev' THEN EXCLUDED.auth_provider
        ELSE users.auth_provider
      END,
      is_admin = EXCLUDED.is_admin
    `,
    [userId, email, provider, isAdmin]
  );
}
