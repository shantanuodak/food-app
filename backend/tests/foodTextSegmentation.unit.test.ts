import { describe, expect, test } from 'vitest';
import { splitFoodTextSegments } from '../src/services/foodTextSegmentation.js';

describe('food text segmentation', () => {
  test('splits comma, newline, and semicolon separators', () => {
    const segments = splitFoodTextSegments('2 eggs, 1 toast\nblack coffee;1 apple');
    expect(segments).toEqual(['2 eggs', '1 toast', 'black coffee', '1 apple']);
  });

  test('splits simple conjunction lists in balanced mode', () => {
    const segments = splitFoodTextSegments('2 eggs and toast');
    expect(segments).toEqual(['2 eggs', 'toast']);
  });

  test('splits ampersand and plus list separators in balanced mode', () => {
    const segments = splitFoodTextSegments('eggs & toast + coffee');
    expect(segments).toEqual(['eggs', 'toast', 'coffee']);
  });

  test('keeps protected dish phrases unsplit', () => {
    const segments = splitFoodTextSegments('mac and cheese');
    expect(segments).toEqual(['mac and cheese']);
  });

  test('keeps likely composed dish phrases unsplit when dish hints exist', () => {
    const segments = splitFoodTextSegments('ham and cheese sandwich');
    expect(segments).toEqual(['ham and cheese sandwich']);
  });

  test('supports mixed separators with conjunction expansion', () => {
    const segments = splitFoodTextSegments('2 eggs and toast, black coffee');
    expect(segments).toEqual(['2 eggs', 'toast', 'black coffee']);
  });

  test('splits multi-quantity lists even when a dish-hint word appears in one part', () => {
    // Regression: this used to collapse to a single segment because
    // "salad" is a dish-hint token. With ≥2 explicit quantities in the
    // parts, the user is clearly giving a list — the dish-hint guard
    // should not block the split.
    const segments = splitFoodTextSegments(
      '1 naan and 1 cup chicken fried rice and salad onion'
    );
    expect(segments).toEqual([
      '1 naan',
      '1 cup chicken fried rice',
      'salad onion'
    ]);
  });

  test('still keeps a single composed-dish phrase unsplit when no quantities', () => {
    // Sanity check that the dish-hint guard still applies in the
    // ambiguous case (no explicit quantities, dish-hint word present).
    const segments = splitFoodTextSegments('chicken caesar salad and breadsticks');
    expect(segments).toEqual(['chicken caesar salad and breadsticks']);
  });
});
