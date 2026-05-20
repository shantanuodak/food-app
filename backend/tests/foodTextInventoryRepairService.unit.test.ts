import { describe, expect, test } from 'vitest';
import type { ParseResult } from '../src/services/deterministicParser.js';
import {
  extractFoodTextInventoryForTests,
  repairFoodTextInventoryCoverage
} from '../src/services/foodTextInventoryRepairService.js';

function result(names: string[], calories = 500): ParseResult {
  const perItemCalories = names.length ? calories / names.length : 0;
  return {
    confidence: names.length ? 0.82 : 0,
    assumptions: [],
    items: names.map((name) => ({
      name,
      quantity: 1,
      amount: 1,
      unit: 'serving',
      unitNormalized: 'serving',
      grams: 100,
      gramsPerUnit: 100,
      calories: perItemCalories,
      protein: 5,
      carbs: 20,
      fat: 5,
      matchConfidence: 0.82,
      nutritionSourceId: 'gemini_estimate',
      originalNutritionSourceId: 'gemini_estimate',
      sourceFamily: 'gemini',
      needsClarification: false,
      manualOverride: false,
      foodDescription: name,
      explanation: 'Estimated from the entered food item.'
    })),
    totals: {
      calories,
      protein: names.length * 5,
      carbs: names.length * 20,
      fat: names.length * 5
    }
  };
}

describe('food text inventory repair', () => {
  test('extracts typo-heavy Indian meal components', () => {
    expect(extractFoodTextInventoryForTests('rajma chawl wth ghee papd and pyaz')).toEqual([
      'Rajma',
      'White rice',
      'Ghee',
      'Papad',
      'Onion salad'
    ]);
  });

  test('replaces collapsed parse with decomposed typed inventory', () => {
    const repaired = repairFoodTextInventoryCoverage(
      'dal baati churma thali with gatte ki sabzi, garlic chutney, onion salad and 1 cup chaas',
      result(['Churma powder', 'Garlic chutney', 'Onion'], 1360)
    );

    expect(repaired.items.map((item) => item.name)).toEqual([
      'Dal',
      'Baati',
      'Churma',
      'Gatte ki sabzi',
      'Garlic chutney',
      'Onion salad',
      'Chaas'
    ]);
    expect(repaired.totals.calories).toBeGreaterThanOrEqual(850);
    expect(repaired.totals.calories).toBeLessThanOrEqual(1800);
  });

  test('suppresses generic aliases already included in combo foods', () => {
    expect(extractFoodTextInventoryForTests('2 missal pav extra farsan half vada pav and cutting chai')).toEqual([
      'Misal pav',
      'Farsan',
      'Vada pav',
      'Cutting chai'
    ]);
  });

  test('decomposes broad combo parser items when typed inventory has more components', () => {
    const repaired = repairFoodTextInventoryCoverage(
      'kadhi khichdi with pickle, papad, potato shaak and 1 tsp ghee',
      result(['Kadhi khichdi with pickle', 'Papad', 'Potato shaak', 'Ghee'], 819)
    );

    expect(repaired.items.map((item) => item.name)).toEqual([
      'Kadhi',
      'Khichdi',
      'Pickle',
      'Papad',
      'Potato shaak',
      'Ghee'
    ]);
  });

  test('leaves adequately covered parses alone', () => {
    const parsed = result(['Jalebi', 'Rabri', 'Pistachios']);
    const repaired = repairFoodTextInventoryCoverage('jalebi stack with rabri and pistachio dust', parsed);

    expect(repaired).toBe(parsed);
  });
});
