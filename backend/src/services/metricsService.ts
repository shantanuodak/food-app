import { pool } from '../db.js';

export type MetricsSnapshot = {
  parse_requests_total: number;
  parse_fallback_total: number;
  parse_escalation_total: number;
  parse_clarification_total: number;
  ai_tokens_input_total: number;
  ai_tokens_output_total: number;
  ai_estimated_cost_usd_total: number;
  cache_hit_ratio: number;
};

function toNumber(value: unknown): number {
  if (value === null || value === undefined) {
    return 0;
  }
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function round(value: number, digits = 6): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

export async function getMetricsSnapshot(): Promise<MetricsSnapshot> {
  const result = await pool.query<{
    parse_requests_total: string;
    parse_clarification_total: string;
    parse_fallback_total: string;
    parse_escalation_total: string;
    ai_tokens_input_total: string;
    ai_tokens_output_total: string;
    ai_estimated_cost_usd_total: string;
    parse_cache_hits_total: string;
  }>(
    `
    SELECT
      (SELECT COUNT(*)::text FROM parse_requests) AS parse_requests_total,
      (SELECT COUNT(*)::text FROM parse_requests WHERE needs_clarification = true) AS parse_clarification_total,
      (SELECT COUNT(*)::text FROM ai_cost_events WHERE feature = 'parse_fallback') AS parse_fallback_total,
      (SELECT COUNT(*)::text FROM ai_cost_events WHERE feature = 'escalation') AS parse_escalation_total,
      (SELECT COALESCE(SUM(input_tokens), 0)::text FROM ai_cost_events) AS ai_tokens_input_total,
      (SELECT COALESCE(SUM(output_tokens), 0)::text FROM ai_cost_events) AS ai_tokens_output_total,
      (SELECT COALESCE(SUM(estimated_cost_usd), 0)::text FROM ai_cost_events) AS ai_estimated_cost_usd_total,
      (SELECT COALESCE(SUM(hit_count), 0)::text FROM parse_cache) AS parse_cache_hits_total
    `
  );

  const row = result.rows[0];
  const parseRequestsTotal = toNumber(row?.parse_requests_total);
  const parseCacheHitsTotal = toNumber(row?.parse_cache_hits_total);

  return {
    parse_requests_total: parseRequestsTotal,
    parse_fallback_total: toNumber(row?.parse_fallback_total),
    parse_escalation_total: toNumber(row?.parse_escalation_total),
    parse_clarification_total: toNumber(row?.parse_clarification_total),
    ai_tokens_input_total: toNumber(row?.ai_tokens_input_total),
    ai_tokens_output_total: toNumber(row?.ai_tokens_output_total),
    ai_estimated_cost_usd_total: round(toNumber(row?.ai_estimated_cost_usd_total), 6),
    cache_hit_ratio: parseRequestsTotal === 0 ? 0 : round(parseCacheHitsTotal / parseRequestsTotal, 6)
  };
}
