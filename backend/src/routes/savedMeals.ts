import { Router } from 'express';
import type { Response } from 'express';
import { z } from 'zod';
import {
  createSavedMeal,
  createSavedMealCollection,
  listSavedMeals,
  logSavedMeal
} from '../services/savedMealsService.js';
import { ApiError } from '../utils/errors.js';

const router = Router();

const totalsSchema = z.object({
  calories: z.number().finite().min(0),
  protein: z.number().finite().min(0),
  carbs: z.number().finite().min(0),
  fat: z.number().finite().min(0)
});

const mealItemSchema = z.object({
  name: z.string().trim().min(1).max(180),
  quantity: z.number().finite().min(0),
  amount: z.number().finite().min(0).optional(),
  unit: z.string().trim().min(1).max(40),
  unitNormalized: z.string().trim().min(1).max(40).optional(),
  grams: z.number().finite().min(0),
  gramsPerUnit: z.number().finite().min(0).nullable().optional(),
  calories: z.number().finite().min(0),
  protein: z.number().finite().min(0),
  carbs: z.number().finite().min(0),
  fat: z.number().finite().min(0),
  nutritionSourceId: z.string().trim().min(1).max(160),
  originalNutritionSourceId: z.string().trim().max(160).optional(),
  sourceFamily: z.string().trim().max(40).optional(),
  matchConfidence: z.number().finite().min(0).max(1),
  needsClarification: z.boolean().nullable().optional(),
  manualOverride: z.unknown().optional()
});

const mealPayloadSchema = z.object({
  rawText: z.string().trim().min(1).max(4000),
  loggedAt: z.string().trim().max(80).optional(),
  inputKind: z.string().trim().max(40).nullable().optional(),
  imageRef: z.string().trim().max(500).nullable().optional(),
  confidence: z.number().finite().min(0).max(1),
  totals: totalsSchema,
  sourcesUsed: z.array(z.string().trim().max(40)).nullable().optional(),
  assumptions: z.array(z.string().trim().max(500)).nullable().optional(),
  items: z.array(mealItemSchema).min(1).max(40)
});

const collectionSchema = z.object({
  name: z.string().trim().min(1).max(80)
});

const saveMealSchema = z.object({
  name: z.string().trim().min(1).max(120),
  collectionId: z.string().uuid().nullable().optional(),
  collectionName: z.string().trim().min(1).max(80).nullable().optional(),
  mealPayload: mealPayloadSchema
});

const savedMealIdParamSchema = z.object({
  id: z.string().uuid()
});

const logSavedMealSchema = z.object({
  loggedAt: z.string().datetime()
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

router.get('/', async (_req, res, next) => {
  try {
    const auth = authContext(res);
    const result = await listSavedMeals(auth.userId, auth);
    res.json(result);
  } catch (error) {
    next(error);
  }
});

router.post('/collections', async (req, res, next) => {
  try {
    const auth = authContext(res);
    const body = collectionSchema.parse(req.body);
    const collection = await createSavedMealCollection(auth.userId, body.name, auth);
    res.status(201).json({ collection });
  } catch (error) {
    next(error);
  }
});

router.post('/', async (req, res, next) => {
  try {
    const auth = authContext(res);
    const body = saveMealSchema.parse(req.body);
    const meal = await createSavedMeal({
      userId: auth.userId,
      auth,
      collectionId: body.collectionId ?? null,
      collectionName: body.collectionName ?? null,
      name: body.name,
      mealPayload: body.mealPayload
    });
    res.status(201).json({ meal });
  } catch (error) {
    next(error);
  }
});

router.post('/:id/log', async (req, res, next) => {
  try {
    const auth = authContext(res);
    const params = savedMealIdParamSchema.parse(req.params);
    const body = logSavedMealSchema.parse(req.body);
    const saved = await logSavedMeal({
      userId: auth.userId,
      auth,
      savedMealId: params.id,
      loggedAt: body.loggedAt
    });
    res.status(201).json(saved);
  } catch (error) {
    next(error);
  }
});

export default router;
