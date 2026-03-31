import { Router } from 'express';
import { z } from 'zod';
import { upsertActivitySnapshot, getActivitySnapshot } from '../services/healthActivityService.js';
import { ApiError } from '../utils/errors.js';

const router = Router();

const upsertSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be YYYY-MM-DD'),
  steps: z.number().finite().min(0),
  activeEnergyKcal: z.number().finite().min(0),
});

const getQuerySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be YYYY-MM-DD'),
});

router.post('/activity', async (req, res, next) => {
  try {
    const userId = res.locals.auth?.userId as string | undefined;
    if (!userId) throw new ApiError(401, 'UNAUTHORIZED', 'Missing user identity');

    const body = upsertSchema.parse(req.body);
    const snapshot = await upsertActivitySnapshot(userId, body.date, body.steps, body.activeEnergyKcal);
    res.json(snapshot);
  } catch (err) {
    next(err);
  }
});

router.get('/activity', async (req, res, next) => {
  try {
    const userId = res.locals.auth?.userId as string | undefined;
    if (!userId) throw new ApiError(401, 'UNAUTHORIZED', 'Missing user identity');

    const query = getQuerySchema.parse(req.query);
    const snapshot = await getActivitySnapshot(userId, query.date);
    if (!snapshot) {
      res.json({ date: query.date, steps: 0, activeEnergyKcal: 0 });
      return;
    }
    res.json(snapshot);
  } catch (err) {
    next(err);
  }
});

export default router;
