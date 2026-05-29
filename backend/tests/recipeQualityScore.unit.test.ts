import { describe, expect, test } from 'vitest';
import { scoreRecipeDraft } from '../src/services/recipeQualityScore.js';
import type { RecipeDraft } from '../src/services/recipeImportService.js';

function makeDraft(overrides: Partial<RecipeDraft> = {}): RecipeDraft {
  return {
    title: 'Weeknight Chicken Stir-Fry',
    sourceUrl: 'https://example.com/chicken-stir-fry',
    sourceDomain: 'example.com',
    sourceName: 'Example Kitchen',
    heroImageUrl: 'https://example.com/img/stir-fry.jpg',
    description: 'A fast, balanced stir-fry for busy weeknights.',
    servings: '4 servings',
    prepTime: '15 mins',
    cookTime: '12 mins',
    totalTime: '27 mins',
    categories: ['Dinner'],
    cuisines: ['Asian'],
    keywords: ['chicken', 'stir fry'],
    ingredients: [
      { rawText: '1 lb boneless chicken thighs, sliced', quantityText: null, unitText: null, ingredientName: null },
      { rawText: '2 tbsp soy sauce', quantityText: null, unitText: null, ingredientName: null },
      { rawText: '1 tbsp sesame oil', quantityText: null, unitText: null, ingredientName: null },
      { rawText: '3 cloves garlic, minced', quantityText: null, unitText: null, ingredientName: null },
      { rawText: '2 cups broccoli florets', quantityText: null, unitText: null, ingredientName: null },
      { rawText: 'Salt and pepper to taste', quantityText: null, unitText: null, ingredientName: null },
    ],
    steps: [
      { text: 'Heat the sesame oil in a large skillet over medium-high heat.' },
      { text: 'Add the chicken and cook until browned, about 5 minutes.' },
      { text: 'Stir in the garlic and broccoli and cook for 4 minutes.' },
      { text: 'Pour in the soy sauce, toss to coat, and serve hot.' },
    ],
    confidence: 0.92,
    warnings: [],
    ...overrides,
  };
}

describe('scoreRecipeDraft — clean recipe', () => {
  test('a clean, complete recipe scores in the excellent band', () => {
    const report = scoreRecipeDraft(makeDraft());
    expect(report.overall).toBeGreaterThanOrEqual(85);
    expect(report.band).toBe('excellent');
    // No high-severity defects on a clean recipe.
    expect(report.defects.filter((d) => d.severity === 'high')).toHaveLength(0);
  });

  test('"salt to taste" without a quantity does not tank parseability', () => {
    const report = scoreRecipeDraft(makeDraft());
    // 5 of 6 lines have a quantity → well above the 0.75 full-marks threshold.
    expect(report.dimensions.ingredientParseability).toBeGreaterThanOrEqual(0.9);
  });
});

describe('scoreRecipeDraft — structural failures', () => {
  test('missing steps zeroes stepIntegrity and emits steps_missing', () => {
    const report = scoreRecipeDraft(makeDraft({ steps: [] }));
    expect(report.dimensions.stepIntegrity).toBe(0);
    expect(report.defects.map((d) => d.code)).toContain('steps_missing');
    expect(report.overall).toBeLessThan(85);
  });

  test('single prose blob of instructions is flagged', () => {
    const blob = 'Heat the oil in a large skillet over medium-high heat and add the chicken, cooking it through until browned on all sides before adding the garlic and broccoli and continuing to cook for several more minutes, then pour the sauce over everything and stir well to combine, letting it simmer briefly so the flavors meld, and finally serve immediately while hot to your guests at the dinner table with steamed rice on the side.';
    const report = scoreRecipeDraft(makeDraft({ steps: [{ text: blob }] }));
    expect(report.defects.map((d) => d.code)).toContain('steps_prose_blob');
  });

  test('missing ingredients zeroes integrity + parseability', () => {
    const report = scoreRecipeDraft(makeDraft({ ingredients: [] }));
    expect(report.dimensions.ingredientIntegrity).toBe(0);
    expect(report.dimensions.ingredientParseability).toBe(0);
    expect(report.defects.map((d) => d.code)).toContain('ingredients_missing');
  });

  test('generic placeholder title is penalized', () => {
    const report = scoreRecipeDraft(makeDraft({ title: 'TikTok' }));
    expect(report.defects.map((d) => d.code)).toContain('title_generic');
    expect(report.dimensions.title).toBeLessThan(0.5);
  });
});

describe('scoreRecipeDraft — noise detection', () => {
  test('blog/ad/social cruft drives the recipe into the poor band', () => {
    const noisy = makeDraft({
      title: 'The BEST Ever EASY Chicken Stir-Fry!! 🔥🔥 #dinner #foodie',
      ingredients: [
        { rawText: '1 lb chicken', quantityText: null, unitText: null, ingredientName: null },
        { rawText: 'Jump to Recipe', quantityText: null, unitText: null, ingredientName: null },
        { rawText: 'Calories 320 kcal Protein 28g', quantityText: null, unitText: null, ingredientName: null },
        { rawText: 'https://amzn.to/buy-my-wok', quantityText: null, unitText: null, ingredientName: null },
      ],
      steps: [
        { text: 'Subscribe to my channel and follow me for more! 🔔' },
        { text: 'Heat oil and cook the chicken.' },
      ],
      heroImageUrl: null,
      servings: null,
      prepTime: null,
      cookTime: null,
      totalTime: null,
    });
    const report = scoreRecipeDraft(noisy);
    expect(report.band).toBe('poor');
    expect(report.overall).toBeLessThan(50);
    const codes = report.defects.map((d) => d.code);
    expect(codes).toContain('title_social_noise');
    expect(codes).toContain('ingredients_junk_lines');
    expect(codes).toContain('noise_phrase');
    expect(codes).toContain('steps_junk');
  });

  test('hashtags and emoji in steps register as noise', () => {
    const report = scoreRecipeDraft(makeDraft({
      steps: [
        { text: 'Heat the oil. 🍳 #cooking' },
        { text: 'Add the chicken and cook through.' },
      ],
    }));
    expect(report.dimensions.noiseFree).toBeLessThan(1);
    const codes = report.defects.map((d) => d.code);
    expect(codes).toContain('noise_hashtag');
  });
});

describe('scoreRecipeDraft — nutrition-fact false positives', () => {
  test('legit ingredients containing sugar/fat/protein are NOT flagged as junk', () => {
    const report = scoreRecipeDraft(makeDraft({
      ingredients: [
        { rawText: '1 cup granulated sugar', quantityText: null, unitText: null, ingredientName: null },
        { rawText: '2 tbsp brown sugar', quantityText: null, unitText: null, ingredientName: null },
        { rawText: '1 lb ground beef', quantityText: null, unitText: null, ingredientName: null },
        { rawText: '1 scoop protein powder', quantityText: null, unitText: null, ingredientName: null },
        { rawText: '2 tbsp coconut fat', quantityText: null, unitText: null, ingredientName: null },
      ],
    }));
    expect(report.defects.map((d) => d.code)).not.toContain('ingredients_junk_lines');
  });

  test('actual nutrition-fact lines ARE flagged as junk', () => {
    const report = scoreRecipeDraft(makeDraft({
      ingredients: [
        { rawText: '1 cup flour', quantityText: null, unitText: null, ingredientName: null },
        { rawText: 'Calories 520 Protein 12g Fat 28g', quantityText: null, unitText: null, ingredientName: null },
        { rawText: 'Sodium: 400mg', quantityText: null, unitText: null, ingredientName: null },
      ],
    }));
    expect(report.defects.map((d) => d.code)).toContain('ingredients_junk_lines');
  });
});

describe('scoreRecipeDraft — parseability gap flag', () => {
  test('flags that structured fields are never populated', () => {
    const report = scoreRecipeDraft(makeDraft());
    expect(report.defects.map((d) => d.code)).toContain('ingredients_unstructured_fields');
  });
});
