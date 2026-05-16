import { z } from 'zod';
import { config } from '../config.js';
import { ApiError } from '../utils/errors.js';
import type { ParseResult, ParsedItem } from './deterministicParser.js';
import { createEmptyParseResult } from './parsePipelineResultUtils.js';
import { normalizeParseResultContract } from './parseContractService.js';
import { generateGeminiMultimodalJson, type GeminiUsage } from './geminiFlashClient.js';
import { tryGeminiPrimaryParse } from './aiNormalizerService.js';

type ImageParseUsageEvent = {
  feature: 'parse_image_primary' | 'parse_image_fallback' | 'parse_image_caption' | 'parse_image_caption_text';
  usage: GeminiUsage;
  estimatedCostUsd: number;
};

export type ImageParseServiceResult = {
  extractedText: string;
  result: ParseResult;
  model: string;
  fallbackUsed: boolean;
  lowConfidenceAccepted: boolean;
  usageEvents: ImageParseUsageEvent[];
};

export type ImageParseDebugEvent = {
  stage: string;
  ok: boolean;
  model?: string;
  reason?: string;
  ms: number;
  confidence?: number;
  items?: number;
  caption?: string;
};

type ImagePart = {
  mimeType: string;
  dataBase64: string;
  contextNote?: string;
  debugEvents?: ImageParseDebugEvent[];
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

const captionSchema = z.object({
  caption: z.string().trim().min(2).max(500)
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

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function getFirst(record: Record<string, unknown>, keys: string[]): unknown {
  for (const key of keys) {
    if (record[key] !== undefined && record[key] !== null) {
      return record[key];
    }
  }
  return undefined;
}

function asText(value: unknown): string {
  if (typeof value === 'string') {
    return value.trim();
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return String(value);
  }
  return '';
}

function asNumber(value: unknown): number | null {
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }
  if (typeof value !== 'string') {
    return null;
  }

  const normalized = value.trim().replace(/,/g, '');
  if (!normalized) {
    return null;
  }

  const match = normalized.match(/-?\d+(?:\.\d+)?/);
  if (!match) {
    return null;
  }

  const parsed = Number(match[0]);
  return Number.isFinite(parsed) ? parsed : null;
}

function clampConfidence(value: unknown, fallback = 0.5): number {
  const parsed = asNumber(value);
  if (parsed === null) {
    return fallback;
  }
  return Math.min(1, Math.max(0, parsed));
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.map((item) => asText(item)).filter(Boolean).slice(0, 8);
}

function extractJsonCandidate(payloadText: string): string | null {
  const trimmed = payloadText.trim();
  if (!trimmed) {
    return null;
  }

  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = fenced?.[1]?.trim() || trimmed;
  const start = candidate.indexOf('{');
  if (start < 0) {
    return null;
  }

  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = start; index < candidate.length; index += 1) {
    const char = candidate[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char === '\\') {
      escaped = true;
      continue;
    }
    if (char === '"') {
      inString = !inString;
      continue;
    }
    if (inString) {
      continue;
    }
    if (char === '{') {
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        return candidate.slice(start, index + 1);
      }
    }
  }

  return null;
}

function normalizeGeminiItem(rawItem: unknown, topLevelConfidence: number): z.input<typeof parseItemSchema> | null {
  const record = asRecord(rawItem);
  if (!record) {
    return null;
  }

  const name =
    asText(getFirst(record, ['name', 'foodName', 'food', 'item', 'label', 'description', 'foodDescription'])) ||
    'Food item';
  const quantity = nonNegative(asNumber(getFirst(record, ['quantity', 'amount', 'servings', 'servingCount', 'count'])) ?? 1);
  const unit =
    asText(getFirst(record, ['unit', 'servingUnit', 'serving_unit', 'portionUnit', 'portion_unit', 'serving', 'portion'])) ||
    'serving';
  const grams = nonNegative(
    asNumber(getFirst(record, ['grams', 'gramWeight', 'weightGrams', 'weight_grams', 'weightG', 'servingGrams', 'serving_grams'])) ?? 0
  );
  const calories = nonNegative(
    asNumber(getFirst(record, ['calories', 'caloriesKcal', 'calories_kcal', 'kcal', 'energyKcal', 'energy_kcal'])) ?? 0
  );
  const protein = nonNegative(asNumber(getFirst(record, ['protein', 'proteinG', 'protein_g', 'proteinGrams'])) ?? 0);
  const carbs = nonNegative(asNumber(getFirst(record, ['carbs', 'carbohydrates', 'carbsG', 'carbs_g', 'carbohydratesG', 'carbohydrates_g'])) ?? 0);
  const fat = nonNegative(asNumber(getFirst(record, ['fat', 'fatG', 'fat_g', 'totalFat', 'total_fat', 'totalFatG'])) ?? 0);
  const hasUsableNutrition = calories > 0 || protein > 0 || carbs > 0 || fat > 0;

  if (!name.trim() || !hasUsableNutrition) {
    return null;
  }

  return {
    name,
    quantity: Math.max(quantity, 0.0001),
    unit,
    grams,
    calories,
    protein,
    carbs,
    fat,
    matchConfidence: clampConfidence(getFirst(record, ['matchConfidence', 'confidence', 'foodConfidence']), topLevelConfidence),
    foodDescription: asText(getFirst(record, ['foodDescription', 'description', 'visibleDescription'])) || name,
    explanation:
      asText(getFirst(record, ['explanation', 'reasoning', 'assumption', 'notes'])) ||
      'AI image estimate based on visible foods; review portion if needed.'
  };
}

function normalizeGeminiPayload(parsed: unknown): z.input<typeof imageParseSchema> | null {
  const record = asRecord(parsed);
  if (!record) {
    return null;
  }

  const confidence = clampConfidence(getFirst(record, ['confidence', 'overallConfidence', 'imageConfidence']), 0.5);
  const rawItems =
    getFirst(record, ['items', 'foods', 'foodItems', 'detectedFoods', 'detected_foods', 'results', 'matches']) ??
    (getFirst(record, ['name', 'foodName', 'food']) ? [record] : []);
  if (!Array.isArray(rawItems)) {
    return null;
  }

  const items = rawItems
    .map((item) => normalizeGeminiItem(item, confidence))
    .filter((item): item is z.input<typeof parseItemSchema> => item !== null);
  if (items.length === 0) {
    return null;
  }

  return {
    extractedText: asText(getFirst(record, ['extractedText', 'detectedText', 'summary', 'caption'])),
    confidence,
    assumptions: stringArray(getFirst(record, ['assumptions', 'notes', 'warnings'])),
    items
  };
}

function priceForModel(model: string): { inputUsdPer1M: number; outputUsdPer1M: number } {
  const normalized = model.trim().toLowerCase();
  if (normalized.includes('flash-lite')) {
    return {
      inputUsdPer1M: config.geminiFlashLiteInputUsdPer1M,
      outputUsdPer1M: config.geminiFlashLiteOutputUsdPer1M
    };
  }

  if (normalized.includes('pro')) {
    return {
      inputUsdPer1M: config.geminiProInputUsdPer1M,
      outputUsdPer1M: config.geminiProOutputUsdPer1M
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

type ImagePromptMode = 'primary' | 'rescue';

function buildImageParsePrompt(mode: ImagePromptMode = 'primary', contextNote?: string): string {
  const note = trimSafe(contextNote);
  const sharedRules = [
    'Output schema exactly:',
    '{"extractedText":string,"confidence":number,"assumptions":string[],"items":[{"name":string,"quantity":number,"unit":string,"grams":number,"calories":number,"protein":number,"carbs":number,"fat":number,"matchConfidence":number,"foodDescription":string,"explanation":string}]}',
    'Rules:',
    '- Prefer visible nutrition-label values for packaged foods; otherwise estimate visible servings.',
    '- Use realistic serving assumptions when quantity is unclear.',
    '- Return non-empty items if edible foods are visible.',
    '- Do not fail only because the exact portion is uncertain; estimate a common visible serving and explain the assumption.',
    '- For common foods such as pizza, rice bowls, sandwiches, salads, drinks, snacks, desserts, roti, chapati, paratha, thepla, naan, dosa, idli, poha, dal, curry, and chutney, return a best-effort item even when the exact recipe is unknown.',
    '- For visible edible foods, calories must be greater than 0. Do not output zero nutrition just because recipe or portion is uncertain.',
    '- If the image shows a flatbread-like food, estimate it as the closest visible broad category such as "paratha", "roti", "thepla", "naan", or "flatbread" instead of returning no items.',
    '- Confidence and matchConfidence are in [0,1].',
    '- Do not return negative numbers.',
    '- extractedText should be a concise comma-separated phrase list in user-entered order.',
    '- assumptions should be [] unless an assumption is essential.',
    '- nutritionSourceId is not needed in output; it is added downstream.',
    '- Keep explanations to one concise user-friendly sentence mentioning visible food, portion/grams, and whether label values or serving estimates were used.',
    '- Do not mention matchConfidence in explanations.',
    '- If image has no food, return confidence 0 and items [].',
    ...(note
      ? [
          '',
          'User-provided photo context:',
          note,
          'Use this context to identify foods and portions when it is compatible with the image. Do not invent foods that contradict the image.'
        ]
      : [])
  ];

  if (mode === 'rescue') {
    return [
      'You are a food-photo fallback parser. The first parse attempt did not produce usable nutrition JSON.',
      'Look at the image again and return strict JSON only (no markdown).',
      'Bias toward a safe best-effort food log rather than rejecting the photo.',
      'If any edible food is visible, items must contain at least one item.',
      'Only return no items when the image clearly contains no edible food or drink.',
      'If the image is blurry, cropped, partially obstructed, or portion size is uncertain, still return the most likely visible food with a conservative serving estimate.',
      'Use broad names when needed, e.g. "pizza", "rice bowl", "sandwich", "coffee", "snack bar", "paratha", "roti", "thepla", "flatbread".',
      'If a cooked bread/flatbread is visible, return an estimated item even if the exact filling or flour type is uncertain.',
      ...sharedRules
    ].join('\n');
  }

  return [
    'You are a nutrition parsing assistant for food photo logs.',
    'Analyze the attached food image carefully and return strict JSON only (no markdown).',
    ...sharedRules
  ].join('\n');
}

function buildImageCaptionFallbackPrompt(contextNote?: string): string {
  const note = trimSafe(contextNote);
  return [
    'Identify the edible food and drink visible in this image.',
    'Return strict JSON only with this exact shape: {"caption":string}.',
    'The caption should be a concise comma-separated meal description suitable for a nutrition logger.',
    'Include likely portions when visible or strongly implied.',
    'Use broad names if exact recipes are uncertain.',
    'For Indian meals, recognize common foods such as rice, dal, rajma, chole, dosa, chutney, sambar, curries, sabzi, roti, naan, paratha, thepla, makhana, and snacks.',
    'Do not return an empty caption if any edible food is visible.',
    ...(note
      ? [
          '',
          'User-provided photo context:',
          note,
          'Use this context only if compatible with the image.'
        ]
      : [])
  ].join('\n');
}

function parseGeminiOutput(payloadText: string): { extractedText: string; result: ParseResult } | null {
  let parsed: unknown;
  try {
    const jsonCandidate = extractJsonCandidate(payloadText);
    if (!jsonCandidate) {
      return null;
    }
    parsed = JSON.parse(jsonCandidate);
  } catch {
    return null;
  }

  const normalizedPayload = normalizeGeminiPayload(parsed);
  if (!normalizedPayload) {
    return null;
  }

  const validated = imageParseSchema.safeParse(normalizedPayload);
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

function acceptedLowConfidenceResult(
  candidate: Awaited<ReturnType<typeof runImageModel>>,
  usageEvents: ImageParseUsageEvent[],
  fallbackUsed: boolean
): ImageParseServiceResult | null {
  if (!candidate || candidate.result.items.length === 0) {
    return null;
  }

  // A nutrition-label/package photo can produce exact calories/macros while
  // still scoring below the broad visual-food threshold. Returning the parsed
  // result with `needsClarification` is better than blocking the user with
  // "couldn't understand photo".
  const confidence = Math.max(candidate.result.confidence, 0.5);
  return {
    extractedText: candidate.extractedText,
    result: {
      ...candidate.result,
      confidence,
      items: candidate.result.items.map((item) => ({
        ...item,
        needsClarification: true
      }))
    },
    model: candidate.usage.model,
    fallbackUsed,
    lowConfidenceAccepted: true,
    usageEvents
  };
}

async function runImageModel(model: string, image: ImagePart, mode: ImagePromptMode = 'primary'): Promise<{
  extractedText: string;
  result: ParseResult;
  usage: GeminiUsage;
} | null> {
  const startedAt = process.hrtime.bigint();
  const stage = mode === 'rescue' ? 'image_structured_rescue' : 'image_structured_primary';
  const response = await generateGeminiMultimodalJson({
    model,
    temperature: 0.1,
    maxOutputTokens: mode === 'rescue' ? 1400 : 1200,
    timeoutMs: config.aiImageTimeoutMs,
    parts: [
      { text: buildImageParsePrompt(mode, image.contextNote) },
      {
        inlineData: {
          mimeType: image.mimeType,
          data: image.dataBase64
        }
      }
    ]
  });

  if (!response) {
    image.debugEvents?.push({
      stage,
      ok: false,
      model,
      reason: 'gemini_no_response',
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10
    });
    return null;
  }

  const parsed = parseGeminiOutput(response.jsonText);
  if (!parsed) {
    image.debugEvents?.push({
      stage,
      ok: false,
      model: response.usage.model,
      reason: 'invalid_or_empty_nutrition_json',
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10
    });
    return null;
  }

  image.debugEvents?.push({
    stage,
    ok: true,
    model: response.usage.model,
    ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10,
    confidence: parsed.result.confidence,
    items: parsed.result.items.length
  });

  return {
    extractedText: parsed.extractedText,
    result: parsed.result,
    usage: response.usage
  };
}

async function runImageCaptionFallback(
  model: string,
  image: ImagePart
): Promise<{ caption: string; usage: GeminiUsage } | null> {
  const startedAt = process.hrtime.bigint();
  const response = await generateGeminiMultimodalJson({
    model,
    temperature: 0.1,
    maxOutputTokens: 240,
    timeoutMs: config.aiImageTimeoutMs,
    parts: [
      { text: buildImageCaptionFallbackPrompt(image.contextNote) },
      {
        inlineData: {
          mimeType: image.mimeType,
          data: image.dataBase64
        }
      }
    ]
  });

  if (!response) {
    image.debugEvents?.push({
      stage: 'image_caption',
      ok: false,
      model,
      reason: 'gemini_no_response',
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10
    });
    return null;
  }

  try {
    const jsonCandidate = extractJsonCandidate(response.jsonText);
    if (!jsonCandidate) {
      return null;
    }
    const parsed = captionSchema.parse(JSON.parse(jsonCandidate) as unknown);
    image.debugEvents?.push({
      stage: 'image_caption',
      ok: true,
      model: response.usage.model,
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10,
      caption: parsed.caption
    });
    return {
      caption: parsed.caption,
      usage: response.usage
    };
  } catch {
    image.debugEvents?.push({
      stage: 'image_caption',
      ok: false,
      model: response.usage.model,
      reason: 'invalid_caption_json',
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10
    });
    return null;
  }
}

function imageSafeResult(result: ParseResult): ParseResult {
  return {
    ...result,
    items: result.items.map((item) => ({
      ...item,
      nutritionSourceId: 'gemini_image_caption_estimate',
      originalNutritionSourceId: item.originalNutritionSourceId || item.nutritionSourceId || 'gemini_image_caption_estimate',
      sourceFamily: 'gemini',
      needsClarification: true,
      foodDescription: item.foodDescription || item.name,
      explanation:
        item.explanation ||
        `Estimated from the visible photo via a brief meal description: ${item.name}. Please confirm portions if needed.`
    }))
  };
}

async function recoverWithCaptionFallback(
  image: ImagePart,
  usageEvents: ImageParseUsageEvent[]
): Promise<ImageParseServiceResult | null> {
  const captionModel = config.aiImagePrimaryModel;
  const caption = await runImageCaptionFallback(captionModel, image);
  if (!caption?.caption.trim()) {
    return null;
  }

  usageEvents.push({
    feature: 'parse_image_caption',
    usage: caption.usage,
    estimatedCostUsd: estimateCostUsd(caption.usage)
  });

  const textStartedAt = process.hrtime.bigint();
  const textAttempt = await tryGeminiPrimaryParse(caption.caption, createEmptyParseResult(caption.caption));
  if (!textAttempt?.result.items.length) {
    image.debugEvents?.push({
      stage: 'image_caption_text',
      ok: false,
      reason: 'text_parse_failed',
      ms: Math.round((Number(process.hrtime.bigint() - textStartedAt) / 1_000_000) * 10) / 10,
      caption: caption.caption
    });
    return null;
  }

  usageEvents.push({
    feature: 'parse_image_caption_text',
    usage: {
      model: textAttempt.usage.model,
      inputTokens: textAttempt.usage.inputTokens,
      outputTokens: textAttempt.usage.outputTokens
    },
    estimatedCostUsd: textAttempt.usage.estimatedCostUsd
  });

  const result = imageSafeResult(normalizeParseResultContract(textAttempt.result, 'gemini'));
  image.debugEvents?.push({
    stage: 'image_caption_text',
    ok: true,
    model: textAttempt.usage.model,
    ms: Math.round((Number(process.hrtime.bigint() - textStartedAt) / 1_000_000) * 10) / 10,
    confidence: result.confidence,
    items: result.items.length,
    caption: caption.caption
  });
  return {
    extractedText: caption.caption,
    result,
    model: textAttempt.usage.model,
    fallbackUsed: true,
    lowConfidenceAccepted: true,
    usageEvents
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
      lowConfidenceAccepted: false,
      usageEvents
    };
  }

  const acceptedPrimary = acceptedLowConfidenceResult(primary, usageEvents, false);
  if (acceptedPrimary && !config.aiImageEnableFallback) {
    return acceptedPrimary;
  }

  if (!config.aiImageEnableFallback) {
    throw new ApiError(422, 'IMAGE_PARSE_LOW_CONFIDENCE', 'Image parse confidence is too low. Please retry with a clearer photo.');
  }

  const captionRecovered = await recoverWithCaptionFallback(image, usageEvents);
  if (captionRecovered) {
    return captionRecovered;
  }

  const fallbackModel = config.aiImageFallbackModel;
  if (fallbackModel.trim().toLowerCase() == config.aiImagePrimaryModel.trim().toLowerCase()) {
    if (acceptedPrimary) {
      return acceptedPrimary;
    }

    // Render/local envs often configure the same model for primary and
    // fallback. Still run a second pass with a rescue prompt so an obvious
    // food photo does not dead-end at "couldn't understand photo" just
    // because the first response was empty, truncated, or overly cautious.
    const rescued = await runImageModel(fallbackModel, image, 'rescue');
    if (rescued?.usage) {
      usageEvents.push({
        feature: 'parse_image_fallback',
        usage: rescued.usage,
        estimatedCostUsd: estimateCostUsd(rescued.usage)
      });
    }
    const rescuedAccepted =
      rescued &&
      rescued.result.items.length > 0 &&
      rescued.result.confidence >= config.aiImageConfidenceMin;
    if (rescuedAccepted) {
      return {
        extractedText: rescued.extractedText,
        result: rescued.result,
        model: rescued.usage.model,
        fallbackUsed: true,
        lowConfidenceAccepted: false,
        usageEvents
      };
    }
    const acceptedRescue = acceptedLowConfidenceResult(rescued, usageEvents, true);
    if (acceptedRescue) {
      return acceptedRescue;
    }
    throw new ApiError(422, 'IMAGE_PARSE_LOW_CONFIDENCE', 'Image parse confidence is too low. Please retry with a clearer photo.');
  }

  const fallback = await runImageModel(fallbackModel, image, 'rescue');
  if (fallback?.usage) {
    usageEvents.push({
      feature: 'parse_image_fallback',
      usage: fallback.usage,
      estimatedCostUsd: estimateCostUsd(fallback.usage)
    });
  }

  if (!fallback || fallback.result.items.length === 0) {
    const accepted = acceptedLowConfidenceResult(primary, usageEvents, false);
    if (accepted) {
      return accepted;
    }
    throw new ApiError(502, 'IMAGE_PARSE_FAILED', 'Unable to estimate nutrition from this image. Please try another photo.');
  }

  return {
    extractedText: fallback.extractedText,
    result: fallback.result,
    model: fallback.usage.model,
    fallbackUsed: true,
    lowConfidenceAccepted: fallback.result.confidence < config.aiImageConfidenceMin,
    usageEvents
  };
}
