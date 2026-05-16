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

  test('rescue prompt explicitly supports Indian flatbread photos', async () => {
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
          extractedText: 'methi paratha with chutney',
          confidence: 0.56,
          assumptions: ['Estimated as one visible Indian flatbread with chutney.'],
          items: [
            {
              name: 'Methi paratha',
              quantity: 1,
              unit: 'piece',
              grams: 120,
              calories: 300,
              protein: 8,
              carbs: 42,
              fat: 11,
              matchConfidence: 0.58,
              foodDescription: 'Methi paratha, 1 piece',
              explanation: 'Estimated from the visible flatbread using a typical paratha serving.'
            }
          ]
        }),
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 140,
          outputTokens: 85
        }
      });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'flatbread-image'
    });

    const rescuePrompt = generateGeminiMultimodalJson.mock.calls[1]?.[0]?.parts[0]?.text;
    expect(rescuePrompt).toContain('paratha');
    expect(rescuePrompt).toContain('flatbread');
    expect(parsed.lowConfidenceAccepted).toBe(true);
    expect(parsed.fallbackUsed).toBe(true);
    expect(parsed.result.items[0].name).toBe('Methi paratha');
    expect(parsed.result.totals.calories).toBe(300);
  });

  test('accepts fenced Gemini JSON with food-app style alternate field names', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'false';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson: vi.fn(async () => ({
        jsonText: [
          '```json',
          JSON.stringify({
            caption: 'margherita pizza',
            overallConfidence: '0.62',
            notes: ['Estimated as two visible slices.'],
            foods: [
              {
                foodName: 'Margherita pizza',
                amount: '2',
                servingUnit: 'slices',
                weightGrams: '220 g',
                caloriesKcal: '560 kcal',
                proteinG: '22g',
                carbsG: '66 g',
                fatG: '22g',
                foodConfidence: '0.60',
                description: 'Margherita pizza, 2 slices'
              }
            ]
          }),
          '```'
        ].join('\n'),
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 120,
          outputTokens: 90
        }
      }))
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'pizza-image'
    });

    expect(parsed.lowConfidenceAccepted).toBe(true);
    expect(parsed.fallbackUsed).toBe(false);
    expect(parsed.extractedText).toBe('margherita pizza');
    expect(parsed.result.items[0].name).toBe('Margherita pizza');
    expect(parsed.result.items[0].unit).toBe('slice');
    expect(parsed.result.items[0].quantity).toBe(2);
    expect(parsed.result.items[0].gramsPerUnit).toBe(110);
    expect(parsed.result.items[0].needsClarification).toBe(true);
    expect(parsed.result.totals).toMatchObject({
      calories: 560,
      protein: 22,
      carbs: 66,
      fat: 22
    });
  });

  test('does not mark high-confidence same-model rescue results as low-confidence accepted', async () => {
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
          extractedText: 'turkey sandwich',
          confidence: 0.91,
          assumptions: [],
          items: [
            {
              name: 'Turkey sandwich',
              quantity: 1,
              unit: 'sandwich',
              grams: 210,
              calories: 430,
              protein: 28,
              carbs: 38,
              fat: 18,
              matchConfidence: 0.9,
              foodDescription: 'Turkey sandwich, 1 sandwich',
              explanation: 'Estimated from the visible sandwich using a typical full sandwich serving.'
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
      dataBase64: 'sandwich-image'
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(2);
    expect(parsed.fallbackUsed).toBe(true);
    expect(parsed.lowConfidenceAccepted).toBe(false);
    expect(parsed.result.confidence).toBe(0.91);
    expect(parsed.result.items[0].needsClarification).toBe(false);
  });

  test('recovers failed composed-meal image parses through caption-to-text fallback', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_FALLBACK_MODEL = 'gemini-2.5-pro';

    const generateGeminiMultimodalJson = vi
      .fn()
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({
        jsonText: JSON.stringify({
          caption: 'white rice with dal, salad, and crunchy Indian snack garnish'
        }),
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 780,
          outputTokens: 32
        }
      });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson
    }));

    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryCheapAIFallbackDetailed: vi.fn(async () => ({
        output: {
          result: {
            confidence: 0.82,
            assumptions: [],
            items: [
              {
                name: 'Rice with dal and salad',
                quantity: 1,
                amount: 1,
                unit: 'bowl',
                unitNormalized: 'bowl',
                grams: 450,
                gramsPerUnit: 450,
                calories: 620,
                protein: 18,
                carbs: 102,
                fat: 16,
                matchConfidence: 0.82,
                nutritionSourceId: 'gemini_estimate',
                originalNutritionSourceId: 'gemini_estimate',
                sourceFamily: 'gemini',
                needsClarification: false,
                manualOverride: false,
                foodDescription: 'Rice with dal, salad, and garnish',
                explanation: 'Estimated as one bowl of white rice with dal and a small salad/garnish portion.'
              }
            ],
            totals: {
              calories: 620,
              protein: 18,
              carbs: 102,
              fat: 16
            }
          },
          usage: {
            model: 'gemini-2.5-flash',
            inputTokens: 310,
            outputTokens: 120,
            estimatedCostUsd: 0.00042
          }
        }
      }))
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'rice-dal-image'
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(3);
    expect(generateGeminiMultimodalJson.mock.calls[2]?.[0]?.parts[0]?.text).toContain('caption');
    expect(parsed.extractedText).toBe('white rice with dal, salad, and crunchy Indian snack garnish');
    expect(parsed.fallbackUsed).toBe(true);
    expect(parsed.lowConfidenceAccepted).toBe(true);
    expect(parsed.result.items).toHaveLength(1);
    expect(parsed.result.items[0].name).toBe('Rice with dal and salad');
    expect(parsed.result.items[0].needsClarification).toBe(true);
    expect(parsed.result.items[0].nutritionSourceId).toBe('gemini_image_caption_estimate');
    expect(parsed.result.totals.calories).toBe(620);
    expect(parsed.usageEvents.map((event) => event.feature)).toEqual([
      'parse_image_caption',
      'parse_image_caption_text'
    ]);
  });
});
