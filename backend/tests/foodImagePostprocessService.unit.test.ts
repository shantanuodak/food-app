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

  test('does not override packaged-product estimates with baked-in facts', () => {
    const processed = postProcessFoodImageResult(
      result([
        item({
          name: 'RXBAR Blueberry Protein Bar',
          unit: 'bar',
          grams: 52,
          calories: 210,
          protein: 12,
          carbs: 23,
          fat: 9,
          matchConfidence: 0.98
        })
      ]),
      {
        imageType: 'nutrition_label',
        extractedText: 'RXBAR Blueberry Protein Bar, calories 180, protein 12g'
      }
    );

    expect(processed.items).toHaveLength(1);
    expect(processed.items[0]).toMatchObject({
      name: 'RXBAR Blueberry Protein Bar',
      quantity: 1,
      unit: 'bar',
      grams: 52,
      calories: 210,
      protein: 12,
      carbs: 23,
      fat: 9,
      needsClarification: false
    });
    expect(processed.items[0].nutritionSourceId).toBe('gemini_image_estimate');
    expect(processed.totals).toEqual({ calories: 210, protein: 12, carbs: 23, fat: 9 });
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

  test('collapses pizza parent and topping fragments into one display item', () => {
    const processed = postProcessFoodImageResult(
      result([
        item({ name: 'Pizza', calories: 266, protein: 11, carbs: 32, fat: 11, matchConfidence: 0.78 }),
        item({ name: 'Cheese', calories: 113, protein: 7, carbs: 1, fat: 9, matchConfidence: 0.8 }),
        item({ name: 'Small Pizza', calories: 1064, protein: 44, carbs: 128, fat: 42, matchConfidence: 0.9 }),
        item({ name: 'Olives', calories: 35, protein: 0.3, carbs: 2, fat: 3, matchConfidence: 0.8 }),
        item({ name: 'Jalapeno', calories: 4, protein: 0.1, carbs: 1, fat: 0, matchConfidence: 0.8 }),
        item({ name: 'Corn', calories: 86, protein: 2.5, carbs: 19, fat: 1, matchConfidence: 0.8 })
      ]),
      {
        imageType: 'multi_component_meal',
        extractedText: 'Pizza, cheese, small pizza, olives, jalapeno, corn'
      }
    );

    expect(processed.items.map((parsedItem) => parsedItem.name)).toEqual(['Small Pizza']);
    expect(processed.items[0].foodDescription).toContain('Cheese');
    expect(processed.totals.calories).toBe(1064);
  });

  test('collapses Indian savory bowl aliases and garnish while preserving sev calories', () => {
    const processed = postProcessFoodImageResult(
      result([
        item({ name: 'Upma', calories: 280, protein: 8, carbs: 42, fat: 9, matchConfidence: 0.78 }),
        item({ name: 'Indian Savory Bowl', calories: 450, protein: 12, carbs: 70, fat: 14, matchConfidence: 0.7 }),
        item({ name: 'Poha', calories: 250, protein: 6, carbs: 45, fat: 6, matchConfidence: 0.72 }),
        item({ name: 'Sev', calories: 130, protein: 4, carbs: 12, fat: 8, matchConfidence: 0.8 }),
        item({ name: 'Onion', calories: 16, protein: 0.4, carbs: 4, fat: 0, matchConfidence: 0.7 }),
        item({ name: 'Cilantro', calories: 1, protein: 0, carbs: 0.1, fat: 0, matchConfidence: 0.7 }),
        item({ name: 'Tomato', calories: 11, protein: 0.5, carbs: 2, fat: 0, matchConfidence: 0.7 }),
        item({ name: 'Curry Leaves', calories: 5, protein: 0.3, carbs: 1, fat: 0, matchConfidence: 0.7 }),
        item({ name: 'Cooked Semolina Grains', calories: 150, protein: 4, carbs: 30, fat: 1, matchConfidence: 0.7 })
      ]),
      {
        imageType: 'multi_component_meal',
        extractedText: 'Upma, Indian savory bowl, upma or poha, sev, onion, cilantro, tomato, curry leaves, rice/semolina grains'
      }
    );

    expect(processed.items.map((parsedItem) => parsedItem.name)).toEqual(['Upma with sev']);
    expect(processed.totals.calories).toBe(410);
  });

  test('drops generic dinner plate containers when real foods are present', () => {
    const processed = postProcessFoodImageResult(
      result([
        item({ name: 'Roasted chicken', calories: 260, protein: 34, carbs: 0, fat: 13, matchConfidence: 0.9 }),
        item({ name: 'Dinner Plate', calories: 500, protein: 20, carbs: 50, fat: 20, matchConfidence: 0.6 }),
        item({ name: 'Mashed potatoes', calories: 210, protein: 4, carbs: 35, fat: 8, matchConfidence: 0.85 }),
        item({ name: 'Beetroot', calories: 60, protein: 1.5, carbs: 12, fat: 0.2, matchConfidence: 0.8 })
      ]),
      {
        imageType: 'multi_component_meal',
        extractedText: 'Roasted chicken, mashed potatoes, dinner plate, beetroot'
      }
    );

    expect(processed.items.map((parsedItem) => parsedItem.name)).toEqual(['Roasted chicken', 'Mashed potatoes', 'Beetroot']);
    expect(processed.totals.calories).toBe(530);
  });
});
