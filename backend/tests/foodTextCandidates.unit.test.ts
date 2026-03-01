import { describe, expect, test } from 'vitest';
import { normalizeFoodUnit, parseFoodTextCandidates } from '../src/services/foodTextCandidates.js';

describe('food text candidate parsing', () => {
  test('parses trailing quantity and compact unit tokens', () => {
    const rows = parseFoodTextCandidates('Black Coffee 1 Cup\nCoke 8oz');
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ query: 'black coffee', quantity: 1, unit: 'cup' });
    expect(rows[1]).toMatchObject({ query: 'coke', quantity: 8, unit: 'oz' });
  });

  test('supports conjunction segmentation via shared splitter', () => {
    const rows = parseFoodTextCandidates('2 eggs and toast');
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ query: 'eggs', quantity: 2 });
    expect(rows[1]).toMatchObject({ query: 'toast' });
  });

  test('keeps protected dish phrases unsplit', () => {
    const rows = parseFoodTextCandidates('mac and cheese');
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ query: 'mac and cheese' });
  });
});

describe('food unit normalization', () => {
  test('normalizes known units with count fallback', () => {
    expect(normalizeFoodUnit('Tablespoons')).toBe('tbsp');
    expect(normalizeFoodUnit('grams')).toBe('g');
    expect(normalizeFoodUnit('')).toBe('count');
  });
});
