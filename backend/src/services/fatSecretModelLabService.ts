import { performance } from 'node:perf_hooks';
import { config } from '../config.js';
import { parseFoodText } from './deterministicParser.js';
import { tryGeminiPrimaryParse } from './aiNormalizerService.js';
import { parseImageWithGemini, type ImageParseDebugEvent } from './imageParseService.js';
import { scoreNutrition, type BenchmarkScores, type NutritionValues } from './benchmarkScoringService.js';

export type FatSecretModelLabCaseKind = 'text' | 'image';

export type FatSecretModelLabCaseInput = {
  kind: FatSecretModelLabCaseKind;
  label?: string | null;
  inputText?: string | null;
  fatSecretQuery?: string | null;
  servingHint?: string | null;
  imageBase64?: string | null;
  mimeType?: string | null;
  contextNote?: string | null;
};

export type FatSecretModelLabOptions = {
  cases?: FatSecretModelLabCaseInput[];
  maxCases?: number;
  targetScore?: number;
  runLabel?: string | null;
  onProgress?: (casesDone: number, totalCases: number) => void;
};

export type FatSecretReference = {
  foodId: string | null;
  foodName: string;
  brandName: string | null;
  servingDescription: string;
  servingHint: string | null;
  scale: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  sourceLabel: string;
  reference: string | null;
};

export type FatSecretModelLabGeminiResult = {
  model: string | null;
  confidence: number | null;
  totals: NutritionValues;
  items: Array<{
    name: string;
    calories: number | null;
    protein: number | null;
    carbs: number | null;
    fat: number | null;
    confidence: number | null;
  }>;
  extractedText?: string | null;
  coverageScore?: number | null;
  costUsd: number;
};

export type FatSecretModelLabCaseResult = {
  kind: FatSecretModelLabCaseKind;
  label: string;
  inputText: string | null;
  fatSecretQuery: string;
  servingHint: string | null;
  reference: FatSecretReference | null;
  gemini: FatSecretModelLabGeminiResult | null;
  scores: BenchmarkScores;
  passedTarget: boolean;
  durationMs: number;
  error: string | null;
};

export type FatSecretModelLabRunResult = {
  runLabel: string | null;
  startedAt: string;
  finishedAt: string;
  targetScore: number;
  caseCount: number;
  scoredCases: number;
  errorCount: number;
  passCount: number;
  passRate: number;
  overallScore: number;
  meetsTarget: boolean;
  estimatedCostUsd: number;
  weakCases: Array<{
    label: string;
    kind: FatSecretModelLabCaseKind;
    score: number;
    error: string | null;
  }>;
  results: FatSecretModelLabCaseResult[];
};

type FatSecretTokenResponse = {
  access_token?: string;
  expires_in?: number;
};

type FatSecretServing = {
  calories?: string;
  protein?: string;
  carbohydrate?: string;
  fat?: string;
  is_default?: string;
  serving_description?: string;
  number_of_units?: string;
  measurement_description?: string;
};

type FatSecretFood = {
  food_id?: string;
  food_name?: string;
  brand_name?: string;
  food_type?: string;
  servings?: {
    serving?: FatSecretServing | FatSecretServing[];
  };
};

type FatSecretSearchResponse = {
  foods_search?: {
    results?: {
      food?: FatSecretFood | FatSecretFood[];
    };
  };
};

const STARTER_TEXT_CASES = [
  'black coffee 1 cup',
  'cold coffee 8 oz',
  'iced latte 12 oz',
  'oat milk latte 12 oz',
  'mango lassi 12 oz',
  'masala chai 1 cup',
  'sweet lassi 1 glass',
  'banana 1 medium',
  'apple 1 medium',
  'avocado toast 2 slices',
  'boiled egg 2 large',
  'scrambled eggs 2 eggs',
  'greek yogurt 1 cup',
  'oatmeal 1 cup',
  'peanut butter 2 tbsp',
  'protein shake 12 oz',
  'caesar salad with chicken',
  'grilled chicken breast 6 oz',
  'salmon fillet 6 oz',
  'white rice 1 cup',
  'brown rice 1 cup',
  'quinoa 1 cup',
  'mac and cheese 1 cup',
  'pepperoni pizza 2 slices',
  'cheeseburger 1 burger',
  'french fries medium',
  'chicken nuggets 6 pieces',
  'buffalo wings 6 pieces',
  'coke 12 oz',
  'orange juice 8 oz',
  'chicken burrito 1 burrito',
  'beef tacos 3 tacos',
  'cheese quesadilla 1 piece',
  'nachos with salsa',
  'guacamole 1 cup',
  'chicken tikka masala 1 cup',
  'dal tadka 1 bowl',
  'rajma chawal 1 bowl',
  'chole bhature 1 plate',
  'pav bhaji 1 plate',
  'samosa 2 pieces',
  'aloo paratha with butter',
  'idli 3 pieces with sambar',
  'masala dosa 1 dosa',
  'palak paneer 1 cup',
  'paneer tikka 6 pieces',
  'garlic naan 1 piece',
  'chicken biryani 1 plate',
  'poha 1 bowl',
  'upma 1 bowl',
  'spaghetti bolognese 1 plate',
  'penne alfredo 1 bowl',
  'margherita pizza 3 slices',
  'lasagna 1 serving',
  'minestrone soup 1 bowl',
  'mushroom risotto 1 cup',
  'tiramisu 1 slice',
  'kung pao chicken 1 bowl',
  'vegetable fried rice 1 bowl',
  'chow mein 1 plate',
  'sweet and sour pork 1 serving',
  'dim sum 6 pieces',
  'hot and sour soup 1 bowl',
  'salmon sushi 8 pieces',
  'chicken teriyaki with rice',
  'tonkotsu ramen 1 bowl',
  'miso soup 1 cup',
  'tempura shrimp 5 pieces',
  'chicken shawarma wrap',
  'falafel 6 pieces',
  'hummus 1 cup with pita',
  'lamb kebab 2 skewers',
  'tabbouleh salad 1 bowl',
  'pad thai shrimp 1 plate',
  'green curry chicken 1 bowl',
  'tom yum soup 1 bowl',
  'pho beef 1 bowl',
  'spring rolls 2 rolls',
  'bibimbap 1 bowl',
  'kimchi fried rice 1 bowl',
  'bulgogi beef 1 serving',
  'greek salad with feta',
  'vanilla ice cream 1 scoop',
  'brownie 1 piece',
  'banana pudding 1 cup',
  'clif bar chocolate chip 68g',
  'chobani greek yogurt strawberry',
  'kind bar dark chocolate nuts',
  'chipotle chicken bowl',
  'mcdonalds big mac',
  'subway turkey sandwich 6 inch',
  'starbucks caramel macchiato grande',
  'panera broccoli cheddar soup bowl',
  'taco bell bean burrito',
  'wendys chili small',
  'dominos pepperoni pizza 2 slices',
  'costco hot dog',
  'trader joes butter chicken',
  'lentil soup 1 bowl',
  'turkey sandwich 1 sandwich',
  'chocolate milkshake 12 oz'
] as const;

const failedScores: BenchmarkScores = {
  calories: 0,
  protein: 0,
  carbs: 0,
  fat: 0,
  overall: 0,
  label: 'failed'
};

let fatSecretTokenCache: { token: string; expiresAtMs: number } | null = null;

export function starterFatSecretModelLabCases(limit = 25): FatSecretModelLabCaseInput[] {
  return STARTER_TEXT_CASES.slice(0, Math.max(1, Math.min(limit, STARTER_TEXT_CASES.length))).map((inputText) => ({
    kind: 'text',
    inputText,
    fatSecretQuery: inputText,
    servingHint: inputText
  }));
}

export async function runFatSecretModelLab(options: FatSecretModelLabOptions = {}): Promise<FatSecretModelLabRunResult> {
  const startedAt = new Date().toISOString();
  const targetScore = clampNumber(options.targetScore ?? 85, 0, 100);
  const maxCases = Math.max(1, Math.min(options.maxCases ?? 25, 100));
  const inputCases = options.cases?.length ? options.cases : starterFatSecretModelLabCases(maxCases);
  const cases = inputCases.slice(0, maxCases);
  const results: FatSecretModelLabCaseResult[] = [];

  for (const input of cases) {
    const result = await runOneCase(input, targetScore);
    results.push(result);
    options.onProgress?.(results.length, cases.length);
  }

  const scoreValues = results.map((result) => result.scores.overall);
  const overallScore = round(average(scoreValues) ?? 0);
  const scoredCases = results.filter((result) => !result.error && result.reference && result.gemini).length;
  const passCount = results.filter((result) => result.passedTarget).length;
  const estimatedCostUsd = round(results.reduce((sum, result) => sum + (result.gemini?.costUsd ?? 0), 0), 6);
  const weakCases = results
    .filter((result) => result.error || result.scores.overall < targetScore)
    .map((result) => ({
      label: result.label,
      kind: result.kind,
      score: result.scores.overall,
      error: result.error
    }));

  return {
    runLabel: options.runLabel ?? null,
    startedAt,
    finishedAt: new Date().toISOString(),
    targetScore,
    caseCount: cases.length,
    scoredCases,
    errorCount: results.length - scoredCases,
    passCount,
    passRate: results.length ? round(passCount / results.length, 4) : 0,
    overallScore,
    meetsTarget: overallScore >= targetScore,
    estimatedCostUsd,
    weakCases,
    results
  };
}

async function runOneCase(input: FatSecretModelLabCaseInput, targetScore: number): Promise<FatSecretModelLabCaseResult> {
  const started = performance.now();
  const kind = input.kind;
  const inputText = cleanText(input.inputText);
  const fatSecretQuery = cleanText(input.fatSecretQuery) || inputText;
  const servingHint = cleanText(input.servingHint) || inputText || fatSecretQuery || null;
  const label = cleanText(input.label) || inputText || fatSecretQuery || 'Untitled case';

  try {
    if (!fatSecretQuery) {
      throw new Error('FatSecret query is required.');
    }

    const reference = await lookupFatSecretReference(fatSecretQuery, servingHint);
    if (!reference) {
      throw new Error('FatSecret did not return a usable serving with calories and macros.');
    }

    const gemini = kind === 'image'
      ? await runImageGeminiCase(input)
      : await runTextGeminiCase(inputText || label);
    const scores = scoreNutrition(reference, gemini.totals);

    return {
      kind,
      label,
      inputText: inputText || null,
      fatSecretQuery,
      servingHint,
      reference,
      gemini,
      scores,
      passedTarget: scores.overall >= targetScore,
      durationMs: round(performance.now() - started),
      error: null
    };
  } catch (err) {
    return {
      kind,
      label,
      inputText: inputText || null,
      fatSecretQuery,
      servingHint,
      reference: null,
      gemini: null,
      scores: failedScores,
      passedTarget: false,
      durationMs: round(performance.now() - started),
      error: err instanceof Error ? err.message : String(err)
    };
  }
}

async function runTextGeminiCase(inputText: string): Promise<FatSecretModelLabGeminiResult> {
  if (!inputText.trim()) {
    throw new Error('Text input is required for a text case.');
  }
  const baseline = parseFoodText(inputText);
  const output = await tryGeminiPrimaryParse(inputText, baseline, {
    timeoutMs: config.geminiTimeoutMs,
    maxAttempts: config.geminiRetryMaxAttempts
  });
  if (!output) {
    throw new Error('Gemini did not return a text parse.');
  }
  return {
    model: output.usage.model,
    confidence: output.result.confidence,
    totals: output.result.totals,
    items: output.result.items.map((item) => ({
      name: item.name,
      calories: finiteNumber(item.calories),
      protein: finiteNumber(item.protein),
      carbs: finiteNumber(item.carbs),
      fat: finiteNumber(item.fat),
      confidence: finiteNumber(item.matchConfidence)
    })),
    costUsd: output.usage.estimatedCostUsd
  };
}

async function runImageGeminiCase(input: FatSecretModelLabCaseInput): Promise<FatSecretModelLabGeminiResult> {
  const imageBase64 = cleanText(input.imageBase64);
  const mimeType = cleanText(input.mimeType);
  if (!imageBase64 || !mimeType) {
    throw new Error('Image data and MIME type are required for an image case.');
  }
  const debugEvents: ImageParseDebugEvent[] = [];
  const parsed = await parseImageWithGemini({
    mimeType,
    dataBase64: imageBase64,
    contextNote: cleanText(input.contextNote) || undefined,
    debugEvents
  });
  const costUsd = parsed.usageEvents.reduce((sum, event) => sum + event.estimatedCostUsd, 0);
  return {
    model: parsed.model,
    confidence: parsed.result.confidence,
    totals: parsed.result.totals,
    items: parsed.result.items.map((item) => ({
      name: item.name,
      calories: finiteNumber(item.calories),
      protein: finiteNumber(item.protein),
      carbs: finiteNumber(item.carbs),
      fat: finiteNumber(item.fat),
      confidence: finiteNumber(item.matchConfidence)
    })),
    extractedText: parsed.extractedText,
    coverageScore: parsed.coverage?.score ?? null,
    costUsd
  };
}

export async function lookupFatSecretReference(query: string, servingHint?: string | null): Promise<FatSecretReference | null> {
  if (!config.fatSecretClientId || !config.fatSecretClientSecret) {
    throw new Error('FatSecret credentials are not configured.');
  }

  const token = await getFatSecretAccessToken();
  if (!token) {
    throw new Error('FatSecret token unavailable.');
  }

  const params = new URLSearchParams({
    search_expression: query,
    format: 'json',
    max_results: '10',
    flag_default_serving: 'true'
  });

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Math.max(1000, config.fatSecretTimeoutMs));

  try {
    const response = await fetch(`${config.fatSecretApiBaseUrl}/foods/search/v2?${params.toString()}`, {
      headers: { Authorization: `Bearer ${token}` },
      signal: controller.signal
    });
    if (!response.ok) {
      throw new Error(`FatSecret token request failed with status ${response.status}.`);
    }

    const data = (await response.json()) as FatSecretSearchResponse;
    const food = selectFatSecretFood(toArray(data.foods_search?.results?.food), query, servingHint ?? query);
    if (!food) return null;

    const serving = selectFatSecretServing(food, servingHint ?? query);
    if (!serving) return null;

    const calories = numberFromString(serving.calories);
    const protein = numberFromString(serving.protein);
    const carbs = numberFromString(serving.carbohydrate);
    const fat = numberFromString(serving.fat);
    if (calories === null || protein === null || carbs === null || fat === null || calories <= 0) return null;

    const scale = servingScale(servingHint ?? query, serving);
    const foodName = food.food_name?.trim() || query;
    const servingDescription = serving.serving_description?.trim() || serving.measurement_description?.trim() || 'default serving';
    return {
      foodId: food.food_id ?? null,
      foodName,
      brandName: food.brand_name?.trim() || null,
      servingDescription,
      servingHint: servingHint ?? null,
      scale,
      calories: round(calories * scale),
      protein: round(protein * scale),
      carbs: round(carbs * scale),
      fat: round(fat * scale),
      sourceLabel: `FatSecret ${foodName}`,
      reference: food.food_id ? `Food ID ${food.food_id}` : null
    };
  } finally {
    clearTimeout(timeout);
  }
}

async function getFatSecretAccessToken(): Promise<string | null> {
  if (fatSecretTokenCache && fatSecretTokenCache.expiresAtMs > Date.now() + 60_000) {
    return fatSecretTokenCache.token;
  }

  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    scope: config.fatSecretScope
  });
  const auth = Buffer.from(`${config.fatSecretClientId}:${config.fatSecretClientSecret}`).toString('base64');
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Math.max(1000, config.fatSecretTimeoutMs));

  try {
    const response = await fetch(config.fatSecretTokenUrl, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body,
      signal: controller.signal
    });
    if (!response.ok) return null;

    const data = (await response.json()) as FatSecretTokenResponse;
    if (!data.access_token) return null;
    fatSecretTokenCache = {
      token: data.access_token,
      expiresAtMs: Date.now() + Math.max(60, data.expires_in ?? 3600) * 1000
    };
    return data.access_token;
  } finally {
    clearTimeout(timeout);
  }
}

function selectFatSecretFood(foods: FatSecretFood[], query: string, hint: string): FatSecretFood | null {
  const withServings = foods.filter((food) => selectFatSecretServing(food, hint));
  if (!withServings.length) return null;
  const normalizedQuery = normalize(query);
  const queryTerms = significantFoodTokens(normalizedQuery);
  return [...withServings].sort((a, b) => foodRank(a, normalizedQuery, queryTerms, hint) - foodRank(b, normalizedQuery, queryTerms, hint))[0] ?? null;
}

function foodRank(food: FatSecretFood, normalizedQuery: string, queryTerms: Set<string>, hint: string): number {
  const name = normalize(food.food_name);
  const brand = normalize(food.brand_name);
  const nameTerms = new Set(tokenize(name));
  let rank = 10;

  if (name === normalizedQuery) rank -= 6;
  if (name.includes(normalizedQuery) || normalizedQuery.includes(name)) rank -= 3;

  for (const term of queryTerms) {
    if (!nameTerms.has(term) && !(brand && tokenize(brand).includes(term))) {
      rank += 4;
    }
  }

  const hintUnit = unitWord(normalize(hint));
  const serving = selectFatSecretServing(food, hint);
  const servingText = normalize(`${serving?.serving_description ?? ''} ${serving?.measurement_description ?? ''}`);
  if (hintUnit) {
    rank += servingText.includes(hintUnit) ? -2 : 3;
  }

  if (brand && normalizedQuery.includes(brand)) {
    rank -= 3;
  } else if (brand) {
    rank += 2;
  }
  if (food.food_type === 'Brand' && !(brand && normalizedQuery.includes(brand))) rank += 1;

  return rank;
}

function selectFatSecretServing(food: FatSecretFood, hint: string): FatSecretServing | null {
  const servings = toArray(food.servings?.serving);
  if (!servings.length) return null;
  const normalizedHint = normalize(hint);
  const hintUnit = unitWord(normalizedHint);
  const hinted = servings.find((serving) => {
    const servingText = normalize(`${serving.serving_description ?? ''} ${serving.measurement_description ?? ''}`);
    return hintUnit ? servingText.includes(hintUnit) : normalizedHint && servingText.includes(normalizedHint);
  });
  if (hinted) return hinted;
  return servings.find((serving) => serving.is_default === '1') ?? servings[0] ?? null;
}

function servingScale(hint: string, serving: FatSecretServing | null): number {
  if (!serving) return 1;
  const amount = amountFromText(hint) ?? 1;
  const hintUnit = unitWord(normalize(hint));
  const servingText = serving.serving_description ?? serving.measurement_description ?? '';
  const servingUnit = unitWord(normalize(servingText));
  if (hintUnit && servingUnit && hintUnit === servingUnit) {
    const servingAmount = amountFromText(servingText) ?? Number(serving.number_of_units ?? 1);
    return Math.max(0.1, amount / (Number.isFinite(servingAmount) && servingAmount > 0 ? servingAmount : 1));
  }
  return 1;
}

function amountFromText(text: string): number | null {
  const mixedFraction = text.match(/\b(\d+(?:\.\d+)?)\s+(\d+)\s*\/\s*(\d+)\b/);
  if (mixedFraction) {
    const whole = Number(mixedFraction[1]);
    const numerator = Number(mixedFraction[2]);
    const denominator = Number(mixedFraction[3]);
    if (Number.isFinite(whole) && Number.isFinite(numerator) && Number.isFinite(denominator) && denominator > 0) {
      return whole + numerator / denominator;
    }
  }

  const fraction = text.match(/\b(\d+)\s*\/\s*(\d+)\b/);
  if (fraction) {
    const numerator = Number(fraction[1]);
    const denominator = Number(fraction[2]);
    if (Number.isFinite(numerator) && Number.isFinite(denominator) && denominator > 0) {
      return numerator / denominator;
    }
  }

  const numeric = text.match(/\b(\d+(?:\.\d+)?)\b/);
  if (numeric) {
    const amount = Number(numeric[1]);
    if (Number.isFinite(amount)) return amount;
  }

  const normalized = normalize(text);
  const wordAmounts: Record<string, number> = {
    one: 1,
    two: 2,
    three: 3,
    four: 4,
    five: 5,
    six: 6,
    seven: 7,
    eight: 8,
    nine: 9,
    ten: 10
  };
  for (const [word, amount] of Object.entries(wordAmounts)) {
    if (normalized.split(/\s+/).includes(word)) return amount;
  }

  return null;
}

function unitWord(text: string): string {
  if (/\b(?:fl\s*oz|oz|ounce|ounces)\b/.test(text)) return 'oz';
  if (/\b(?:cup|cups)\b/.test(text)) return 'cup';
  if (/\b(?:slice|slices)\b/.test(text)) return 'slice';
  if (/\b(?:piece|pieces)\b/.test(text)) return 'piece';
  if (/\b(?:item|items)\b/.test(text)) return 'item';
  if (/\b(?:bowl|bowls)\b/.test(text)) return 'bowl';
  if (/\b(?:plate|plates)\b/.test(text)) return 'plate';
  if (/\b(?:serving|servings)\b/.test(text)) return 'serving';
  if (/\b(?:glass|glasses)\b/.test(text)) return 'glass';
  if (/\b(?:bottle|bottles)\b/.test(text)) return 'bottle';
  if (/\b(?:tbsp|tablespoon|tablespoons)\b/.test(text)) return 'tbsp';
  if (/\b(?:tsp|teaspoon|teaspoons)\b/.test(text)) return 'tsp';
  if (/\b(?:container|containers)\b/.test(text)) return 'container';
  if (/\b(?:bar|bars)\b/.test(text)) return 'bar';
  if (/\b(?:sandwich|sandwiches|sub|subs)\b/.test(text)) return 'sandwich';
  if (/\b(?:burger|burgers)\b/.test(text)) return 'burger';
  if (/\b(?:wrap|wraps)\b/.test(text)) return 'wrap';
  if (/\b(?:taco|tacos)\b/.test(text)) return 'taco';
  if (/\b(?:small|medium|large)\b/.test(text)) return text.match(/\b(small|medium|large)\b/)?.[1] ?? '';
  if (/(?:\b\d+(?:\.\d+)?\s*g\b|\b(?:gram|grams|g)\b)/.test(text)) return 'g';
  return '';
}

function numberFromString(value: string | undefined): number | null {
  if (!value) return null;
  const parsed = Number(value.replace(/,/g, '').trim());
  return Number.isFinite(parsed) ? parsed : null;
}

function finiteNumber(value: number | null | undefined): number | null {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : null;
}

function average(values: number[]): number | null {
  const usable = values.filter((value) => Number.isFinite(value));
  if (!usable.length) return null;
  return usable.reduce((sum, value) => sum + value, 0) / usable.length;
}

function round(value: number, digits = 1): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function clampNumber(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  return Math.max(min, Math.min(max, value));
}

function cleanText(value: string | null | undefined): string {
  return (value ?? '').trim();
}

function normalize(value: string | undefined | null): string {
  return (value ?? '').toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}

function tokenize(value: string): string[] {
  return value.split(/\s+/).filter(Boolean);
}

function significantFoodTokens(normalizedQuery: string): Set<string> {
  const ignored = new Set([
    'a',
    'an',
    'the',
    'of',
    'and',
    'with',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    'small',
    'medium',
    'large',
    'slice',
    'slices',
    'piece',
    'pieces',
    'cup',
    'cups',
    'oz',
    'ounce',
    'ounces',
    'g',
    'gram',
    'grams',
    'serving',
    'servings',
    'inch',
    'in'
  ]);
  return new Set(tokenize(normalizedQuery).filter((token) => !ignored.has(token) && !/^\d+(?:\.\d+)?(?:g|oz)?$/.test(token)));
}

function toArray<T>(value: T | T[] | undefined): T[] {
  if (!value) return [];
  return Array.isArray(value) ? value : [value];
}
