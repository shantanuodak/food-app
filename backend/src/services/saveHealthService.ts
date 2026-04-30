import { pool } from '../db.js';

/**
 * Save-health monitor.
 *
 * Surfaces users whose parse:save ratio is suspiciously low — the signal
 * that would have caught the 18-day silent image-save failure (commit
 * 0443246) days earlier. The bug pattern: parses keep landing but no
 * food_logs follow, because a regression on the client or a backend
 * config drift (missing storage bucket, RLS misconfig, expired Supabase
 * JWT, …) is short-circuiting the save POST before it lands.
 *
 * Severity buckets:
 *   - critical: ≥5 parses in window AND 0 saves
 *   - warning : ≥10 parses AND save_rate < 0.10
 *   - healthy : everything else (omitted unless the caller opts in)
 *
 * The 5-parse threshold is enough activity to be confident the user is
 * genuinely trying — single-parse-zero-save users are noise (they typed
 * "a" and changed their mind). The 10% rate threshold accounts for the
 * normal 2–4× re-parse-per-save ratio caused by typo correction and
 * photo retakes.
 */

export type SaveHealthSeverity = 'critical' | 'warning' | 'healthy';

export interface SaveHealthUser {
  userId: string;
  email: string;
  parseCount: number;
  saveCount: number;
  saveRate: number;
  lastParseAt: string;
  lastSaveAt: string | null;
  severity: SaveHealthSeverity;
}

export interface SaveHealthReport {
  windowDays: number;
  checkedAt: string;
  thresholds: {
    criticalMinParses: number;
    warningMinParses: number;
    warningMaxSaveRate: number;
  };
  users: SaveHealthUser[];
  summary: {
    criticalCount: number;
    warningCount: number;
    healthyCount: number;
  };
}

const CRITICAL_MIN_PARSES = 5;
const WARNING_MIN_PARSES = 10;
const WARNING_MAX_SAVE_RATE = 0.10;

interface QueryRow {
  user_id: string;
  email: string;
  parses: string;
  saves: string;
  last_parse: Date;
  last_save: Date | null;
}

/**
 * Single round-trip CTE: union the activity tables, group per user, then
 * join `users` for the email. Pulls only users with ≥CRITICAL_MIN_PARSES
 * so we don't drag the entire user table into memory just to count them.
 *
 * Cost: O(N) over rows in the 7-day window for both source tables. Both
 * are indexed on (user_id, created_at) thanks to migration 0018.
 */
async function fetchActivity(windowDays: number): Promise<QueryRow[]> {
  const result = await pool.query<QueryRow>(
    `WITH activity AS (
       SELECT user_id, created_at, 'parse' AS source FROM parse_requests
         WHERE created_at > NOW() - ($1::int || ' days')::interval
       UNION ALL
       SELECT user_id, created_at, 'save'  AS source FROM food_logs
         WHERE created_at > NOW() - ($1::int || ' days')::interval
     ),
     agg AS (
       SELECT user_id,
              COUNT(*) FILTER (WHERE source = 'parse') AS parses,
              COUNT(*) FILTER (WHERE source = 'save')  AS saves,
              MAX(created_at) FILTER (WHERE source = 'parse') AS last_parse,
              MAX(created_at) FILTER (WHERE source = 'save')  AS last_save
       FROM activity
       GROUP BY user_id
     )
     SELECT a.user_id, u.email,
            a.parses::text, a.saves::text,
            a.last_parse, a.last_save
       FROM agg a
       JOIN users u ON u.id = a.user_id
      WHERE a.parses >= $2
      ORDER BY a.parses DESC, a.saves ASC`,
    [windowDays, CRITICAL_MIN_PARSES]
  );
  return result.rows;
}

function classify(parseCount: number, saveCount: number): SaveHealthSeverity {
  if (parseCount >= CRITICAL_MIN_PARSES && saveCount === 0) return 'critical';
  if (parseCount >= WARNING_MIN_PARSES && (saveCount / parseCount) < WARNING_MAX_SAVE_RATE) return 'warning';
  return 'healthy';
}

export async function getSaveHealthReport(options: {
  windowDays?: number;
  includeHealthy?: boolean;
} = {}): Promise<SaveHealthReport> {
  const windowDays = Math.max(1, Math.min(30, options.windowDays ?? 7));
  const includeHealthy = options.includeHealthy === true;

  const rows = await fetchActivity(windowDays);

  let criticalCount = 0;
  let warningCount = 0;
  let healthyCount = 0;
  const users: SaveHealthUser[] = [];

  for (const row of rows) {
    const parses = Number(row.parses);
    const saves = Number(row.saves);
    const severity = classify(parses, saves);
    if (severity === 'critical') criticalCount++;
    else if (severity === 'warning') warningCount++;
    else healthyCount++;

    if (severity === 'healthy' && !includeHealthy) continue;

    users.push({
      userId: row.user_id,
      email: row.email,
      parseCount: parses,
      saveCount: saves,
      saveRate: parses === 0 ? 0 : Number((saves / parses).toFixed(3)),
      lastParseAt: row.last_parse.toISOString(),
      lastSaveAt: row.last_save ? row.last_save.toISOString() : null,
      severity
    });
  }

  return {
    windowDays,
    checkedAt: new Date().toISOString(),
    thresholds: {
      criticalMinParses: CRITICAL_MIN_PARSES,
      warningMinParses: WARNING_MIN_PARSES,
      warningMaxSaveRate: WARNING_MAX_SAVE_RATE
    },
    users,
    summary: { criticalCount, warningCount, healthyCount }
  };
}
