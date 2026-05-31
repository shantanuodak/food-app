import { afterEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };

afterEach(() => {
  vi.resetModules();
  vi.restoreAllMocks();
  process.env = { ...baseEnv };
});

function useTestDatabaseUrl() {
  process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
}

describe('recipeImportService.structureRecipeText', () => {
  test('preserves heuristic steps when extraction-first returns no instructions', async () => {
    useTestDatabaseUrl();

    const extractRecipeFromText = vi.fn().mockResolvedValue({
      title: 'Mediterranean Bowl',
      sourceUrl: 'https://instagram.com/p/abc',
      sourceDomain: 'instagram.com',
      sourceName: 'Chef',
      heroImageUrl: null,
      description: null,
      servings: null,
      prepTime: null,
      cookTime: null,
      totalTime: null,
      categories: [],
      cuisines: [],
      keywords: [],
      ingredients: [
        {
          rawText: '1 cucumber, chopped',
          quantityText: '1',
          unitText: null,
          ingredientName: 'cucumber, chopped'
        }
      ],
      steps: [],
      confidence: 0.7,
      warnings: ['Imported from shared text. Review before saving.']
    });

    vi.doMock('../src/services/recipeCleanupService.js', () => ({
      cleanupRecipeDraft: vi.fn(),
      extractRecipeFromText
    }));
    vi.doMock('../src/services/recipeAudioImportService.js', () => ({
      buildRecipeDraftFromTranscript: vi.fn().mockReturnValue({
        title: 'Chicken',
        sourceUrl: 'https://instagram.com/p/abc',
        sourceDomain: 'instagram.com',
        sourceName: 'Chef',
        heroImageUrl: null,
        description: null,
        servings: null,
        prepTime: null,
        cookTime: null,
        totalTime: null,
        categories: [],
        cuisines: [],
        keywords: [],
        ingredients: [
          {
            rawText: '1 cucumber',
            quantityText: '1',
            unitText: null,
            ingredientName: 'cucumber'
          }
        ],
        steps: [{ text: 'Mix and serve.' }],
        confidence: 0.4,
        warnings: ['Imported from shared text. Review before saving.']
      })
    }));

    const { structureRecipeText } = await import('../src/services/recipeImportService.js');
    const result = await structureRecipeText({
      userId: '11111111-1111-1111-1111-111111111111',
      text: 'Cucumber bowl. Mix and serve.',
      sourceUrl: 'https://instagram.com/p/abc',
      sourceName: 'Chef'
    });

    expect(extractRecipeFromText).toHaveBeenCalledTimes(1);
    expect(result.draft.title).toBe('Mediterranean Bowl');
    expect(result.draft.ingredients).toHaveLength(1);
    expect(result.draft.steps).toEqual([{ text: 'Mix and serve.' }]);
  });
});
