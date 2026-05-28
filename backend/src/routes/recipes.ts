import { Router } from 'express';
import type { Response } from 'express';
import { z } from 'zod';
import { importRecipeFromUrl, listRecipes, saveRecipe } from '../services/recipeImportService.js';
import { ApiError } from '../utils/errors.js';

const router = Router();

const importFromUrlSchema = z.object({
  url: z.string().trim().min(1).max(3000)
});

const recipeIngredientSchema = z.object({
  rawText: z.string().trim().min(1).max(700),
  quantityText: z.string().trim().max(120).nullable().optional(),
  unitText: z.string().trim().max(80).nullable().optional(),
  ingredientName: z.string().trim().max(220).nullable().optional()
});

const recipeStepSchema = z.object({
  text: z.string().trim().min(1).max(2000)
});

const reviewedRecipeSchema = z.object({
  importId: z.string().uuid().nullable().optional(),
  title: z.string().trim().min(1).max(180),
  sourceUrl: z.string().trim().min(1).max(3000),
  sourceName: z.string().trim().max(180).nullable().optional(),
  heroImageUrl: z.string().trim().max(1000).nullable().optional(),
  description: z.string().trim().max(2000).nullable().optional(),
  servings: z.string().trim().max(120).nullable().optional(),
  prepTime: z.string().trim().max(120).nullable().optional(),
  cookTime: z.string().trim().max(120).nullable().optional(),
  totalTime: z.string().trim().max(120).nullable().optional(),
  categories: z.array(z.string().trim().min(1).max(80)).max(20).optional(),
  cuisines: z.array(z.string().trim().min(1).max(80)).max(20).optional(),
  keywords: z.array(z.string().trim().min(1).max(80)).max(30).optional(),
  ingredients: z.array(recipeIngredientSchema).min(1).max(120),
  steps: z.array(recipeStepSchema).max(200).optional(),
  nutrition: z.unknown().optional()
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
    const result = await listRecipes(auth.userId);
    res.json(result);
  } catch (error) {
    next(error);
  }
});

router.post('/import-from-url', async (req, res, next) => {
  try {
    const auth = authContext(res);
    const body = importFromUrlSchema.parse(req.body);
    const result = await importRecipeFromUrl({
      userId: auth.userId,
      auth,
      url: body.url
    });
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
});

router.post('/', async (req, res, next) => {
  try {
    const auth = authContext(res);
    const body = reviewedRecipeSchema.parse(req.body);
    const recipe = await saveRecipe({
      userId: auth.userId,
      auth,
      recipe: {
        importId: body.importId ?? null,
        title: body.title,
        sourceUrl: body.sourceUrl,
        sourceName: body.sourceName ?? null,
        heroImageUrl: body.heroImageUrl ?? null,
        description: body.description ?? null,
        servings: body.servings ?? null,
        prepTime: body.prepTime ?? null,
        cookTime: body.cookTime ?? null,
        totalTime: body.totalTime ?? null,
        categories: body.categories ?? [],
        cuisines: body.cuisines ?? [],
        keywords: body.keywords ?? [],
        ingredients: body.ingredients.map((ingredient) => ({
          rawText: ingredient.rawText,
          quantityText: ingredient.quantityText ?? null,
          unitText: ingredient.unitText ?? null,
          ingredientName: ingredient.ingredientName ?? null
        })),
        steps: (body.steps ?? []).map((step) => ({ text: step.text })),
        nutrition: body.nutrition
      }
    });
    res.status(201).json({ recipe });
  } catch (error) {
    next(error);
  }
});

export default router;
