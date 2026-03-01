import { Router } from 'express';
import { z } from 'zod';
import { ApiError } from '../utils/errors.js';
import { getOnboardingProvenance, upsertOnboarding } from '../services/onboardingService.js';

const router = Router();

function isValidTimezone(value: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

const onboardingSchema = z.object({
  goal: z.enum(['lose', 'maintain', 'gain']),
  dietPreference: z.string().min(1).max(255),
  allergies: z.array(z.string().min(1).max(50)).max(30).default([]),
  units: z.enum(['metric', 'imperial']),
  activityLevel: z.enum(['low', 'moderate', 'high']),
  timezone: z
    .string()
    .trim()
    .min(1)
    .max(100)
    .refine((value) => isValidTimezone(value), 'timezone must be a valid IANA timezone')
    .default('UTC')
});

router.post('/', async (req, res, next) => {
  try {
    const body = onboardingSchema.parse(req.body);
    const auth = res.locals.auth as { userId: string; authProvider?: string; email?: string | null };

    const response = await upsertOnboarding({
      userId: auth.userId,
      authProvider: auth.authProvider,
      userEmail: auth.email,
      goal: body.goal,
      dietPreference: body.dietPreference,
      allergies: body.allergies,
      units: body.units,
      activityLevel: body.activityLevel,
      timezone: body.timezone
    });

    res.status(200).json(response);
  } catch (err) {
    next(err);
  }
});

router.get('/provenance', async (req, res, next) => {
  try {
    const auth = res.locals.auth as { userId: string };
    const provenance = await getOnboardingProvenance(auth.userId);
    if (!provenance) {
      throw new ApiError(404, 'ONBOARDING_NOT_FOUND', 'Onboarding profile not found');
    }
    res.status(200).json(provenance);
  } catch (err) {
    next(err);
  }
});

export default router;
