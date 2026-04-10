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
