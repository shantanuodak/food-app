import { Router } from 'express';
import { z } from 'zod';
import { config } from '../config.js';
import { ApiError } from '../utils/errors.js';
import { getMetricsSnapshot } from '../services/metricsService.js';
import { getAlertSnapshot } from '../services/alertRulesService.js';
import {
  runGoldenSetEval,
  saveEvalRun,
  getEvalRunHistory,
  getEvalRunById
} from '../services/evalService.js';
import { pool } from '../db.js';

const router = Router();

const evalRunRequestSchema = z.object({
  caseSet: z.enum(['golden', 'exploration', 'combined']).optional().default('golden'),
  cacheMode: z.enum(['cached', 'fresh']).optional().default('cached'),
  benchmarkProviders: z.array(z.enum(['usda', 'fatsecret', 'curated'])).optional().default(['usda', 'fatsecret', 'curated']),
  maxCases: z.number().int().min(1).max(500).optional()
});

// ---------------------------------------------------------------------------
// Auth helper (same pattern as internalMetrics.ts)
// ---------------------------------------------------------------------------

function requireInternalKey(key: string | undefined): void {
  if (!config.internalMetricsKey) {
    throw new ApiError(503, 'INTERNAL_METRICS_DISABLED', 'Internal metrics key is not configured');
  }
  if (!key || key !== config.internalMetricsKey) {
    throw new ApiError(403, 'FORBIDDEN', 'Invalid internal metrics key');
  }
}

// ---------------------------------------------------------------------------
// GET /v1/internal/dashboard/overview
// Combined metrics + alerts in one call for the Overview tab
// ---------------------------------------------------------------------------

router.get('/overview', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const [metrics, alerts] = await Promise.all([getMetricsSnapshot(), getAlertSnapshot()]);

    // Today's cost
    const todayCostResult = await pool.query<{ total: string }>(
      `SELECT COALESCE(SUM(estimated_cost_usd), 0)::text AS total
       FROM ai_cost_events
       WHERE created_at >= CURRENT_DATE`
    );
    const todayCostUsd = Number(todayCostResult.rows[0]?.total ?? 0);

    // Today's parse requests
    const todayParsesResult = await pool.query<{ total: string }>(
      `SELECT COUNT(*)::text AS total
       FROM parse_requests
       WHERE created_at >= CURRENT_DATE`
    );
    const todayParses = Number(todayParsesResult.rows[0]?.total ?? 0);

    // Latest eval run summary
    const latestEvalResult = await pool.query<{
      id: string;
      run_at: Date;
      pass_rate: number;
      total_cases: number;
      passed: number;
    }>(
      `SELECT id, run_at, pass_rate, total_cases, passed
       FROM eval_runs
       ORDER BY run_at DESC
       LIMIT 1`
    );
    const latestEval = latestEvalResult.rows[0]
      ? {
          id: latestEvalResult.rows[0].id,
          runAt: latestEvalResult.rows[0].run_at.toISOString(),
          passRate: latestEvalResult.rows[0].pass_rate,
          totalCases: latestEvalResult.rows[0].total_cases,
          passed: latestEvalResult.rows[0].passed
        }
      : null;

    res.json({
      generatedAt: new Date().toISOString(),
      metrics,
      alerts,
      todayCostUsd,
      todayParses,
      latestEval
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// POST /v1/internal/dashboard/evals/run
// Triggers a golden set eval run in the background (free-tier Render drops
// HTTP connections on long requests, so we fire-and-forget and persist the
// result to the eval_runs table when done). The dashboard polls
// /evals/status to see progress.
// ---------------------------------------------------------------------------

type EvalRunStatus = {
  state: 'idle' | 'running' | 'complete' | 'error';
  startedAt: string | null;
  finishedAt: string | null;
  runId: string | null;
  error: string | null;
  totalCases: number;
  casesDone: number;
};

const evalStatus: EvalRunStatus = {
  state: 'idle',
  startedAt: null,
  finishedAt: null,
  runId: null,
  error: null,
  totalCases: 0,
  casesDone: 0
};

router.post('/evals/run', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));

    if (evalStatus.state === 'running') {
      res.status(409).json({
        error: { code: 'EVAL_ALREADY_RUNNING', message: 'An eval run is already in progress' },
        status: evalStatus
      });
      return;
    }

    const options = evalRunRequestSchema.parse(req.body ?? {});
    const defaultCases = options.caseSet === 'golden' ? 57 : 50;
    const requestedCases = options.maxCases ?? defaultCases;
    const totalCases = Math.min(
      requestedCases,
      options.cacheMode === 'fresh' ? 75 : 500,
      options.caseSet === 'golden' ? 57 : 500
    );

    // Reset status and respond immediately; don't block the request
    evalStatus.state = 'running';
    evalStatus.startedAt = new Date().toISOString();
    evalStatus.finishedAt = null;
    evalStatus.runId = null;
    evalStatus.error = null;
    evalStatus.totalCases = totalCases;
    evalStatus.casesDone = 0;

    // Fire and forget
    (async () => {
      try {
        const result = await runGoldenSetEval({
          ...options,
          onProgress: (casesDone, totalCases) => {
            evalStatus.casesDone = casesDone;
            evalStatus.totalCases = totalCases;
          }
        });
        const runId = await saveEvalRun(result, result.runType);
        evalStatus.state = 'complete';
        evalStatus.finishedAt = new Date().toISOString();
        evalStatus.runId = runId;
        evalStatus.casesDone = result.totalCases;
      } catch (err) {
        evalStatus.state = 'error';
        evalStatus.finishedAt = new Date().toISOString();
        evalStatus.error = err instanceof Error ? err.message : String(err);
        console.error('[eval_run_failed]', err);
      }
    })();

    res.status(202).json({ started: true, status: evalStatus });
  } catch (err) {
    next(err);
  }
});

// Poll this endpoint to see if the background eval is done
router.get('/evals/status', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    res.json(evalStatus);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// GET /v1/internal/dashboard/evals/history
// Last 20 eval runs (summaries only)
// ---------------------------------------------------------------------------

router.get('/evals/history', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const history = await getEvalRunHistory(20);
    res.json({ history });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// GET /v1/internal/dashboard/evals/:runId
// Full case-level results for a specific run
// ---------------------------------------------------------------------------

router.get('/evals/:runId', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const result = await getEvalRunById(req.params.runId!);
    if (!result) {
      throw new ApiError(404, 'NOT_FOUND', 'Eval run not found');
    }
    res.json({ result });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// GET /v1/internal/dashboard/recent-parses
// Last 50 parse requests with nutrition totals
// ---------------------------------------------------------------------------

router.get('/recent-parses', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));

    const { rows } = await pool.query<{
      request_id: string;
      raw_text: string;
      created_at: Date;
      needs_clarification: boolean;
      parse_version: string;
      log_id: string | null;
      saved_at: Date | null;
      total_calories: string | null;
      total_protein_g: string | null;
      total_carbs_g: string | null;
      total_fat_g: string | null;
      parse_confidence: string | null;
    }>(
      `SELECT
         pr.request_id,
         pr.raw_text,
         pr.created_at,
         pr.needs_clarification,
         pr.parse_version,
         fl.id AS log_id,
         fl.created_at AS saved_at,
         fl.total_calories::text,
         fl.total_protein_g::text,
         fl.total_carbs_g::text,
         fl.total_fat_g::text,
         fl.parse_confidence::text
       FROM parse_requests pr
       LEFT JOIN LATERAL (
         SELECT fl.*
         FROM food_logs fl
         WHERE fl.user_id = pr.user_id
           AND (
             fl.parse_request_id = pr.request_id
             OR (
               fl.parse_request_id IS NULL
               AND LOWER(REGEXP_REPLACE(TRIM(fl.raw_text), '\\s+', ' ', 'g')) =
                   LOWER(REGEXP_REPLACE(TRIM(pr.raw_text), '\\s+', ' ', 'g'))
               AND fl.created_at BETWEEN pr.created_at - INTERVAL '5 seconds'
                                     AND pr.created_at + INTERVAL '10 minutes'
             )
           )
         ORDER BY
           CASE WHEN fl.parse_request_id = pr.request_id THEN 0 ELSE 1 END,
           ABS(EXTRACT(EPOCH FROM (fl.created_at - pr.created_at)))
         LIMIT 1
       ) fl ON true
       ORDER BY pr.created_at DESC
       LIMIT 50`
    );

    const parses = rows.map((r) => ({
      requestId: r.request_id,
      rawText: r.raw_text,
      createdAt: r.created_at.toISOString(),
      needsClarification: r.needs_clarification,
      parseVersion: r.parse_version,
      saveStatus: r.log_id ? 'saved' : 'parse_only',
      logId: r.log_id,
      savedAt: r.saved_at ? r.saved_at.toISOString() : null,
      calories: r.total_calories !== null ? Number(r.total_calories) : null,
      proteinG: r.total_protein_g !== null ? Number(r.total_protein_g) : null,
      carbsG: r.total_carbs_g !== null ? Number(r.total_carbs_g) : null,
      fatG: r.total_fat_g !== null ? Number(r.total_fat_g) : null,
      confidence: r.parse_confidence !== null ? Number(r.parse_confidence) : null
    }));

    res.json({ parses });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// GET /v1/internal/dashboard/cost-breakdown
// 7-day cost by feature per day
// ---------------------------------------------------------------------------

router.get('/cost-breakdown', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));

    const { rows } = await pool.query<{
      feature: string;
      day: string;
      total_cost: string;
      input_tokens: string;
      output_tokens: string;
      request_count: string;
    }>(
      `SELECT
         feature,
         DATE(created_at)::text AS day,
         SUM(estimated_cost_usd)::text AS total_cost,
         SUM(input_tokens)::text AS input_tokens,
         SUM(output_tokens)::text AS output_tokens,
         COUNT(*)::text AS request_count
       FROM ai_cost_events
       WHERE created_at > NOW() - INTERVAL '7 days'
       GROUP BY feature, DATE(created_at)
       ORDER BY day DESC, total_cost DESC`
    );

    // Today's total vs budget
    const todayResult = await pool.query<{ total: string }>(
      `SELECT COALESCE(SUM(estimated_cost_usd), 0)::text AS total
       FROM ai_cost_events WHERE created_at >= CURRENT_DATE`
    );

    const breakdown = rows.map((r) => ({
      feature: r.feature,
      day: r.day,
      totalCostUsd: Number(r.total_cost),
      inputTokens: Number(r.input_tokens),
      outputTokens: Number(r.output_tokens),
      requestCount: Number(r.request_count)
    }));

    res.json({
      breakdown,
      todayCostUsd: Number(todayResult.rows[0]?.total ?? 0),
      dailyBudgetUsd: config.aiDailyBudgetUsd
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// GET /v1/internal/dashboard/cache-stats
// Cache health: totals, top entries, recent hit rate
// ---------------------------------------------------------------------------

router.get('/cache-stats', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));

    const [totalsResult, topResult, recentResult] = await Promise.all([
      pool.query<{ total_entries: string; avg_confidence: string; total_hits: string }>(
        `SELECT
           COUNT(*)::text AS total_entries,
           AVG(confidence)::text AS avg_confidence,
           COALESCE(SUM(hit_count), 0)::text AS total_hits
         FROM parse_cache`
      ),
      pool.query<{
        text_hash: string;
        cache_scope: string;
        confidence: string;
        hit_count: string;
        created_at: Date;
        last_used_at: Date;
        normalized_json: unknown;
      }>(
        `SELECT text_hash, cache_scope, confidence::text, hit_count::text,
                created_at, last_used_at, normalized_json
         FROM parse_cache
         ORDER BY hit_count DESC
         LIMIT 10`
      ),
      pool.query<{ hits_last_24h: string; entries_last_24h: string }>(
        `SELECT
           COALESCE(SUM(hit_count), 0)::text AS hits_last_24h,
           COUNT(*)::text AS entries_last_24h
         FROM parse_cache
         WHERE last_used_at > NOW() - INTERVAL '24 hours'`
      )
    ]);

    const totals = totalsResult.rows[0];
    const recent = recentResult.rows[0];

    interface ParsedNutrition {
      items?: Array<{ name?: string }>;
      totals?: { calories?: number };
    }

    const topEntries = topResult.rows.map((r) => {
      const parsed = r.normalized_json as ParsedNutrition;
      const firstItemName = parsed?.items?.[0]?.name ?? '';
      const calories = parsed?.totals?.calories ?? 0;
      return {
        textHash: r.text_hash,
        cacheScope: r.cache_scope,
        confidence: Number(r.confidence),
        hitCount: Number(r.hit_count),
        createdAt: r.created_at.toISOString(),
        lastUsedAt: r.last_used_at.toISOString(),
        foodName: firstItemName,
        calories
      };
    });

    res.json({
      totalEntries: Number(totals?.total_entries ?? 0),
      avgConfidence: Number(totals?.avg_confidence ?? 0),
      totalHits: Number(totals?.total_hits ?? 0),
      hitsLast24h: Number(recent?.hits_last_24h ?? 0),
      entriesLast24h: Number(recent?.entries_last_24h ?? 0),
      topEntries
    });
  } catch (err) {
    next(err);
  }
});

export default router;
