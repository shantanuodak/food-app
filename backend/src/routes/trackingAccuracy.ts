import { Router } from 'express';
import { z } from 'zod';
import { getTrackingAccuracy } from '../services/trackingAccuracyService.js';

const router = Router();

const querySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be YYYY-MM-DD'),
  tz: z.string().trim().min(1).max(100).optional()
});

router.get('/tracking-accuracy', async (req, res, next) => {
  try {
    const userId = (res.locals.auth as { userId: string }).userId;
    const query = querySchema.parse(req.query);
    const timezone = query.tz || 'UTC';
    const summary = await getTrackingAccuracy(userId, query.date, timezone);
    res.json(summary);
  } catch (err) {
    next(err);
  }
});

export default router;
