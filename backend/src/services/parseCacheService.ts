import { createHash } from 'node:crypto';
import { pool } from '../db.js';
import type { ParseResult } from './deterministicParser.js';

type CacheRecord = {
  textHash: string;
  result: ParseResult;
};

export type ParseCacheDebugInfo = {
  scope: string;
  normalizedText: string;
  textHash: string;
};

function normalizeForCache(text: string): string {
  return text
    .normalize('NFKD')
    .replace(/\p{Mark}+/gu, '')
    .replace(/[\u200B-\u200D\uFEFF]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ');
}

function textHash(text: string, scope: string): string {
  return createHash('sha256')
    .update(`${scope}::${normalizeForCache(text)}`)
    .digest('hex');
}

export function buildParseCacheDebugInfo(text: string, scope: string): ParseCacheDebugInfo {
  const normalizedText = normalizeForCache(text);
  return {
    scope,
    normalizedText,
    textHash: textHash(text, scope)
  };
}

export async function getParseCache(text: string, scope = 'global'): Promise<CacheRecord | null> {
  const hash = textHash(text, scope);
  const result = await pool.query<{ normalized_json: ParseResult }>(
    `
    SELECT normalized_json
    FROM parse_cache
    WHERE text_hash = $1
      AND cache_scope = $2
    `,
    [hash, scope]
  );

  const row = result.rows[0];
  if (!row) {
    return null;
  }

  await pool.query(
    `
    UPDATE parse_cache
    SET last_used_at = NOW(), hit_count = hit_count + 1
    WHERE text_hash = $1
      AND cache_scope = $2
    `,
    [hash, scope]
  );

  return {
    textHash: hash,
    result: row.normalized_json
  };
}

export async function setParseCache(text: string, parseResult: ParseResult, scope = 'global'): Promise<void> {
  const hash = textHash(text, scope);
  await pool.query(
    `
    INSERT INTO parse_cache (text_hash, cache_scope, normalized_json, confidence, created_at, last_used_at, hit_count)
    VALUES ($1, $2, $3::jsonb, $4, NOW(), NOW(), 0)
    ON CONFLICT (text_hash)
    DO UPDATE SET
      cache_scope = EXCLUDED.cache_scope,
      normalized_json = EXCLUDED.normalized_json,
      confidence = EXCLUDED.confidence,
      last_used_at = NOW()
    `,
    [hash, scope, JSON.stringify(parseResult), parseResult.confidence]
  );
}

export async function purgeParseCacheByScopePrefix(scopePrefix: string): Promise<number> {
  const normalizedPrefix = scopePrefix.trim();
  if (!normalizedPrefix) {
    return 0;
  }

  const result = await pool.query(
    `
    DELETE FROM parse_cache
    WHERE cache_scope LIKE $1
    `,
    [`${normalizedPrefix}%`]
  );
  return result.rowCount || 0;
}
