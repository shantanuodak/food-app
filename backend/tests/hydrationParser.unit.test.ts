import { describe, expect, test } from 'vitest';
import { hydrationAmountToMl, parseHydrationText } from '../src/services/hydrationParser.js';

describe('hydration parser', () => {
  test('parses explicit metric water amounts', () => {
    expect(parseHydrationText('500 ml water')).toMatchObject({
      status: 'matched',
      amountMl: 500,
      inputAmount: 500,
      inputUnit: 'ml'
    });

    expect(parseHydrationText('1.5 liters of water')).toMatchObject({
      status: 'matched',
      amountMl: 1500,
      inputAmount: 1.5,
      inputUnit: 'l'
    });
  });

  test('parses ounces, cups, and number words', () => {
    expect(parseHydrationText('16 oz water')).toMatchObject({
      status: 'matched',
      amountMl: 473,
      inputAmount: 16,
      inputUnit: 'fl_oz'
    });

    expect(parseHydrationText('two cups water')).toMatchObject({
      status: 'matched',
      amountMl: 473,
      inputAmount: 2,
      inputUnit: 'cup'
    });

    expect(parseHydrationText('one and a half liters water')).toMatchObject({
      status: 'matched',
      amountMl: 1500,
      inputAmount: 1.5,
      inputUnit: 'l'
    });

    expect(parseHydrationText('12 oz club soda')).toMatchObject({
      status: 'matched',
      amountMl: 355,
      inputAmount: 12,
      inputUnit: 'fl_oz'
    });
  });

  test('asks for amount when text is water but no volume is present', () => {
    const result = parseHydrationText('bottle of water');

    expect(result.status).toBe('needs_amount');
    expect(result.reasonCodes).toContain('missing_amount');
    expect(result.suggestions).toEqual([
      { amountMl: 250, label: '250 ml' },
      { amountMl: 500, label: '500 ml' },
      { amountMl: 750, label: '750 ml' }
    ]);
  });

  test('stays conservative for non-water foods and caloric drinks', () => {
    expect(parseHydrationText('watermelon slices')).toMatchObject({ status: 'not_hydration' });
    expect(parseHydrationText('12 oz coconut water')).toMatchObject({ status: 'not_hydration' });
    expect(parseHydrationText('coffee with water')).toMatchObject({ status: 'not_hydration' });
  });

  test('converts known units to milliliters', () => {
    expect(hydrationAmountToMl(1, 'l')).toBe(1000);
    expect(hydrationAmountToMl(8, 'fl_oz')).toBe(237);
    expect(hydrationAmountToMl(1, 'cup')).toBe(237);
  });
});
