import { Router } from 'express';
import type { NextFunction, Request, Response } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { importRecipeFromUrl, listRecipes, saveRecipe, deleteRecipe, structureRecipeText } from '../services/recipeImportService.js';
import { importRecipeFromAudio } from '../services/recipeAudioImportService.js';
import { config } from '../config.js';
import { ApiError } from '../utils/errors.js';
import {
  checkRecipeImportRateLimit,
  type RecipeRateLane
} from '../services/recipeImportRateLimiterService.js';

const router = Router();
const audioUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    files: 1,
    fileSize: config.recipeAudioMaxBytes
  }
});

const importFromUrlSchema = z.object({
  url: z.string().trim().min(1).max(3000)
});

const recipeIdParamSchema = z.object({
  id: z.string().uuid()
});

const structureTextSchema = z.object({
  text: z.string().trim().min(1).max(8000),
  sourceUrl: z.string().trim().min(1).max(3000),
  sourceName: z.string().trim().max(180).nullable().optional(),
  heroImageUrl: z.string().trim().max(1000).nullable().optional()
});

const importFromAudioSchema = z.object({
  sourceUrl: z.string().trim().min(1).max(3000),
  sourceName: z.string().trim().max(180).nullable().optional(),
  heroImageUrl: z.string().trim().max(1000).nullable().optional(),
  audioUrl: z.string().trim().max(3000).nullable().optional(),
  language: z.string().trim().min(2).max(12).nullable().optional()
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

function enforceRecipeRateLimit(userId: string, lane: RecipeRateLane): void {
  const result = checkRecipeImportRateLimit(userId, lane);
  if (!result.allowed) {
    const error = new ApiError(429, 'RECIPE_RATE_LIMITED', 'Too many recipe requests. Please retry shortly.');
    (error as ApiError & { retryAfterSeconds?: number }).retryAfterSeconds = result.retryAfterSeconds;
    throw error;
  }
}

function audioUploadMiddleware(req: Request, res: Response, next: NextFunction): void {
  audioUpload.single('audio')(req, res, (error: unknown) => {
    if (!error) {
      next();
      return;
    }

    if (error instanceof multer.MulterError) {
      if (error.code === 'LIMIT_FILE_SIZE') {
        next(new ApiError(413, 'RECIPE_AUDIO_FILE_TOO_LARGE', 'Audio file is too large'));
        return;
      }
      next(new ApiError(400, 'RECIPE_AUDIO_UPLOAD_INVALID', error.message));
      return;
    }

    next(error);
  });
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
    enforceRecipeRateLimit(auth.userId, 'url');
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

router.post('/structure-text', async (req, res, next) => {
  try {
    const auth = authContext(res);
    enforceRecipeRateLimit(auth.userId, 'url');
    const body = structureTextSchema.parse(req.body);
    const result = await structureRecipeText({
      userId: auth.userId,
      auth,
      text: body.text,
      sourceUrl: body.sourceUrl,
      sourceName: body.sourceName ?? null,
      heroImageUrl: body.heroImageUrl ?? null
    });
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
});

router.post('/import-from-audio', audioUploadMiddleware, async (req, res, next) => {
  try {
    const auth = authContext(res);
    enforceRecipeRateLimit(auth.userId, 'audio');
    const body = importFromAudioSchema.parse(req.body);
    const audioFile = req.file
      ? {
          buffer: req.file.buffer,
          mimeType: req.file.mimetype,
          filename: req.file.originalname || 'recipe-audio.m4a'
        }
      : undefined;

    const result = await importRecipeFromAudio({
      userId: auth.userId,
      auth,
      sourceUrl: body.sourceUrl,
      sourceName: body.sourceName ?? null,
      heroImageUrl: body.heroImageUrl ?? null,
      audioUrl: body.audioUrl ?? null,
      language: body.language ?? null,
      audio: audioFile
    });
    res.status(201).json(result);
  } catch (error) {
    next(error);
  }
});

router.post('/', async (req, res, next) => {
  try {
    const auth = authContext(res);
    enforceRecipeRateLimit(auth.userId, 'save');
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

router.delete('/:id', async (req, res, next) => {
  try {
    const auth = authContext(res);
    enforceRecipeRateLimit(auth.userId, 'save');
    const params = recipeIdParamSchema.parse(req.params);
    const result = await deleteRecipe(auth.userId, params.id);
    res.json(result);
  } catch (error) {
    next(error);
  }
});

export default router;
