import { afterEach, describe, expect, test, vi } from 'vitest';

// Reproduces the unbounded-memory bug in the in-memory rate limiters: under a
// flood of distinct user IDs the bucket Map grows without bound between the
// time-gated prunes. With the fix, the Map is capped (FIFO eviction).

const baseEnv = { ...process.env };

afterEach(() => {
  vi.resetModules();
  process.env = { ...baseEnv };
});

describe('rate limiter bucket cap (memory safety valve)', () => {
  test('parse limiter bounds the bucket Map under a flood of distinct users', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.PARSE_RATE_LIMIT_ENABLED = 'true';
    process.env.PARSE_RATE_LIMIT_WINDOW_MS = '100000';
    process.env.PARSE_RATE_LIMIT_MAX_REQUESTS = '5';

    const mod = await import('../src/services/parseRateLimiterService.js');
    mod.resetParseRateLimitStateForTests();
    mod.setParseRateLimitMaxBucketsForTests(10);

    const t0 = 5_000_000;
    for (let i = 0; i < 1000; i += 1) {
      mod.checkParseRateLimit(`flood-user-${i}`, t0);
    }

    expect(mod.getParseRateLimitBucketCountForTests()).toBeLessThanOrEqual(10);
  });

  test('recipe limiter bounds the bucket Map under a flood of distinct users', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.RECIPE_RATE_LIMIT_ENABLED = 'true';
    process.env.RECIPE_RATE_LIMIT_WINDOW_MS = '100000';

    const mod = await import('../src/services/recipeImportRateLimiterService.js');
    mod.resetRecipeImportRateLimitStateForTests();
    mod.setRecipeImportRateLimitMaxBucketsForTests(10);

    const t0 = 6_000_000;
    for (let i = 0; i < 1000; i += 1) {
      mod.checkRecipeImportRateLimit(`flood-user-${i}`, 'url', t0);
    }

    expect(mod.getRecipeImportRateLimitBucketCountForTests()).toBeLessThanOrEqual(10);
  });
});
