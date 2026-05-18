import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };

beforeEach(() => {
  process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v1';
});

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
      })),
      generateGeminiMultimodalText: vi.fn(async () => null)
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

    const generateGeminiMultimodalText = vi.fn().mockResolvedValueOnce(null);

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'pizza-image'
    });

    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(2);
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

    const generateGeminiMultimodalText = vi.fn().mockResolvedValueOnce(null);

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'flatbread-image'
    });

    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(2);
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
      })),
      generateGeminiMultimodalText: vi.fn(async () => null)
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

    const generateGeminiMultimodalText = vi.fn().mockResolvedValueOnce(null);

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'sandwich-image'
    });

    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(2);
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
      .mockResolvedValueOnce(null);

    const generateGeminiMultimodalText = vi.fn().mockResolvedValueOnce({
      jsonText: 'white rice with dal, salad, and crunchy Indian snack garnish',
      usage: {
        model: 'gemini-2.5-flash',
        inputTokens: 780,
        outputTokens: 32
      }
    });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryGeminiPrimaryParse: vi.fn(async () => ({
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
      }))
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'rice-dal-image'
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(1);
    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(1);
    expect(generateGeminiMultimodalText.mock.calls[0]?.[0]?.parts[0]?.text).toContain('one plain line of comma-separated food names');
    expect(generateGeminiMultimodalText.mock.calls[0]?.[0]?.parts[0]?.text).not.toContain('JSON');
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

  test('accepts plain-text image captions before text nutrition recovery', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_FALLBACK_MODEL = 'gemini-2.5-pro';

    const generateGeminiMultimodalJson = vi
      .fn()
      .mockResolvedValueOnce(null);

    const generateGeminiMultimodalText = vi.fn().mockResolvedValueOnce({
      jsonText: 'masala dosa with sambar and three chutneys',
      usage: {
        model: 'gemini-2.5-flash',
        inputTokens: 770,
        outputTokens: 12
      }
    });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryGeminiPrimaryParse: vi.fn(async () => ({
        result: {
          confidence: 0.84,
          assumptions: [],
          items: [
            {
              name: 'Masala dosa with sambar and chutneys',
              quantity: 1,
              amount: 1,
              unit: 'plate',
              unitNormalized: 'plate',
              grams: 520,
              gramsPerUnit: 520,
              calories: 720,
              protein: 18,
              carbs: 104,
              fat: 26,
              matchConfidence: 0.84,
              nutritionSourceId: 'gemini_estimate',
              originalNutritionSourceId: 'gemini_estimate',
              sourceFamily: 'gemini',
              needsClarification: false,
              manualOverride: false,
              foodDescription: 'Masala dosa with sambar and chutneys',
              explanation: 'Estimated as one restaurant plate of masala dosa with sambar and chutneys.'
            }
          ],
          totals: {
            calories: 720,
            protein: 18,
            carbs: 104,
            fat: 26
          }
        },
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 300,
          outputTokens: 120,
          estimatedCostUsd: 0.00042
        }
      }))
    }));

    const debugEvents: Array<{ stage: string; ok: boolean; caption?: string }> = [];
    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'dosa-image',
      debugEvents
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(1);
    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(1);
    expect(parsed.extractedText).toBe('masala dosa with sambar and three chutneys');
    expect(parsed.result.items[0].name).toBe('Masala dosa with sambar and chutneys');
    expect(debugEvents.some((event) => event.stage === 'image_caption' && event.ok && event.caption === parsed.extractedText)).toBe(true);
  });

  test('tries fallback model for plain caption recovery when primary caption fails', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_FALLBACK_MODEL = 'gemini-2.5-pro';

    const generateGeminiMultimodalJson = vi.fn().mockResolvedValueOnce(null);

    const generateGeminiMultimodalText = vi
      .fn()
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({
        jsonText: 'masala dosa, sambar, coconut chutney, tomato chutney',
        usage: {
          model: 'gemini-2.5-pro',
          inputTokens: 810,
          outputTokens: 16
        }
      });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryGeminiPrimaryParse: vi.fn(async () => ({
        result: {
          confidence: 0.86,
          assumptions: [],
          items: [
            {
              name: 'Masala dosa with sambar and chutneys',
              quantity: 1,
              amount: 1,
              unit: 'plate',
              unitNormalized: 'plate',
              grams: 520,
              gramsPerUnit: 520,
              calories: 720,
              protein: 18,
              carbs: 104,
              fat: 26,
              matchConfidence: 0.86,
              nutritionSourceId: 'gemini_estimate',
              originalNutritionSourceId: 'gemini_estimate',
              sourceFamily: 'gemini',
              needsClarification: false,
              manualOverride: false,
              foodDescription: 'Masala dosa with sambar and chutneys',
              explanation: 'Estimated as one restaurant plate of masala dosa with sambar and chutneys.'
            }
          ],
          totals: {
            calories: 720,
            protein: 18,
            carbs: 104,
            fat: 26
          }
        },
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 300,
          outputTokens: 120,
          estimatedCostUsd: 0.00042
        }
      }))
    }));

    const debugEvents: Array<{ stage: string; ok: boolean; model?: string; caption?: string }> = [];
    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'dosa-image',
      debugEvents
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(1);
    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(2);
    expect(generateGeminiMultimodalText.mock.calls[0]?.[0]?.model).toBe('gemini-2.5-flash');
    expect(generateGeminiMultimodalText.mock.calls[1]?.[0]?.model).toBe('gemini-2.5-flash');
    expect(parsed.extractedText).toBe('masala dosa, sambar, coconut chutney, tomato chutney');
    expect(parsed.result.totals.calories).toBe(720);
    expect(debugEvents).toContainEqual(expect.objectContaining({ stage: 'image_caption', ok: false, model: 'gemini-2.5-flash' }));
    expect(debugEvents).toContainEqual(
      expect.objectContaining({
        stage: 'image_caption',
        ok: true,
        model: 'gemini-2.5-pro',
        caption: parsed.extractedText
      })
    );
  });

  test('does not accept sparse one-item caption when context indicates a multi-food thali', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_FALLBACK_MODEL = 'gemini-2.5-pro';

    const generateGeminiMultimodalJson = vi.fn().mockResolvedValueOnce(null);

    const generateGeminiMultimodalText = vi
      .fn()
      .mockResolvedValueOnce({
        jsonText: 'dal',
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 475,
          outputTokens: 1
        }
      })
      .mockResolvedValueOnce({
        jsonText: 'dal, baati, potato sabzi, green chutney, sliced onion, dry chutney powder',
        usage: {
          model: 'gemini-2.5-pro',
          inputTokens: 840,
          outputTokens: 20
        }
      });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryGeminiPrimaryParse: vi.fn(async (caption: string) => ({
        result: {
          confidence: 0.88,
          assumptions: [],
          items: caption.split(',').map((name, index) => ({
            name: name.trim(),
            quantity: 1,
            amount: 1,
            unit: index === 0 ? 'cup' : 'serving',
            unitNormalized: index === 0 ? 'cup' : 'serving',
            grams: index === 0 ? 198 : 40,
            gramsPerUnit: index === 0 ? 198 : 40,
            calories: [230, 280, 140, 20, 10, 35][index] ?? 20,
            protein: [18, 8, 3, 1, 0.3, 1][index] ?? 1,
            carbs: [40, 48, 20, 4, 2, 6][index] ?? 4,
            fat: [0.8, 6, 6, 0.2, 0.1, 1.5][index] ?? 1,
            matchConfidence: 0.88,
            nutritionSourceId: 'gemini_estimate',
            originalNutritionSourceId: 'gemini_estimate',
            sourceFamily: 'gemini',
            needsClarification: false,
            manualOverride: false,
            foodDescription: name.trim(),
            explanation: 'Estimated from visible thali component.'
          })),
          totals: {
            calories: 715,
            protein: 31.3,
            carbs: 120,
            fat: 14.6
          }
        },
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 330,
          outputTokens: 160,
          estimatedCostUsd: 0.00055
        }
      }))
    }));

    const debugEvents: Array<{ stage: string; ok: boolean; reason?: string; model?: string; caption?: string }> = [];
    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'thali-image',
      contextNote: 'Indian thali with dal, baati, potato sabzi, green chutney, sliced onion, and dry chutney powder.',
      debugEvents
    });

    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(2);
    expect(parsed.extractedText).toBe('dal, baati, potato sabzi, green chutney, sliced onion, dry chutney powder');
    expect(parsed.result.items.map((item) => item.name)).toEqual([
      'dal',
      'baati',
      'potato sabzi',
      'green chutney',
      'Onion',
      'Churma powder'
    ]);
    expect(debugEvents).toContainEqual(
      expect.objectContaining({
        stage: 'image_caption',
        ok: false,
        model: 'gemini-2.5-flash',
        reason: 'caption_too_sparse_for_multi_food_context',
        caption: 'dal'
      })
    );
  });

  test('escalates two-item captions after failed structured image parsing', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_FALLBACK_MODEL = 'gemini-2.5-pro';

    const generateGeminiMultimodalJson = vi.fn().mockResolvedValueOnce(null);

    const generateGeminiMultimodalText = vi
      .fn()
      .mockResolvedValueOnce({
        jsonText: 'dal, baati',
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 561,
          outputTokens: 4
        }
      })
      .mockResolvedValueOnce({
        jsonText: 'dal, baati, potato sabzi, green chutney, sliced onion, dry chutney powder',
        usage: {
          model: 'gemini-2.5-pro',
          inputTokens: 840,
          outputTokens: 20
        }
      });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryGeminiPrimaryParse: vi.fn(async (caption: string) => ({
        result: {
          confidence: 0.88,
          assumptions: [],
          items: caption.split(',').map((name, index) => ({
            name: name.trim(),
            quantity: 1,
            amount: 1,
            unit: index === 0 ? 'cup' : 'serving',
            unitNormalized: index === 0 ? 'cup' : 'serving',
            grams: 50,
            gramsPerUnit: 50,
            calories: [230, 280, 140, 20, 10, 35][index] ?? 20,
            protein: [18, 8, 3, 1, 0.3, 1][index] ?? 1,
            carbs: [40, 48, 20, 4, 2, 6][index] ?? 4,
            fat: [0.8, 6, 6, 0.2, 0.1, 1.5][index] ?? 1,
            matchConfidence: 0.88,
            nutritionSourceId: 'gemini_estimate',
            originalNutritionSourceId: 'gemini_estimate',
            sourceFamily: 'gemini',
            needsClarification: false,
            manualOverride: false,
            foodDescription: name.trim(),
            explanation: 'Estimated from visible thali component.'
          })),
          totals: {
            calories: 715,
            protein: 31.3,
            carbs: 120,
            fat: 14.6
          }
        },
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 330,
          outputTokens: 160,
          estimatedCostUsd: 0.00055
        }
      }))
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'thali-image'
    });

    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(2);
    expect(parsed.extractedText).toBe('dal, baati, potato sabzi, green chutney, sliced onion, dry chutney powder');
    expect(parsed.result.items).toHaveLength(6);
  });

  test('uses multi-food context instead of deferred sparse caption when stronger caption model fails', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_FALLBACK_MODEL = 'gemini-2.5-pro';

    const generateGeminiMultimodalJson = vi.fn().mockResolvedValueOnce(null);
    const generateGeminiMultimodalText = vi
      .fn()
      .mockResolvedValueOnce({
        jsonText: 'dal',
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 561,
          outputTokens: 1
        }
      })
      .mockResolvedValueOnce(null);

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryGeminiPrimaryParse: vi.fn(async (caption: string) => ({
        result: {
          confidence: 0.88,
          assumptions: [],
          items: caption.split(',').map((name, index) => ({
            name: name.trim().replace(/^Indian thali with\s+/i, ''),
            quantity: 1,
            amount: 1,
            unit: 'serving',
            unitNormalized: 'serving',
            grams: 50,
            gramsPerUnit: 50,
            calories: [230, 280, 140, 20, 10, 35][index] ?? 20,
            protein: 1,
            carbs: 4,
            fat: 1,
            matchConfidence: 0.88,
            nutritionSourceId: 'gemini_estimate',
            originalNutritionSourceId: 'gemini_estimate',
            sourceFamily: 'gemini',
            needsClarification: false,
            manualOverride: false,
            foodDescription: name.trim(),
            explanation: 'Estimated from context and visible thali component.'
          })),
          totals: {
            calories: 715,
            protein: 31.3,
            carbs: 120,
            fat: 14.6
          }
        },
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 330,
          outputTokens: 160,
          estimatedCostUsd: 0.00055
        }
      }))
    }));

    const debugEvents: Array<{ stage: string; ok: boolean; reason?: string; model?: string; caption?: string }> = [];
    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const contextNote = 'Indian thali with dal, baati, potato sabzi, green chutney, sliced onion, and dry chutney powder.';
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'thali-image',
      contextNote,
      debugEvents
    });

    expect(parsed.extractedText).toBe(contextNote);
    expect(parsed.result.items.length).toBeGreaterThanOrEqual(5);
    expect(debugEvents).toContainEqual(
      expect.objectContaining({
        stage: 'image_caption',
        ok: true,
        model: 'context',
        reason: 'using_multi_food_context_after_sparse_caption'
      })
    );
  });

  test('rejects Gemini boilerplate captions instead of saving zero-calorie non-food rows', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_FALLBACK_MODEL = 'gemini-2.5-pro';

    const generateGeminiMultimodalJson = vi
      .fn()
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(null);

    const generateGeminiMultimodalText = vi.fn().mockResolvedValueOnce({
      jsonText: 'Here is the JSON requested:\n```json',
      usage: {
        model: 'gemini-2.5-flash',
        inputTokens: 454,
        outputTokens: 9
      }
    });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryGeminiPrimaryParse: vi.fn(async () => ({
        result: {
          confidence: 0.1,
          assumptions: [],
          items: [
            {
              name: 'JSON request text',
              quantity: 1,
              amount: 1,
              unit: 'serving',
              unitNormalized: 'serving',
              grams: 0,
              gramsPerUnit: 0,
              calories: 0,
              protein: 0,
              carbs: 0,
              fat: 0,
              matchConfidence: 0.1,
              nutritionSourceId: 'gemini_estimate',
              originalNutritionSourceId: 'gemini_estimate',
              sourceFamily: 'gemini',
              needsClarification: true,
              manualOverride: false,
              foodDescription: 'JSON request text',
              explanation: 'Non-food text.'
            }
          ],
          totals: {
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0
          }
        },
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 300,
          outputTokens: 120,
          estimatedCostUsd: 0.00042
        }
      }))
    }));

    const debugEvents: Array<{ stage: string; ok: boolean; reason?: string }> = [];
    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    await expect(
      parseImageWithGemini({
        mimeType: 'image/jpeg',
        dataBase64: 'boilerplate-image',
        debugEvents
      })
    ).rejects.toMatchObject({
      code: 'IMAGE_PARSE_FAILED'
    });

    expect(debugEvents).toContainEqual(
      expect.objectContaining({
        stage: 'image_caption',
        ok: false,
        reason: 'caption_boilerplate'
      })
    );
  });

  test('accepts fenced top-level food item arrays from Gemini image parsing', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'false';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';

    const generateGeminiMultimodalJson = vi.fn(async () => ({
      jsonText: [
        '```json',
        JSON.stringify([
          {
            name: 'Dal',
            quantity: 1,
            unit: 'bowl',
            grams: 240,
            calories: 260,
            protein: 14,
            carbs: 38,
            fat: 7,
            matchConfidence: 0.9,
            foodDescription: 'Dal, 1 bowl',
            explanation: 'Estimated from one visible bowl of dal.'
          },
          {
            name: 'Baati',
            quantity: 2,
            unit: 'pieces',
            grams: 160,
            calories: 420,
            protein: 10,
            carbs: 62,
            fat: 14,
            matchConfidence: 0.84,
            foodDescription: 'Baati, 2 pieces',
            explanation: 'Estimated from two visible baati pieces.'
          }
        ]),
        '```'
      ].join('\n'),
      usage: {
        model: 'gemini-2.5-flash',
        inputTokens: 700,
        outputTokens: 180
      }
    }));

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText: vi.fn(async () => null)
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'thali-array-image'
    });

    expect(parsed.fallbackUsed).toBe(false);
    expect(parsed.lowConfidenceAccepted).toBe(false);
    expect(parsed.extractedText).toBe('Dal, Baati');
    expect(parsed.result.items.map((item) => item.name)).toEqual(['Dal', 'Baati']);
    expect(parsed.result.totals.calories).toBe(680);
  });

  test('V2 inventory parser returns complete multi-cuisine food logs in one fast call', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v2';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_COVERAGE_MIN = '0.75';
    process.env.AI_IMAGE_FAST_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_INVENTORY_MODEL = 'gemini-2.5-flash';

    const generateGeminiMultimodalJson = vi.fn(async () => ({
      jsonText: JSON.stringify({
        imageType: 'tray_or_thali',
        cuisineHints: ['indian'],
        visibleComponents: [
          { name: 'Dal', category: 'lentil curry', zone: 'left compartment', portionHint: 'large serving', confidence: 0.95, isSmallSide: false },
          { name: 'Baati', category: 'bread', zone: 'center', portionHint: '2 pieces', confidence: 0.9, isSmallSide: false },
          { name: 'Potato sabzi', category: 'vegetable side', zone: 'right bowl', portionHint: 'small bowl', confidence: 0.85, isSmallSide: false },
          { name: 'Green chutney', category: 'condiment', zone: 'top bowl', portionHint: 'small spoonful', confidence: 0.82, isSmallSide: true }
        ],
        items: [
          { name: 'Dal', quantity: 1, unit: 'serving', grams: 260, calories: 260, protein: 14, carbs: 38, fat: 7, matchConfidence: 0.9, foodDescription: 'Dal, 1 serving', explanation: 'Estimated from a large visible serving of dal.' },
          { name: 'Baati', quantity: 2, unit: 'pieces', grams: 160, calories: 420, protein: 10, carbs: 62, fat: 14, matchConfidence: 0.86, foodDescription: 'Baati, 2 pieces', explanation: 'Estimated from two visible baati breads.' },
          { name: 'Potato sabzi', quantity: 1, unit: 'small bowl', grams: 100, calories: 150, protein: 3, carbs: 22, fat: 6, matchConfidence: 0.82, foodDescription: 'Potato sabzi, small bowl', explanation: 'Estimated from a small visible serving of potato sabzi.' },
          { name: 'Green chutney', quantity: 1, unit: 'tablespoon', grams: 15, calories: 15, protein: 0.5, carbs: 2, fat: 0.5, matchConfidence: 0.8, foodDescription: 'Green chutney, 1 tablespoon', explanation: 'Estimated from a small chutney portion.' }
        ],
        coverage: { visibleComponentCount: 4, parsedItemCount: 4, score: 1, warnings: [] },
        extractedText: 'dal, baati, potato sabzi, green chutney',
        confidence: 0.88,
        assumptions: []
      }),
      usage: {
        model: 'gemini-2.5-flash',
        inputTokens: 900,
        outputTokens: 360
      }
    }));

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText: vi.fn(async () => null)
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'thali-v2-image'
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(1);
    expect(generateGeminiMultimodalJson.mock.calls[0]?.[0]?.timeoutMs).toBe(5500);
    expect(generateGeminiMultimodalJson.mock.calls[0]?.[0]?.parts[0]?.text).toContain('US/Western');
    expect(generateGeminiMultimodalJson.mock.calls[0]?.[0]?.parts[0]?.text).toContain('Chinese/East Asian');
    expect(generateGeminiMultimodalJson.mock.calls[0]?.[0]?.parts[0]?.text).toContain('Italian/Mediterranean');
    expect(parsed.usageEvents[0].feature).toBe('parse_image_inventory_v2');
    expect(parsed.fallbackUsed).toBe(false);
    expect(parsed.lowConfidenceAccepted).toBe(false);
    expect(parsed.result.items.map((item) => item.name)).toEqual(['Dal', 'Baati', 'Potato sabzi', 'Green chutney']);
    expect(parsed.result.totals.calories).toBe(845);
  });

  test('V2 structured inventory runs first and keeps packaged protein drinks as one item', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v2';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_COVERAGE_MIN = '0.75';
    process.env.AI_IMAGE_FAST_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_INVENTORY_MODEL = 'gemini-2.5-flash';

    const generateGeminiMultimodalJson = vi.fn(async () => ({
      jsonText: JSON.stringify({
        imageType: 'drink',
        cuisineHints: ['packaged'],
        visibleComponents: [
          { name: 'Mixed Berry Vanilla Protein Drink bottle', category: 'drink', zone: 'center', portionHint: '1 bottle', confidence: 0.95, isSmallSide: false }
        ],
        items: [
          { name: 'Mixed Berry Vanilla Protein Drink', quantity: 1, unit: 'bottle', grams: 330, calories: 160, protein: 30, carbs: 5, fat: 3, matchConfidence: 0.95, foodDescription: 'Mixed berry vanilla protein drink, 1 bottle', explanation: 'Visible packaged protein drink bottle.' },
          { name: 'Mixed Berry Vanilla Greek Yogurt', quantity: 1, unit: 'cup', grams: 245, calories: 185, protein: 20, carbs: 26, fat: 0, matchConfidence: 0.8, foodDescription: 'Mixed berry vanilla Greek yogurt', explanation: 'Mistaken flavor split.' },
          { name: 'Mixed Berries', quantity: 1, unit: 'cup', grams: 150, calories: 80, protein: 1, carbs: 20, fat: 0.5, matchConfidence: 0.9, foodDescription: 'Mixed berries', explanation: 'Mistaken flavor split.' }
        ],
        coverage: { visibleComponentCount: 1, parsedItemCount: 3, score: 1, warnings: [] },
        extractedText: 'Mixed Berry Vanilla Protein Drink',
        confidence: 0.93,
        assumptions: []
      }),
      usage: {
        model: 'gemini-2.5-flash',
        inputTokens: 760,
        outputTokens: 260
      }
    }));
    const generateGeminiMultimodalText = vi.fn(async () => null);

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'protein-drink-image'
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(1);
    expect(parsed.usageEvents.map((event) => event.feature)).toEqual(['parse_image_inventory_v2']);
    expect(parsed.extractedText).toBe('Mixed Berry Vanilla Protein Drink');
    expect(parsed.result.items.map((item) => item.name)).toEqual(['Mixed Berry Vanilla Protein Drink']);
    expect(parsed.result.totals).toEqual({ calories: 160, protein: 30, carbs: 5, fat: 3 });
  });

  test('V2 fast caption recovery treats packaged protein drink flavor fragments as one item', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v2';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_COVERAGE_MIN = '0.75';
    process.env.AI_IMAGE_FAST_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_INVENTORY_MODEL = 'gemini-2.5-flash';

    const generateGeminiMultimodalJson = vi.fn(async () => null);
    const generateGeminiMultimodalText = vi.fn().mockResolvedValueOnce({
      jsonText: 'Mixed Berry Vanilla Protein Drink, Mixed Berry Vanilla',
      usage: { model: 'gemini-2.5-flash', inputTokens: 420, outputTokens: 10 }
    });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'protein-drink-caption-image'
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(1);
    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(1);
    expect(parsed.fallbackUsed).toBe(true);
    expect(parsed.model).toBe('gemini-2.5-flash');
    expect(parsed.extractedText).toBe('Mixed Berry Vanilla Protein Drink');
    expect(parsed.result.items.map((item) => item.name)).toEqual(['Mixed Berry Vanilla Protein Drink']);
    expect(parsed.result.items[0]).toMatchObject({
      quantity: 1,
      unit: 'bottle',
      calories: 170,
      protein: 25,
      carbs: 14,
      fat: 2.5,
      needsClarification: true
    });
  });

  test('V2 product caption can return before a slow inventory path finishes', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v2';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_COVERAGE_MIN = '0.75';
    process.env.AI_IMAGE_FAST_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_PRODUCT_BUDGET_MS = '5000';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_INVENTORY_MODEL = 'gemini-2.5-flash';

    const debugEvents = [];
    const generateGeminiMultimodalJson = vi.fn(() => new Promise<null>(() => {}));
    const generateGeminiMultimodalText = vi.fn().mockResolvedValueOnce({
      jsonText: 'RXBAR blueberry protein bar, 1 bar',
      usage: { model: 'gemini-2.5-flash', inputTokens: 420, outputTokens: 10 }
    });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'rxbar-product-image',
      debugEvents
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(1);
    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(1);
    expect(parsed.fallbackUsed).toBe(true);
    expect(parsed.result.items.map((item) => item.name)).toEqual(['RXBAR Blueberry Protein Bar']);
    expect(parsed.result.totals.calories).toBe(180);
    expect(debugEvents).toContainEqual(
      expect.objectContaining({
        stage: 'image_orchestrator_v2',
        ok: true,
        reason: 'fast_product_caption_return'
      })
    );
  });

  test('V2 sparse thali caption expands with staple and side probes before accepting heuristics', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v2';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_COVERAGE_MIN = '0.75';
    process.env.AI_IMAGE_FAST_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_FALLBACK_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_INVENTORY_MODEL = 'gemini-2.5-flash';

    const debugEvents = [];
    const generateGeminiMultimodalJson = vi.fn(async () => null);
    const generateGeminiMultimodalText = vi
      .fn()
      .mockResolvedValueOnce({
        jsonText: 'Dal, Potato Sab',
        usage: { model: 'gemini-2.5-flash', inputTokens: 420, outputTokens: 8 }
      })
      .mockResolvedValueOnce({
        jsonText: 'Baati',
        usage: { model: 'gemini-2.5-flash', inputTokens: 410, outputTokens: 4 }
      })
      .mockResolvedValueOnce({
        jsonText: 'Green chutney, Onion, Churma powder',
        usage: { model: 'gemini-2.5-flash', inputTokens: 415, outputTokens: 9 }
      });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'sparse-thali-caption-image',
      debugEvents
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(1);
    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(3);
    expect(parsed.usageEvents.map((event) => event.feature)).toEqual([
      'parse_image_caption',
      'parse_image_caption',
      'parse_image_caption'
    ]);
    expect(parsed.result.items.map((item) => item.name)).toEqual(
      expect.arrayContaining(['Dal', 'Potato sabzi', 'Baati', 'Green chutney', 'Onion', 'Churma powder'])
    );
    expect(parsed.result.items).toHaveLength(6);
    expect(parsed.result.totals.calories).toBeGreaterThan(850);
    expect(debugEvents).toContainEqual(
      expect.objectContaining({
        stage: 'image_caption_fast_v2',
        ok: true,
        reason: 'expanded_sparse_known_meal_component_caption'
      })
    );
  });

  test('V2 sparse caption guard is cuisine-agnostic for generic meal components', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v2';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_COVERAGE_MIN = '0.75';
    process.env.AI_IMAGE_FAST_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_FALLBACK_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_INVENTORY_MODEL = 'gemini-2.5-flash';

    const debugEvents = [];
    const generateGeminiMultimodalJson = vi.fn(async () => null);
    const generateGeminiMultimodalText = vi
      .fn()
      .mockResolvedValueOnce({
        jsonText: 'Rice',
        usage: { model: 'gemini-2.5-flash', inputTokens: 420, outputTokens: 3 }
      })
      .mockResolvedValueOnce({
        jsonText: 'Roasted chicken, rice',
        usage: { model: 'gemini-2.5-flash', inputTokens: 410, outputTokens: 6 }
      })
      .mockResolvedValueOnce({
        jsonText: 'Carrots, ranch dressing',
        usage: { model: 'gemini-2.5-flash', inputTokens: 415, outputTokens: 6 }
      });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'generic-sparse-caption-image',
      debugEvents
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(1);
    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(3);
    expect(parsed.result.items.map((item) => item.name)).toEqual(
      expect.arrayContaining(['White rice', 'Roasted chicken', 'Carrots', 'Ranch dressing'])
    );
    expect(debugEvents).toContainEqual(
      expect.objectContaining({
        stage: 'image_caption_fast_v2',
        ok: true,
        reason: 'expanded_sparse_single_component_caption'
      })
    );
  });

  test('V2 sparse single-component thali caption must pass structured rescue before returning', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v2';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_COVERAGE_MIN = '0.75';
    process.env.AI_IMAGE_FAST_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_FALLBACK_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_INVENTORY_MODEL = 'gemini-2.5-flash';

    const debugEvents = [];
    const generateGeminiMultimodalJson = vi
      .fn()
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({
        jsonText: JSON.stringify({
          extractedText: 'dal, baati, potato sabzi, green chutney, onion',
          confidence: 0.86,
          assumptions: ['Estimated from all visible tray compartments.'],
          items: [
            { name: 'Dal', quantity: 1, unit: 'serving', grams: 240, calories: 240, protein: 14, carbs: 38, fat: 6, matchConfidence: 0.86, foodDescription: 'Dal, 1 serving', explanation: 'Estimated from visible dal.' },
            { name: 'Baati', quantity: 2, unit: 'pieces', grams: 120, calories: 360, protein: 9, carbs: 58, fat: 12, matchConfidence: 0.82, foodDescription: 'Baati, 2 pieces', explanation: 'Estimated from visible baati.' },
            { name: 'Potato sabzi', quantity: 1, unit: 'serving', grams: 120, calories: 160, protein: 3, carbs: 25, fat: 6, matchConfidence: 0.78, foodDescription: 'Potato sabzi, 1 serving', explanation: 'Estimated from visible potato sabzi.' },
            { name: 'Green chutney', quantity: 2, unit: 'tbsp', grams: 30, calories: 30, protein: 1, carbs: 4, fat: 1, matchConfidence: 0.72, foodDescription: 'Green chutney, 2 tbsp', explanation: 'Estimated from visible chutney.' },
            { name: 'Onion', quantity: 1, unit: 'small side', grams: 40, calories: 16, protein: 0.4, carbs: 3.7, fat: 0, matchConfidence: 0.72, foodDescription: 'Onion, small side', explanation: 'Estimated from visible sliced onion.' }
          ]
        }),
        usage: { model: 'gemini-2.5-flash', inputTokens: 900, outputTokens: 260 }
      });
    const generateGeminiMultimodalText = vi
      .fn()
      .mockResolvedValueOnce({
        jsonText: 'Baati',
        usage: { model: 'gemini-2.5-flash', inputTokens: 420, outputTokens: 3 }
      })
      .mockResolvedValueOnce({
        jsonText: 'Baati',
        usage: { model: 'gemini-2.5-flash', inputTokens: 410, outputTokens: 3 }
      })
      .mockResolvedValueOnce({
        jsonText: 'Baati',
        usage: { model: 'gemini-2.5-flash', inputTokens: 415, outputTokens: 3 }
      });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'baati-only-caption-thali-image',
      debugEvents
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(2);
    expect(generateGeminiMultimodalJson.mock.calls[1]?.[0]?.parts[0]?.text).toContain('fallback parser');
    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(3);
    expect(parsed.fallbackUsed).toBe(true);
    expect(parsed.orchestratorVersion).toBe('v2');
    expect(parsed.extractedText).toBe('dal, baati, potato sabzi, green chutney, onion');
    expect(parsed.result.items.map((item) => item.name)).toEqual(['Dal', 'Baati', 'Potato sabzi', 'Green chutney', 'Onion']);
    expect(debugEvents).toContainEqual(
      expect.objectContaining({
        stage: 'image_caption_heuristic_v2',
        ok: false,
        reason: 'sparse_single_component_caption_structured_rescue_deferred'
      })
    );
  });

  test('V2 hard rescue uses bounded image timeouts instead of the legacy long timeout', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v2';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_COVERAGE_MIN = '0.75';
    process.env.AI_IMAGE_FAST_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_RESCUE_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_HARD_RESCUE_BUDGET_MS = '12000';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_FALLBACK_MODEL = 'gemini-2.5-pro';
    process.env.AI_IMAGE_INVENTORY_MODEL = 'gemini-2.5-flash';

    const generateGeminiMultimodalJson = vi
      .fn()
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(null);
    const generateGeminiMultimodalText = vi.fn(async () => null);

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    await expect(
      parseImageWithGemini({
        mimeType: 'image/jpeg',
        dataBase64: 'failed-hard-rescue-image'
      })
    ).rejects.toMatchObject({ code: 'IMAGE_PARSE_FAILED' });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(3);
    expect(generateGeminiMultimodalJson.mock.calls[1]?.[0]?.timeoutMs).toBeLessThanOrEqual(6000);
    expect(generateGeminiMultimodalJson.mock.calls[2]?.[0]?.timeoutMs).toBeLessThanOrEqual(6000);
    expect(generateGeminiMultimodalJson.mock.calls[1]?.[0]?.timeoutMs).not.toBe(35000);
  });

  test('V2 returns a reviewable sparse caption estimate when hard rescue times out', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v2';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_COVERAGE_MIN = '0.75';
    process.env.AI_IMAGE_FAST_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_RESCUE_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_HARD_RESCUE_BUDGET_MS = '18000';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_FALLBACK_MODEL = 'gemini-2.5-pro';
    process.env.AI_IMAGE_INVENTORY_MODEL = 'gemini-2.5-flash';

    const debugEvents = [];
    const generateGeminiMultimodalJson = vi
      .fn()
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(null);
    const generateGeminiMultimodalText = vi
      .fn()
      .mockResolvedValueOnce({
        jsonText: 'white rice, dal',
        usage: { model: 'gemini-2.5-flash', inputTokens: 420, outputTokens: 5 }
      })
      .mockResolvedValueOnce({
        jsonText: 'white rice',
        usage: { model: 'gemini-2.5-flash', inputTokens: 410, outputTokens: 3 }
      })
      .mockResolvedValueOnce({
        jsonText: 'white rice',
        usage: { model: 'gemini-2.5-flash', inputTokens: 415, outputTokens: 3 }
      });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'sparse-caption-hard-rescue-timeout-image',
      debugEvents
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(3);
    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(3);
    expect(parsed.fallbackUsed).toBe(true);
    expect(parsed.lowConfidenceAccepted).toBe(true);
    expect(parsed.coverage?.partial).toBe(true);
    expect(parsed.result.items.map((item) => item.name)).toEqual(['White rice', 'Dal']);
    expect(parsed.result.items.every((item) => item.needsClarification)).toBe(true);
    expect(debugEvents).toContainEqual(
      expect.objectContaining({
        stage: 'image_orchestrator_v2',
        ok: true,
        reason: 'bounded_rescue_failed_using_reviewable_caption'
      })
    );
  });

  test('V2 fast caption recovery uses text nutrition parser for foods outside heuristic inventory', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v2';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_COVERAGE_MIN = '0.75';
    process.env.AI_IMAGE_FAST_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_INVENTORY_MODEL = 'gemini-2.5-flash';

    const generateGeminiMultimodalJson = vi.fn(async () => null);
    const generateGeminiMultimodalText = vi.fn().mockResolvedValueOnce({
      jsonText: 'beef empanadas, chimichurri, black bean salad',
      usage: { model: 'gemini-2.5-flash', inputTokens: 430, outputTokens: 12 }
    });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    vi.doMock('../src/services/aiNormalizerService.js', () => ({
      tryGeminiPrimaryParse: vi.fn(async (caption: string) => ({
        result: {
          confidence: 0.84,
          assumptions: [],
          items: [
            {
              name: 'Beef empanadas with chimichurri and black bean salad',
              quantity: 1,
              amount: 1,
              unit: 'plate',
              unitNormalized: 'plate',
              grams: 480,
              gramsPerUnit: 480,
              calories: 820,
              protein: 32,
              carbs: 86,
              fat: 38,
              matchConfidence: 0.84,
              nutritionSourceId: 'gemini_estimate',
              originalNutritionSourceId: 'gemini_estimate',
              sourceFamily: 'gemini',
              needsClarification: false,
              manualOverride: false,
              foodDescription: caption,
              explanation: 'Estimated as one plate from the caption inventory.'
            }
          ],
          totals: {
            calories: 820,
            protein: 32,
            carbs: 86,
            fat: 38
          }
        },
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 320,
          outputTokens: 110,
          estimatedCostUsd: 0.0004
        }
      }))
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'latin-food-caption-image'
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(1);
    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(1);
    expect(parsed.usageEvents.map((event) => event.feature)).toEqual([
      'parse_image_caption',
      'parse_image_caption_text'
    ]);
    expect(parsed.extractedText).toBe('Beef Empanadas, Chimichurri, Black Bean Salad');
    expect(parsed.result.items[0].name).toBe('Beef empanadas with chimichurri and black bean salad');
    expect(parsed.result.items[0].needsClarification).toBe(true);
    expect(parsed.result.totals.calories).toBe(820);
  });

  test('V2 inventory parser returns reviewable partial parses instead of failing sparse multi-item meals', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v2';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_COVERAGE_MIN = '0.75';
    process.env.AI_IMAGE_FAST_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_INVENTORY_MODEL = 'gemini-2.5-flash';

    const debugEvents = [];
    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson: vi.fn(async () => ({
        jsonText: JSON.stringify({
          imageType: 'tray_or_thali',
          cuisineHints: ['indian'],
          visibleComponents: [
            { name: 'Dal', category: 'lentil curry', zone: 'left', portionHint: 'large serving', confidence: 0.9, isSmallSide: false },
            { name: 'Baati', category: 'bread', zone: 'center', portionHint: '2 pieces', confidence: 0.75, isSmallSide: false },
            { name: 'Potato sabzi', category: 'vegetable side', zone: 'right', portionHint: 'small bowl', confidence: 0.7, isSmallSide: false },
            { name: 'Green chutney', category: 'condiment', zone: 'top', portionHint: 'small spoonful', confidence: 0.7, isSmallSide: true },
            { name: 'Onion', category: 'salad', zone: 'bottom', portionHint: 'small side', confidence: 0.65, isSmallSide: true }
          ],
          items: [
            { name: 'Dal', quantity: 1, unit: 'serving', grams: 260, calories: 260, protein: 14, carbs: 38, fat: 7, matchConfidence: 0.9, foodDescription: 'Dal, 1 serving', explanation: 'Estimated from visible dal.' },
            { name: 'Green chutney', quantity: 1, unit: 'tablespoon', grams: 15, calories: 15, protein: 0.5, carbs: 2, fat: 0.5, matchConfidence: 0.7, foodDescription: 'Green chutney, 1 tablespoon', explanation: 'Estimated from visible chutney.' }
          ],
          coverage: { visibleComponentCount: 5, parsedItemCount: 2, score: 0.4, warnings: ['Visible tray looks partially covered; review missing bread and sides.'] },
          extractedText: 'dal, green chutney',
          confidence: 0.82,
          assumptions: []
        }),
        usage: {
          model: 'gemini-2.5-flash',
          inputTokens: 900,
          outputTokens: 260
        }
      })),
      generateGeminiMultimodalText: vi.fn(async () => null)
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'partial-thali-v2-image',
      debugEvents
    });

    expect(parsed.fallbackUsed).toBe(false);
    expect(parsed.lowConfidenceAccepted).toBe(true);
    expect(parsed.result.confidence).toBeLessThan(0.7);
    expect(parsed.result.items.map((item) => item.needsClarification)).toEqual([true, true]);
    expect(parsed.result.assumptions).toContain('Visible tray looks partially covered; review missing bread and sides.');
    expect(debugEvents).toContainEqual(
      expect.objectContaining({
        stage: 'image_inventory_v2',
        ok: true,
        reason: 'partial_coverage'
      })
    );
  });

  test('V2 fast caption recovery removes thali fragments before nutrition parsing', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v2';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_COVERAGE_MIN = '0.75';
    process.env.AI_IMAGE_FAST_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_INVENTORY_MODEL = 'gemini-2.5-flash';

    const generateGeminiMultimodalJson = vi.fn(async () => null);
    const generateGeminiMultimodalText = vi.fn().mockResolvedValueOnce({
      jsonText: 'dal, green, ba, green chutney',
      usage: { model: 'gemini-2.5-flash', inputTokens: 420, outputTokens: 8 }
    });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'fragmented-thali-image'
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(1);
    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(1);
    expect(parsed.extractedText).toBe('Dal, Green chutney, Baati');
    expect(parsed.result.items.map((item) => item.name)).toEqual(['Dal', 'Green chutney', 'Baati']);
    const itemNames = parsed.result.items.map((item) => item.name.toLowerCase());
    ['green', 'ba', 'al', 'potato'].forEach((name) => expect(itemNames).not.toContain(name));
  });

  test('V2 fast caption recovery merges flatbread and chutney duplicates into one clean item each', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.AI_IMAGE_PARSE_ENABLED = 'true';
    process.env.AI_IMAGE_ORCHESTRATOR_VERSION = 'v2';
    process.env.AI_IMAGE_ENABLE_FALLBACK = 'true';
    process.env.AI_IMAGE_CONFIDENCE_MIN = '0.7';
    process.env.AI_IMAGE_COVERAGE_MIN = '0.75';
    process.env.AI_IMAGE_FAST_TIMEOUT_MS = '6000';
    process.env.AI_IMAGE_PRIMARY_MODEL = 'gemini-2.5-flash';
    process.env.AI_IMAGE_INVENTORY_MODEL = 'gemini-2.5-flash';

    const generateGeminiMultimodalJson = vi.fn(async () => null);
    const generateGeminiMultimodalText = vi.fn().mockResolvedValueOnce({
      jsonText: 'thepla, mango, chutney, fenugreek par',
      usage: { model: 'gemini-2.5-flash', inputTokens: 420, outputTokens: 10 }
    });

    vi.doMock('../src/services/geminiFlashClient.js', () => ({
      generateGeminiMultimodalJson,
      generateGeminiMultimodalText
    }));

    const { parseImageWithGemini } = await import('../src/services/imageParseService.js');
    const parsed = await parseImageWithGemini({
      mimeType: 'image/jpeg',
      dataBase64: 'flatbread-duplicates-image'
    });

    expect(generateGeminiMultimodalJson).toHaveBeenCalledTimes(1);
    expect(generateGeminiMultimodalText).toHaveBeenCalledTimes(1);
    expect(parsed.extractedText).toBe('Thepla, Mango chutney');
    expect(parsed.result.items.map((item) => item.name)).toEqual(['Methi paratha', 'Mango chutney']);
    const itemNames = parsed.result.items.map((item) => item.name.toLowerCase());
    ['thepla', 'fenugreek paratha', 'methi flatbread', 'meth', 'methi par', 'mango'].forEach((name) =>
      expect(itemNames).not.toContain(name)
    );
  });
});
