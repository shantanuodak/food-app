import { Router } from 'express';
import { z } from 'zod';
import { config } from '../config.js';
import { timingSafeKeyEqual } from '../utils/internalKey.js';
import { ApiError } from '../utils/errors.js';
import {
  deactivateNotificationDevice,
  getNotificationStats,
  listNotificationTemplates,
  recordNotificationEvent,
  registerNotificationDevice,
  runNotificationSweep,
  updateNotificationTemplate,
  upsertNotificationPreferences
} from '../services/notificationService.js';

function requireInternalKey(key: string | undefined): void {
  if (!config.internalMetricsKey) {
    throw new ApiError(503, 'INTERNAL_METRICS_DISABLED', 'Internal metrics key is not configured');
  }
  if (!key || !timingSafeKeyEqual(key, config.internalMetricsKey)) {
    throw new ApiError(403, 'FORBIDDEN', 'Invalid internal metrics key');
  }
}

function isValidTimezone(value: string): boolean {
  try {
    // Throws RangeError for unknown IANA zones.
    new Intl.DateTimeFormat('en-US', { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

const timeSchema = z.string().regex(/^\d{1,2}:\d{2}(:\d{2})?$/);

const deviceSchema = z.object({
  token: z.string().trim().min(32).max(512),
  platform: z.literal('ios').default('ios'),
  environment: z.enum(['development', 'production']),
  appVersion: z.string().trim().max(40).nullable().optional(),
  buildNumber: z.string().trim().max(40).nullable().optional(),
  deviceModel: z.string().trim().max(80).nullable().optional(),
  osVersion: z.string().trim().max(40).nullable().optional(),
  locale: z.string().trim().max(40).nullable().optional()
});

// Unregister must demand the same proper-length token as registration, so junk
// 1-char path params get rejected up front instead of hitting the DB.
export const deviceTokenParamSchema = z.string().trim().min(32).max(512);

export const preferenceSchema = z.object({
  timezone: z
    .string()
    .trim()
    .min(1)
    .max(80)
    .refine(isValidTimezone, 'timezone must be a valid IANA timezone'),
  remindersEnabled: z.boolean(),
  breakfastEnabled: z.boolean(),
  lunchEnabled: z.boolean(),
  dinnerEnabled: z.boolean(),
  breakfastStart: timeSchema,
  breakfastEnd: timeSchema,
  lunchStart: timeSchema,
  lunchEnd: timeSchema,
  dinnerStart: timeSchema,
  dinnerEnd: timeSchema,
  eatingWindowEnabled: z.boolean(),
  eatingWindowStart: timeSchema,
  eatingWindowEnd: timeSchema,
  engagementEnabled: z.boolean().optional(),
  discoveryEnabled: z.boolean().optional()
});

const eventSchema = z.object({
  deliveryKey: z.string().trim().min(1).max(160),
  templateKey: z.string().trim().min(1).max(80),
  destination: z.enum(['voice', 'text', 'camera', 'streaks', 'reminders', 'home']),
  eventType: z.enum(['opened', 'action_tapped', 'snoozed']),
  actionIdentifier: z.string().trim().max(120).optional().nullable()
});

const templateSchema = z.object({
  kind: z.enum(['meal', 'engagement', 'discovery']),
  title: z.string().trim().min(1).max(120),
  body: z.string().trim().min(1).max(240),
  destination: z.enum(['voice', 'text', 'camera', 'streaks', 'reminders', 'home']),
  isEnabled: z.boolean()
});

export const userRouter = Router();

userRouter.post('/devices', async (req, res, next) => {
  try {
    const auth = res.locals.auth as { userId: string } | undefined;
    if (!auth?.userId) throw new ApiError(401, 'UNAUTHORIZED', 'Authentication required');
    const device = await registerNotificationDevice(auth.userId, deviceSchema.parse(req.body));
    res.status(200).json({ device });
  } catch (err) {
    next(err);
  }
});

userRouter.delete('/devices/:token', async (req, res, next) => {
  try {
    const auth = res.locals.auth as { userId: string } | undefined;
    if (!auth?.userId) throw new ApiError(401, 'UNAUTHORIZED', 'Authentication required');
    await deactivateNotificationDevice(auth.userId, deviceTokenParamSchema.parse(req.params.token));
    res.status(204).send();
  } catch (err) {
    next(err);
  }
});

userRouter.put('/preferences', async (req, res, next) => {
  try {
    const auth = res.locals.auth as { userId: string } | undefined;
    if (!auth?.userId) throw new ApiError(401, 'UNAUTHORIZED', 'Authentication required');
    const preferences = await upsertNotificationPreferences(auth.userId, preferenceSchema.parse(req.body));
    res.status(200).json({ preferences });
  } catch (err) {
    next(err);
  }
});

userRouter.post('/events', async (req, res, next) => {
  try {
    const auth = res.locals.auth as { userId: string } | undefined;
    if (!auth?.userId) throw new ApiError(401, 'UNAUTHORIZED', 'Authentication required');
    const outcome = await recordNotificationEvent(auth.userId, eventSchema.parse(req.body));
    res.status(202).json(outcome);
  } catch (err) {
    next(err);
  }
});

export const adminRouter = Router();

adminRouter.get('/templates', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    res.status(200).json({ templates: await listNotificationTemplates() });
  } catch (err) {
    next(err);
  }
});

adminRouter.patch('/templates/:templateKey', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const templateKey = z.string().min(1).max(80).parse(req.params.templateKey);
    const template = await updateNotificationTemplate(templateKey, templateSchema.parse(req.body));
    if (!template) {
      throw new ApiError(404, 'NOTIFICATION_TEMPLATE_NOT_FOUND', 'Notification template not found');
    }
    res.status(200).json({ template });
  } catch (err) {
    next(err);
  }
});

adminRouter.post('/run', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const now = typeof req.body?.now === 'string' ? new Date(req.body.now) : new Date();
    if (Number.isNaN(now.getTime())) {
      throw new ApiError(400, 'INVALID_NOW', 'now must be an ISO timestamp');
    }
    const summary = await runNotificationSweep(now);
    res.status(200).json({ summary });
  } catch (err) {
    next(err);
  }
});

adminRouter.get('/stats', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const days = typeof req.query.days === 'string' ? Number(req.query.days) : 7;
    if (!Number.isFinite(days)) {
      throw new ApiError(400, 'INVALID_DAYS', 'days must be numeric');
    }
    res.status(200).json(await getNotificationStats(days));
  } catch (err) {
    next(err);
  }
});
