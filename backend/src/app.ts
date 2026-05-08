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
import trackingAccuracyRoutes from './routes/trackingAccuracy.js';
import { submitRouter as feedbackSubmitRoutes, adminRouter as feedbackAdminRoutes } from './routes/feedback.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';
import { getLatestAppliedMigration } from './db/schemaMetadata.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function createApp() {
  const app = express();

  app.use(requestIdMiddleware);

  // 10mb accommodates base64-encoded photos (~4-8 MB raw).
  // Individual routes enforce tighter limits via application-level validation
  // (e.g. config.aiImageMaxBytes in the image parse handler).
  app.use(express.json({ limit: '10mb' }));

  app.get('/health', async (_req, res) => {
    const commit = process.env.RENDER_GIT_COMMIT || process.env.GIT_COMMIT || 'unknown';
    try {
      const schemaVersion = await getLatestAppliedMigration();
      res.json({
        status: 'ok',
        commit,
        schemaVersion: schemaVersion ?? 'unknown'
      });
    } catch {
      // Health must stay cheap and resilient — do not fail this endpoint if DB
      // metadata probing has a transient issue.
      res.json({
        status: 'ok',
        commit,
        schemaVersion: 'unknown'
      });
    }
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
  app.use('/v1/profile', authRequired, trackingAccuracyRoutes);
  // User feedback submission (auth-gated). Admin list views are mounted under
  // both the testing-dashboard namespace and the shorter internal alias so
  // older tooling/comments do not drift from the same Supabase-backed data.
  app.use('/v1/feedback', authRequired, feedbackSubmitRoutes);
  app.use('/v1/internal', internalMetricsRoutes);
  app.use('/v1/internal/feedback', feedbackAdminRoutes);
  app.use('/v1/internal/dashboard', evalDashboardRoutes);
  app.use('/v1/internal/dashboard/feedback', feedbackAdminRoutes);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
