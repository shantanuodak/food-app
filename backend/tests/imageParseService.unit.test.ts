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
});
