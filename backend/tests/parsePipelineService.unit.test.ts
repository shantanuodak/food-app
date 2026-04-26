import { afterEach, describe, expect, test, vi } from 'vitest';
import type { ParseResult } from '../src/services/deterministicParser.js';

const baseEnv = { ...process.env };

function buildItem(overrides?: Partial<ParseResult['items'][number]>): ParseResult['items'][number] {
  return {
    name: 'egg',
    quantity: 1,
    unit: 'count',
    grams: 50,
    calories: 72,
    protein: 6.3,
    carbs: 0.6,
    fat: 4.8,
    matchConfidence: 0.9,
    nutritionSourceId: 'gemini_estimate',
    sourceFamily: 'gemini',
    originalNutritionSourceId: 'gemini_estimate',
    foodDescription: 'Egg',
    explanation: 'Estimated from the entered food item.',
    ...overrides
  };
}

function parseResult(overrides?: Partial<ParseResult>): ParseResult {
  return {
    confidence: 0.9,
    assumptions: [],
    items: [buildItem()],
    totals: {
      calories: 72,
      protein: 6.3,
      carbs: 0.6,
      fat: 4.8
    },
    ...overrides
  };
}

afterEach(() => {
  vi.resetModules();
  vi.restoreAllMocks();
  process.env = { ...baseEnv };
});

describe('parse pipeline routing', () => {
  test('short-circuits on accepted cache result', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const getParseCache = vi.fn(async () => ({ textHash: 'hash-cache', result: parseResult() }));
    const setParseCache = vi.fn(async () => {});
    const tryCheapAIFallback = vi.fn(async () => null);

    vi.doMock('../src/services/parseCacheService.js', () => ({
      getParseCache,
      setParseCache,
      buildParseCacheDebugInfo: (text: string, scope: string) => ({
        scope,
        normalizedText: text.trim().toLowerCase(),
        textHash: `${scope}:${text.trim().toLowerCase()}`
      })
    }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryCheapAIFallback,
      tryCheapAIFallbackDetailed: async (...args: Parameters<typeof tryCheapAIFallback>) => ({
        output: await tryCheapAIFallback(...args)
      })
    }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => []
    }));

    const { runPrimaryParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runPrimaryParsePipeline('2 eggs', {
      cacheScope: 'user:v2:primary',
      allowFallback: true,
      featureFlags: { geminiEnabled: true },
      userId: 'u1'
    });

    expect(output.route).toBe('cache');
    expect(output.cacheHit).toBe(true);
    expect(output.fallbackUsed).toBe(false);
    expect(output.result.items[0]?.nutritionSourceId).toBe('gemini_estimate');
    expect(tryCheapAIFallback).not.toHaveBeenCalled();
    expect(setParseCache).not.toHaveBeenCalled();
  });

  test('skips cached results sourced from retired providers and reparses with gemini', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    // This test verifies the retired-provider invalidation path: legacy cached
    // results from FatSecret should be ignored and re-parsed with Gemini.
    // The 'fatsecret' source family is no longer in the live type union,
    // so we cast through unknown to construct the legacy shape.
    const getParseCache = vi.fn(async () => ({
      textHash: 'hash-cache',
      result: parseResult({
        items: [
          {
            ...buildItem(),
            nutritionSourceId: 'fatsecret_estimate',
            sourceFamily: 'fatsecret' as unknown as 'cache',
            originalNutritionSourceId: 'fatsecret_estimate'
          }
        ]
      })
    }));
    const setParseCache = vi.fn(async () => {});
    const tryCheapAIFallback = vi.fn(async () => ({
      result: parseResult({
        confidence: 0.82
      }),
      usage: {
        model: 'gemini-2.5-flash',
        inputTokens: 10,
        outputTokens: 30,
        estimatedCostUsd: 0.001
      }
    }));

    vi.doMock('../src/services/parseCacheService.js', () => ({
      getParseCache,
      setParseCache,
      buildParseCacheDebugInfo: (text: string, scope: string) => ({
        scope,
        normalizedText: text.trim().toLowerCase(),
        textHash: `${scope}:${text.trim().toLowerCase()}`
      })
    }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryCheapAIFallback,
      tryCheapAIFallbackDetailed: async (...args: Parameters<typeof tryCheapAIFallback>) => ({
        output: await tryCheapAIFallback(...args)
      })
    }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => []
    }));

    const { runPrimaryParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runPrimaryParsePipeline('2 eggs', {
      cacheScope: 'user:v2:primary',
      allowFallback: true,
      featureFlags: { geminiEnabled: true },
      userId: 'u1'
    });

    expect(output.route).toBe('gemini');
    expect(output.cacheHit).toBe(false);
    expect(output.fallbackUsed).toBe(true);
    expect(output.result.items[0]?.nutritionSourceId).toBe('gemini_estimate');
    expect(tryCheapAIFallback).toHaveBeenCalledTimes(1);
    expect(setParseCache).toHaveBeenCalledTimes(1);
  });

  test('uses gemini fallback when cache misses', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const getParseCache = vi.fn(async () => null);
    const setParseCache = vi.fn(async () => {});
    const tryCheapAIFallback = vi.fn(async () => ({
      result: parseResult(),
      usage: {
        model: 'gemini-2.5-flash',
        inputTokens: 10,
        outputTokens: 30,
        estimatedCostUsd: 0.001
      }
    }));

    vi.doMock('../src/services/parseCacheService.js', () => ({
      getParseCache,
      setParseCache,
      buildParseCacheDebugInfo: (text: string, scope: string) => ({
        scope,
        normalizedText: text.trim().toLowerCase(),
        textHash: `${scope}:${text.trim().toLowerCase()}`
      })
    }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryCheapAIFallback,
      tryCheapAIFallbackDetailed: async (...args: Parameters<typeof tryCheapAIFallback>) => ({
        output: await tryCheapAIFallback(...args)
      })
    }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => []
    }));

    const { runPrimaryParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runPrimaryParsePipeline('2 eggs', {
      cacheScope: 'user:v2:primary',
      allowFallback: true,
      featureFlags: { geminiEnabled: true },
      userId: 'u1'
    });

    expect(output.route).toBe('gemini');
    expect(output.cacheHit).toBe(false);
    expect(output.fallbackUsed).toBe(true);
    expect(output.fallbackModel).toBe('gemini-2.5-flash');
    expect(output.result.items[0]?.nutritionSourceId).toBe('gemini_estimate');
    expect(setParseCache).toHaveBeenCalledTimes(1);
  });

  test('returns unresolved when gemini yields no result', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const getParseCache = vi.fn(async () => null);
    const setParseCache = vi.fn(async () => {});
    const tryCheapAIFallback = vi.fn(async () => null);

    vi.doMock('../src/services/parseCacheService.js', () => ({
      getParseCache,
      setParseCache,
      buildParseCacheDebugInfo: (text: string, scope: string) => ({
        scope,
        normalizedText: text.trim().toLowerCase(),
        textHash: `${scope}:${text.trim().toLowerCase()}`
      })
    }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryCheapAIFallback,
      tryCheapAIFallbackDetailed: async (...args: Parameters<typeof tryCheapAIFallback>) => ({
        output: await tryCheapAIFallback(...args)
      })
    }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => ['Please list each food with quantity.']
    }));

    const { runPrimaryParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runPrimaryParsePipeline('2 eggs and toast', {
      cacheScope: 'user:v2:primary',
      allowFallback: true,
      featureFlags: { geminiEnabled: true },
      userId: 'u1'
    });

    expect(output.route).toBe('unresolved');
    expect(output.fallbackUsed).toBe(false);
    expect(output.result.items.length).toBe(0);
    expect(output.needsClarification).toBe(true);
    expect(output.clarificationQuestions.length).toBeGreaterThan(0);
    expect(setParseCache).not.toHaveBeenCalled();
  });

  test('returns specific gemini failure reason codes when fallback fails', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const getParseCache = vi.fn(async () => null);
    const setParseCache = vi.fn(async () => {});
    const tryCheapAIFallback = vi.fn(async () => null);
    const tryCheapAIFallbackDetailed = vi.fn(async () => ({
      output: null,
      failureReason: 'gemini_timeout'
    }));

    vi.doMock('../src/services/parseCacheService.js', () => ({
      getParseCache,
      setParseCache,
      buildParseCacheDebugInfo: (text: string, scope: string) => ({
        scope,
        normalizedText: text.trim().toLowerCase(),
        textHash: `${scope}:${text.trim().toLowerCase()}`
      })
    }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryCheapAIFallback,
      tryCheapAIFallbackDetailed
    }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => ['Please list each food with quantity.']
    }));

    const { runPrimaryParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runPrimaryParsePipeline('2 eggs and toast', {
      cacheScope: 'user:v2:primary',
      allowFallback: true,
      featureFlags: { geminiEnabled: true },
      userId: 'u1'
    });

    expect(output.route).toBe('unresolved');
    expect(output.reasonCodes).toEqual(['gemini_timeout']);
    expect(setParseCache).not.toHaveBeenCalled();
  });

  test('returns unresolved when gemini is disabled', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const getParseCache = vi.fn(async () => null);
    const setParseCache = vi.fn(async () => {});
    const tryCheapAIFallback = vi.fn(async () => ({
      result: parseResult({ confidence: 0.84 }),
      usage: {
        model: 'gemini-2.5-flash',
        inputTokens: 14,
        outputTokens: 26,
        estimatedCostUsd: 0.001
      }
    }));

    vi.doMock('../src/services/parseCacheService.js', () => ({
      getParseCache,
      setParseCache,
      buildParseCacheDebugInfo: (text: string, scope: string) => ({
        scope,
        normalizedText: text.trim().toLowerCase(),
        textHash: `${scope}:${text.trim().toLowerCase()}`
      })
    }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryCheapAIFallback,
      tryCheapAIFallbackDetailed: async (...args: Parameters<typeof tryCheapAIFallback>) => ({
        output: await tryCheapAIFallback(...args)
      })
    }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => []
    }));

    const { runPrimaryParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runPrimaryParsePipeline('vanilla icecream scoop', {
      cacheScope: 'user:v2:primary',
      allowFallback: true,
      featureFlags: { geminiEnabled: false },
      userId: 'u1'
    });

    expect(output.route).toBe('unresolved');
    expect(output.fallbackUsed).toBe(false);
    expect(tryCheapAIFallback).not.toHaveBeenCalled();
    expect(output.result.items).toHaveLength(0);
    expect(setParseCache).not.toHaveBeenCalled();
  });
});

describe('runSegmentAwareParsePipeline — multi-segment routing', () => {
  // Regression test for the canonical bug: when the user types a
  // multi-food entry (e.g. "2 naan, paneer masala, rice bowl, salad"),
  // sending the joined text to Gemini in one call sometimes makes it
  // consolidate everything into a single item ("Naan x2"), losing
  // every other food. The fix is to never send multi-segment input as
  // one prompt — always go one Gemini call per segment.
  test('per-segment routing returns one item per segment even when combined-call mocks would consolidate', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const getParseCache = vi.fn(async () => null);
    const setParseCache = vi.fn(async () => {});

    // Gemini stub that simulates the historical consolidation bug:
    // - If called with multi-line input → returns ONE item (Naan).
    // - If called with a single segment → returns one well-formed item
    //   matching that segment. The fix should never invoke the
    //   multi-line branch in the first place.
    const tryCheapAIFallback = vi.fn(async (text: string) => {
      const lower = text.toLowerCase();
      const isMultiLine = text.includes('\n');

      if (isMultiLine) {
        return {
          result: parseResult({
            items: [buildItem({ name: 'Naan', quantity: 2, calories: 560 })],
            totals: { calories: 560, protein: 18, carbs: 96, fat: 12 }
          }),
          usage: { model: 'gemini-2.5-flash', inputTokens: 80, outputTokens: 40, estimatedCostUsd: 0.001 }
        };
      }

      const matchedName =
        lower.includes('naan') ? 'Naan' :
        lower.includes('paneer') || lower.includes('panner') ? 'Butter Paneer Masala' :
        lower.includes('rice') || lower.includes('rixe') ? 'Rice bowl' :
        lower.includes('salad') ? 'Onion salad' :
        lower.includes('butter') ? 'Buttermilk' :
        'Generic food';

      return {
        result: parseResult({
          items: [buildItem({ name: matchedName, calories: 200, protein: 10, carbs: 20, fat: 8 })],
          totals: { calories: 200, protein: 10, carbs: 20, fat: 8 }
        }),
        usage: { model: 'gemini-2.5-flash', inputTokens: 20, outputTokens: 30, estimatedCostUsd: 0.0005 }
      };
    });

    vi.doMock('../src/services/parseCacheService.js', () => ({
      getParseCache,
      setParseCache,
      buildParseCacheDebugInfo: (text: string, scope: string) => ({
        scope,
        normalizedText: text.trim().toLowerCase(),
        textHash: `${scope}:${text.trim().toLowerCase()}`
      })
    }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryCheapAIFallback,
      tryCheapAIFallbackDetailed: async (...args: Parameters<typeof tryCheapAIFallback>) => ({
        output: await tryCheapAIFallback(...args)
      })
    }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => []
    }));

    const { runSegmentAwareParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runSegmentAwareParsePipeline(
      '2 naan, 1 cup butter panner masala, rixe bowl, onion salad and buttermilk',
      {
        cacheScope: 'user:v2:primary',
        allowFallback: true,
        featureFlags: { geminiEnabled: true },
        userId: 'u1'
      }
    );

    // Core assertion: we get one item per segment, not the consolidated
    // single Naan that the multi-line branch would have produced.
    expect(output.result.items.length).toBeGreaterThanOrEqual(4);

    // None of the Gemini calls should have included a newline — all
    // segments must have gone in as their own prompt.
    const calls = tryCheapAIFallback.mock.calls;
    expect(calls.length).toBeGreaterThanOrEqual(4);
    for (const call of calls) {
      const [callText] = call as [string, ...unknown[]];
      expect(callText.includes('\n')).toBe(false);
    }

    // Items should reflect the per-segment vocabulary, not just Naan.
    const itemNames = output.result.items.map((i) => i.name.toLowerCase());
    expect(itemNames.some((n) => n.includes('naan'))).toBe(true);
    expect(itemNames.some((n) => n.includes('paneer'))).toBe(true);
  });

  test('emits placeholder items for segments Gemini cannot parse so iOS can render Retry', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const getParseCache = vi.fn(async () => null);
    const setParseCache = vi.fn(async () => {});

    // Gemini stub: succeeds for "1 cup chicken tikka masala", returns
    // null (no items) for the typo'd segments. Mirrors the real failure
    // mode the user observed on production.
    const tryCheapAIFallback = vi.fn(async (text: string) => {
      const lower = text.toLowerCase();
      if (lower.includes('chicken tikka masala')) {
        return {
          result: parseResult({
            items: [buildItem({ name: 'Chicken tikka masala', calories: 400 })],
            totals: { calories: 400, protein: 30, carbs: 20, fat: 25 }
          }),
          usage: { model: 'gemini-2.5-flash', inputTokens: 20, outputTokens: 40, estimatedCostUsd: 0.001 }
        };
      }
      return null; // typos / unknown → Gemini gives up
    });

    vi.doMock('../src/services/parseCacheService.js', () => ({
      getParseCache,
      setParseCache,
      buildParseCacheDebugInfo: (text: string, scope: string) => ({
        scope,
        normalizedText: text.trim().toLowerCase(),
        textHash: `${scope}:${text.trim().toLowerCase()}`
      })
    }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryCheapAIFallback,
      tryCheapAIFallbackDetailed: async (...args: Parameters<typeof tryCheapAIFallback>) => ({
        output: await tryCheapAIFallback(...args)
      })
    }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => []
    }));

    const { runSegmentAwareParsePipeline, UNRESOLVED_PLACEHOLDER_SOURCE_ID } = await import(
      '../src/services/parsePipelineService.js'
    );
    const output = await runSegmentAwareParsePipeline(
      '3 naans, 1 glass buttermil, 1 cup chicken tikka masala and frid rice 1 cup',
      {
        cacheScope: 'user:v2:primary',
        allowFallback: true,
        featureFlags: { geminiEnabled: true },
        userId: 'u1'
      }
    );

    // We expect one item per segment — successful ones with real
    // nutrition, failed ones with the unresolved-placeholder marker.
    expect(output.result.items.length).toBe(4);

    const placeholders = output.result.items.filter(
      (it) => it.nutritionSourceId === UNRESOLVED_PLACEHOLDER_SOURCE_ID
    );
    const real = output.result.items.filter(
      (it) => it.nutritionSourceId !== UNRESOLVED_PLACEHOLDER_SOURCE_ID
    );

    // 3 segments failed (naans, buttermil typo, frid rice typo) → 3 placeholders
    expect(placeholders.length).toBe(3);
    expect(real.length).toBe(1);
    expect(real[0].name.toLowerCase()).toContain('chicken tikka masala');

    // Placeholder items carry the original segment text as their name
    // so the iOS retry call can re-parse exactly that text.
    const placeholderNames = placeholders.map((p) => p.name);
    expect(placeholderNames).toContain('3 naans');
    expect(placeholderNames).toContain('1 glass buttermil');
    expect(placeholderNames).toContain('frid rice 1 cup');

    // All placeholders have zero nutrition + needsClarification flag
    // so iOS knows to show the retry affordance, not log them as 0-cal foods.
    for (const p of placeholders) {
      expect(p.calories).toBe(0);
      expect(p.needsClarification).toBe(true);
    }

    // Placeholders must NOT be cached — caching the failure would mean
    // a future identical input never gets a fresh Gemini retry.
    const cacheCalls = setParseCache.mock.calls;
    for (const call of cacheCalls) {
      const [text] = call as [string, ...unknown[]];
      expect(['3 naans', '1 glass buttermil', 'frid rice 1 cup']).not.toContain(text);
    }
  });

  test('all-cache-hit short-circuit still returns one item per segment without calling Gemini', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    // Each segment is independently cached.
    const getParseCache = vi.fn(async (text: string) => ({
      textHash: `hash-${text}`,
      result: parseResult({
        items: [buildItem({ name: text.trim() })],
        totals: { calories: 100, protein: 5, carbs: 10, fat: 5 }
      })
    }));
    const setParseCache = vi.fn(async () => {});
    const tryCheapAIFallback = vi.fn(async () => null);

    vi.doMock('../src/services/parseCacheService.js', () => ({
      getParseCache,
      setParseCache,
      buildParseCacheDebugInfo: (text: string, scope: string) => ({
        scope,
        normalizedText: text.trim().toLowerCase(),
        textHash: `${scope}:${text.trim().toLowerCase()}`
      })
    }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryCheapAIFallback,
      tryCheapAIFallbackDetailed: async (...args: Parameters<typeof tryCheapAIFallback>) => ({
        output: await tryCheapAIFallback(...args)
      })
    }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => []
    }));

    const { runSegmentAwareParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runSegmentAwareParsePipeline('eggs and toast', {
      cacheScope: 'user:v2:primary',
      allowFallback: true,
      featureFlags: { geminiEnabled: true },
      userId: 'u1'
    });

    expect(output.cacheHit).toBe(true);
    expect(output.route).toBe('cache');
    expect(output.result.items).toHaveLength(2);
    expect(tryCheapAIFallback).not.toHaveBeenCalled();
  });
});
