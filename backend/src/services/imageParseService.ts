import { z } from 'zod';
import sharp from 'sharp';
import { config } from '../config.js';
import { ApiError } from '../utils/errors.js';
import type { ParseResult, ParsedItem } from './deterministicParser.js';
import { createEmptyParseResult } from './parsePipelineResultUtils.js';
import { normalizeParseResultContract } from './parseContractService.js';
import { generateGeminiMultimodalJson, generateGeminiMultimodalText, type GeminiUsage } from './geminiFlashClient.js';
import { tryGeminiPrimaryParse } from './aiNormalizerService.js';
import { postProcessFoodImageResult, type FoodImagePostprocessContext } from './foodImagePostprocessService.js';

type ImageParseUsageEvent = {
  feature:
    | 'parse_image_primary'
    | 'parse_image_fallback'
    | 'parse_image_caption'
    | 'parse_image_caption_text'
    | 'parse_image_inventory_v2';
  usage: GeminiUsage;
  estimatedCostUsd: number;
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

type ImageType =
  | 'nutrition_label'
  | 'single_food'
  | 'multi_component_meal'
  | 'tray_or_thali'
  | 'drink'
  | 'menu_or_screenshot'
  | 'non_food'
  | 'unclear';

type ImageVisibleComponent = {
  name: string;
  category: string;
  zone: string;
  portionHint: string;
  confidence: number;
  isSmallSide: boolean;
};

export type ImageParseCoverage = {
  imageType: ImageType;
  cuisineHints: string[];
  visibleComponents: ImageVisibleComponent[];
  visibleComponentCount: number;
  parsedItemCount: number;
  score: number;
  warnings: string[];
  partial: boolean;
};

export type ImageParseServiceResult = {
  extractedText: string;
  result: ParseResult;
  model: string;
  fallbackUsed: boolean;
  lowConfidenceAccepted: boolean;
  usageEvents: ImageParseUsageEvent[];
  orchestratorVersion: 'v1' | 'v2';
  coverage?: ImageParseCoverage;
};

type V2ImageParsePayload = {
  extractedText: string;
  confidence: number;
  assumptions: string[];
  imageType: ImageType;
  cuisineHints: string[];
  visibleComponents: ImageVisibleComponent[];
  coverage: {
    visibleComponentCount: number;
    parsedItemCount: number;
    score: number;
    warnings: string[];
  };
  items: Array<{
    name: string;
    quantity: number;
    unit: string;
    grams: number;
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
    matchConfidence?: number;
    foodDescription?: string;
    explanation?: string;
  }>;
};

type ImagePart = {
  mimeType: string;
  dataBase64: string;
  contextNote?: string;
  debugEvents?: ImageParseDebugEvent[];
  variantLabel?: string;
};

const visionMinOptimizeBytes = 900_000;
const visionMaxEdgePx = 1600;
const visionJpegQuality = 82;

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

function balancedJsonSlice(candidate: string, start: number): string | null {
  const opener = candidate[start];
  if (opener !== '{' && opener !== '[') {
    return null;
  }

  const stack: string[] = [];
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
      stack.push('}');
    } else if (char === '[') {
      stack.push(']');
    } else if (char === '}' || char === ']') {
      if (stack[stack.length - 1] !== char) {
        return null;
      }
      stack.pop();
      if (stack.length === 0) {
        return candidate.slice(start, index + 1);
      }
    }
  }

  return null;
}

function extractJsonCandidate(payloadText: string): string | null {
  const trimmed = payloadText.trim();
  if (!trimmed) {
    return null;
  }

  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = fenced?.[1]?.trim() || trimmed;

  for (let index = 0; index < candidate.length; index += 1) {
    const char = candidate[index];
    if (char !== '{' && char !== '[') {
      continue;
    }
    const slice = balancedJsonSlice(candidate, index);
    if (!slice) {
      continue;
    }
    try {
      JSON.parse(slice);
      return slice;
    } catch {
      // Keep scanning; Gemini sometimes includes prose examples before the
      // actual payload.
    }
  }

  return null;
}

function parseCaptionPayload(payloadText: string): string | null {
  const trimmed = payloadText.trim();
  if (!trimmed) {
    return null;
  }

  const jsonCandidate = extractJsonCandidate(trimmed);
  if (jsonCandidate) {
    try {
      const parsed = captionSchema.parse(JSON.parse(jsonCandidate) as unknown);
      return parsed.caption;
    } catch {
      // Fall through to tolerate JSON strings or plain text below.
    }
  }

  try {
    const parsed = JSON.parse(trimmed) as unknown;
    if (typeof parsed === 'string') {
      return parsed.trim().slice(0, 500) || null;
    }
    const record = asRecord(parsed);
    if (record) {
      const caption = asText(getFirst(record, ['caption', 'description', 'meal', 'text']));
      return caption ? caption.slice(0, 500) : null;
    }
  } catch {
    // Plain text is acceptable for caption fallback because it is fed into
    // the stricter text nutrition parser next.
  }

  return trimmed.slice(0, 500);
}

function captionRejectionReason(caption: string): string | null {
  const normalized = caption.trim().toLowerCase();
  if (!normalized) {
    return 'empty_caption';
  }

  const boilerplateSignals = [
    'here is the json',
    'json requested',
    '```',
    '{"caption"',
    'output schema',
    'strict json',
    'code block'
  ];
  if (boilerplateSignals.some((signal) => normalized.includes(signal))) {
    return 'caption_boilerplate';
  }

  if (/^\s*[{[]/.test(caption)) {
    return 'caption_boilerplate';
  }

  const genericCaptions = new Set([
    'food',
    'meal',
    'dish',
    'plate',
    'bowl',
    'tray',
    'snack',
    'snacks',
    'plate of food',
    'bowl of food',
    'indian food',
    'asian food',
    'restaurant food',
    'homemade food',
    'various foods',
    'mixed foods',
    'several foods'
  ]);
  if (genericCaptions.has(normalized)) {
    return 'generic_caption';
  }

  return null;
}

function captionFoodSegmentCount(caption: string): number {
  return caption
    .split(/[,;\n]+|\s+\band\b\s+|\s+\bwith\b\s+/i)
    .map((segment) => segment.trim())
    .filter((segment) => segment.length >= 2)
    .length;
}

function shouldTryStrongerCaptionModel(caption: string, contextNote?: string): boolean {
  const segmentCount = captionFoodSegmentCount(caption);
  if (segmentCount < 3) {
    return true;
  }

  if (segmentCount >= 4) {
    return false;
  }

  const note = trimSafe(contextNote);
  if (captionFoodSegmentCount(note) > segmentCount) {
    return true;
  }

  const multiFoodSignals = [
    'thali',
    'tray',
    'plate',
    'bowl with',
    'with chutney',
    'with onions',
    'with onion',
    'with rice',
    'with dal',
    'with curry',
    'with sabzi',
    'compartment',
    'sides'
  ];

  return multiFoodSignals.some((signal) => note.toLowerCase().includes(signal));
}

function resultHasPositiveNutrition(result: ParseResult): boolean {
  return result.items.some((item) => item.calories > 0 || item.protein > 0 || item.carbs > 0 || item.fat > 0);
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
  if (Array.isArray(parsed)) {
    const items = parsed
      .map((item) => normalizeGeminiItem(item, 0.75))
      .filter((item): item is z.input<typeof parseItemSchema> => item !== null);
    if (items.length === 0) {
      return null;
    }
    const confidence =
      items.reduce((sum, item) => sum + clampConfidence(item.matchConfidence, 0.75), 0) / items.length;
    return {
      extractedText: items.map((item) => item.name).join(', '),
      confidence,
      assumptions: [],
      items
    };
  }

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
type ImageCaptionPromptMode = 'concise' | 'inventory' | 'staples' | 'sides';

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
    '- The photo may be rotated sideways or upside down. Mentally rotate it and inspect all edges/corners before deciding what foods are visible.',
    '- Scan the whole image before answering. For trays, thalis, compartment plates, bowls with sides, or meals with condiments, include every visible edible component, not only the largest item.',
    '- For metal trays, shiny reflections, shadows, or rotation can make foods less obvious; still inspect every compartment and do not stop after the first liquid/curry.',
    '- If a compartmented tray/thali has visible food in multiple compartments, do not return only one or two items; inspect for breads, sabzi/vegetables, onion/salad, chutneys, pickles, and dry powders.',
    '- Include small but visible sides such as chutney, onion, pickle, salad, sauces, dry chutney/powder, garnish, and drinks as separate low-calorie items when visible.',
    '- For Indian thali-style meals, list dal/curry, bread/rice, sabzi, chutneys, onion/salad, pickle/powder separately when visible.',
    '- For dal baati / dal bati plates, include the baati/bati breads, dal, sabzi, chutney, onion, and dry churma/chutney/powder when visible.',
    '- If round brown baked bread balls are visible, identify them as baati/bati. If diced yellow-brown vegetables are visible, identify them as potato sabzi. If sliced purple/red onion is visible, include sliced onion. If a small mound of brown powder is visible, include dry chutney/churma powder.',
    '- If multiple edible components are visible, items must contain multiple items.',
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
    'First, mentally rotate the image through 0, 90, 180, and 270 degrees; then inspect all tray compartments and edges.',
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

function buildImageCaptionFallbackPrompt(contextNote?: string, mode: ImageCaptionPromptMode = 'concise'): string {
  const note = trimSafe(contextNote);
  const inventoryRules =
    mode === 'inventory'
      ? [
          'This is an inventory pass. Do not summarize the meal.',
          'Mentally divide the image into tray/plate zones: top, bottom, left, right, center, and small bowls/compartments.',
          'Name each visible food component separately, including small sides and condiments.',
          'Avoid generic color-only words like "green"; use likely food names such as green chutney, salad, herbs, spinach, or vegetable curry.',
          'If a tray contains breads plus dal plus sides, include the breads and all side compartments.'
        ]
      : [];
  const stapleRules =
    mode === 'staples'
      ? [
          'This is a staple-food pass. Focus on carb/staple items that are easy to miss.',
          'Look specifically for bread balls, baati/bati, buns, rolls, roti, chapati, naan, paratha, dosa, rice, noodles, potatoes, pasta, tortillas, wraps, pancakes, waffles, and cereal.',
          'Do not stop at the curry/liquid. If any bread/rice/starch is visible, name it clearly.'
        ]
      : [];
  const sideRules =
    mode === 'sides'
      ? [
          'This is a side-component pass. Focus on small compartments, edges, sauces, dips, salads, pickles, chutneys, powders, garnishes, and vegetables.',
          'Look specifically for sliced onion, green chutney, potato sabzi, dry chutney/churma powder, pickle, salad, lemon, sauces, and dressings.',
          'Return only edible side components you can see.'
        ]
      : [];
  return [
    'Identify the edible food and drink visible in this image.',
    'The image may be rotated sideways or upside down; mentally rotate it and inspect every edge/corner.',
    'Inspect the entire image, including all plate/tray compartments and small side bowls.',
    'For shiny metal trays, ignore reflections and look for food in each compartment.',
    'List every distinct visible edible component, not just the largest or most obvious food.',
    'For thalis/trays, include breads/rice, dal/curry, sabzi, chutney, onion/salad, pickle, and dry chutney/powder when visible.',
    'For dal baati / dal bati trays, include baati/bati breads, dal, sabzi, chutney, onions, and dry churma/chutney/powder when visible.',
    'If the image contains a compartmented tray/thali with visible foods, do not return only one or two foods unless every other compartment is truly empty.',
    'Look specifically for round brown baati/bati breads, diced potato sabzi, sliced red onion, green chutney, dal, and dry brown chutney/churma powder.',
    'If the image contains multiple foods, return multiple comma-separated foods.',
    ...inventoryRules,
    ...stapleRules,
    ...sideRules,
    'Reply with one plain line of comma-separated food names suitable for a nutrition logger.',
    'No intro text, no labels, no code blocks, no bullet points, and no explanation.',
    'Good examples:',
    '- masala dosa, sambar, coconut chutney, tomato chutney',
    '- white rice, dal, salad, crunchy garnish',
    '- white rice, rajma, red onion, lemon',
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

function buildImageInventoryV2Prompt(contextNote?: string): string {
  const note = trimSafe(contextNote);
  return [
    'You are Food App image parser V2. Return strict JSON only, no markdown.',
    'Goal: produce a fast useful food log from one image within one response.',
    '',
    'Output schema exactly:',
    '{"imageType":"nutrition_label|single_food|multi_component_meal|tray_or_thali|drink|menu_or_screenshot|non_food|unclear","cuisineHints":string[],"visibleComponents":[{"name":string,"category":string,"zone":string,"portionHint":string,"confidence":number,"isSmallSide":boolean}],"items":[{"name":string,"quantity":number,"unit":string,"grams":number,"calories":number,"protein":number,"carbs":number,"fat":number,"matchConfidence":number,"foodDescription":string,"explanation":string}],"coverage":{"visibleComponentCount":number,"parsedItemCount":number,"score":number,"warnings":string[]},"extractedText":string,"confidence":number,"assumptions":string[]}',
    '',
    'Hard rules:',
    '- First build a visual inventory of every edible component, then estimate nutrition from that inventory.',
    '- If food is visible, return at least one positive-calorie item. Do not output zero nutrition for visible food.',
    '- For multi-component plates, trays, thalis, bowls with sides, bento boxes, lunch trays, takeout meals, and restaurant plates, include each distinct visible component.',
    '- Include small visible sides separately when they matter: chutney, sauce, dressing, pickle, onion/salad, garnish, lemon, dips, salsa, aioli, dry powders, crunchy toppings.',
    '- If uncertain, use broad names and conservative portions; mark confidence lower and explain briefly.',
    '- The image may be rotated; mentally inspect it at 0, 90, 180, and 270 degrees.',
    '- Ignore plate/tray reflections and inspect each compartment/edge.',
    '- For a packaged product, bottle, can, protein shake, soda, nutrition label, snack bar, or branded drink, return the product as ONE item unless separate edible foods are clearly visible.',
    '- Do not split flavor words into ingredients. Example: "mixed berry vanilla protein drink" is one protein drink, not protein drink + yogurt + berries.',
    '- For product/package photos, use the visible product name and label facts when possible. If label facts are not fully readable, estimate one bottle/can/bar/serving.',
    '- coverage.score should reflect how completely items cover visibleComponents. 1 means all visible foods are represented. Below 0.75 means partial.',
    '- Keep explanations short and user-friendly. No chain-of-thought.',
    '',
    'Global cuisine coverage guidance:',
    '- US/Western: burgers, sandwiches, wraps, pizza, fries, salads, eggs, pancakes, waffles, cereal, oatmeal, protein bars, grilled meats, coffee, soda, smoothies.',
    '- India and Indian subcontinent: rice, roti, chapati, paratha, naan, puri, dal, sabzi, curries, biryani, dosa, idli, vada, sambar, chutney, thali, chaat, paneer, rajma, chole, sweets, lassi.',
    '- Chinese/East Asian: rice, fried rice, noodles, stir-fry, dumplings, buns, soups, sauced chicken/beef/pork/tofu, vegetables, spring rolls, congee.',
    '- Italian/Mediterranean: pasta, pizza, risotto, lasagna, bread, cheese, olive oil, salads, sauces, meatballs, grilled fish/meat, antipasti.',
    '- Also recognize Mexican, Middle Eastern, Japanese, Thai, Vietnamese, Korean, and generic mixed meals when visible.',
    '',
    'Use food roles when exact cuisine is unclear:',
    '- staple carb, protein, sauce/curry, vegetable side, condiment, drink, dessert, packaged/label item.',
    '',
    'Quality bar:',
    '- A tray/thali with dal, breads/rice, sabzi, chutney, onion/salad, pickle/powder must not return only dal or only chutney.',
    '- If only part of the meal is identifiable, return the identified items and set coverage.score below 0.75 with a warning.',
    '- For nutrition labels/package photos, prefer visible label facts and one package/serving.',
    ...(note
      ? [
          '',
          'User-provided photo context:',
          note,
          'Use this context only when compatible with the image. Do not invent foods that contradict the image.'
        ]
      : [])
  ].join('\n');
}

function normalizeImageType(value: unknown): ImageType {
  const normalized = asText(value).toLowerCase().replace(/[\s-]+/g, '_');
  const allowed: ImageType[] = [
    'nutrition_label',
    'single_food',
    'multi_component_meal',
    'tray_or_thali',
    'drink',
    'menu_or_screenshot',
    'non_food',
    'unclear'
  ];
  return allowed.includes(normalized as ImageType) ? (normalized as ImageType) : 'unclear';
}

function normalizeV2Component(rawComponent: unknown): V2ImageParsePayload['visibleComponents'][number] | null {
  const record = asRecord(rawComponent);
  if (!record) {
    return null;
  }
  const name = asText(getFirst(record, ['name', 'food', 'label', 'description', 'component']));
  if (!name) {
    return null;
  }
  return {
    name,
    category: asText(getFirst(record, ['category', 'role', 'foodRole', 'type'])) || 'food',
    zone: asText(getFirst(record, ['zone', 'location', 'area', 'position'])) || 'visible area',
    portionHint: asText(getFirst(record, ['portionHint', 'portion', 'amountHint', 'servingHint'])) || 'visible portion',
    confidence: clampConfidence(getFirst(record, ['confidence', 'matchConfidence']), 0.6),
    isSmallSide:
      getFirst(record, ['isSmallSide', 'smallSide', 'condiment']) === true ||
      ['condiment', 'sauce', 'dip', 'pickle', 'garnish'].some((signal) =>
        asText(getFirst(record, ['category', 'role', 'foodRole', 'type'])).toLowerCase().includes(signal)
      )
  };
}

function normalizeV2Payload(parsed: unknown): V2ImageParsePayload | null {
  const record = asRecord(parsed);
  if (!record) {
    return null;
  }

  const imageType = normalizeImageType(getFirst(record, ['imageType', 'type', 'mealType', 'photoType']));
  const rawComponents =
    getFirst(record, ['visibleComponents', 'components', 'inventory', 'detectedComponents', 'detected_foods']) ?? [];
  const visibleComponents = Array.isArray(rawComponents)
    ? rawComponents
        .map((component) => normalizeV2Component(component))
        .filter((component): component is V2ImageParsePayload['visibleComponents'][number] => component !== null)
    : [];

  const confidence = clampConfidence(getFirst(record, ['confidence', 'overallConfidence', 'imageConfidence']), 0.5);
  const rawItems =
    getFirst(record, ['items', 'foods', 'foodItems', 'nutritionItems', 'detectedFoods', 'results', 'matches']) ??
    [];
  if (!Array.isArray(rawItems)) {
    return null;
  }
  const items = rawItems
    .map((item) => normalizeGeminiItem(item, confidence))
    .filter((item): item is z.input<typeof parseItemSchema> => item !== null);

  const rawCoverage = asRecord(getFirst(record, ['coverage', 'coverageScore', 'coverageSummary']));
  const visibleComponentCount = Math.max(
    0,
    Math.round(
      asNumber(getFirst(rawCoverage ?? {}, ['visibleComponentCount', 'visibleComponents', 'detectedCount'])) ??
        visibleComponents.length
    )
  );
  const parsedItemCount = Math.max(
    0,
    Math.round(asNumber(getFirst(rawCoverage ?? {}, ['parsedItemCount', 'parsedItems', 'itemCount'])) ?? items.length)
  );
  const computedCoverage =
    visibleComponentCount > 0 ? Math.min(1, Math.max(0, parsedItemCount / visibleComponentCount)) : items.length > 0 ? 1 : 0;
  const coverageScore = clampConfidence(
    getFirst(rawCoverage ?? {}, ['score', 'coverage', 'coverageScore']) ?? getFirst(record, ['coverageScore', 'score']),
    computedCoverage
  );
  const warnings = [
    ...stringArray(getFirst(rawCoverage ?? {}, ['warnings', 'notes', 'gaps'])),
    ...stringArray(getFirst(record, ['warnings', 'coverageWarnings']))
  ].slice(0, 8);

  return {
    extractedText:
      asText(getFirst(record, ['extractedText', 'detectedText', 'summary', 'caption'])) ||
      items.map((item) => item.name).join(', ') ||
      visibleComponents.map((component) => component.name).join(', '),
    confidence,
    assumptions: stringArray(getFirst(record, ['assumptions', 'notes'])),
    imageType,
    cuisineHints: stringArray(getFirst(record, ['cuisineHints', 'cuisines', 'cuisine'])),
    visibleComponents,
    coverage: {
      visibleComponentCount,
      parsedItemCount,
      score: coverageScore,
      warnings
    },
    items
  };
}

function singleProductSignalScore(text: string): number {
  const normalized = text.toLowerCase();
  const strongSignals = [
    'nutrition facts',
    'nutrition label',
    'protein drink',
    'protein shake',
    'protein bar',
    'prebiotic soda',
    'sparkling water',
    'bottle',
    'can',
    'carton',
    'package',
    'packaged',
    'bar',
    'drink',
    'shake',
    'beverage',
    'soda'
  ];
  return strongSignals.reduce((score, signal) => score + (normalized.includes(signal) ? 1 : 0), 0);
}

function isLikelySinglePackagedProduct(payload: V2ImageParsePayload): boolean {
  const text = [
    payload.imageType,
    payload.extractedText,
    ...payload.visibleComponents.flatMap((component) => [component.name, component.category, component.portionHint]),
    ...payload.items.flatMap((item) => [item.name, item.unit, item.foodDescription ?? '', item.explanation ?? ''])
  ].join(' ');
  const productSignals = singleProductSignalScore(text);
  if (payload.imageType === 'nutrition_label' || payload.imageType === 'drink') {
    return productSignals > 0;
  }
  return payload.imageType === 'single_food' && productSignals >= 2;
}

function singleProductItemScore(item: z.input<typeof parseItemSchema>, index: number, extractedText: string): number {
  const name = `${item.name} ${item.unit} ${item.foodDescription ?? ''} ${item.explanation ?? ''}`.toLowerCase();
  const extractedKey = captionSegmentKey(extractedText);
  const itemKey = captionSegmentKey(item.name);
  let score = 100 - index;

  if (singleProductSignalScore(name) > 0) score += 60;
  if (/\b(protein|drink|shake|bar|bottle|can|soda|water|beverage|carton|package|packaged)\b/.test(name)) score += 40;
  if (/\b(bottle|can|bar|package|serving)\b/.test(String(item.unit).toLowerCase())) score += 20;
  if (extractedKey && itemKey && (extractedKey.includes(itemKey) || itemKey.includes(extractedKey))) score += 20;
  if (/\b(berries|berry|yogurt|fruit|flavor|flavoured|flavored)\b/.test(name) && !/\b(drink|shake|bar|bottle|protein)\b/.test(name)) {
    score -= 45;
  }

  return score + clampConfidence(item.matchConfidence, 0.5) * 10;
}

function normalizeSingleProductInventory(payload: V2ImageParsePayload): V2ImageParsePayload {
  if (payload.items.length <= 1 || !isLikelySinglePackagedProduct(payload)) {
    return payload;
  }

  const [best] = [...payload.items].sort(
    (left, right) =>
      singleProductItemScore(right, payload.items.indexOf(right), payload.extractedText) -
      singleProductItemScore(left, payload.items.indexOf(left), payload.extractedText)
  );
  const component =
    payload.visibleComponents[0] ?? {
      name: best.name,
      category: payload.imageType === 'drink' ? 'drink' : 'packaged product',
      zone: 'visible product',
      portionHint: `${best.quantity} ${best.unit}`,
      confidence: clampConfidence(best.matchConfidence, payload.confidence),
      isSmallSide: false
    };

  return {
    ...payload,
    extractedText: best.name,
    visibleComponents: [
      {
        ...component,
        name: best.name,
        category: component.category || (payload.imageType === 'drink' ? 'drink' : 'packaged product'),
        portionHint: component.portionHint || `${best.quantity} ${best.unit}`,
        isSmallSide: false
      }
    ],
    coverage: {
      visibleComponentCount: 1,
      parsedItemCount: 1,
      score: 1,
      warnings: []
    },
    assumptions: [
      ...payload.assumptions,
      'Treated the visible packaged product as one item instead of splitting flavor words into ingredients.'
    ].slice(0, 8),
    items: [best]
  };
}

function imagePayloadToParseResult(
  value: z.infer<typeof imageParseSchema>,
  postprocessContext?: FoodImagePostprocessContext
): { extractedText: string; result: ParseResult } | null {
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
  const result = postProcessFoodImageResult(
    normalizeImageParseResult(normalizeParseResultContract(baseResult, 'gemini')),
    {
      extractedText,
      assumptions: baseResult.assumptions,
      ...postprocessContext
    }
  );

  return {
    extractedText,
    result
  };
}

function itemSpecificity(item: ParsedItem, key: string): number {
  return (
    captionSegmentSpecificity(item.name, key) +
    Math.min(1, Math.max(0, item.matchConfidence || 0)) * 10 +
    (item.calories > 0 || item.protein > 0 || item.carbs > 0 || item.fat > 0 ? 5 : 0)
  );
}

function combineItemsAsCompound(items: ParsedItem[], compoundName: string, indexes: number[]): ParsedItem {
  const first = items[indexes[0]];
  const quantity = compoundName.toLowerCase().includes('chutney') ? 2 : 1;
  const unit = compoundName.toLowerCase().includes('chutney') ? 'tbsp' : 'serving';
  const grams = round(indexes.reduce((sum, index) => sum + nonNegative(items[index].grams), 0), 1);
  const calories = round(indexes.reduce((sum, index) => sum + nonNegative(items[index].calories), 0), 1);
  const protein = round(indexes.reduce((sum, index) => sum + nonNegative(items[index].protein), 0), 1);
  const carbs = round(indexes.reduce((sum, index) => sum + nonNegative(items[index].carbs), 0), 1);
  const fat = round(indexes.reduce((sum, index) => sum + nonNegative(items[index].fat), 0), 1);
  const confidence = round(
    indexes.reduce((sum, index) => sum + Math.min(1, Math.max(0, items[index].matchConfidence || 0.65)), 0) / indexes.length,
    2
  );

  return {
    ...first,
    name: compoundName,
    quantity,
    amount: quantity,
    unit,
    unitNormalized: unit,
    grams,
    gramsPerUnit: grams > 0 ? round(grams / quantity, 4) : null,
    calories,
    protein,
    carbs,
    fat,
    matchConfidence: confidence,
    foodDescription: `${compoundName}, ${quantity} ${unit}`,
    explanation: first.explanation || `Estimated visible ${compoundName.toLowerCase()} from the photo.`
  };
}

function addParsedCompoundItems(items: ParsedItem[]): ParsedItem[] {
  const keyed = items.map((item, index) => ({ item, index, key: captionSegmentKey(item.name) }));
  const consumed = new Set<number>();
  const additions: ParsedItem[] = [];

  const addIfPresent = (name: string, leftKeys: string[], rightKeys: string[]): void => {
    const left = keyed.find((entry) => !consumed.has(entry.index) && leftKeys.includes(entry.key));
    const right = keyed.find((entry) => !consumed.has(entry.index) && rightKeys.includes(entry.key));
    if (!left || !right || left.index === right.index) return;
    consumed.add(left.index);
    consumed.add(right.index);
    additions.push(combineItemsAsCompound(items, name, [left.index, right.index]));
  };

  addIfPresent('Mango chutney', ['mango'], ['chutney']);
  addIfPresent('Green chutney', ['green'], ['chutney']);
  addIfPresent('Potato sabzi', ['potato', 'aloo'], ['sabzi', 'vegetable', 'vegetables']);

  if (additions.length === 0) {
    return items;
  }
  return [...items.filter((_item, index) => !consumed.has(index)), ...additions];
}

function rebuildTotals(items: ParsedItem[]): ParseResult['totals'] {
  return {
    calories: round(items.reduce((sum, item) => sum + nonNegative(item.calories), 0), 1),
    protein: round(items.reduce((sum, item) => sum + nonNegative(item.protein), 0), 1),
    carbs: round(items.reduce((sum, item) => sum + nonNegative(item.carbs), 0), 1),
    fat: round(items.reduce((sum, item) => sum + nonNegative(item.fat), 0), 1)
  };
}

function normalizeImageParseResult(result: ParseResult): ParseResult {
  const combinedItems = addParsedCompoundItems(result.items);
  const totalItems = combinedItems.length;
  const selected = new Map<string, { item: ParsedItem; specificity: number; index: number }>();

  combinedItems.forEach((item, index) => {
    const key = captionSegmentKey(item.name);
    if (unsafeCaptionSegmentReason(key, totalItems)) {
      return;
    }
    const groupKey = captionSemanticGroupKey(key);
    const specificity = itemSpecificity(item, key);
    const existing = selected.get(groupKey);
    if (!existing || specificity > existing.specificity) {
      selected.set(groupKey, { item, specificity, index });
    }
  });

  const items = Array.from(selected.values())
    .sort((left, right) => left.index - right.index)
    .map(({ item }) => item);
  if (items.length === 0) {
    return result;
  }

  return {
    ...result,
    items,
    totals: rebuildTotals(items)
  };
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

  return imagePayloadToParseResult(validated.data);
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
    usageEvents,
    orchestratorVersion: 'v1'
  };
}

async function prepareImageForVision(image: ImagePart): Promise<ImagePart> {
  if (image.dataBase64.length < 128) {
    return image;
  }

  const startedAt = process.hrtime.bigint();
  try {
    const original = Buffer.from(image.dataBase64, 'base64');
    if (original.length < visionMinOptimizeBytes) {
      return image;
    }

    const optimized = await sharp(original, { failOn: 'none' })
      .rotate()
      .resize({
        width: visionMaxEdgePx,
        height: visionMaxEdgePx,
        fit: 'inside',
        withoutEnlargement: true
      })
      .jpeg({ quality: visionJpegQuality, mozjpeg: true })
      .toBuffer();

    if (optimized.length <= 0 || optimized.length >= original.length * 0.95) {
      return image;
    }

    image.debugEvents?.push({
      stage: 'image_prepare',
      ok: true,
      reason: 'optimized_for_vision',
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10,
      caption: `${original.length}B -> ${optimized.length}B`
    });

    return {
      ...image,
      mimeType: 'image/jpeg',
      dataBase64: optimized.toString('base64'),
      variantLabel: image.variantLabel ?? 'optimized'
    };
  } catch (err) {
    image.debugEvents?.push({
      stage: 'image_prepare',
      ok: false,
      reason: 'optimize_failed',
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10,
      caption: err instanceof Error ? err.message.slice(0, 120) : undefined
    });
    return image;
  }
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

async function runImageInventoryV2(image: ImagePart): Promise<{
  extractedText: string;
  result: ParseResult;
  usage: GeminiUsage;
  coverage: ImageParseCoverage;
} | null> {
  const startedAt = process.hrtime.bigint();
  const model = config.aiImageInventoryModel.trim() || config.geminiFlashModel;
  const timeoutMs = Math.min(Math.max(config.aiImageFastTimeoutMs, 3_500), 5_500);
  const response = await generateGeminiMultimodalJson({
    model,
    temperature: 0.05,
    maxOutputTokens: 1100,
    timeoutMs,
    maxAttempts: 1,
    parts: [
      { text: buildImageInventoryV2Prompt(image.contextNote) },
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
      stage: 'image_inventory_v2',
      ok: false,
      model,
      reason: 'gemini_no_response',
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10
    });
    return null;
  }

  let parsedJson: unknown;
  try {
    const jsonCandidate = extractJsonCandidate(response.jsonText);
    if (!jsonCandidate) {
      throw new Error('missing_json');
    }
    parsedJson = JSON.parse(jsonCandidate);
  } catch {
    image.debugEvents?.push({
      stage: 'image_inventory_v2',
      ok: false,
      model: response.usage.model,
      reason: 'invalid_or_empty_inventory_json',
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10
    });
    return null;
  }

  const normalizedPayload = normalizeV2Payload(parsedJson);
  const normalized = normalizedPayload ? normalizeSingleProductInventory(normalizedPayload) : null;
  if (!normalized || normalized.items.length === 0) {
    image.debugEvents?.push({
      stage: 'image_inventory_v2',
      ok: false,
      model: response.usage.model,
      reason: normalized?.visibleComponents.length ? 'inventory_without_usable_nutrition' : 'invalid_or_empty_inventory_json',
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10,
      items: normalized?.items.length ?? 0,
      caption: normalized?.visibleComponents.map((component) => component.name).join(', ').slice(0, 160)
    });
    return null;
  }

  const visibleCount = normalized.coverage.visibleComponentCount || normalized.visibleComponents.length;
  const parsedCount = normalized.coverage.parsedItemCount || normalized.items.length;
  const looksPartial =
    normalized.coverage.score < config.aiImageCoverageMin ||
    (visibleCount >= 3 && parsedCount < Math.max(2, Math.ceil(visibleCount * 0.6)));
  const coverageWarnings = normalized.coverage.warnings.length
    ? normalized.coverage.warnings
    : looksPartial
      ? ['Some visible foods may need review.']
      : [];
  const coverage: ImageParseCoverage = {
    imageType: normalized.imageType,
    cuisineHints: normalized.cuisineHints,
    visibleComponents: normalized.visibleComponents,
    visibleComponentCount: visibleCount,
    parsedItemCount: parsedCount,
    score: normalized.coverage.score,
    warnings: coverageWarnings,
    partial: looksPartial
  };
  const adjustedConfidence = looksPartial
    ? Math.min(normalized.confidence, Math.max(0.5, config.aiImageConfidenceMin - 0.01))
    : normalized.confidence;

  const validated = imageParseSchema.safeParse({
    extractedText: normalized.extractedText,
    confidence: adjustedConfidence,
    assumptions: [
      ...normalized.assumptions,
      ...coverageWarnings,
      normalized.cuisineHints.length ? `Cuisine hints: ${normalized.cuisineHints.join(', ')}` : ''
    ].filter(Boolean),
    items: normalized.items
  });
  if (!validated.success) {
    image.debugEvents?.push({
      stage: 'image_inventory_v2',
      ok: false,
      model: response.usage.model,
      reason: 'invalid_normalized_inventory_payload',
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10
    });
    return null;
  }

  const converted = imagePayloadToParseResult(validated.data, {
    imageType: normalized.imageType,
    visibleComponents: normalized.visibleComponents,
    extractedText: normalized.extractedText,
    assumptions: normalized.assumptions
  });
  if (!converted || !resultHasPositiveNutrition(converted.result)) {
    image.debugEvents?.push({
      stage: 'image_inventory_v2',
      ok: false,
      model: response.usage.model,
      reason: 'inventory_zero_nutrition',
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10
    });
    return null;
  }

  const result = looksPartial
    ? {
        ...converted.result,
        confidence: adjustedConfidence,
        items: converted.result.items.map((item) => ({
          ...item,
          needsClarification: true,
          explanation:
            item.explanation ||
            'Estimated from the visible photo; please confirm portions because this looks like a partial meal.'
        }))
      }
    : converted.result;

  image.debugEvents?.push({
    stage: 'image_inventory_v2',
    ok: true,
    model: response.usage.model,
    reason: looksPartial ? 'partial_coverage' : 'complete_or_good_coverage',
    ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10,
    confidence: result.confidence,
    items: result.items.length,
    caption: [
      `type=${normalized.imageType}`,
      `coverage=${round(normalized.coverage.score, 2)}`,
      `visible=${visibleCount}`,
      `parsed=${parsedCount}`,
      normalized.visibleComponents.map((component) => component.name).join(', ')
    ]
      .filter(Boolean)
      .join(' · ')
      .slice(0, 220)
  });

  return {
    extractedText: converted.extractedText,
    result,
    usage: response.usage,
    coverage
  };
}

async function runImageCaptionFallback(
  model: string,
  image: ImagePart,
  mode: ImageCaptionPromptMode = 'concise',
  timeoutMs = config.aiImageTimeoutMs
): Promise<{ caption: string; usage: GeminiUsage } | null> {
  const startedAt = process.hrtime.bigint();
  const response = await generateGeminiMultimodalText({
    model,
    temperature: 0.1,
    maxOutputTokens: mode === 'inventory' ? 120 : 80,
    timeoutMs,
    maxAttempts: 1,
    parts: [
      { text: buildImageCaptionFallbackPrompt(image.contextNote, mode) },
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
    const caption = parseCaptionPayload(response.jsonText);
    if (!caption) {
      image.debugEvents?.push({
        stage: 'image_caption',
        ok: false,
        model: response.usage.model,
        reason: 'empty_caption',
        ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10
      });
      return null;
    }
    const rejected = captionRejectionReason(caption);
    if (rejected) {
      image.debugEvents?.push({
        stage: 'image_caption',
        ok: false,
        model: response.usage.model,
        reason: rejected,
        ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10,
        caption: caption.slice(0, 160)
      });
      return null;
    }
    image.debugEvents?.push({
      stage: 'image_caption',
      ok: true,
      model: response.usage.model,
      reason: `${image.variantLabel ?? 'original'}_${mode}_caption`,
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10,
      caption
    });
    return {
      caption,
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

function splitCaptionFoodSegments(caption: string): string[] {
  return caption
    .split(/[,;\n]+|\s+\band\b\s+|\s+\bwith\b\s+/i)
    .map((segment) =>
      segment
        .trim()
        .replace(/^[-*\d.)\s]+/, '')
        .replace(/\s+/g, ' ')
    )
    .filter((segment) => segment.length >= 2)
    .filter((segment) => !captionRejectionReason(segment));
}

function toDisplayFoodName(key: string, fallback: string): string {
  const knownNames: Record<string, string> = {
    dal: 'Dal',
    daal: 'Dal',
    baati: 'Baati',
    bati: 'Baati',
    'green chutney': 'Green chutney',
    'mint chutney': 'Green chutney',
    'cilantro chutney': 'Green chutney',
    'mango chutney': 'Mango chutney',
    'potato sabzi': 'Potato sabzi',
    'aloo sabzi': 'Potato sabzi',
    churma: 'Churma powder',
    'churma powder': 'Churma powder',
    'dry chutney': 'Churma powder',
    'dry chutney powder': 'Churma powder',
    onion: 'Onion',
    'sliced onion': 'Onion',
    'red onion': 'Onion',
    'methi paratha': 'Methi paratha',
    'fenugreek paratha': 'Methi paratha',
    'methi flatbread': 'Methi paratha',
    'fenugreek flatbread': 'Methi paratha',
    thepla: 'Thepla',
    'methi thepla': 'Thepla'
  };
  if (knownNames[key]) {
    return knownNames[key];
  }
  return fallback
    .trim()
    .replace(/\s+/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function captionSegmentKey(segment: string): string {
  return segment
    .toLowerCase()
    .replace(/\b(bati)\b/g, 'baati')
    .replace(/\b(chur)\b/g, 'churma')
    .replace(/\b(green sauce)\b/g, 'green chutney')
    .replace(/\b(red onion|onion slices)\b/g, 'onion')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function captionSemanticGroupKey(key: string): string {
  if (/\b(methi|fenugreek)\s+(paratha|flatbread)\b/.test(key) || key === 'thepla' || key === 'methi thepla') {
    return 'methi_flatbread';
  }
  if (/\b(green|mint|cilantro)\s+chutney\b/.test(key)) {
    return 'green_chutney';
  }
  if (key === 'churma' || /\b(churma|dry chutney)\s*(powder)?\b/.test(key)) {
    return 'churma_powder';
  }
  if (/\b(mango)\s+chutney\b/.test(key)) {
    return 'mango_chutney';
  }
  if (/\b(potato|aloo)\s+sabzi\b/.test(key)) {
    return 'potato_sabzi';
  }
  if (/\bmixed\s+vegetables?\b/.test(key)) {
    return 'mixed_vegetables';
  }
  if (/\b(red|sliced)?\s*onion\b/.test(key)) {
    return 'onion';
  }
  return key;
}

function captionSegmentSpecificity(name: string, key: string): number {
  let score = key.length;
  if (/\b(chutney|sabzi|curry|powder|paratha|flatbread|thepla|baati)\b/.test(key)) score += 20;
  if (/^(green|red|white|brown|yellow|vegetable|mango|potato|chutney)$/.test(key)) score -= 25;
  if (key === 'methi paratha') score += 12;
  if (key === 'fenugreek paratha') score += 10;
  if (key === 'methi flatbread') score += 8;
  if (key === 'thepla') score += 5;
  return score + name.length / 100;
}

function unsafeCaptionSegmentReason(key: string, totalSegments: number): string | null {
  if (!key || key.length < 3) return 'short_fragment';
  const fragments = new Set([
    'al',
    'ba',
    'meth',
    'methi par',
    'fenugreek par',
    'green',
    'red',
    'white',
    'brown',
    'yellow'
  ]);
  if (fragments.has(key)) return 'unsafe_fragment';
  if (totalSegments > 1 && /^(vegetable|vegetables|chutney|sauce|potato)$/.test(key)) return 'generic_fragment';
  return null;
}

type CaptionSegmentCandidate = {
  name: string;
  key: string;
  groupKey: string;
  specificity: number;
};

function makeCaptionCandidate(segment: string, totalSegments: number): CaptionSegmentCandidate | null {
  const key = captionSegmentKey(segment);
  if (unsafeCaptionSegmentReason(key, totalSegments)) {
    return null;
  }
  const name = toDisplayFoodName(key, segment);
  return {
    name,
    key,
    groupKey: captionSemanticGroupKey(key),
    specificity: captionSegmentSpecificity(name, key)
  };
}

function addCombinedCompoundCandidates(
  candidates: CaptionSegmentCandidate[],
  rawSegments: string[],
  totalSegments: number
): CaptionSegmentCandidate[] {
  const keys = new Set(rawSegments.map(captionSegmentKey).filter(Boolean));
  const additions: string[] = [];

  if (keys.has('mango') && keys.has('chutney')) additions.push('mango chutney');
  if (keys.has('green') && keys.has('chutney')) additions.push('green chutney');
  if (keys.has('dal') && keys.has('ba')) additions.push('baati');
  if ((keys.has('dal') || keys.has('ba') || keys.has('baati')) && keys.has('green')) additions.push('green chutney');
  if ((keys.has('potato') || keys.has('aloo')) && (keys.has('sabzi') || keys.has('vegetable') || keys.has('vegetables'))) {
    additions.push('potato sabzi');
  }

  const added = additions
    .map((segment) => makeCaptionCandidate(segment, totalSegments))
    .filter((candidate): candidate is CaptionSegmentCandidate => Boolean(candidate));

  return [...candidates, ...added];
}

function shouldDropStandaloneBecauseCompoundExists(
  candidate: CaptionSegmentCandidate,
  candidates: CaptionSegmentCandidate[]
): boolean {
  const singletonKeys = new Set(['mango', 'green', 'chutney', 'potato', 'aloo', 'sabzi', 'churma']);
  if (!singletonKeys.has(candidate.key)) {
    return false;
  }
  return candidates.some(
    (other) =>
      other !== candidate &&
      other.key.includes(candidate.key) &&
      other.key !== candidate.key &&
      /\b(chutney|sabzi|powder)\b/.test(other.key)
  );
}

function captionCandidateFirstIndex(rawSegments: string[], candidate: CaptionSegmentCandidate): number {
  const directIndex = rawSegments.findIndex((segment) => captionSemanticGroupKey(captionSegmentKey(segment)) === candidate.groupKey);
  if (directIndex >= 0) {
    return directIndex;
  }

  const rawKeys = rawSegments.map(captionSegmentKey);
  if (candidate.groupKey === 'mango_chutney') {
    return Math.min(...['mango', 'chutney'].map((key) => rawKeys.indexOf(key)).filter((index) => index >= 0));
  }
  if (candidate.groupKey === 'green_chutney') {
    return Math.min(...['green', 'chutney'].map((key) => rawKeys.indexOf(key)).filter((index) => index >= 0));
  }
  if (candidate.groupKey === 'potato_sabzi') {
    return Math.min(...['potato', 'aloo', 'sabzi', 'vegetable', 'vegetables'].map((key) => rawKeys.indexOf(key)).filter((index) => index >= 0));
  }

  return Number.MAX_SAFE_INTEGER;
}

function normalizeCaptionInventorySegments(captions: string[]): string[] {
  const rawSegments = captions.flatMap(splitCaptionFoodSegments);
  const totalSegments = rawSegments.length;
  const initialCandidates = rawSegments
    .map((segment) => makeCaptionCandidate(segment, totalSegments))
    .filter((candidate): candidate is CaptionSegmentCandidate => Boolean(candidate));

  const candidates = addCombinedCompoundCandidates(initialCandidates, rawSegments, totalSegments).filter(
    (candidate, _index, all) => !shouldDropStandaloneBecauseCompoundExists(candidate, all)
  );

  const selected = new Map<string, CaptionSegmentCandidate>();
  for (const candidate of candidates) {
    const existing = selected.get(candidate.groupKey);
    if (!existing || candidate.specificity > existing.specificity) {
      selected.set(candidate.groupKey, candidate);
    }
  }

  return Array.from(selected.values())
    .sort((left, right) => captionCandidateFirstIndex(rawSegments, left) - captionCandidateFirstIndex(rawSegments, right))
    .map((candidate) => candidate.name)
    .slice(0, 12);
}

function mergeCaptionTexts(captions: string[]): string {
  return normalizeCaptionInventorySegments(captions).join(', ');
}

async function buildRotatedImageVariant(image: ImagePart, angle: 90 | -90): Promise<ImagePart | null> {
  const startedAt = process.hrtime.bigint();
  try {
    const buffer = Buffer.from(image.dataBase64, 'base64');
    const rotated = await sharp(buffer, { failOn: 'none' })
      .rotate(angle)
      .jpeg({ quality: 82, mozjpeg: true })
      .toBuffer();
    image.debugEvents?.push({
      stage: 'image_variant',
      ok: true,
      reason: angle === 90 ? 'rotated_90' : 'rotated_minus_90',
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10,
      caption: `${buffer.length}B -> ${rotated.length}B`
    });
    return {
      ...image,
      mimeType: 'image/jpeg',
      dataBase64: rotated.toString('base64'),
      variantLabel: angle === 90 ? 'rotated_90' : 'rotated_minus_90'
    };
  } catch (err) {
    image.debugEvents?.push({
      stage: 'image_variant',
      ok: false,
      reason: angle === 90 ? 'rotate_90_failed' : 'rotate_minus_90_failed',
      ms: Math.round((Number(process.hrtime.bigint() - startedAt) / 1_000_000) * 10) / 10,
      caption: err instanceof Error ? err.message.slice(0, 120) : undefined
    });
    return null;
  }
}

function captionInventoryLooksSparse(caption: string): boolean {
  const segments = splitCaptionFoodSegments(caption);
  if (segments.length < 4) {
    return true;
  }
  return segments.some((segment) => /^(green|red|brown|white|yellow)$/i.test(segment.trim()));
}

function coverageFromCaptionInventory(caption: string, result: ParseResult): ImageParseCoverage {
  const segments = splitCaptionFoodSegments(caption);
  const visibleComponentCount = Math.max(segments.length, result.items.length);
  const parsedItemCount = result.items.length;
  const score = visibleComponentCount > 0 ? round(Math.min(1, parsedItemCount / visibleComponentCount), 2) : 0;
  const partial = visibleComponentCount >= 3 && parsedItemCount < visibleComponentCount;
  return {
    imageType: visibleComponentCount >= 3 ? 'multi_component_meal' : 'unclear',
    cuisineHints: [],
    visibleComponents: segments.map((name) => ({
      name,
      category: 'food',
      zone: 'caption probe',
      portionHint: 'visible portion',
      confidence: 0.7,
      isSmallSide: /chutney|sauce|pickle|onion|salad|powder|garnish|dip/i.test(name)
    })),
    visibleComponentCount,
    parsedItemCount,
    score,
    warnings: partial ? ['Some visible foods may need review because the image inventory was assembled from fast caption probes.'] : [],
    partial
  };
}

type CaptionEstimate = {
  name: string;
  aliases: string[];
  quantity: number;
  unit: string;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
};

const captionEstimateLibrary: CaptionEstimate[] = [
  { name: 'Upma', aliases: ['upma', 'semolina upma', 'rava upma'], quantity: 1, unit: 'bowl', grams: 240, calories: 310, protein: 8, carbs: 52, fat: 8 },
  { name: 'Poha', aliases: ['poha', 'flattened rice'], quantity: 1, unit: 'bowl', grams: 240, calories: 280, protein: 6, carbs: 50, fat: 7 },
  { name: 'Sev', aliases: ['sev', 'crunchy sev', 'crunchy garnish', 'namkeen topping'], quantity: 1, unit: 'small topping', grams: 25, calories: 140, protein: 4, carbs: 13, fat: 8 },
  { name: 'Green chutney', aliases: ['green chutney', 'mint chutney', 'cilantro chutney'], quantity: 2, unit: 'tbsp', grams: 30, calories: 30, protein: 1, carbs: 4, fat: 1 },
  { name: 'Mango chutney', aliases: ['mango chutney', 'mango pickle', 'mango sauce'], quantity: 2, unit: 'tbsp', grams: 35, calories: 70, protein: 0.3, carbs: 17, fat: 0.2 },
  { name: 'Potato sabzi', aliases: ['potato sabzi', 'aloo sabzi', 'potato sab'], quantity: 1, unit: 'serving', grams: 120, calories: 160, protein: 3, carbs: 25, fat: 6 },
  { name: 'Baati', aliases: ['baati', 'bati'], quantity: 2, unit: 'pieces', grams: 120, calories: 360, protein: 9, carbs: 58, fat: 12 },
  { name: 'Churma powder', aliases: ['churma', 'dry chutney powder', 'dry chutney', 'chutney powder'], quantity: 2, unit: 'tbsp', grams: 25, calories: 110, protein: 2, carbs: 16, fat: 5 },
  { name: 'Dal', aliases: ['dal', 'daal', 'lentil curry'], quantity: 1, unit: 'serving', grams: 240, calories: 240, protein: 14, carbs: 38, fat: 6 },
  { name: 'Onion', aliases: ['onion', 'sliced onion', 'red onion'], quantity: 1, unit: 'small side', grams: 40, calories: 16, protein: 0.4, carbs: 3.7, fat: 0 },
  { name: 'Methi paratha', aliases: ['methi paratha', 'fenugreek paratha', 'methi flatbread', 'fenugreek flatbread', 'thepla', 'methi thepla'], quantity: 1, unit: 'piece', grams: 90, calories: 230, protein: 6, carbs: 30, fat: 10 },
  { name: 'Mixed vegetables', aliases: ['mixed vegetables', 'mixed vegetable sabzi', 'vegetable sabzi'], quantity: 1, unit: 'cup', grams: 140, calories: 120, protein: 4, carbs: 18, fat: 4 },
  { name: 'White rice', aliases: ['white rice', 'rice'], quantity: 1, unit: 'cup', grams: 158, calories: 205, protein: 4.3, carbs: 44.5, fat: 0.4 },
  { name: 'Rajma', aliases: ['rajma', 'kidney bean curry'], quantity: 1, unit: 'serving', grams: 200, calories: 300, protein: 15, carbs: 40, fat: 10 },
  { name: 'Chole', aliases: ['chole', 'chickpea curry'], quantity: 1, unit: 'serving', grams: 200, calories: 330, protein: 14, carbs: 48, fat: 10 },
  { name: 'Chapati', aliases: ['chapati', 'roti'], quantity: 1, unit: 'piece', grams: 45, calories: 120, protein: 3.5, carbs: 20, fat: 3 },
  { name: 'Paratha', aliases: ['paratha'], quantity: 1, unit: 'piece', grams: 80, calories: 250, protein: 6, carbs: 32, fat: 11 },
  { name: 'Dosa', aliases: ['dosa', 'masala dosa'], quantity: 1, unit: 'piece', grams: 180, calories: 300, protein: 6, carbs: 48, fat: 9 },
  { name: 'Medu vada', aliases: ['medu vada', 'vada', 'vadai'], quantity: 2, unit: 'pieces', grams: 140, calories: 300, protein: 8, carbs: 34, fat: 15 },
  { name: 'Sambar', aliases: ['sambar'], quantity: 1, unit: 'bowl', grams: 180, calories: 120, protein: 6, carbs: 18, fat: 3 },
  { name: 'Coconut chutney', aliases: ['coconut chutney'], quantity: 2, unit: 'tbsp', grams: 30, calories: 80, protein: 1, carbs: 4, fat: 7 },
  { name: 'Small Pizza', aliases: ['small pizza', 'personal pizza', 'whole small pizza'], quantity: 1, unit: 'pizza', grams: 330, calories: 890, protein: 36, carbs: 105, fat: 36 },
  { name: 'Pizza slice', aliases: ['pizza slice', 'pizza'], quantity: 1, unit: 'slice', grams: 110, calories: 290, protein: 12, carbs: 30, fat: 14 },
  { name: 'Burger', aliases: ['burger'], quantity: 1, unit: 'burger', grams: 220, calories: 550, protein: 25, carbs: 45, fat: 30 },
  { name: 'Fries', aliases: ['fries', 'french fries'], quantity: 1, unit: 'serving', grams: 120, calories: 365, protein: 4, carbs: 48, fat: 17 },
  { name: 'Chicken wings', aliases: ['chicken wings', 'buffalo wings', 'wings'], quantity: 4, unit: 'pieces', grams: 180, calories: 430, protein: 34, carbs: 2, fat: 30 },
  { name: 'Carrots', aliases: ['carrots', 'carrot sticks', 'baby carrots'], quantity: 1, unit: 'serving', grams: 80, calories: 35, protein: 1, carbs: 8, fat: 0.2 },
  { name: 'Celery', aliases: ['celery', 'celery sticks'], quantity: 1, unit: 'serving', grams: 80, calories: 15, protein: 0.6, carbs: 3, fat: 0.2 },
  { name: 'Ranch dressing', aliases: ['ranch', 'ranch dressing', 'white dip', 'creamy dip'], quantity: 2, unit: 'tbsp', grams: 30, calories: 130, protein: 1, carbs: 2, fat: 13 },
  { name: 'Blue cheese dressing', aliases: ['blue cheese', 'blue cheese dressing'], quantity: 2, unit: 'tbsp', grams: 30, calories: 140, protein: 1, carbs: 1, fat: 15 },
  { name: 'Fried rice', aliases: ['fried rice'], quantity: 1, unit: 'serving', grams: 300, calories: 500, protein: 14, carbs: 75, fat: 16 },
  { name: 'Noodles', aliases: ['noodles', 'chow mein'], quantity: 1, unit: 'serving', grams: 300, calories: 450, protein: 12, carbs: 70, fat: 14 },
  { name: 'Pasta', aliases: ['pasta'], quantity: 1, unit: 'serving', grams: 300, calories: 450, protein: 16, carbs: 70, fat: 12 },
  { name: 'Roasted chicken', aliases: ['roasted chicken', 'grilled chicken', 'chicken leg', 'chicken drumstick'], quantity: 1, unit: 'piece', grams: 140, calories: 260, protein: 32, carbs: 0, fat: 14 },
  { name: 'Mashed potatoes', aliases: ['mashed potatoes', 'creamy potatoes', 'potato mash'], quantity: 1, unit: 'serving', grams: 180, calories: 210, protein: 4, carbs: 34, fat: 8 },
  { name: 'Macaroni and cheese', aliases: ['macaroni and cheese', 'mac and cheese', 'macaroni cheese'], quantity: 1, unit: 'serving', grams: 180, calories: 360, protein: 13, carbs: 42, fat: 16 },
  { name: 'Corn casserole', aliases: ['corn casserole', 'corn gratin', 'corn bake'], quantity: 1, unit: 'serving', grams: 140, calories: 240, protein: 8, carbs: 28, fat: 11 },
  { name: 'Beetroot', aliases: ['beetroot', 'beets', 'beet salad', 'beetroot side'], quantity: 1, unit: 'side', grams: 80, calories: 60, protein: 1.5, carbs: 13, fat: 0.2 }
];

function findCaptionEstimate(segment: string): CaptionEstimate | null {
  const key = captionSegmentKey(segment);
  if (key.length < 3) {
    return null;
  }
  return (
    captionEstimateLibrary.find((estimate) =>
      estimate.aliases.some((alias) => key === captionSegmentKey(alias) || key.includes(captionSegmentKey(alias)))
    ) ?? null
  );
}

function captionAccessorySegmentsAreSafe(segments: string[], items: ParsedItem[]): boolean {
  const itemKey = captionSegmentKey(items.map((item) => item.name).join(' '));
  const unmatched = segments
    .map((segment) => captionSegmentKey(segment))
    .filter((key) => key && !findCaptionEstimate(key));

  if (unmatched.length === 0) return true;

  if (/\bpizza\b/.test(itemKey)) {
    return unmatched.every((key) =>
      /\b(cheese|mozzarella|olive|olives|jalapeno|jalapenos|pepperoni|corn|mushroom|mushrooms|onion|onions|pepper|peppers|tomato|tomatoes|sauce|basil|pineapple|wooden board)\b/.test(
        key
      )
    );
  }

  if (/\b(upma|poha)\b/.test(itemKey)) {
    return unmatched.every((key) => /\b(onion|cilantro|coriander|tomato|curry leaves|semolina|rice|grain|grains)\b/.test(key));
  }

  return false;
}

function captionHeuristicResult(caption: string): ParseResult | null {
  const segments = splitCaptionFoodSegments(caption);
  const items: ParsedItem[] = [];
  const seen = new Set<string>();

  for (const segment of segments) {
    const estimate = findCaptionEstimate(segment);
    if (!estimate || seen.has(estimate.name)) continue;
    seen.add(estimate.name);
    items.push({
      name: estimate.name,
      quantity: estimate.quantity,
      unit: estimate.unit,
      grams: estimate.grams,
      calories: estimate.calories,
      protein: estimate.protein,
      carbs: estimate.carbs,
      fat: estimate.fat,
      matchConfidence: 0.72,
      nutritionSourceId: 'image_caption_heuristic',
      originalNutritionSourceId: 'image_caption_heuristic',
      sourceFamily: 'gemini',
      needsClarification: true,
      foodDescription: `${estimate.name}, ${estimate.quantity} ${estimate.unit}`,
      explanation: `Estimated from the photo inventory as ${estimate.quantity} ${estimate.unit}; please review portions if needed.`
    });
  }

  if (items.length === 0) {
    return null;
  }

  if (items.length / Math.max(1, segments.length) < 0.5 && !captionAccessorySegmentsAreSafe(segments, items)) {
    return null;
  }

  return {
    confidence: 0.72,
    assumptions: ['Estimated from fast photo inventory; review portions if anything looks off.'],
    items,
    totals: {
      calories: round(items.reduce((sum, item) => sum + item.calories, 0), 1),
      protein: round(items.reduce((sum, item) => sum + item.protein, 0), 1),
      carbs: round(items.reduce((sum, item) => sum + item.carbs, 0), 1),
      fat: round(items.reduce((sum, item) => sum + item.fat, 0), 1)
    }
  };
}

function productCaptionSignalScore(key: string): number {
  let score = 0;
  if (/\bprotein\s+(drink|shake|beverage)\b/.test(key)) score += 100;
  if (/\b(protein|nutrition|energy|snack)\s+bar\b/.test(key)) score += 90;
  if (/\b(sparkling water|prebiotic soda|diet soda|soda|cola|coke)\b/.test(key)) score += 80;
  if (/\b(drink|shake|beverage|bottle|can|bar|carton|package)\b/.test(key)) score += 35;
  if (/\b(chobani|premier protein|rxbar|quest|fairlife|ensure|boost|spindrift|poppi|waterloo|coca cola|diet coke)\b/.test(key)) {
    score += 25;
  }
  return score;
}

function productCaptionFragmentAllowed(fragmentKey: string, productKey: string): boolean {
  if (!fragmentKey) return true;
  if (productKey.includes(fragmentKey) || fragmentKey.includes(productKey)) return true;

  const allowedFragments = new Set([
    'mixed',
    'mixed berry',
    'berry',
    'berries',
    'vanilla',
    'mixed berry vanilla',
    'chobani',
    'premier',
    'premier protein',
    'protein',
    'shake',
    'drink',
    'bottle',
    'can',
    'bar'
  ]);
  return allowedFragments.has(fragmentKey);
}

function bestProductCaptionSegment(segments: string[]): string | null {
  const scored = segments
    .map((segment, index) => {
      const key = captionSegmentKey(segment);
      return {
        segment: segment.trim(),
        key,
        score: productCaptionSignalScore(key) + key.length / 100 - index / 1000
      };
    })
    .filter((candidate) => candidate.score >= 80)
    .sort((left, right) => right.score - left.score);

  return scored[0]?.segment ?? null;
}

function singleProductCaptionResult(caption: string): ParseResult | null {
  const segments = splitCaptionFoodSegments(caption);
  if (segments.length === 0) {
    return null;
  }

  const productSegment = bestProductCaptionSegment(segments);
  if (!productSegment) {
    return null;
  }

  const productKey = captionSegmentKey(productSegment);
  if (!productKey) {
    return null;
  }

  const unrelated = segments
    .map((segment) => captionSegmentKey(segment))
    .filter((key) => key !== productKey)
    .filter((key) => !productCaptionFragmentAllowed(key, productKey));

  if (unrelated.length > 0) {
    return null;
  }

  const captionKey = captionSegmentKey(caption);
  const brandPrefix =
    /\bchobani\b/.test(captionKey) && !/\bchobani\b/.test(productKey)
      ? 'Chobani '
      : /\bpremier\s+protein\b/.test(captionKey) && !/\bpremier\b/.test(productKey)
        ? 'Premier Protein '
        : '';
  const displayName = `${brandPrefix}${toDisplayFoodName(productKey, productSegment)}`.replace(/\s+/g, ' ').trim();

  let quantity = 1;
  let unit = 'serving';
  let grams = 330;
  let calories = 170;
  let protein = 25;
  let carbs = 14;
  let fat = 2.5;

  if (/\bpremier\b/.test(captionKey)) {
    unit = 'bottle';
    grams = 330;
    calories = 160;
    protein = 30;
    carbs = 5;
    fat = 3;
  } else if (/\bchobani\b/.test(captionKey) || /\bprotein\s+(drink|shake|beverage)\b/.test(productKey)) {
    unit = 'bottle';
    grams = 296;
    calories = 170;
    protein = 25;
    carbs = 14;
    fat = 2.5;
  } else if (/\b(protein|nutrition|energy|snack)\s+bar\b/.test(productKey) || /\brxbar\b/.test(captionKey)) {
    unit = 'bar';
    grams = /\brxbar\b/.test(captionKey) ? 52 : 60;
    calories = /\brxbar\b/.test(captionKey) ? 180 : 210;
    protein = /\brxbar\b/.test(captionKey) ? 12 : 15;
    carbs = /\brxbar\b/.test(captionKey) ? 24 : 24;
    fat = /\brxbar\b/.test(captionKey) ? 6 : 7;
  } else if (/\b(diet|zero|sparkling water|waterloo)\b/.test(captionKey)) {
    unit = /\bcan\b/.test(productKey) ? 'can' : 'bottle';
    grams = 355;
    calories = /\bspindrift\b/.test(captionKey) ? 10 : 1;
    protein = 0;
    carbs = /\bspindrift\b/.test(captionKey) ? 2 : 0;
    fat = 0;
  } else if (/\b(soda|cola|coke|prebiotic soda|poppi)\b/.test(productKey)) {
    unit = /\bcan\b/.test(productKey) ? 'can' : 'bottle';
    grams = 355;
    calories = /\bpoppi|prebiotic\b/.test(captionKey) ? 25 : 140;
    protein = 0;
    carbs = /\bpoppi|prebiotic\b/.test(captionKey) ? 6 : 39;
    fat = 0;
  }

  const item: ParsedItem = {
    name: displayName,
    quantity,
    unit,
    grams,
    calories,
    protein,
    carbs,
    fat,
    matchConfidence: 0.82,
    nutritionSourceId: 'image_caption_product_heuristic',
    originalNutritionSourceId: 'image_caption_product_heuristic',
    sourceFamily: 'gemini',
    needsClarification: true,
    foodDescription: `${displayName}, ${quantity} ${unit}`,
    explanation: `Estimated as one visible packaged ${unit}; review the label if you want exact brand values.`
  };

  return {
    confidence: 0.82,
    assumptions: ['Treated the visible packaged product as one item instead of splitting flavor words into ingredients.'],
    items: [item],
    totals: { calories, protein, carbs, fat }
  };
}

async function parseCaptionToImageResult(
  caption: string,
  image: ImagePart,
  usageEvents: ImageParseUsageEvent[],
  orchestratorVersion: 'v1' | 'v2',
  coverage?: ImageParseCoverage
): Promise<ImageParseServiceResult | null> {
  if (orchestratorVersion === 'v2') {
    const productResult = singleProductCaptionResult(caption);
    if (productResult) {
      const resolvedCoverage = coverage ?? coverageFromCaptionInventory(caption, productResult);
      image.debugEvents?.push({
        stage: 'image_caption_product_v2',
        ok: true,
        model: 'heuristic',
        reason: 'single_packaged_product',
        ms: 0,
        confidence: productResult.confidence,
        items: productResult.items.length,
        caption
      });
      return {
        extractedText: productResult.items[0]?.name ?? caption,
        result: productResult,
        model: 'heuristic',
        fallbackUsed: true,
        lowConfidenceAccepted: true,
        usageEvents,
        orchestratorVersion,
        coverage: resolvedCoverage
      };
    }
  }

  const textStartedAt = process.hrtime.bigint();
  const textAttempt = await tryGeminiPrimaryParse(caption, createEmptyParseResult(caption));
  if (!textAttempt?.result.items.length || !resultHasPositiveNutrition(textAttempt.result)) {
    image.debugEvents?.push({
      stage: 'image_caption_text',
      ok: false,
      reason: textAttempt?.result.items.length ? 'text_parse_non_food_or_zero_nutrition' : 'text_parse_failed',
      ms: Math.round((Number(process.hrtime.bigint() - textStartedAt) / 1_000_000) * 10) / 10,
      caption
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

  const result = postProcessFoodImageResult(
    normalizeImageParseResult(imageSafeResult(normalizeParseResultContract(textAttempt.result, 'gemini'))),
    { extractedText: caption, assumptions: textAttempt.result.assumptions }
  );
  const resolvedCoverage = coverage ?? coverageFromCaptionInventory(caption, result);
  image.debugEvents?.push({
    stage: 'image_caption_text',
    ok: true,
    model: textAttempt.usage.model,
    ms: Math.round((Number(process.hrtime.bigint() - textStartedAt) / 1_000_000) * 10) / 10,
    confidence: result.confidence,
    items: result.items.length,
    caption
  });
  return {
    extractedText: caption,
    result,
    model: textAttempt.usage.model,
    fallbackUsed: true,
    lowConfidenceAccepted: true,
    usageEvents,
    orchestratorVersion,
    coverage: orchestratorVersion === 'v2' ? resolvedCoverage : undefined
  };
}

async function recoverWithV2CaptionEnsemble(
  image: ImagePart,
  usageEvents: ImageParseUsageEvent[]
): Promise<ImageParseServiceResult | null> {
  const model = config.aiImageInventoryModel.trim() || config.geminiFlashModel;
  const timeoutMs = Math.min(Math.max(config.aiImageFastTimeoutMs, 2_800), 4_000);
  const caption = await runImageCaptionFallback(model, image, 'inventory', timeoutMs);
  if (caption?.caption.trim()) {
    usageEvents.push({
      feature: 'parse_image_caption',
      usage: caption.usage,
      estimatedCostUsd: estimateCostUsd(caption.usage)
    });
  }

  let mergedCaption = caption?.caption ? mergeCaptionTexts([caption.caption]) : '';
  if (!mergedCaption) {
    image.debugEvents?.push({
      stage: 'image_caption_fast_v2',
      ok: false,
      model,
      reason: caption ? 'empty_merged_caption' : 'caption_probe_failed',
      ms: 0
    });
  }

  const contextCaption = trimSafe(image.contextNote);
  if (
    contextCaption &&
    (captionFoodSegmentCount(contextCaption) >= 3 ||
      captionFoodSegmentCount(contextCaption) > captionFoodSegmentCount(mergedCaption))
  ) {
    const contextMerged = mergeCaptionTexts([mergedCaption, contextCaption]);
    if (captionFoodSegmentCount(contextMerged) > captionFoodSegmentCount(mergedCaption)) {
      mergedCaption = contextMerged;
      image.debugEvents?.push({
        stage: 'image_caption_fast_v2',
        ok: true,
        model: 'context',
        reason: 'merged_sparse_caption_with_context',
        ms: 0,
        items: captionFoodSegmentCount(mergedCaption),
        caption: mergedCaption.slice(0, 180)
      });
    }
  }

  if (!mergedCaption && contextCaption && captionFoodSegmentCount(contextCaption) >= 2) {
    mergedCaption = mergeCaptionTexts([contextCaption]);
    image.debugEvents?.push({
      stage: 'image_caption_fast_v2',
      ok: true,
      model: 'context',
      reason: 'using_context_after_caption_failure',
      ms: 0,
      items: captionFoodSegmentCount(mergedCaption),
      caption: mergedCaption.slice(0, 180)
    });
  }

  if (!mergedCaption) {
    return null;
  }

  image.debugEvents?.push({
    stage: 'image_caption_fast_v2',
    ok: true,
    model,
    reason: 'single_caption_inventory',
    ms: 0,
    items: captionFoodSegmentCount(mergedCaption),
    caption: mergedCaption.slice(0, 180)
  });

  const productHeuristic = singleProductCaptionResult(mergedCaption);
  if (productHeuristic) {
    const productCoverage = coverageFromCaptionInventory(mergedCaption, productHeuristic);
    image.debugEvents?.push({
      stage: 'image_caption_product_v2',
      ok: true,
      model: 'heuristic',
      reason: 'single_packaged_product',
      ms: 0,
      confidence: productHeuristic.confidence,
      items: productHeuristic.items.length,
      caption: mergedCaption.slice(0, 180)
    });
    return {
      extractedText: productHeuristic.items[0]?.name ?? mergedCaption,
      result: productHeuristic,
      model,
      fallbackUsed: true,
      lowConfidenceAccepted: true,
      usageEvents,
      orchestratorVersion: 'v2',
      coverage: productCoverage
    };
  }

  const heuristic = captionHeuristicResult(mergedCaption);
  if (heuristic) {
    const heuristicCoverage = coverageFromCaptionInventory(mergedCaption, heuristic);
    const normalizedHeuristic = postProcessFoodImageResult(
      imageSafeResult(normalizeParseResultContract(heuristic, 'gemini')),
      {
        extractedText: mergedCaption,
        assumptions: heuristic.assumptions,
        imageType: heuristicCoverage.imageType,
        visibleComponents: heuristicCoverage.visibleComponents
      }
    );
    image.debugEvents?.push({
      stage: 'image_caption_heuristic_v2',
      ok: true,
      model: 'heuristic',
      reason: 'common_food_inventory_estimate',
      ms: 0,
      confidence: normalizedHeuristic.confidence,
      items: normalizedHeuristic.items.length,
      caption: mergedCaption.slice(0, 180)
    });
    return {
      extractedText: mergedCaption,
      result: normalizedHeuristic,
      model,
      fallbackUsed: true,
      lowConfidenceAccepted: true,
      usageEvents,
      orchestratorVersion: 'v2',
      coverage: heuristicCoverage
    };
  }

  image.debugEvents?.push({
    stage: 'image_caption_heuristic_v2',
    ok: false,
    model: 'heuristic',
    reason: 'no_safe_heuristic_match_trying_caption_text',
    ms: 0,
    items: captionFoodSegmentCount(mergedCaption),
    caption: mergedCaption.slice(0, 180)
  });
  return parseCaptionToImageResult(mergedCaption, image, usageEvents, 'v2');
}

async function recoverWithStructuredRescue(
  image: ImagePart,
  usageEvents: ImageParseUsageEvent[]
): Promise<ImageParseServiceResult | null> {
  const rescueModels = Array.from(
    new Set([config.aiImagePrimaryModel.trim(), config.aiImageFallbackModel.trim()].filter(Boolean))
  );

  for (const model of rescueModels) {
    const rescued = await runImageModel(model, image, 'rescue');
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
        usageEvents,
        orchestratorVersion: 'v1'
      };
    }

    const acceptedRescue = acceptedLowConfidenceResult(rescued, usageEvents, true);
    if (acceptedRescue) {
      return acceptedRescue;
    }
  }

  return null;
}

async function recoverWithCaptionFallback(
  image: ImagePart,
  usageEvents: ImageParseUsageEvent[]
): Promise<ImageParseServiceResult | null> {
  const captionModels = [config.aiImagePrimaryModel, config.aiImageFallbackModel]
    .map((model) => model.trim())
    .filter(Boolean);
  const rawCaptionAttempts: Array<{ model: string | undefined; mode: ImageCaptionPromptMode }> = [
    { model: captionModels[0], mode: 'concise' },
    { model: captionModels[0], mode: 'inventory' },
    { model: captionModels[1], mode: 'inventory' }
  ];
  const captionAttempts = Array.from(
    new Map(
      rawCaptionAttempts
        .filter((attempt): attempt is { model: string; mode: ImageCaptionPromptMode } => Boolean(attempt.model))
        .map((attempt) => [`${attempt.model}:${attempt.mode}`, attempt])
    ).values()
  );

  const deferredSparseCaptions: Array<{ caption: string; usage: GeminiUsage }> = [];

  async function parseCaptionText(caption: { caption: string }): Promise<ImageParseServiceResult | null> {
    const textStartedAt = process.hrtime.bigint();
    const textAttempt = await tryGeminiPrimaryParse(caption.caption, createEmptyParseResult(caption.caption));
    if (!textAttempt?.result.items.length || !resultHasPositiveNutrition(textAttempt.result)) {
      image.debugEvents?.push({
        stage: 'image_caption_text',
        ok: false,
        reason: textAttempt?.result.items.length ? 'text_parse_non_food_or_zero_nutrition' : 'text_parse_failed',
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

    const result = postProcessFoodImageResult(
      normalizeImageParseResult(imageSafeResult(normalizeParseResultContract(textAttempt.result, 'gemini'))),
      { extractedText: caption.caption, assumptions: textAttempt.result.assumptions }
    );
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
      usageEvents,
      orchestratorVersion: 'v1'
    };
  }

  for (const [index, attempt] of captionAttempts.entries()) {
    const caption = await runImageCaptionFallback(attempt.model, image, attempt.mode);
    if (!caption?.caption.trim()) {
      continue;
    }

    usageEvents.push({
      feature: 'parse_image_caption',
      usage: caption.usage,
      estimatedCostUsd: estimateCostUsd(caption.usage)
    });

    if (index < captionAttempts.length - 1 && shouldTryStrongerCaptionModel(caption.caption, image.contextNote)) {
      image.debugEvents?.push({
        stage: 'image_caption',
        ok: false,
        model: caption.usage.model,
        reason: 'caption_too_sparse_for_multi_food_context',
        ms: 0,
        caption: caption.caption
      });
      deferredSparseCaptions.push(caption);
      continue;
    }

    const parsed = await parseCaptionText(caption);
    if (parsed) {
      return parsed;
    }
  }

  const contextCaption = trimSafe(image.contextNote);
  if (captionFoodSegmentCount(contextCaption) >= 3) {
    image.debugEvents?.push({
      stage: 'image_caption',
      ok: true,
      model: 'context',
      reason: 'using_multi_food_context_after_sparse_caption',
      ms: 0,
      caption: contextCaption
    });
    const parsed = await parseCaptionText({ caption: contextCaption });
    if (parsed) {
      return {
        ...parsed,
        extractedText: contextCaption
      };
    }
  }

  // Sparse captions such as "dal" are useful as a last resort for true
  // single-food photos, but they are dangerous for trays/thalis because they
  // silently drop visible sides. Give the structured rescue prompt one more
  // chance to inspect the image before accepting a sparse caption.
  const structuredRescue = await recoverWithStructuredRescue(image, usageEvents);
  if (structuredRescue) {
    return structuredRescue;
  }

  for (const caption of deferredSparseCaptions) {
    const parsed = await parseCaptionText(caption);
    if (parsed) {
      return parsed;
    }
  }

  return null;
}

export async function parseImageWithGemini(image: ImagePart): Promise<ImageParseServiceResult> {
  if (!config.aiImageParseEnabled) {
    throw new ApiError(403, 'IMAGE_PARSE_DISABLED', 'Image parse is disabled.');
  }

  const visionImage = await prepareImageForVision(image);
  const usageEvents: ImageParseUsageEvent[] = [];
  const useV2 = config.aiImageOrchestratorVersion.trim().toLowerCase() === 'v2';

  if (useV2) {
    const inventoryV2 = await runImageInventoryV2(visionImage);
    if (inventoryV2?.usage) {
      usageEvents.push({
        feature: 'parse_image_inventory_v2',
        usage: inventoryV2.usage,
        estimatedCostUsd: estimateCostUsd(inventoryV2.usage)
      });
    }

    if (inventoryV2 && resultHasPositiveNutrition(inventoryV2.result)) {
      return {
        extractedText: inventoryV2.extractedText,
        result: inventoryV2.result,
        model: inventoryV2.usage.model,
        fallbackUsed: false,
        lowConfidenceAccepted:
          inventoryV2.result.confidence < config.aiImageConfidenceMin ||
          inventoryV2.coverage.score < config.aiImageCoverageMin,
        usageEvents,
        orchestratorVersion: 'v2',
        coverage: inventoryV2.coverage
      };
    }

    visionImage.debugEvents?.push({
      stage: 'image_orchestrator_v2',
      ok: false,
      reason: 'inventory_failed_trying_caption_recovery',
      ms: 0
    });

    const captionEnsemble = await recoverWithV2CaptionEnsemble(visionImage, usageEvents);
    if (captionEnsemble && resultHasPositiveNutrition(captionEnsemble.result)) {
      return captionEnsemble;
    }

    visionImage.debugEvents?.push({
      stage: 'image_orchestrator_v2',
      ok: false,
      reason: 'v2_failed_without_safe_result',
      ms: 0
    });
    throw new ApiError(502, 'IMAGE_PARSE_FAILED', 'Unable to estimate nutrition from this image. Please try another photo.');
  }

  const primary = await runImageModel(config.aiImagePrimaryModel, visionImage);
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
      usageEvents,
      orchestratorVersion: 'v1'
    };
  }

  const acceptedPrimary = acceptedLowConfidenceResult(primary, usageEvents, false);
  if (acceptedPrimary && !config.aiImageEnableFallback) {
    return acceptedPrimary;
  }

  if (!config.aiImageEnableFallback) {
    throw new ApiError(422, 'IMAGE_PARSE_LOW_CONFIDENCE', 'Image parse confidence is too low. Please retry with a clearer photo.');
  }

  const captionRecovered = await recoverWithCaptionFallback(visionImage, usageEvents);
  if (captionRecovered) {
    return captionRecovered;
  }

  if (acceptedPrimary) {
    return acceptedPrimary;
  }

  throw new ApiError(502, 'IMAGE_PARSE_FAILED', 'Unable to estimate nutrition from this image. Please try another photo.');
}
