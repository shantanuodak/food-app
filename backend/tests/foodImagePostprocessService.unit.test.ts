import { describe, expect, test } from 'vitest';
import type { ParseResult, ParsedItem } from '../src/services/deterministicParser.js';
import { postProcessFoodImageResult } from '../src/services/foodImagePostprocessService.js';

function item(overrides: Partial<ParsedItem> & Pick<ParsedItem, 'name' | 'calories'>): ParsedItem {
  return {
    name: overrides.name,
    quantity: overrides.quantity ?? 1,
    unit: overrides.unit ?? 'serving',
    grams: overrides.grams ?? 100,
    calories: overrides.calories,
    protein: overrides.protein ?? 1,
    carbs: overrides.carbs ?? 1,
    fat: overrides.fat ?? 1,
    matchConfidence: overrides.matchConfidence ?? 0.8,
    nutritionSourceId: overrides.nutritionSourceId ?? 'gemini_image_estimate',
    originalNutritionSourceId: overrides.originalNutritionSourceId ?? 'gemini_image_estimate',
    sourceFamily: overrides.sourceFamily ?? 'gemini',
    needsClarification: overrides.needsClarification ?? false,
    foodDescription: overrides.foodDescription ?? overrides.name,
    explanation: overrides.explanation ?? `Estimated ${overrides.name}.`,
    amount: overrides.amount ?? overrides.quantity ?? 1,
    unitNormalized: overrides.unitNormalized ?? overrides.unit ?? 'serving',
    gramsPerUnit: overrides.gramsPerUnit ?? overrides.grams ?? 100,
    manualOverride: overrides.manualOverride ?? false
  };
}

function result(items: ParsedItem[]): ParseResult {
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

describe('food image postprocessing', () => {
  test('keeps packaged protein drinks as one item instead of flavor fragments', () => {
    const processed = postProcessFoodImageResult(
      result([
        item({
          name: 'Mixed Berry Vanilla Protein Drink',
          unit: 'bottle',
          grams: 330,
          calories: 160,
          protein: 30,
          carbs: 5,
          fat: 3,
          matchConfidence: 0.95
        }),
        item({ name: 'Mixed Berry Vanilla Greek Yogurt', calories: 185, protein: 20, carbs: 26, fat: 0, matchConfidence: 0.8 }),
        item({ name: 'Mixed Berries', calories: 80, protein: 1, carbs: 20, fat: 0.5, matchConfidence: 0.9 })
      ]),
      {
        imageType: 'drink',
        extractedText: 'Mixed Berry Vanilla Protein Drink bottle',
        visibleComponents: [{ name: 'Mixed Berry Vanilla Protein Drink bottle', category: 'drink' }]
      }
    );

    expect(processed.items.map((parsedItem) => parsedItem.name)).toEqual(['Mixed Berry Vanilla Protein Drink']);
    expect(processed.totals).toEqual({ calories: 160, protein: 30, carbs: 5, fat: 3 });
  });

  test('does not collapse product-looking items when another separate food is visible', () => {
    const processed = postProcessFoodImageResult(
      result([
        item({ name: 'Protein shake', unit: 'bottle', calories: 180, protein: 30, carbs: 8, fat: 3 }),
        item({ name: 'Banana', unit: 'medium', calories: 105, protein: 1.3, carbs: 27, fat: 0.3 })
      ]),
      { imageType: 'multi_component_meal', extractedText: 'protein shake and banana' }
    );

    expect(processed.items.map((parsedItem) => parsedItem.name)).toEqual(['Protein shake', 'Banana']);
    expect(processed.totals.calories).toBe(285);
  });

  test('merges flatbread alias duplicates into one clean item', () => {
    const processed = postProcessFoodImageResult(
      result([
        item({ name: 'Methi Paratha', calories: 230, protein: 6, carbs: 30, fat: 10, matchConfidence: 0.86 }),
        item({ name: 'Fenugreek Paratha', calories: 200, protein: 5, carbs: 28, fat: 8, matchConfidence: 0.8 }),
        item({ name: 'Methi Flatbread', calories: 180, protein: 5, carbs: 26, fat: 7, matchConfidence: 0.76 }),
        item({ name: 'Thepla', calories: 170, protein: 5, carbs: 25, fat: 6, matchConfidence: 0.75 })
      ]),
      { imageType: 'tray_or_thali', extractedText: 'methi paratha, fenugreek paratha, thepla' }
    );

    expect(processed.items.map((parsedItem) => parsedItem.name)).toEqual(['Methi Paratha']);
    expect(processed.totals).toEqual({ calories: 230, protein: 6, carbs: 30, fat: 10 });
  });

  test('repairs savory Indian compound fragments without keeping standalone mango or potato', () => {
    const processed = postProcessFoodImageResult(
      result([
        item({ name: 'Mango', unit: 'medium', calories: 135, protein: 1, carbs: 35, fat: 1, matchConfidence: 0.78 }),
        item({ name: 'Potato', calories: 100, protein: 2, carbs: 20, fat: 1, matchConfidence: 0.75 }),
        item({ name: 'Dal', calories: 240, protein: 14, carbs: 38, fat: 6, matchConfidence: 0.9 })
      ]),
      {
        imageType: 'tray_or_thali',
        extractedText: 'dal, mango chutney, potato sabzi',
        visibleComponents: [
          { name: 'dal', category: 'lentil curry' },
          { name: 'mango chutney', category: 'condiment' },
          { name: 'potato sabzi', category: 'vegetable side' }
        ]
      }
    );

    expect(processed.items.map((parsedItem) => parsedItem.name)).toEqual(['Mango chutney', 'Potato sabzi', 'Dal']);
    expect(processed.items.map((parsedItem) => parsedItem.name)).not.toContain('Mango');
    expect(processed.items.map((parsedItem) => parsedItem.name)).not.toContain('Potato');
  });
});
