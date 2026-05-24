import { Router } from 'express';
import type { Response } from 'express';
import { z } from 'zod';
import { parseHydrationText } from '../services/hydrationParser.js';
import {
  deleteHydrationGoal,
  deleteHydrationLog,
  getHydrationDayLogs,
  getHydrationDaySummary,
  getHydrationGoal,
  getHydrationProgress,
  saveHydrationLog,
  updateHydrationLog,
  upsertHydrationGoal,
  type HydrationSource
} from '../services/hydrationService.js';
import { ApiError } from '../utils/errors.js';

const router = Router();

const dateQuery = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be in YYYY-MM-DD format');
const sourceSchema = z.enum(['text', 'voice', 'quick_add', 'manual']);

const parseHydrationSchema = z.object({
  text: z.string().trim().min(1).max(500)
});

const goalSchema = z.object({
  dailyGoalMl: z.number().finite().int().min(250).max(10000)
});

const logSchema = z.object({
  loggedAt: z.string().datetime(),
  rawText: z.string().trim().min(1).max(500),
  amountMl: z.number().finite().positive().max(10000),
  inputAmount: z.number().finite().positive().max(10000).nullable().optional(),
  inputUnit: z.string().trim().min(1).max(30).nullable().optional(),
  source: sourceSchema.default('text'),
  confidence: z.number().finite().min(0).max(1).default(1)
});

const patchLogSchema = logSchema.partial().extend({
  amountMl: z.number().finite().positive().max(10000)
});

const logIdParamSchema = z.object({
  id: z.string().uuid('id must be a UUID')
});

const summaryQuerySchema = z.object({
  date: dateQuery,
  tz: z.string().trim().min(1).max(100).optional()
});

const progressQuerySchema = z.object({
  from: dateQuery,
  to: dateQuery,
  tz: z.string().trim().min(1).max(100).optional()
});

function authContext(res: Response) {
  const auth = res.locals.auth as { userId?: string; authProvider?: string | null; email?: string | null } | undefined;
  if (!auth?.userId) throw new ApiError(401, 'UNAUTHORIZED', 'Missing user identity');
  return {
    userId: auth.userId,
    authProvider: auth.authProvider,
    userEmail: auth.email
  };
}

router.post('/parse', (req, res, next) => {
  try {
    const body = parseHydrationSchema.parse(req.body);
    res.status(200).json(parseHydrationText(body.text));
  } catch (error) {
    next(error);
  }
});

router.get('/goal', async (_req, res, next) => {
  try {
    const auth = authContext(res);
    const goal = await getHydrationGoal(auth.userId);
    res.status(200).json({ goal });
  } catch (error) {
    next(error);
  }
});

router.put('/goal', async (req, res, next) => {
  try {
    const auth = authContext(res);
    const body = goalSchema.parse(req.body);
    const goal = await upsertHydrationGoal(auth.userId, body.dailyGoalMl, auth);
    res.status(200).json({ goal });
  } catch (error) {
    next(error);
  }
});

router.delete('/goal', async (_req, res, next) => {
  try {
    const auth = authContext(res);
    const result = await deleteHydrationGoal(auth.userId);
    res.status(200).json(result);
  } catch (error) {
    next(error);
  }
});

router.post('/logs', async (req, res, next) => {
  try {
    const auth = authContext(res);
    const body = logSchema.parse(req.body);
    const log = await saveHydrationLog({
      userId: auth.userId,
      auth,
      loggedAt: body.loggedAt,
      rawText: body.rawText,
      amountMl: body.amountMl,
      inputAmount: body.inputAmount,
      inputUnit: body.inputUnit,
      source: body.source as HydrationSource,
      confidence: body.confidence
    });
    res.status(201).json({ log });
  } catch (error) {
    next(error);
  }
});

router.patch('/logs/:id', async (req, res, next) => {
  try {
    const auth = authContext(res);
    const params = logIdParamSchema.parse(req.params);
    const body = patchLogSchema.parse(req.body);
    const log = await updateHydrationLog({
      userId: auth.userId,
      logId: params.id,
      loggedAt: body.loggedAt,
      rawText: body.rawText,
      amountMl: body.amountMl,
      inputAmount: body.inputAmount,
      inputUnit: body.inputUnit,
      source: body.source as HydrationSource | undefined,
      confidence: body.confidence
    });
    res.status(200).json({ log });
  } catch (error) {
    next(error);
  }
});

router.delete('/logs/:id', async (req, res, next) => {
  try {
    const auth = authContext(res);
    const params = logIdParamSchema.parse(req.params);
    const result = await deleteHydrationLog(auth.userId, params.id);
    res.status(200).json(result);
  } catch (error) {
    next(error);
  }
});

router.get('/day-summary', async (req, res, next) => {
  try {
    const auth = authContext(res);
    const query = summaryQuerySchema.parse(req.query);
    const summary = await getHydrationDaySummary(auth.userId, query.date, query.tz);
    res.status(200).json(summary);
  } catch (error) {
    next(error);
  }
});

router.get('/day-logs', async (req, res, next) => {
  try {
    const auth = authContext(res);
    const query = summaryQuerySchema.parse(req.query);
    const logs = await getHydrationDayLogs(auth.userId, query.date, query.tz);
    res.status(200).json(logs);
  } catch (error) {
    next(error);
  }
});

router.get('/progress', async (req, res, next) => {
  try {
    const auth = authContext(res);
    const query = progressQuerySchema.parse(req.query);
    const progress = await getHydrationProgress(auth.userId, query.from, query.to, query.tz);
    res.status(200).json(progress);
  } catch (error) {
    next(error);
  }
});

export default router;
