import { Router } from 'express';
import { z } from 'zod';
import { ApiError } from '../utils/errors.js';
import {
  defaultAdminFeatureFlags,
  getAdminFeatureFlagsForUser,
  upsertAdminFeatureFlags
} from '../services/adminFeatureFlagsService.js';
import { purgeParseCacheByScopePrefix } from '../services/parseCacheService.js';

const router = Router();

const flagsSchema = z.object({
  geminiEnabled: z.boolean(),
  fatsecretEnabled: z.boolean()
});

const purgeCacheSchema = z.object({
  scopePrefix: z.string().trim().min(3).max(300)
});

router.get('/', async (req, res, next) => {
  try {
    const auth = res.locals.auth as { userId: string; isAdmin: boolean };
    if (!auth.isAdmin) {
      res.status(200).json({ isAdmin: false });
      return;
    }

    const existing = await getAdminFeatureFlagsForUser(auth.userId);
    const flags = existing ?? defaultAdminFeatureFlags();
    res.status(200).json({ isAdmin: true, flags });
  } catch (err) {
    next(err);
  }
});

router.put('/', async (req, res, next) => {
  try {
    const auth = res.locals.auth as { userId: string; isAdmin: boolean };
    if (!auth.isAdmin) {
      throw new ApiError(403, 'FORBIDDEN', 'Admin access required');
    }
    const body = flagsSchema.parse(req.body);
    const flags = await upsertAdminFeatureFlags(auth.userId, body);
    res.status(200).json({ isAdmin: true, flags });
  } catch (err) {
    next(err);
  }
});

router.post('/purge-cache', async (req, res, next) => {
  try {
    const auth = res.locals.auth as { userId: string; isAdmin: boolean };
    if (!auth.isAdmin) {
      throw new ApiError(403, 'FORBIDDEN', 'Admin access required');
    }
    const body = purgeCacheSchema.parse(req.body);
    const deleted = await purgeParseCacheByScopePrefix(body.scopePrefix);
    res.status(200).json({
      status: 'ok',
      deleted
    });
  } catch (err) {
    next(err);
  }
});

export default router;
