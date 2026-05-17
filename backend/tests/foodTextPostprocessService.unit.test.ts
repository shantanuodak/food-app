import { describe, expect, test } from 'vitest';
import type { ParseResult } from '../src/services/deterministicParser.js';
import { postProcessFoodTextResult } from '../src/services/foodTextPostprocessService.js';

function item(overrides: Partial<ParseResult['items'][number]>): ParseResult['items'][number] {
  return {
    name: 'Food',
    quantity: 1,
    unit: 'serving',
    grams: 100,
    calories: 100,
    protein: 5,
    carbs: 10,
    fat: 4,
    matchConfidence: 0.9,
    nutritionSourceId: 'gemini_estimate',
    sourceFamily: 'gemini',
    originalNutritionSourceId: 'gemini_estimate',
    explanation: 'Estimated from the entered food item.',
    ...overrides
  };
}

function result(items: ParseResult['items']): ParseResult {
  return {
    confidence: 0.9,
    assumptions: [],
    items,
    totals: {
      calories: items.reduce((sum, current) => sum + current.calories, 0),
      protein: items.reduce((sum, current) => sum + current.protein, 0),
      carbs: items.reduce((sum, current) => sum + current.carbs, 0),
      fat: items.reduce((sum, current) => sum + current.fat, 0)
    }
  };
}

describe('postProcessFoodTextResult', () => {
  test('collapses product flavor fragments into the packaged product', () => {
    const parsed = result([
      item({
        name: 'Mixed Berry Vanilla Protein Drink',
        unit: 'bottle',
        calories: 160,
        protein: 30,
        carbs: 5,
        fat: 3
      }),
      item({
        name: 'Mixed Berry Vanilla Greek Yogurt',
        unit: 'cup',
        calories: 185,
        protein: 20,
        carbs: 26,
        fat: 0
      }),
      item({
        name: 'Mixed Berries',
        unit: 'cup',
        calories: 80,
        protein: 1,
        carbs: 20,
        fat: 0.5
      })
    ]);

    const cleaned = postProcessFoodTextResult('mixed berry vanilla protein drink', parsed);

    expect(cleaned.items).toHaveLength(1);
    expect(cleaned.items[0].name).toBe('Mixed Berry Vanilla Protein Drink');
    expect(cleaned.totals.calories).toBe(160);
  });

  test('repairs mango chutney when Gemini splits it into fruit and chutney fragments', () => {
    const parsed = result([
      item({ name: 'Mango', unit: 'medium', calories: 135, protein: 1, carbs: 35, fat: 1 }),
      item({ name: 'Chutney', unit: 'tbsp', calories: 30, protein: 0, carbs: 7, fat: 0 })
    ]);

    const cleaned = postProcessFoodTextResult('mango chutney with dal baati', parsed);

    expect(cleaned.items).toHaveLength(1);
    expect(cleaned.items[0].name).toBe('Mango chutney');
    expect(cleaned.totals.calories).toBe(30);
  });

  test('does not merge explicit text aliases that the user typed as separate foods', () => {
    const parsed = result([
      item({ name: 'Methi Paratha', calories: 230, protein: 6, carbs: 30, fat: 10 }),
      item({ name: 'Thepla', calories: 170, protein: 5, carbs: 25, fat: 6 })
    ]);

    const cleaned = postProcessFoodTextResult('methi paratha, thepla', parsed);

    expect(cleaned.items.map((current) => current.name)).toEqual(['Methi Paratha', 'Thepla']);
    expect(cleaned.totals.calories).toBe(400);
  });
});
