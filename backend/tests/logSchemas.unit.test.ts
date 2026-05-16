import { describe, expect, test } from 'vitest';
import { blocksSaveForClarification, type LogItemSchema } from '../src/routes/logSchemas.js';

function item(overrides: Partial<LogItemSchema>): LogItemSchema {
  return {
    name: 'custom item',
    quantity: 1,
    amount: 1,
    unit: 'serving',
    unitNormalized: 'serving',
    grams: 100,
    gramsPerUnit: 100,
    calories: 120,
    protein: 5,
    carbs: 10,
    fat: 4,
    nutritionSourceId: 'gemini_estimate',
    originalNutritionSourceId: 'gemini_estimate',
    matchConfidence: 0.4,
    needsClarification: true,
    ...overrides
  };
}

describe('log save clarification blocking', () => {
  test('does not block saveable low-confidence nutrition rows', () => {
    expect(blocksSaveForClarification(item({ matchConfidence: 0.4, needsClarification: true }))).toBe(false);
  });

  test('blocks unresolved placeholders without manual override', () => {
    expect(
      blocksSaveForClarification(
        item({
          calories: 0,
          protein: 0,
          carbs: 0,
          fat: 0,
          grams: 0,
          gramsPerUnit: 0,
          nutritionSourceId: 'unresolved_placeholder',
          originalNutritionSourceId: 'unresolved_placeholder',
          matchConfidence: 0,
          needsClarification: true
        })
      )
    ).toBe(true);
  });

  test('allows unresolved placeholders after explicit manual override', () => {
    expect(
      blocksSaveForClarification(
        item({
          calories: 0,
          protein: 0,
          carbs: 0,
          fat: 0,
          grams: 0,
          nutritionSourceId: 'unresolved_placeholder',
          matchConfidence: 0,
          needsClarification: true,
          manualOverride: { enabled: true, reason: 'User entered nutrition manually.', editedFields: ['calories'] }
        })
      )
    ).toBe(false);
  });
});
