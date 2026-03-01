import { describe, expect, test } from 'vitest';
import { __fatsecretTestUtils } from '../src/services/fatsecretParserService.js';

describe('fatsecret parser candidate extraction', () => {
  test('parses trailing quantity and unit from text', () => {
    const rows = __fatsecretTestUtils.buildCandidatesFromText('Black Coffee 1 Cup\nCoke 8oz');
    expect(rows.length).toBe(2);

    expect(rows[0]?.query).toBe('black coffee');
    expect(rows[0]?.quantity).toBe(1);
    expect(rows[0]?.unit).toBe('cup');

    expect(rows[1]?.query).toBe('coke');
    expect(rows[1]?.quantity).toBe(8);
    expect(rows[1]?.unit).toBe('oz');
  });

  test('splits one-line conjunction input into multiple candidates', () => {
    const rows = __fatsecretTestUtils.buildCandidatesFromText('2 eggs and toast');
    expect(rows.length).toBe(2);
    expect(rows[0]?.query).toBe('eggs');
    expect(rows[0]?.quantity).toBe(2);
    expect(rows[1]?.query).toBe('toast');
  });

  test('keeps protected conjunction dishes unsplit', () => {
    const rows = __fatsecretTestUtils.buildCandidatesFromText('mac and cheese');
    expect(rows.length).toBe(1);
    expect(rows[0]?.query).toBe('mac and cheese');
  });
});

describe('fatsecret parser description profile', () => {
  test('extracts per-100g macro profile from food_description', () => {
    const profile = __fatsecretTestUtils.parseDescriptionProfile(
      'Per 100g - Calories: 165kcal | Fat: 3.6g | Carbs: 0g | Protein: 31g'
    );

    expect(profile).not.toBeNull();
    expect(profile?.referenceQuantity).toBe(100);
    expect(profile?.referenceUnit).toBe('g');
    expect(profile?.referenceGrams).toBe(100);
    expect(profile?.calories).toBe(165);
    expect(profile?.protein).toBe(31);
    expect(profile?.carbs).toBe(0);
    expect(profile?.fat).toBe(3.6);
  });

  test('normalizes known units', () => {
    expect(__fatsecretTestUtils.normalizeUnit('Tablespoons')).toBe('tbsp');
    expect(__fatsecretTestUtils.normalizeUnit('grams')).toBe('g');
    expect(__fatsecretTestUtils.normalizeUnit('')).toBe('count');
  });
});

describe('fatsecret parser serving scaling', () => {
  test('prefers provider serving metrics for ambiguous count units', () => {
    const resolved = __fatsecretTestUtils.buildItemFromServingForTest(
      {
        rawSegment: 'black coffee',
        query: 'black coffee',
        quantity: 1,
        unit: 'count',
        gramsHint: null,
        caloriesHintPer100g: null
      },
      {
        servingId: 'cup_1',
        unit: 'cup',
        servingUnits: 1,
        metricGrams: 240,
        calories: 2,
        protein: 0.3,
        carbs: 0,
        fat: 0,
        rawDescription: '1 cup'
      }
    );

    expect(resolved.item.grams).toBe(240);
    expect(resolved.item.calories).toBe(2);
    expect(resolved.assumptions).toEqual([]);
  });

  test('does not divide by servingUnits for ambiguous count units', () => {
    const resolved = __fatsecretTestUtils.buildItemFromServingForTest(
      {
        rawSegment: 'black coffee',
        query: 'black coffee',
        quantity: 1,
        unit: 'count',
        gramsHint: null,
        caloriesHintPer100g: null
      },
      {
        servingId: 'grams_100',
        unit: 'g',
        servingUnits: 100,
        metricGrams: 100,
        calories: 1,
        protein: 0.2,
        carbs: 0,
        fat: 0,
        rawDescription: '100 g'
      }
    );

    expect(resolved.item.calories).toBe(1);
    expect(resolved.item.grams).toBe(100);
    expect(resolved.assumptions).toEqual([]);
  });
});

describe('fatsecret semantic ranking safeguards', () => {
  test('penalizes semantically contradictory summary names', () => {
    const icecreamCandidate = __fatsecretTestUtils.scoreSummaryForTest('vanilla icecream scoop', {
      foodName: '2-scoop Rice',
      foodDescription: 'Per 100g - Calories: 130 | Fat: 0.3g | Carbs: 28g | Protein: 2.7g'
    });
    const realIcecreamCandidate = __fatsecretTestUtils.scoreSummaryForTest('vanilla icecream scoop', {
      foodName: 'Vanilla Ice Cream',
      foodDescription: 'Per 100g - Calories: 207 | Fat: 11g | Carbs: 24g | Protein: 3.5g'
    });

    expect(icecreamCandidate.contentOverlap).toBe(0);
    expect(realIcecreamCandidate.contentOverlap).toBeGreaterThan(0);
    expect(icecreamCandidate.score).toBeLessThan(realIcecreamCandidate.score);
  });

  test('rejects low-overlap multi-token matches', () => {
    const weakMatchAccepted = __fatsecretTestUtils.isSummaryAcceptedForTest('vanilla icecream scoop', 0.24, 0);
    const meaningfulMatchAccepted = __fatsecretTestUtils.isSummaryAcceptedForTest('vanilla icecream scoop', 0.41, 0.67);

    expect(weakMatchAccepted).toBe(false);
    expect(meaningfulMatchAccepted).toBe(true);
  });
});
