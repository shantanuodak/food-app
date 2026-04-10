import { pool } from '../db.js';
import { config } from '../config.js';
import { ensureUserExists } from './userService.js';

// Note: 'fatsecret' and 'alias' values may exist in old DB rows but are no longer
// produced by the live parse pipeline. The type stays union-permissive for read paths.
export type ParsePrimaryRoute = 'cache' | 'alias' | 'fatsecret' | 'gemini' | 'unresolved';

export type ParseRequestRecord = {
  requestId: string;
  userId: string;
  parseVersion: string;
  rawText: string;
  needsClarification: boolean;
  cacheHit: boolean;
  primaryRoute: ParsePrimaryRoute;
  createdAt: string;
};

export async function createParseRequest(input: {
  requestId: string;
  userId: string;
  rawText: string;
  needsClarification: boolean;
  cacheHit: boolean;
  primaryRoute: ParsePrimaryRoute;
  authProvider?: string | null;
  email?: string | null;
}): Promise<void> {
  await ensureUserExists(input.userId, {
    authProvider: input.authProvider,
    email: input.email
  });

  const upsert = async (primaryRoute: ParsePrimaryRoute): Promise<void> => {
    await pool.query(
      `
      INSERT INTO parse_requests (
        request_id, user_id, parse_version, raw_text, needs_clarification, cache_hit, primary_route, created_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,NOW())
      ON CONFLICT (request_id)
      DO UPDATE SET
        parse_version = EXCLUDED.parse_version,
        raw_text = EXCLUDED.raw_text,
        needs_clarification = EXCLUDED.needs_clarification,
        cache_hit = EXCLUDED.cache_hit,
        primary_route = EXCLUDED.primary_route,
        created_at = NOW()
      `,
      [input.requestId, input.userId, config.parseVersion, input.rawText, input.needsClarification, input.cacheHit, primaryRoute]
    );
  };

  try {
    await upsert(input.primaryRoute);
  } catch (err) {
    const code = typeof err === 'object' && err && 'code' in err ? String((err as { code?: unknown }).code ?? '') : '';
    const constraint =
      typeof err === 'object' && err && 'constraint' in err ? String((err as { constraint?: unknown }).constraint ?? '') : '';

    if (
      (input.primaryRoute === 'fatsecret' || input.primaryRoute === 'unresolved') &&
      code === '23514' &&
      constraint === 'parse_requests_primary_route_check'
    ) {
      console.warn(
        '[parse_requests_route_fallback]',
        JSON.stringify({
          requestId: input.requestId,
          from: input.primaryRoute,
          to: 'gemini',
          reason: input.primaryRoute === 'fatsecret' ? 'constraint_missing_fatsecret' : 'constraint_missing_unresolved'
        })
      );
      await upsert('gemini');
      return;
    }

    throw err;
  }
}

export async function getParseRequestForUser(userId: string, parseRequestId: string): Promise<ParseRequestRecord | null> {
  const result = await pool.query<{
    request_id: string;
    user_id: string;
    parse_version: string;
    raw_text: string;
    needs_clarification: boolean;
    cache_hit: boolean;
    primary_route: ParsePrimaryRoute;
    created_at: string;
  }>(
    `
    SELECT request_id, user_id, parse_version, raw_text, needs_clarification, cache_hit, primary_route, created_at
    FROM parse_requests
    WHERE user_id = $1
      AND request_id = $2
    `,
    [userId, parseRequestId]
  );

  const row = result.rows[0];
  if (!row) {
    return null;
  }

  return {
    requestId: row.request_id,
    userId: row.user_id,
    parseVersion: row.parse_version,
    rawText: row.raw_text,
    needsClarification: row.needs_clarification,
    cacheHit: row.cache_hit,
    primaryRoute: row.primary_route,
    createdAt: row.created_at
  };
}

export function isParseRequestStale(record: ParseRequestRecord): boolean {
  const created = new Date(record.createdAt);
  if (Number.isNaN(created.valueOf())) {
    return true;
  }

  const maxAgeMs = config.parseRequestTtlHours * 60 * 60 * 1000;
  return Date.now() - created.getTime() > maxAgeMs;
}
