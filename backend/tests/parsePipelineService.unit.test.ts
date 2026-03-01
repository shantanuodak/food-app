import { afterEach, describe, expect, test, vi } from 'vitest';
import type { ParseResult } from '../src/services/deterministicParser.js';

const baseEnv = { ...process.env };

function parseResult(overrides?: Partial<ParseResult>): ParseResult {
  return {
    confidence: 0.9,
    assumptions: [],
    items: [
      {
        name: 'egg',
        quantity: 1,
        unit: 'count',
        grams: 50,
        calories: 72,
        protein: 6.3,
        carbs: 0.6,
        fat: 4.8,
        matchConfidence: 0.9,
        nutritionSourceId: 'seed_egg'
      }
    ],
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
    const tryFatSecretParse = vi.fn(async () => null);
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
    vi.doMock('../src/services/fatsecretParserService.js', () => ({ tryFatSecretParse }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({ tryCheapAIFallback }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => []
    }));

    const { runPrimaryParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runPrimaryParsePipeline('2 eggs', {
      cacheScope: 'user:v2:primary',
      allowFallback: true,
      featureFlags: { fatsecretEnabled: true, geminiEnabled: true },
      userId: 'u1'
    });

    expect(output.route).toBe('cache');
    expect(output.cacheHit).toBe(true);
    expect(output.fallbackUsed).toBe(false);
    expect(output.result.items[0]?.nutritionSourceId).toBe('cache_estimate');
    expect(tryFatSecretParse).not.toHaveBeenCalled();
    expect(tryCheapAIFallback).not.toHaveBeenCalled();
    expect(setParseCache).not.toHaveBeenCalled();
  });

  test('uses fatsecret route when accepted and skips gemini', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const getParseCache = vi.fn(async () => null);
    const setParseCache = vi.fn(async () => {});
    const tryFatSecretParse = vi.fn(async () => parseResult());
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
    vi.doMock('../src/services/fatsecretParserService.js', () => ({ tryFatSecretParse }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({ tryCheapAIFallback }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => []
    }));

    const { runPrimaryParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runPrimaryParsePipeline('2 eggs', {
      cacheScope: 'user:v2:primary',
      allowFallback: true,
      featureFlags: { fatsecretEnabled: true, geminiEnabled: true },
      userId: 'u1'
    });

    expect(output.route).toBe('fatsecret');
    expect(output.cacheHit).toBe(false);
    expect(output.fallbackUsed).toBe(false);
    expect(output.result.items[0]?.nutritionSourceId).toBe('fatsecret_estimate');
    expect(tryCheapAIFallback).not.toHaveBeenCalled();
    expect(setParseCache).toHaveBeenCalledTimes(1);
  });

  test('uses gemini fallback when cache and fatsecret miss', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const getParseCache = vi.fn(async () => null);
    const setParseCache = vi.fn(async () => {});
    const tryFatSecretParse = vi.fn(async () => null);
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
    vi.doMock('../src/services/fatsecretParserService.js', () => ({ tryFatSecretParse }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({ tryCheapAIFallback }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => []
    }));

    const { runPrimaryParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runPrimaryParsePipeline('2 eggs', {
      cacheScope: 'user:v2:primary',
      allowFallback: true,
      featureFlags: { fatsecretEnabled: true, geminiEnabled: true },
      userId: 'u1'
    });

    expect(output.route).toBe('gemini');
    expect(output.cacheHit).toBe(false);
    expect(output.fallbackUsed).toBe(true);
    expect(output.fallbackModel).toBe('gemini-2.5-flash');
    expect(output.result.items[0]?.nutritionSourceId).toBe('gemini_estimate');
    expect(setParseCache).toHaveBeenCalledTimes(1);
  });

  test('falls back to fatsecret candidate if gemini returns empty', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const getParseCache = vi.fn(async () => null);
    const setParseCache = vi.fn(async () => {});
    const tryFatSecretParse = vi.fn(async () => parseResult({ confidence: 0.5 }));
    const tryCheapAIFallback = vi.fn(async () => ({
      result: parseResult({
        confidence: 0.4,
        items: [],
        totals: { calories: 0, protein: 0, carbs: 0, fat: 0 }
      }),
      usage: {
        model: 'gemini-2.5-flash',
        inputTokens: 12,
        outputTokens: 8,
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
    vi.doMock('../src/services/fatsecretParserService.js', () => ({ tryFatSecretParse }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({ tryCheapAIFallback }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => ['Please list each food with quantity.']
    }));

    const { runPrimaryParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runPrimaryParsePipeline('2 eggs and toast', {
      cacheScope: 'user:v2:primary',
      allowFallback: true,
      featureFlags: { fatsecretEnabled: true, geminiEnabled: true },
      userId: 'u1'
    });

    expect(output.route).toBe('fatsecret');
    expect(output.fallbackUsed).toBe(true);
    expect(output.result.items.length).toBeGreaterThan(0);
    expect(output.needsClarification).toBe(true);
    expect(output.clarificationQuestions.length).toBeGreaterThan(0);
  });

  test('uses gemini when fatsecret candidate is below confidence threshold', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const getParseCache = vi.fn(async () => null);
    const setParseCache = vi.fn(async () => {});
    const tryFatSecretParse = vi.fn(async () => parseResult({ confidence: 0.31 }));
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
    vi.doMock('../src/services/fatsecretParserService.js', () => ({ tryFatSecretParse }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({ tryCheapAIFallback }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => []
    }));

    const { runPrimaryParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runPrimaryParsePipeline('vanilla icecream scoop', {
      cacheScope: 'user:v2:primary',
      allowFallback: true,
      featureFlags: { fatsecretEnabled: true, geminiEnabled: true },
      userId: 'u1'
    });

    expect(output.route).toBe('gemini');
    expect(output.fallbackUsed).toBe(true);
    expect(tryFatSecretParse).toHaveBeenCalledTimes(1);
    expect(tryCheapAIFallback).toHaveBeenCalledTimes(1);
    expect(output.result.confidence).toBeGreaterThan(0.8);
  });

  test('returns unresolved route when no provider yields items', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const getParseCache = vi.fn(async () => null);
    const setParseCache = vi.fn(async () => {});
    const tryFatSecretParse = vi.fn(async () => null);
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
    vi.doMock('../src/services/fatsecretParserService.js', () => ({ tryFatSecretParse }));
    vi.doMock('../src/services/aiNormalizerService.js', () => ({ tryCheapAIFallback }));
    vi.doMock('../src/services/clarificationService.js', () => ({
      buildClarificationQuestions: () => ['Please list each food with quantity.']
    }));

    const { runPrimaryParsePipeline } = await import('../src/services/parsePipelineService.js');
    const output = await runPrimaryParsePipeline('3 eggs', {
      cacheScope: 'user:v2:primary',
      allowFallback: true,
      featureFlags: { fatsecretEnabled: true, geminiEnabled: true },
      userId: 'u1'
    });

    expect(output.route).toBe('unresolved');
    expect(output.cacheHit).toBe(false);
    expect(output.fallbackUsed).toBe(false);
    expect(output.result.items).toHaveLength(0);
    expect(output.needsClarification).toBe(true);
    expect(setParseCache).not.toHaveBeenCalled();
  });
});
