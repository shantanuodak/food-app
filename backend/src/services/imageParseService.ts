import { z } from 'zod';
import { config } from '../config.js';
import { ApiError } from '../utils/errors.js';
import type { ParseResult, ParsedItem } from './deterministicParser.js';
import { createEmptyParseResult } from './parsePipelineResultUtils.js';
import { normalizeParseResultContract } from './parseContractService.js';
import { generateGeminiMultimodalJson, generateGeminiMultimodalText, type GeminiUsage } from './geminiFlashClient.js';
import { tryGeminiPrimaryParse } from './aiNormalizerService.js';

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
type ImageCaptionPromptMode = 'concise' | 'inventory';

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

function imagePayloadToParseResult(value: z.infer<typeof imageParseSchema>): { extractedText: string; result: ParseResult } | null {
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
  const response = await generateGeminiMultimodalJson({
    model,
    temperature: 0.05,
    maxOutputTokens: 1100,
    timeoutMs: config.aiImageFastTimeoutMs,
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

  const normalized = normalizeV2Payload(parsedJson);
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

  const converted = imagePayloadToParseResult(validated.data);
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
  mode: ImageCaptionPromptMode = 'concise'
): Promise<{ caption: string; usage: GeminiUsage } | null> {
  const startedAt = process.hrtime.bigint();
  const response = await generateGeminiMultimodalText({
    model,
    temperature: 0.1,
    maxOutputTokens: mode === 'inventory' ? 120 : 80,
    timeoutMs: config.aiImageTimeoutMs,
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
      reason: mode === 'inventory' ? 'inventory_caption' : 'concise_caption',
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
  const captionAttempts = Array.from(
    new Map(
      [
        { model: captionModels[0], mode: 'concise' as const },
        { model: captionModels[0], mode: 'inventory' as const },
        { model: captionModels[1], mode: 'inventory' as const }
      ]
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

  const usageEvents: ImageParseUsageEvent[] = [];
  const useV2 = config.aiImageOrchestratorVersion.trim().toLowerCase() === 'v2';

  if (useV2) {
    const inventoryV2 = await runImageInventoryV2(image);
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

    image.debugEvents?.push({
      stage: 'image_orchestrator_v2',
      ok: false,
      reason: 'falling_back_to_v1',
      ms: 0
    });
  }

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

  const captionRecovered = await recoverWithCaptionFallback(image, usageEvents);
  if (captionRecovered) {
    return captionRecovered;
  }

  if (acceptedPrimary) {
    return acceptedPrimary;
  }

  throw new ApiError(502, 'IMAGE_PARSE_FAILED', 'Unable to estimate nutrition from this image. Please try another photo.');
}
