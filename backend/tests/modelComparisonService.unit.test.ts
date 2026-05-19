import { describe, expect, test } from 'vitest';
import {
  isBenchmarkCaseAllowedForModelComparison,
  shouldAdoptFatSecretForModelComparison
} from '../src/services/modelComparisonService.js';
import type { FatSecretReference } from '../src/services/fatSecretModelLabService.js';

describe('modelComparisonService truth filtering', () => {
  test('excludes FatSecret-backed truth in expanded mode', () => {
    expect(
      isBenchmarkCaseAllowedForModelComparison(
        {
          referenceSourceType: 'official_brand',
          referenceSourceLabel: 'FatSecret Cheerios listing',
          referenceSourceUrl: 'https://foods.fatsecret.com/calories-nutrition/general-mills/cheerios'
        },
        'expanded'
      )
    ).toBe(false);
  });

  test('keeps official and USDA truth in expanded mode', () => {
    expect(
      isBenchmarkCaseAllowedForModelComparison(
        {
          referenceSourceType: 'official_restaurant',
          referenceSourceLabel: "McDonald's official Big Mac nutrition page",
          referenceSourceUrl: 'https://www.mcdonalds.com/us/en-us/product/big-mac.html'
        },
        'expanded'
      )
    ).toBe(true);
  });
});

describe('modelComparisonService FatSecret adoption policy', () => {
  test('adopts exact commercial database matches when calories are plausible', () => {
    const decision = shouldAdoptFatSecretForModelComparison(
      '1 Clif Bar Chocolate Chip 68g',
      geminiPrediction(250, 0.92),
      [fatSecretMatch({ foodName: 'Chocolate Chip Energy Bar', brandName: 'Clif Bar', servingDescription: '1 bar', calories: 250 })],
      { calories: 250, protein: 10, carbs: 43, fat: 5 }
    );

    expect(decision).toEqual({ adopt: true, source: 'gemini_fatsecret' });
  });

  test('keeps Gemini for simple whole foods with high confidence', () => {
    const decision = shouldAdoptFatSecretForModelComparison(
      '1 medium apple',
      geminiPrediction(95, 0.95),
      [fatSecretMatch({ foodName: 'Apple', brandName: null, servingDescription: '1 apple', calories: 100 })],
      { calories: 100, protein: 0, carbs: 24, fat: 0.5 }
    );

    expect(decision.adopt).toBe(false);
    expect(decision.source).toBe('gemini_fatsecret_fallback_simple_food');
  });

  test('rejects single component matches for composed meal requests', () => {
    const decision = shouldAdoptFatSecretForModelComparison(
      'Chipotle chicken bowl with white rice black beans tomato salsa cheese and lettuce',
      geminiPrediction(660, 0.9),
      [fatSecretMatch({ foodName: 'Black Beans', brandName: 'Chipotle Mexican Grill', servingDescription: '1 serving', calories: 130 })],
      { calories: 130, protein: 8, carbs: 22, fat: 1.5 }
    );

    expect(decision.adopt).toBe(false);
    expect(decision.source).toBe('gemini_fatsecret_fallback_composite_match');
  });

  test('adopts serving-aligned prepared food when FatSecret materially corrects Gemini', () => {
    const decision = shouldAdoptFatSecretForModelComparison(
      'one slice pizza',
      geminiPrediction(310, 0.82),
      [fatSecretMatch({ foodName: 'Cheese Pizza', brandName: null, servingDescription: '1 slice', calories: 210 })],
      { calories: 210, protein: 10, carbs: 29, fat: 6 }
    );

    expect(decision).toEqual({ adopt: true, source: 'gemini_fatsecret' });
  });

  test('rejects token mismatches even when serving text looks usable', () => {
    const decision = shouldAdoptFatSecretForModelComparison(
      '2 plain rotis',
      geminiPrediction(340, 0.82),
      [fatSecretMatch({ foodName: 'Plain Muffin', brandName: null, servingDescription: '1 small', calories: 201 })],
      { calories: 201, protein: 5, carbs: 28, fat: 7 }
    );

    expect(decision.adopt).toBe(false);
    expect(decision.source).toBe('gemini_fatsecret_fallback_token_mismatch');
  });

  test('keeps Gemini for close generic prepared-food swaps', () => {
    const decision = shouldAdoptFatSecretForModelComparison(
      'one grilled cheese sandwich',
      geminiPrediction(380, 0.84),
      [fatSecretMatch({ foodName: 'Grilled Cheese Sandwich', brandName: null, servingDescription: '1 sandwich', calories: 291 })],
      { calories: 291, protein: 9, carbs: 27, fat: 15 }
    );

    expect(decision.adopt).toBe(false);
    expect(decision.source).toBe('gemini_fatsecret_fallback_similar_calories');
  });
});

function geminiPrediction(calories: number, confidence: number) {
  return {
    ok: true,
    confidence,
    totals: { calories, protein: 0, carbs: 0, fat: 0 }
  };
}

function fatSecretMatch(overrides: Partial<FatSecretReference>): FatSecretReference {
  return {
    foodId: 'test',
    foodName: 'Test Food',
    brandName: null,
    servingDescription: '1 serving',
    servingHint: null,
    scale: 1,
    calories: 100,
    protein: 0,
    carbs: 0,
    fat: 0,
    sourceLabel: 'FatSecret Test Food',
    reference: 'Food ID test',
    ...overrides
  };
}
