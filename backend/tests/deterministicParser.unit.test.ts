import { describe, expect, test } from 'vitest';
import { calculateDeterministicConfidence, parseFoodText } from '../src/services/deterministicParser.js';

describe('deterministic parser unit coverage', () => {
  test('parses common quantities and units', () => {
    const parsed = parseFoodText('2 eggs, 1 cup rice, black coffee');
    expect(parsed.items.length).toBe(3);

    const egg = parsed.items.find((item) => item.name === 'egg');
    const rice = parsed.items.find((item) => item.name === 'rice');
    const coffee = parsed.items.find((item) => item.name === 'coffee');

    expect(egg?.quantity).toBe(2);
    expect(egg?.unit).toBe('count');

    expect(rice?.quantity).toBe(1);
    expect(rice?.unit).toBe('cup');

    expect(coffee?.unit).toBe('cup');
    expect(parsed.totals.calories).toBeGreaterThan(0);
  });

  test('handles mixed units and punctuation-heavy input', () => {
    const parsed = parseFoodText(' 8 oz chicken!!! , 2   slices toast?? ');
    expect(parsed.items.length).toBe(2);

    const chicken = parsed.items.find((item) => item.name === 'chicken');
    const toast = parsed.items.find((item) => item.name === 'toast');

    expect(chicken?.unit).toBe('oz');
    expect(chicken?.grams).toBeGreaterThan(200);

    expect(toast?.quantity).toBe(2);
    expect(toast?.unit).toBe('slice');
    expect(parsed.confidence).toBeGreaterThanOrEqual(0);
    expect(parsed.confidence).toBeLessThanOrEqual(1);
  });

  test('unknown food is flagged in assumptions and does not create invalid nutrition item', () => {
    const parsed = parseFoodText('mystery galaxy shake');

    expect(parsed.items.length).toBe(0);
    expect(parsed.assumptions.length).toBeGreaterThan(0);
    expect(parsed.assumptions.join(' ')).toContain('No confident nutrition match');
    expect(parsed.totals.calories).toBe(0);
    expect(parsed.confidence).toBeLessThan(0.5);
  });
});

describe('deterministic confidence scoring', () => {
  test('enforces hard lower and upper bounds', () => {
    expect(
      calculateDeterministicConfidence({
        matchQuality: -10,
        quantityUnitQuality: -3,
        portionPlausibility: -1,
        coverage: -20
      })
    ).toBe(0);

    expect(
      calculateDeterministicConfidence({
        matchQuality: 10,
        quantityUnitQuality: 5,
        portionPlausibility: 99,
        coverage: 2
      })
    ).toBe(1);
  });

  test('hits threshold edges used by routing policy', () => {
    expect(
      calculateDeterministicConfidence({
        matchQuality: 0.5,
        quantityUnitQuality: 0.5,
        portionPlausibility: 0.5,
        coverage: 0.5
      })
    ).toBe(0.5);

    expect(
      calculateDeterministicConfidence({
        matchQuality: 0.85,
        quantityUnitQuality: 0.85,
        portionPlausibility: 0.85,
        coverage: 0.85
      })
    ).toBe(0.85);
  });
});
