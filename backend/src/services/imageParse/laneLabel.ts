import { z } from 'zod';
import { config } from '../../config.js';
import { ApiError } from '../../utils/errors.js';
import type { ParseResult, ParsedItem } from '../deterministicParser.js';
import { generateGeminiMultimodalJson, type GeminiUsage } from '../geminiFlashClient.js';
import { buildLabelParsePrompt } from './prompts/labelParse.js';
import type { ImageParseServiceResult } from './types.js';

const labelItemSchema = z.object({
  name: z.string().trim().min(1).default('Packaged food (label)'),
  brand: z.string().trim().nullable().optional(),
  servingSize: z.string().trim().min(1).default('1 serving'),
  servingSizeG: z.coerce.number().finite().min(0).default(0),
  calories: z.coerce.number().finite().min(0).default(0),
  proteinG: z.coerce.number().finite().min(0).default(0),
  carbsG: z.coerce.number().finite().min(0).default(0),
  fatG: z.coerce.number().finite().min(0).default(0),
  fiberG: z.coerce.number().finite().min(0).nullable().optional(),
  sugarG: z.coerce.number().finite().min(0).nullable().optional(),
  sodiumMg: z.coerce.number().finite().min(0).nullable().optional()
});

const labelResponseSchema = z.object({
  imageType: z.string().optional(),
  items: z.array(labelItemSchema).min(1),
  confidence: z.coerce.number().finite().min(0).max(1).default(0.75),
  coverage: z.object({
    score: z.coerce.number().finite().min(0).max(1).default(1),
    warnings: z.array(z.string()).default([])
  }).optional()
});

function round(value: number, digits = 1): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function estimateCostUsd(usage: GeminiUsage): number {
  const model = usage.model.toLowerCase();
  const inputRate = model.includes('lite') ? config.geminiFlashLiteInputUsdPer1M : config.geminiFlashInputUsdPer1M;
  const outputRate = model.includes('lite') ? config.geminiFlashLiteOutputUsdPer1M : config.geminiFlashOutputUsdPer1M;
  return (usage.inputTokens / 1_000_000) * inputRate + (usage.outputTokens / 1_000_000) * outputRate;
}

function extractJson(text: string): string | null {
  const trimmed = text.trim();
  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i)?.[1]?.trim();
  if (fenced) return fenced;
  const start = trimmed.indexOf('{');
  const end = trimmed.lastIndexOf('}');
  return start >= 0 && end > start ? trimmed.slice(start, end + 1) : null;
}

function numberAfter(pattern: RegExp, text: string): number | null {
  const match = text.match(pattern);
  if (!match) return null;
  const value = Number(match[1].replace(/,/g, ''));
  return Number.isFinite(value) ? value : null;
}

function heuristicParse(ocrText: string): z.infer<typeof labelResponseSchema> | null {
  const calories = numberAfter(/\bcalories\s*[:\-]?\s*(\d{1,4})\b/i, ocrText);
  const fatG = numberAfter(/\btotal\s+fat\s*[:\-]?\s*(\d+(?:\.\d+)?)\s*g\b/i, ocrText) ?? 0;
  const carbsG = numberAfter(/\b(?:total\s+)?carbohydrate\s*[:\-]?\s*(\d+(?:\.\d+)?)\s*g\b/i, ocrText) ?? 0;
  const proteinG = numberAfter(/\bprotein\s*[:\-]?\s*(\d+(?:\.\d+)?)\s*g\b/i, ocrText) ?? 0;
  const servingMatch = ocrText.match(/\bserving size\s*[:\-]?\s*([^\n\r]{1,60})/i)?.[1]?.trim();
  if (calories === null && fatG === 0 && carbsG === 0 && proteinG === 0) return null;
  return {
    imageType: 'nutrition_label',
    confidence: calories === null ? 0.62 : 0.72,
    coverage: {
      score: calories === null ? 0.7 : 0.85,
      warnings: calories === null ? ['Calories were estimated from visible macros.'] : []
    },
    items: [
      {
        name: 'Packaged food (label)',
        brand: null,
        servingSize: servingMatch || '1 serving',
        servingSizeG: 0,
        calories: calories ?? round(fatG * 9 + carbsG * 4 + proteinG * 4, 0),
        proteinG,
        carbsG,
        fatG,
        fiberG: numberAfter(/\bfiber\s*[:\-]?\s*(\d+(?:\.\d+)?)\s*g\b/i, ocrText),
        sugarG: numberAfter(/\bsugars?\s*[:\-]?\s*(\d+(?:\.\d+)?)\s*g\b/i, ocrText),
        sodiumMg: numberAfter(/\bsodium\s*[:\-]?\s*(\d{1,4})\s*mg\b/i, ocrText)
      }
    ]
  };
}

function parseResultFromLabel(payload: z.infer<typeof labelResponseSchema>): ParseResult {
  const items: ParsedItem[] = payload.items.map((item) => {
    const name = [item.brand ?? '', item.name].filter(Boolean).join(' ').trim() || 'Packaged food (label)';
    return {
      name,
      quantity: 1,
      amount: 1,
      unit: item.servingSize,
      unitNormalized: item.servingSize,
      grams: round(item.servingSizeG),
      gramsPerUnit: item.servingSizeG > 0 ? round(item.servingSizeG) : null,
      calories: round(item.calories),
      protein: round(item.proteinG),
      carbs: round(item.carbsG),
      fat: round(item.fatG),
      matchConfidence: payload.confidence,
      nutritionSourceId: 'gemini_label_estimate',
      originalNutritionSourceId: 'gemini_label_estimate',
      sourceFamily: 'gemini',
      needsClarification: payload.confidence < 0.7,
      manualOverride: false,
      foodDescription: `${name}, ${item.servingSize}`,
      explanation: 'Parsed from the visible Nutrition Facts panel.'
    };
  });
  return {
    confidence: payload.confidence,
    assumptions: payload.coverage?.warnings ?? [],
    items,
    totals: {
      calories: round(items.reduce((sum, item) => sum + item.calories, 0)),
      protein: round(items.reduce((sum, item) => sum + item.protein, 0)),
      carbs: round(items.reduce((sum, item) => sum + item.carbs, 0)),
      fat: round(items.reduce((sum, item) => sum + item.fat, 0))
    }
  };
}

export async function parseLabel(args: {
  ocrText: string;
  imageBase64?: string;
  mimeType?: string;
  contextNote?: string;
  signal?: AbortSignal;
  timeoutMs?: number;
}): Promise<ImageParseServiceResult & { laneSource: string; laneLatencyMs: number }> {
  const startedAt = Date.now();
  const parts = [
    { text: buildLabelParsePrompt({ ocrText: args.ocrText, contextNote: args.contextNote }) },
    ...(args.imageBase64 && args.mimeType
      ? [{ inlineData: { mimeType: args.mimeType, data: args.imageBase64 } }]
      : [])
  ];
  const response = await generateGeminiMultimodalJson({
    model: config.aiImageLabelModel,
    parts,
    temperature: 0,
    maxOutputTokens: 650,
    timeoutMs: args.timeoutMs ?? 3000,
    maxAttempts: 1
  });

  let payload: z.infer<typeof labelResponseSchema> | null = null;
  if (response) {
    const json = extractJson(response.jsonText);
    if (json) {
      try {
        const parsed = JSON.parse(json);
        const result = labelResponseSchema.safeParse(parsed);
        if (result.success) payload = result.data;
      } catch {
        payload = null;
      }
    }
  }

  payload ??= heuristicParse(args.ocrText);
  if (!payload) {
    throw new ApiError(422, 'LABEL_PARSE_FAILED', 'Unable to parse Nutrition Facts from this label.');
  }

  return {
    extractedText: payload.items.map((item) => [item.brand, item.name].filter(Boolean).join(' ') || item.name).join(', '),
    result: parseResultFromLabel(payload),
    model: response?.usage.model ?? 'ocr_label_heuristic',
    fallbackUsed: !response,
    lowConfidenceAccepted: payload.confidence < config.aiImageConfidenceMin,
    usageEvents: response
      ? [
          {
            feature: 'parse_image_label',
            usage: response.usage,
            estimatedCostUsd: estimateCostUsd(response.usage)
          }
        ]
      : [],
    orchestratorVersion: 'v2',
    coverage: {
      imageType: 'nutrition_label',
      cuisineHints: [],
      visibleComponents: [
        {
          name: 'Nutrition Facts panel',
          category: 'label',
          zone: 'visible label',
          portionHint: payload.items[0]?.servingSize ?? '1 serving',
          confidence: payload.confidence,
          isSmallSide: false
        }
      ],
      visibleComponentCount: 1,
      parsedItemCount: payload.items.length,
      score: payload.coverage?.score ?? 1,
      warnings: payload.coverage?.warnings ?? [],
      partial: (payload.coverage?.score ?? 1) < 0.75
    },
    laneSource: response ? 'gemini' : 'ocr_heuristic',
    laneLatencyMs: Math.max(0, Date.now() - startedAt)
  };
}
