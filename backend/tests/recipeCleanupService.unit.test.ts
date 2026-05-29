import { describe, expect, test, vi } from 'vitest';
import { cleanupRecipeDraft } from '../src/services/recipeCleanupService.js';
import { scoreRecipeDraft } from '../src/services/recipeQualityScore.js';
import type { RecipeDraft } from '../src/services/recipeImportService.js';

// A deliberately noisy raw draft, mirroring what the scraper/reader emits:
// unstructured ingredient lines, a junk nutrition line + a "Jump to Recipe"
// line, and ALL instructions crammed into one prose blob.
function noisyRawDraft(): RecipeDraft {
  return {
    title: 'The BEST Ever Creamy Garlic Pasta!! | FoodBlog',
    sourceUrl: 'https://foodblog.example/garlic-pasta',
    sourceDomain: 'foodblog.example',
    sourceName: 'FoodBlog',
    heroImageUrl: 'https://foodblog.example/img/pasta.jpg',
    description: 'This is hands down the best pasta you will ever make, trust me, keep reading!',
    servings: '4 servings',
    prepTime: '10 mins',
    cookTime: '15 mins',
    totalTime: '25 mins',
    categories: [],
    cuisines: [],
    keywords: [],
    ingredients: [
      { rawText: '8 oz spaghetti', quantityText: null, unitText: null, ingredientName: null },
      { rawText: '4 cloves garlic minced', quantityText: null, unitText: null, ingredientName: null },
      { rawText: '2 tbsp butter', quantityText: null, unitText: null, ingredientName: null },
      { rawText: '1 cup heavy cream', quantityText: null, unitText: null, ingredientName: null },
      { rawText: 'Jump to Recipe', quantityText: null, unitText: null, ingredientName: null },
      { rawText: 'Calories 520 kcal Protein 12g Fat 28g', quantityText: null, unitText: null, ingredientName: null },
    ],
    steps: [
      { text: 'Cook the spaghetti in salted boiling water until al dente then in a pan melt the butter and add the garlic cooking until fragrant before pouring in the cream and simmering until thickened then toss the drained pasta in the sauce and season to taste and serve immediately with parmesan on top.' },
    ],
    confidence: 0.92,
    warnings: [],
  };
}

// What a well-behaved Gemini cleanup returns for the draft above.
const CANNED_CLEAN_JSON = JSON.stringify({
  title: 'Creamy Garlic Pasta',
  description: 'A quick creamy garlic spaghetti.',
  ingredients: [
    { quantity: '8', unit: 'oz', name: 'spaghetti', raw: '8 oz spaghetti' },
    { quantity: '4', unit: 'cloves', name: 'garlic, minced', raw: '4 cloves garlic, minced' },
    { quantity: '2', unit: 'tbsp', name: 'butter', raw: '2 tbsp butter' },
    { quantity: '1', unit: 'cup', name: 'heavy cream', raw: '1 cup heavy cream' },
  ],
  steps: [
    'Cook the spaghetti in salted boiling water until al dente.',
    'Melt the butter in a pan and add the garlic; cook until fragrant.',
    'Pour in the cream and simmer until thickened.',
    'Toss the drained pasta in the sauce, season to taste, and serve with parmesan.',
  ],
});

function fakeGenerate(jsonText: string) {
  return vi.fn().mockResolvedValue({ jsonText, usage: { model: 'test', inputTokens: 100, outputTokens: 200 } });
}

describe('cleanupRecipeDraft — happy path', () => {
  test('populates structured fields, drops junk, splits steps, cleans title', async () => {
    const raw = noisyRawDraft();
    const { cleaned, changed } = await cleanupRecipeDraft(raw, { generate: fakeGenerate(CANNED_CLEAN_JSON) });

    expect(changed).toBe(true);
    // Junk lines gone (6 → 4).
    expect(cleaned.ingredients).toHaveLength(4);
    // Structured fields populated.
    expect(cleaned.ingredients[0]).toMatchObject({ quantityText: '8', unitText: 'oz', ingredientName: 'spaghetti' });
    // Prose blob split into multiple steps.
    expect(cleaned.steps.length).toBeGreaterThanOrEqual(4);
    // Title cleaned.
    expect(cleaned.title).toBe('Creamy Garlic Pasta');
    // Non-text fields preserved.
    expect(cleaned.heroImageUrl).toBe(raw.heroImageUrl);
    expect(cleaned.servings).toBe('4 servings');
  });

  test('cleaned draft scores materially higher than the raw draft', async () => {
    const raw = noisyRawDraft();
    const rawScore = scoreRecipeDraft(raw).overall;
    const { cleaned } = await cleanupRecipeDraft(raw, { generate: fakeGenerate(CANNED_CLEAN_JSON) });
    const cleanedScore = scoreRecipeDraft(cleaned).overall;

    expect(cleanedScore).toBeGreaterThan(rawScore);
    // The raw draft is poor/fair; the cleaned one should reach the good+ band.
    expect(cleanedScore).toBeGreaterThanOrEqual(85);
  });

  test('tolerates markdown-fenced JSON', async () => {
    const fenced = '```json\n' + CANNED_CLEAN_JSON + '\n```';
    const { changed, cleaned } = await cleanupRecipeDraft(noisyRawDraft(), { generate: fakeGenerate(fenced) });
    expect(changed).toBe(true);
    expect(cleaned.ingredients).toHaveLength(4);
  });
});

describe('cleanupRecipeDraft — guardrails (never make it worse)', () => {
  test('LLM unavailable (null) returns the original untouched', async () => {
    const raw = noisyRawDraft();
    const generate = vi.fn().mockResolvedValue(null);
    const { changed, cleaned, skippedReason } = await cleanupRecipeDraft(raw, { generate });
    expect(changed).toBe(false);
    expect(skippedReason).toBe('llm_unavailable');
    expect(cleaned).toBe(raw);
  });

  test('unparseable JSON returns the original untouched', async () => {
    const { changed, skippedReason } = await cleanupRecipeDraft(noisyRawDraft(), { generate: fakeGenerate('not json at all') });
    expect(changed).toBe(false);
    expect(skippedReason).toBe('llm_parse_error');
  });

  test('LLM that empties out ingredients is rejected (keeps raw)', async () => {
    const emptied = JSON.stringify({ title: 'X', ingredients: [], steps: [] });
    const raw = noisyRawDraft();
    const { changed, cleaned, skippedReason } = await cleanupRecipeDraft(raw, { generate: fakeGenerate(emptied) });
    expect(changed).toBe(false);
    expect(skippedReason).toBe('llm_unusable');
    expect(cleaned.ingredients).toHaveLength(6);
  });

  test('LLM that drops all steps falls back to the original steps', async () => {
    const noSteps = JSON.stringify({
      title: 'Creamy Garlic Pasta',
      ingredients: [{ quantity: '8', unit: 'oz', name: 'spaghetti', raw: '8 oz spaghetti' }],
      steps: [],
    });
    const raw = noisyRawDraft();
    const { changed, cleaned } = await cleanupRecipeDraft(raw, { generate: fakeGenerate(noSteps) });
    expect(changed).toBe(true);
    // Steps weren't provided by the LLM, so the original step survives.
    expect(cleaned.steps).toEqual(raw.steps);
  });
});
