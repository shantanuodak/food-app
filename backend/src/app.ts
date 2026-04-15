import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import { requestIdMiddleware } from './utils/requestId.js';
import { authRequired } from './middleware/auth.js';
import onboardingRoutes from './routes/onboarding.js';
import parseRoutes from './routes/parse.js';
import logsRoutes from './routes/logs.js';
import internalMetricsRoutes from './routes/internalMetrics.js';
import evalDashboardRoutes from './routes/evalDashboard.js';
import adminFeatureFlagsRoutes from './routes/adminFeatureFlags.js';
import healthRoutes from './routes/health.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function createApp() {
  const app = express();

  app.use(requestIdMiddleware);

  // 10mb accommodates base64-encoded photos (~4-8 MB raw).
  // Individual routes enforce tighter limits via application-level validation
  // (e.g. config.aiImageMaxBytes in the image parse handler).
  app.use(express.json({ limit: '10mb' }));

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });

  // Testing dashboard — served as a static HTML page
  app.get('/testing-dashboard', (_req, res) => {
    res.sendFile(path.join(__dirname, 'testing-dashboard', 'index.html'));
  });

  app.use('/v1/onboarding', authRequired, onboardingRoutes);
  app.use('/v1/logs/parse', authRequired, parseRoutes);
  app.use('/v1/logs', authRequired, logsRoutes);
  app.use('/v1/admin/feature-flags', authRequired, adminFeatureFlagsRoutes);
  app.use('/v1/health', authRequired, healthRoutes);
  app.use('/v1/internal', internalMetricsRoutes);
  app.use('/v1/internal/dashboard', evalDashboardRoutes);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
