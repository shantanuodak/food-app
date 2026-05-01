import { Router } from 'express';
import { config } from '../config.js';
import { ApiError } from '../utils/errors.js';
import { getMetricsSnapshot } from '../services/metricsService.js';
import { getAlertSnapshot } from '../services/alertRulesService.js';
import { recordSaveAttempt, type SaveAttemptOutcome, type SaveAttemptSource } from '../services/saveAttemptService.js';
import { z } from 'zod';

const router = Router();

const saveAttemptSchema = z.object({
  userId: z.string().uuid().optional().nullable(),
  parseRequestId: z.string().trim().min(1).max(120).optional().nullable(),
  rowId: z.string().trim().min(1).max(120).optional().nullable(),
  idempotencyKey: z.string().trim().min(1).max(160).optional().nullable(),
  source: z.enum(['auto', 'manual', 'retry', 'patch', 'server']),
  outcome: z.enum(['attempted', 'succeeded', 'failed', 'skipped_no_eligible_state', 'skipped_duplicate']),
  errorCode: z.string().trim().min(1).max(120).optional().nullable(),
  latencyMs: z.number().int().min(0).max(3_600_000).optional().nullable(),
  logId: z.string().uuid().optional().nullable(),
  clientBuild: z.string().trim().min(1).max(80).optional().nullable(),
  backendCommit: z.string().trim().min(1).max(80).optional().nullable(),
  metadata: z.record(z.string(), z.unknown()).optional()
});

function requireInternalKey(key: string | undefined): void {
  if (!config.internalMetricsKey) {
    throw new ApiError(503, 'INTERNAL_METRICS_DISABLED', 'Internal metrics key is not configured');
  }

  if (!key || key !== config.internalMetricsKey) {
    throw new ApiError(403, 'FORBIDDEN', 'Invalid internal metrics key');
  }
}

router.get('/metrics', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const metrics = await getMetricsSnapshot();
    res.status(200).json({
      generatedAt: new Date().toISOString(),
      metrics
    });
  } catch (err) {
    next(err);
  }
});

router.get('/alerts', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const alerts = await getAlertSnapshot();
    res.status(200).json(alerts);
  } catch (err) {
    next(err);
  }
});

router.post('/save-attempts', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const body = saveAttemptSchema.parse(req.body ?? {});
    await recordSaveAttempt({
      userId: body.userId,
      parseRequestId: body.parseRequestId,
      rowId: body.rowId,
      idempotencyKey: body.idempotencyKey,
      source: body.source as SaveAttemptSource,
      outcome: body.outcome as SaveAttemptOutcome,
      errorCode: body.errorCode,
      latencyMs: body.latencyMs,
      logId: body.logId,
      clientBuild: body.clientBuild,
      backendCommit: body.backendCommit,
      metadata: body.metadata
    });
    res.status(202).json({ status: 'accepted' });
  } catch (err) {
    next(err);
  }
});

export default router;
