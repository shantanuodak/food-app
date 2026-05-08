import { Router } from 'express';
import { z } from 'zod';
import { getRewardsSummary } from '../services/rewardsService.js';
import { ApiError } from '../utils/errors.js';

const router = Router();

const summaryQuerySchema = z.object({
  tz: z.string().trim().min(1).max(100).optional()
});

router.get('/summary', async (req, res, next) => {
  try {
    const userId = res.locals.auth?.userId as string | undefined;
    if (!userId) throw new ApiError(401, 'UNAUTHORIZED', 'Missing user identity');

    const query = summaryQuerySchema.parse(req.query);
    const summary = await getRewardsSummary(userId, query.tz);
    res.json(summary);
  } catch (err) {
    next(err);
  }
});

export default router;
