import { z } from 'zod';
import { config } from '../config.js';
import { ApiError } from '../utils/errors.js';
import type { ParseResult, ParsedItem } from './deterministicParser.js';
import { normalizeParseResultContract } from './parseContractService.js';
import { generateGeminiMultimodalJson, type GeminiUsage } from './geminiFlashClient.js';

type ImageParseUsageEvent = {
  feature: 'parse_image_primary' | 'parse_image_fallback';
  usage: GeminiUsage;
  estimatedCostUsd: number;
};

export type ImageParseServiceResult = {
  extractedText: string;
  result: ParseResult;
  model: string;
  fallbackUsed: boolean;
  usageEvents: ImageParseUsageEvent[];
};

type ImagePart = {
  mimeType: string;
  dataBase64: string;
};

const parseItemSchema = z.object({
  name: z.string().min(1),
  quantity: z.number().nonnegative(),
  unit: z.string().min(1),
  grams: z.number().nonnegative(),
  calories: z.number().nonnegative(),
  protein: z.number().nonnegative(),
  carbs: z.number().nonnegative(),
  fat: z.number().nonnegative(),
  matchConfidence: z.number().min(0).max(1).optional(),
  foodDescription: z.string().optional(),
  explanation: z.string().optional()
});

const imageParseSchema = z.object({
  extractedText: z.string().optional(),
  confidence: z.number().min(0).max(1),
  assumptions: z.array(z.string()).default([]),
  items: z.array(parseItemSchema).min(1)
});

function round(value: number, digits = 4): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function nonNegative(value: number): number {
  if (!Number.isFinite(value) || value < 0) {
    return 0;
  }
  return value;
}

function trimSafe(value: string | undefined | null): string {
  return (value || '').trim();
}

function priceForModel(model: string): { inputUsdPer1M: number; outputUsdPer1M: number } {
  const normalized = model.trim().toLowerCase();
  if (normalized.includes('flash-lite')) {
    return {
      inputUsdPer1M: config.geminiFlashLiteInputUsdPer1M,
      outputUsdPer1M: config.geminiFlashLiteOutputUsdPer1M
    };
  }

  return {
    inputUsdPer1M: config.geminiFlashInputUsdPer1M,
    outputUsdPer1M: config.geminiFlashOutputUsdPer1M
  };
}

function estimateCostUsd(usage: GeminiUsage): number {
  const rates = priceForModel(usage.model);
  const inputCost = (nonNegative(usage.inputTokens) / 1_000_000) * nonNegative(rates.inputUsdPer1M);
  const outputCost = (nonNegative(usage.outputTokens) / 1_000_000) * nonNegative(rates.outputUsdPer1M);
  return round(inputCost + outputCost, 6);
}

function buildImageParsePrompt(): string {
  return [
    'You are a nutrition parsing assistant for food photo logs.',
    'Analyze the attached food image and return strict JSON only (no markdown).',
    'Output schema exactly:',
    '{"extractedText":string,"confidence":number,"assumptions":string[],"items":[{"name":string,"quantity":number,"unit":string,"grams":number,"calories":number,"protein":number,"carbs":number,"fat":number,"matchConfidence":number,"foodDescription":string,"explanation":string}]}',
    'Rules:',
    '- Use realistic serving assumptions when quantity is unclear.',
    '- Return non-empty items if edible foods are visible.',
    '- Confidence and matchConfidence are in [0,1].',
    '- Do not return negative numbers.',
    '- extractedText should be a concise comma-separated phrase list in user-entered order.',
    '- assumptions should be [] unless an assumption is essential.',
    '- nutritionSourceId is not needed in output; it is added downstream.',
    '- Keep explanations concise and user-friendly (1-2 sentences).',
    '- If image has no food, return confidence 0 and items [].'
  ].join('\n');
}

function parseGeminiOutput(payloadText: string): { extractedText: string; result: ParseResult } | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(payloadText);
  } catch {
    return null;
  }

  const validated = imageParseSchema.safeParse(parsed);
  if (!validated.success) {
    return null;
  }

  const value = validated.data;
  const normalizedItems: ParsedItem[] = value.items.map((item) => {
    const quantity = Math.max(nonNegative(item.quantity), 0.0001);
    const grams = nonNegative(item.grams);
    const unit = trimSafe(item.unit) || 'count';
    const name = trimSafe(item.name) || 'Food item';
    const matchConfidence = nonNegative(item.matchConfidence ?? value.confidence);

    return {
      name,
      quantity,
      unit,
      grams,
      calories: nonNegative(item.calories),
      protein: nonNegative(item.protein),
      carbs: nonNegative(item.carbs),
      fat: nonNegative(item.fat),
      matchConfidence: Math.min(1, matchConfidence),
      nutritionSourceId: 'gemini_image_estimate',
      originalNutritionSourceId: 'gemini_image_estimate',
      sourceFamily: 'gemini',
      amount: quantity,
      unitNormalized: unit,
      gramsPerUnit: grams > 0 ? round(grams / quantity, 4) : null,
      needsClarification: false,
      manualOverride: false,
      foodDescription: trimSafe(item.foodDescription) || name,
      explanation: trimSafe(item.explanation) || 'AI image estimate based on visible foods.'
    };
  });

  if (normalizedItems.length === 0) {
    return null;
  }

  const extractedText = trimSafe(value.extractedText) || normalizedItems.map((item) => item.name).join(', ');

  const baseResult: ParseResult = {
    confidence: Math.min(1, nonNegative(value.confidence)),
    assumptions: Array.isArray(value.assumptions) ? value.assumptions.slice(0, 8) : [],
    items: normalizedItems,
    totals: {
      calories: 0,
      protein: 0,
      carbs: 0,
      fat: 0
    }
  };

  return {
    extractedText,
    result: normalizeParseResultContract(baseResult, 'gemini')
  };
}

async function runImageModel(model: string, image: ImagePart): Promise<{
  extractedText: string;
  result: ParseResult;
  usage: GeminiUsage;
} | null> {
  const response = await generateGeminiMultimodalJson({
    model,
    temperature: 0.1,
    parts: [
      { text: buildImageParsePrompt() },
      {
        inlineData: {
          mimeType: image.mimeType,
          data: image.dataBase64
        }
      }
    ]
  });

  if (!response) {
    return null;
  }

  const parsed = parseGeminiOutput(response.jsonText);
  if (!parsed) {
    return null;
  }

  return {
    extractedText: parsed.extractedText,
    result: parsed.result,
    usage: response.usage
  };
}

export async function parseImageWithGemini(image: ImagePart): Promise<ImageParseServiceResult> {
  if (!config.aiImageParseEnabled) {
    throw new ApiError(403, 'IMAGE_PARSE_DISABLED', 'Image parse is disabled.');
  }

  const usageEvents: ImageParseUsageEvent[] = [];

  const primary = await runImageModel(config.aiImagePrimaryModel, image);
  if (primary?.usage) {
    usageEvents.push({
      feature: 'parse_image_primary',
      usage: primary.usage,
      estimatedCostUsd: estimateCostUsd(primary.usage)
    });
  }

  const primaryAccepted =
    primary &&
    primary.result.items.length > 0 &&
    primary.result.confidence >= config.aiImageConfidenceMin;

  if (primaryAccepted) {
    return {
      extractedText: primary.extractedText,
      result: primary.result,
      model: primary.usage.model,
      fallbackUsed: false,
      usageEvents
    };
  }

  if (!config.aiImageEnableFallback) {
    throw new ApiError(422, 'IMAGE_PARSE_LOW_CONFIDENCE', 'Image parse confidence is too low. Please retry with a clearer photo.');
  }

  const fallbackModel = config.aiImageFallbackModel;
  if (fallbackModel.trim().toLowerCase() == config.aiImagePrimaryModel.trim().toLowerCase()) {
    throw new ApiError(422, 'IMAGE_PARSE_LOW_CONFIDENCE', 'Image parse confidence is too low. Please retry with a clearer photo.');
  }

  const fallback = await runImageModel(fallbackModel, image);
  if (fallback?.usage) {
    usageEvents.push({
      feature: 'parse_image_fallback',
      usage: fallback.usage,
      estimatedCostUsd: estimateCostUsd(fallback.usage)
    });
  }

  if (!fallback || fallback.result.items.length === 0) {
    throw new ApiError(502, 'IMAGE_PARSE_FAILED', 'Unable to estimate nutrition from this image. Please try another photo.');
  }

  return {
    extractedText: fallback.extractedText,
    result: fallback.result,
    model: fallback.usage.model,
    fallbackUsed: true,
    usageEvents
  };
}
