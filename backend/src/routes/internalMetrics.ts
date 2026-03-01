import { Router } from 'express';
import { config } from '../config.js';
import { ApiError } from '../utils/errors.js';
import { getMetricsSnapshot } from '../services/metricsService.js';
import { getAlertSnapshot } from '../services/alertRulesService.js';

const router = Router();

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

export default router;
