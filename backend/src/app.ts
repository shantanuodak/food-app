import express from 'express';
import helmet from 'helmet';
import path from 'path';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'url';
import type { Request, Response, NextFunction } from 'express';
import { requestIdMiddleware } from './utils/requestId.js';
import { authRequired } from './middleware/auth.js';
import onboardingRoutes from './routes/onboarding.js';
import userRoutes from './routes/users.js';
import parseRoutes from './routes/parse.js';
import logsRoutes from './routes/logs.js';
import hydrationRoutes from './routes/hydration.js';
import rewardsRoutes from './routes/rewards.js';
import savedMealsRoutes from './routes/savedMeals.js';
import authDiagnosticRoutes from './routes/authDiagnostics.js';
import internalMetricsRoutes from './routes/internalMetrics.js';
import internalImageParseTestRoutes from './routes/internalImageParseTest.js';
import evalDashboardRoutes from './routes/evalDashboard.js';
import adminFeatureFlagsRoutes from './routes/adminFeatureFlags.js';
import healthRoutes from './routes/health.js';
import waitlistRoutes from './routes/waitlist.js';
import { submitRouter as feedbackSubmitRoutes, adminRouter as feedbackAdminRoutes } from './routes/feedback.js';
import { publicRouter as roadmapPublicRoutes, adminRouter as roadmapAdminRoutes } from './routes/roadmap.js';
import { userRouter as notificationRoutes, adminRouter as notificationAdminRoutes } from './routes/notifications.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';
import { getLatestAppliedMigration } from './db/schemaMetadata.js';
import { config } from './config.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DASHBOARD_COOKIE_NAME = 'food_app_dashboard';
const DASHBOARD_COOKIE_MAX_AGE_SECONDS = 8 * 60 * 60;

export function dashboardSessionValueForTests(): string {
  return createHmac('sha256', config.internalMetricsKey).update('testing-dashboard-page').digest('hex');
}

function parseCookies(header: string | undefined): Record<string, string> {
  if (!header) {
    return {};
  }
  return Object.fromEntries(
    header
      .split(';')
      .map((part) => part.trim())
      .filter(Boolean)
      .map((part) => {
        const index = part.indexOf('=');
        if (index === -1) {
          return [part, ''];
        }
        return [part.slice(0, index), decodeURIComponent(part.slice(index + 1))];
      })
  );
}

export function isDashboardCookieHeaderValidForTests(cookieHeader: string | undefined): boolean {
  if (!config.internalMetricsKey) {
    return false;
  }
  const token = parseCookies(cookieHeader)[DASHBOARD_COOKIE_NAME];
  if (!token) {
    return false;
  }

  const expected = Buffer.from(dashboardSessionValueForTests(), 'utf8');
  const actual = Buffer.from(token, 'utf8');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function isDashboardSessionValid(req: Request): boolean {
  return isDashboardCookieHeaderValidForTests(req.header('cookie'));
}

function renderDashboardLogin(res: Response, failed = false): void {
  res.status(failed ? 403 : 401).type('html').send(`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Testing Dashboard Login</title>
    <style>
      body { margin: 0; min-height: 100vh; display: grid; place-items: center; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #0f1220; color: #f6f7ff; }
      form { width: min(420px, calc(100vw - 32px)); padding: 28px; border: 1px solid rgba(144, 151, 255, 0.28); border-radius: 18px; background: rgba(20, 24, 44, 0.92); box-shadow: 0 24px 80px rgba(0, 0, 0, 0.35); }
      h1 { margin: 0 0 8px; font-size: 24px; }
      p { margin: 0 0 20px; color: #a8afd4; line-height: 1.45; }
      label { display: block; margin-bottom: 8px; color: #c6cae8; font-size: 13px; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; }
      input { box-sizing: border-box; width: 100%; border: 1px solid rgba(144, 151, 255, 0.34); border-radius: 12px; padding: 13px 14px; color: #fff; background: #171b31; font-size: 16px; }
      button { margin-top: 14px; width: 100%; border: 0; border-radius: 12px; padding: 13px 14px; color: #fff; background: #4f5dff; font-size: 16px; font-weight: 800; cursor: pointer; }
      .error { margin-bottom: 14px; color: #ff9a9a; }
    </style>
  </head>
  <body>
    <form method="post" action="/testing-dashboard/login">
      <h1>Testing Dashboard</h1>
      <p>Enter the internal dashboard key to open this admin surface.</p>
      ${failed ? '<div class="error">Invalid dashboard key.</div>' : ''}
      <label for="dashboardKey">Internal Key</label>
      <input id="dashboardKey" name="dashboardKey" type="password" autocomplete="current-password" autofocus />
      <button type="submit">Open Dashboard</button>
    </form>
  </body>
</html>`);
}

function requireDashboardPageAccess(req: Request, res: Response, next: NextFunction): void {
  if (isDashboardSessionValid(req)) {
    next();
    return;
  }
  renderDashboardLogin(res);
}

function resolveDashboardArtifactsRoot(): string {
  const configured = process.env.QA_ARTIFACTS_DIR;
  const candidates = [
    configured,
    path.resolve(process.cwd(), 'artifacts'),
    path.resolve(process.cwd(), '..', 'artifacts'),
    path.resolve(__dirname, '..', '..', 'artifacts')
  ].filter((candidate): candidate is string => Boolean(candidate));

  return candidates.find((candidate) => existsSync(candidate)) ?? candidates[0];
}

export function createApp() {
  const app = express();
  const dashboardArtifactsRoot = resolveDashboardArtifactsRoot();
  app.set('trust proxy', 1);

  app.use(requestIdMiddleware);
  app.use(
    helmet({
      // The testing dashboard is currently a single static HTML file with
      // inline CSS/JS. Keep CSP disabled until that dashboard is split into
      // separate assets with nonces/hashes; Helmet still adds the other
      // standard hardening headers.
      contentSecurityPolicy: false,
      crossOriginEmbedderPolicy: false
    })
  );

  // 10mb accommodates base64-encoded photos (~4-8 MB raw).
  // Individual routes enforce tighter limits via application-level validation
  // (e.g. config.aiImageMaxBytes in the image parse handler).
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: false, limit: '20kb' }));

  app.get('/health', async (_req, res) => {
    const commit = process.env.RENDER_GIT_COMMIT || process.env.GIT_COMMIT || 'unknown';
    try {
      const schemaVersion = await getLatestAppliedMigration();
      res.json({
        status: 'ok',
        commit,
        schemaVersion: schemaVersion ?? 'unknown',
        imageOrchestratorVersion: config.aiImageOrchestratorVersion
      });
    } catch {
      // Health must stay cheap and resilient — do not fail this endpoint if DB
      // metadata probing has a transient issue.
      res.json({
        status: 'ok',
        commit,
        schemaVersion: 'unknown',
        imageOrchestratorVersion: config.aiImageOrchestratorVersion
      });
    }
  });

  app.post('/testing-dashboard/login', (req, res) => {
    const submittedKey = typeof req.body?.dashboardKey === 'string' ? req.body.dashboardKey : '';
    if (!config.internalMetricsKey || submittedKey !== config.internalMetricsKey) {
      renderDashboardLogin(res, true);
      return;
    }

    res.cookie(DASHBOARD_COOKIE_NAME, dashboardSessionValueForTests(), {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      path: '/testing-dashboard',
      maxAge: DASHBOARD_COOKIE_MAX_AGE_SECONDS * 1000
    });
    res.redirect('/testing-dashboard');
  });

  // Testing dashboard — served as a static HTML page after a server-side gate.
  app.get('/testing-dashboard', requireDashboardPageAccess, (_req, res) => {
    res.sendFile(path.join(__dirname, 'testing-dashboard', 'index.html'));
  });
  app.use(
    '/testing-dashboard/artifacts/visual-qa',
    requireDashboardPageAccess,
    express.static(path.join(dashboardArtifactsRoot, 'visual-qa', 'screenshots'), {
      fallthrough: false,
      index: false
    })
  );
  app.use(
    '/testing-dashboard/artifacts/qa',
    requireDashboardPageAccess,
    express.static(path.join(dashboardArtifactsRoot, 'qa'), {
      fallthrough: false,
      index: false
    })
  );

  app.use('/v1/onboarding', authRequired, onboardingRoutes);
  app.use('/v1/users', authRequired, userRoutes);
  app.use('/v1/logs/parse', authRequired, parseRoutes);
  app.use('/v1/logs', authRequired, logsRoutes);
  app.use('/v1/hydration', authRequired, hydrationRoutes);
  app.use('/v1/rewards', authRequired, rewardsRoutes);
  app.use('/v1/saved-meals', authRequired, savedMealsRoutes);
  app.use('/v1/auth-diagnostics', authRequired, authDiagnosticRoutes);
  app.use('/v1/admin/feature-flags', authRequired, adminFeatureFlagsRoutes);
  app.use('/v1/health', authRequired, healthRoutes);
  app.use('/v1/waitlist', waitlistRoutes);
  app.use('/v1/roadmap', authRequired, roadmapPublicRoutes);
  app.use('/v1/notifications', authRequired, notificationRoutes);
  // User feedback submission (auth-gated). Admin list views are mounted under
  // both the testing-dashboard namespace and the shorter internal alias so
  // older tooling/comments do not drift from the same Supabase-backed data.
  app.use('/v1/feedback', authRequired, feedbackSubmitRoutes);
  app.use('/v1/internal', internalMetricsRoutes);
  app.use('/v1/internal/test', internalImageParseTestRoutes);
  app.use('/v1/internal/feedback', feedbackAdminRoutes);
  app.use('/v1/internal/dashboard', evalDashboardRoutes);
  app.use('/v1/internal/dashboard/feedback', feedbackAdminRoutes);
  app.use('/v1/internal/dashboard/roadmap', roadmapAdminRoutes);
  app.use('/v1/internal/dashboard/notifications', notificationAdminRoutes);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
