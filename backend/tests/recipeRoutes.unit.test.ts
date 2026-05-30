import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const TEST_USER_ID = '11111111-1111-1111-1111-111111111111';

const structureRecipeText = vi.fn();
const importRecipeFromUrl = vi.fn();
const importRecipeFromAudio = vi.fn();
const listRecipes = vi.fn();
const saveRecipe = vi.fn();
const deleteRecipe = vi.fn();

vi.mock('../src/services/recipeImportService.js', () => ({
  structureRecipeText,
  importRecipeFromUrl,
  listRecipes,
  saveRecipe,
  deleteRecipe
}));

vi.mock('../src/services/recipeAudioImportService.js', () => ({
  importRecipeFromAudio
}));

// Inject an authenticated user without touching the DB. The real authRequired
// middleware verifies a token and runs a DB-bound auth context, so we replace
// it with a stub that just populates res.locals.auth the way the dev path does.
vi.mock('../src/middleware/auth.js', () => ({
  authRequired: (_req: unknown, res: { locals: Record<string, unknown> }, next: () => void) => {
    res.locals.auth = { userId: TEST_USER_ID, authProvider: 'dev', email: `${TEST_USER_ID}@dev.local` };
    next();
  }
}));

const { createApp } = await import('../src/app.js');
const { ApiError } = await import('../src/utils/errors.js');
const { resetRecipeImportRateLimitStateForTests } = await import(
  '../src/services/recipeImportRateLimiterService.js'
);

describe('POST /v1/recipes/structure-text', () => {
  beforeEach(() => {
    resetRecipeImportRateLimitStateForTests();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('structures raw caption text into a draft and returns 201', async () => {
    structureRecipeText.mockResolvedValue({ draft: { title: 'Caption Soup' } });

    const response = await request(createApp())
      .post('/v1/recipes/structure-text')
      .send({
        text: '2 cups flour\n1 tsp salt\nMix and bake.',
        sourceUrl: 'https://instagram.com/p/abc',
        sourceName: 'Chef'
      });

    expect(response.status).toBe(201);
    expect(response.body).toEqual({ draft: { title: 'Caption Soup' } });
    expect(structureRecipeText).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: TEST_USER_ID,
        text: '2 cups flour\n1 tsp salt\nMix and bake.',
        sourceUrl: 'https://instagram.com/p/abc',
        sourceName: 'Chef',
        heroImageUrl: null
      })
    );
    const callArg = structureRecipeText.mock.calls[0]![0] as { auth?: { userId?: string } };
    expect(callArg.auth?.userId).toBe(TEST_USER_ID);
  });

  it('rejects an empty caption with 400 and never calls the service', async () => {
    const response = await request(createApp())
      .post('/v1/recipes/structure-text')
      .send({ text: '', sourceUrl: 'https://instagram.com/p/abc' });

    expect(response.status).toBe(400);
    expect(structureRecipeText).not.toHaveBeenCalled();
  });

  it('propagates a 422 "no ingredients" ApiError from the service', async () => {
    structureRecipeText.mockRejectedValue(
      new ApiError(
        422,
        'RECIPE_AUDIO_NO_RECIPE_TEXT',
        'Audio transcript did not include enough ingredient details'
      )
    );

    const response = await request(createApp())
      .post('/v1/recipes/structure-text')
      .send({ text: 'follow me for more videos', sourceUrl: 'https://tiktok.com/@x/video/1' });

    expect(response.status).toBe(422);
    expect(response.body.error?.code ?? response.body.code).toBe('RECIPE_AUDIO_NO_RECIPE_TEXT');
    expect(structureRecipeText).toHaveBeenCalledTimes(1);
  });
});
