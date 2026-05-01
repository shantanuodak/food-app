import { pool } from '../db.js';

let cachedSchemaVersion: string | null = null;
let cachedAtMs = 0;
const cacheTtlMs = 30_000;

export async function getLatestAppliedMigration(forceRefresh = false): Promise<string | null> {
  const now = Date.now();
  if (!forceRefresh && cachedSchemaVersion !== null && now - cachedAtMs < cacheTtlMs) {
    return cachedSchemaVersion;
  }

  const result = await pool.query<{ id: string }>(
    `
    SELECT id
    FROM schema_migrations
    ORDER BY applied_at DESC, id DESC
    LIMIT 1
    `
  );

  cachedSchemaVersion = result.rows[0]?.id ?? null;
  cachedAtMs = now;
  return cachedSchemaVersion;
}

