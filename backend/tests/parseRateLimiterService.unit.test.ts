import { afterEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };

afterEach(() => {
  vi.resetModules();
  process.env = { ...baseEnv };
});

describe('parse rate limiter', () => {
  test('allows requests within limit and blocks over limit', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.PARSE_RATE_LIMIT_ENABLED = 'true';
    process.env.PARSE_RATE_LIMIT_WINDOW_MS = '10000';
    process.env.PARSE_RATE_LIMIT_MAX_REQUESTS = '2';

    const { checkParseRateLimit, resetParseRateLimitStateForTests } = await import('../src/services/parseRateLimiterService.js');
    resetParseRateLimitStateForTests();

    const t0 = 1_000_000;
    expect(checkParseRateLimit('user-a', t0).allowed).toBe(true);
    expect(checkParseRateLimit('user-a', t0 + 100).allowed).toBe(true);
    const blocked = checkParseRateLimit('user-a', t0 + 200);
    expect(blocked.allowed).toBe(false);
    expect(blocked.retryAfterSeconds).toBeGreaterThan(0);
  });

  test('resets bucket after window passes', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.PARSE_RATE_LIMIT_ENABLED = 'true';
    process.env.PARSE_RATE_LIMIT_WINDOW_MS = '1000';
    process.env.PARSE_RATE_LIMIT_MAX_REQUESTS = '1';

    const { checkParseRateLimit, resetParseRateLimitStateForTests } = await import('../src/services/parseRateLimiterService.js');
    resetParseRateLimitStateForTests();

    const t0 = 2_000_000;
    expect(checkParseRateLimit('user-b', t0).allowed).toBe(true);
    expect(checkParseRateLimit('user-b', t0 + 200).allowed).toBe(false);
    expect(checkParseRateLimit('user-b', t0 + 1_500).allowed).toBe(true);
  });
});
