import { afterEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };

afterEach(() => {
  vi.resetModules();
  vi.restoreAllMocks();
  process.env = { ...baseEnv };
});

describe('ai normalizer Gemini response repair', () => {
  test('coerces common Gemini JSON drift into a valid parse result', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.GEMINI_API_KEY = 'test-key';
    process.env.AI_FALLBACK_ENABLED = 'true';

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiJsonWithDiagnostics: vi.fn(async () => ({
        jsonText: '```json\n{"confidence":"0.82","assumptions":["ignored"],"items":[{"name":"Diet Coke","quantity":"1","unit":"can","grams":"355","calories":"0","protein":"0","carbs":"0","fat":"0","matchConfidence":"0.86"}],"totals":{"calories":"999","protein":"9","carbs":"9","fat":"9"}}\n```',
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 10,
          outputTokens: 30
        }
      }))
    }));

    const { tryCheapAIFallbackDetailed } = await import('../src/services/aiNormalizerService.js');
    const attempt = await tryCheapAIFallbackDetailed('diet coke', {
      confidence: 0,
      assumptions: [],
      items: [],
      totals: { calories: 0, protein: 0, carbs: 0, fat: 0 }
    });

    expect(attempt.output).toBeTruthy();
    expect(attempt.output?.result.assumptions).toEqual([]);
    expect(attempt.output?.result.items[0]?.nutritionSourceId).toBe('gemini_estimate');
    expect(attempt.output?.result.items[0]?.sourceFamily).toBe('gemini');
    expect(attempt.output?.result.items[0]?.quantity).toBe(1);
    expect(attempt.output?.result.items[0]?.calories).toBe(0);
    expect(attempt.output?.result.totals).toEqual({ calories: 0, protein: 0, carbs: 0, fat: 0 });
  });

  test('derives calories from macros when Gemini omits calories', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.GEMINI_API_KEY = 'test-key';
    process.env.AI_FALLBACK_ENABLED = 'true';

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiJsonWithDiagnostics: vi.fn(async () => ({
        jsonText: JSON.stringify({
          confidence: 0.78,
          assumptions: [],
          items: [
            {
              name: 'Greek yogurt marinated chicken',
              quantity: 1,
              unit: 'serving',
              grams: 160,
              protein: 38,
              carbs: 1,
              fat: 4,
              matchConfidence: 0.78,
              nutritionSourceId: ''
            }
          ],
          totals: { calories: 0, protein: 0, carbs: 0, fat: 0 }
        }),
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 10,
          outputTokens: 30
        }
      }))
    }));

    const { tryCheapAIFallbackDetailed } = await import('../src/services/aiNormalizerService.js');
    const attempt = await tryCheapAIFallbackDetailed('greek yogurt marinated chicken', {
      confidence: 0,
      assumptions: [],
      items: [],
      totals: { calories: 0, protein: 0, carbs: 0, fat: 0 }
    });

    expect(attempt.output?.result.items[0]?.calories).toBe(192);
    expect(attempt.output?.result.totals.calories).toBe(192);
    expect(attempt.output?.result.items[0]?.nutritionSourceId).toBe('gemini_estimate');
  });
});
