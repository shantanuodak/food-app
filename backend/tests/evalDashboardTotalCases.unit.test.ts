import { beforeAll, describe, expect, test } from 'vitest';

// Reproduces the `||` vs `??` bug: an empty cases array (length 0) was treated
// as "falsy" and the status showed maxCases (e.g. 25) instead of 0.

let resolveTotalCases: typeof import('../src/routes/evalDashboard.js')['resolveTotalCases'];

beforeAll(async () => {
  process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
  resolveTotalCases = (await import('../src/routes/evalDashboard.js')).resolveTotalCases;
});

describe('evalDashboard resolveTotalCases', () => {
  test('respects an empty cases array (0), not the default', () => {
    expect(resolveTotalCases(0, 25)).toBe(0); // with `||` this was wrongly 25
  });
  test('falls back to max when cases is undefined', () => {
    expect(resolveTotalCases(undefined, 25)).toBe(25);
  });
  test('uses the case count when present, capped at max', () => {
    expect(resolveTotalCases(3, 25)).toBe(3);
    expect(resolveTotalCases(30, 25)).toBe(25);
  });
});
