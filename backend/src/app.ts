import express from 'express';
import { requestIdMiddleware } from './utils/requestId.js';
import { authRequired } from './middleware/auth.js';
import onboardingRoutes from './routes/onboarding.js';
import parseRoutes from './routes/parse.js';
import logsRoutes from './routes/logs.js';
import internalMetricsRoutes from './routes/internalMetrics.js';
import adminFeatureFlagsRoutes from './routes/adminFeatureFlags.js';
import healthRoutes from './routes/health.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';

export function createApp() {
  const app = express();

  app.use(express.json({ limit: '32kb' }));
  app.use(requestIdMiddleware);

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });

  app.use('/v1/onboarding', authRequired, onboardingRoutes);
  app.use('/v1/logs/parse', authRequired, parseRoutes);
  app.use('/v1/logs', authRequired, logsRoutes);
  app.use('/v1/admin/feature-flags', authRequired, adminFeatureFlagsRoutes);
  app.use('/v1/health', authRequired, healthRoutes);
  app.use('/v1/internal', internalMetricsRoutes);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
