import { afterEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };

afterEach(() => {
  vi.resetModules();
  vi.clearAllMocks();
  process.env = { ...baseEnv };
});

describe('image parse service', () => {
  test('returns usable nutrition-label items even when image confidence is below the visual threshold', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'false';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash-lite';

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson: vi.fn(async () => ({
        jsonText: JSON.stringify({
          extractedText: 'Chobani probiotic drink nutrition label',
          confidence: 0.42,
          assumptions: [],
          items: [
            {
              name: 'Chobani probiotic drink',
              quantity: 1,
              unit: 'bottle',
              grams: 296,
              calories: 170,
              protein: 20,
              carbs: 16,
              fat: 3,
              matchConfidence: 0.68,
              foodDescription: 'Chobani probiotic drink, 1 bottle',
              explanation: 'Nutrition was estimated from the visible bottle label for one serving.'
            }
          ]
        }),
        usage: {
          model: 'gemini-2.5-flash-lite',
          inputTokens: 100,
          outputTokens: 50
        }
      }))
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'test-image'
    });

    expect(parsed.lowConfidenceAccepted).toBe(true);
    expect(parsed.fallbackUsed).toBe(false);
    expect(parsed.result.confidence).toBe(0.5);
    expect(parsed.result.items).toHaveLength(1);
    expect(parsed.result.items[0].name).toBe('Chobani probiotic drink');
    expect(parsed.result.items[0].needsClarification).toBe(true);
    expect(parsed.result.totals.calories).toBe(170);
  });

  test('runs rescue prompt when primary and fallback models match and first image parse is unusable', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_FALLBACK_MODEL = 'gemini-2.5-flash';

    const generateGeminiMultimodalJson = vi
      .fn()
      .mockResolvedValueOnce({
        jsonText: JSON.stringify({
          extractedText: '',
          confidence: 0,
          assumptions: [],
          items: []
        }),
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 120,
          outputTokens: 20
        }
      })
      .mockResolvedValueOnce({
        jsonText: JSON.stringify({
          extractedText: 'margherita pizza',
          confidence: 0.44,
          assumptions: ['Estimated as two visible slices of margherita pizza.'],
          items: [
            {
              name: 'Margherita pizza',
              quantity: 2,
              unit: 'slices',
              grams: 220,
              calories: 560,
              protein: 22,
              carbs: 66,
              fat: 22,
              matchConfidence: 0.6,
              foodDescription: 'Margherita pizza, 2 slices',
              explanation: 'Estimated from visible pizza slices using a common serving size.'
            }
          ]
        }),
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 130,
          outputTokens: 80
        }
      });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'pizza-image'
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(2);
    expect(generateGeminiMultimodalJson.mock.calls[1]?.[0]?.parts[0]?.text).toContain('fallback parser');
    expect(parsed.lowConfidenceAccepted).toBe(true);
    expect(parsed.fallbackUsed).toBe(true);
    expect(parsed.result.confidence).toBe(0.5);
    expect(parsed.extractedText).toBe('margherita pizza');
    expect(parsed.result.items[0].name).toBe('Margherita pizza');
    expect(parsed.result.totals.calories).toBe(560);
  });
});
