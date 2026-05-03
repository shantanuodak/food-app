import { Router } from 'express';
import { z } from 'zod';
import { config } from '../config.js';
import { ApiError } from '../utils/errors.js';
import { listRecentFeedback, saveFeedback } from '../services/feedbackService.js';

/**
 * Two routes share this file but mount at different paths:
 *
 *   POST /v1/feedback              — auth-gated user submission
 *   GET  /v1/internal/feedback     — admin-gated list view (testing dashboard)
 *
 * The submission route uses the standard Bearer-token auth middleware that
 * populates `res.locals.auth` (same pattern as `onboarding.ts`). The admin
 * list route uses the `requireInternalKey` pattern from `internalMetrics.ts`.
 */

// User-facing: bounded message + optional metadata. Anything missing is
// allowed so the client doesn't have to do detective work; we just record
// what we get.
const submitSchema = z.object({
  message: z.string().trim().min(1).max(4000),
  appVersion: z.string().trim().max(40).optional(),
  buildNumber: z.string().trim().max(40).optional(),
  deviceModel: z.string().trim().max(80).optional(),
  osVersion: z.string().trim().max(40).optional(),
  locale: z.string().trim().max(40).optional()
});

export const submitRouter = Router();

submitRouter.post('/', async (req, res, next) => {
  try {
    const auth = res.locals.auth as { userId: string; email?: string | null } | undefined;
    const body = submitSchema.parse(req.body);

    const saved = await saveFeedback({
      userId: auth?.userId ?? null,
      userEmail: auth?.email ?? null,
      message: body.message,
      appVersion: body.appVersion ?? null,
      buildNumber: body.buildNumber ?? null,
      deviceModel: body.deviceModel ?? null,
      osVersion: body.osVersion ?? null,
      locale: body.locale ?? null
    });

    res.status(201).json({ id: saved.id, createdAt: saved.createdAt });
  } catch (err) {
    next(err);
  }
});

// -------------------------------------------------------------------------
// Internal admin list endpoint (testing dashboard).
// Mounted under /v1/internal so the requireInternalKey gate matches the
// existing pattern used by /metrics, /alerts, and the dashboard endpoints.
// -------------------------------------------------------------------------

function requireInternalKey(key: string | undefined): void {
  if (!config.internalMetricsKey) {
    throw new ApiError(503, 'INTERNAL_METRICS_DISABLED', 'Internal metrics key is not configured');
  }
  if (!key || key !== config.internalMetricsKey) {
    throw new ApiError(403, 'FORBIDDEN', 'Invalid internal metrics key');
  }
}

const listQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).optional()
});

export const adminRouter = Router();

adminRouter.get('/', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const { limit } = listQuerySchema.parse(req.query);
    const items = await listRecentFeedback(limit ?? 100);
    res.status(200).json({ items });
  } catch (err) {
    next(err);
  }
});
