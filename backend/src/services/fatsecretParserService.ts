import { config } from '../config.js';
import type { ParseResult, ParsedServingOption } from './deterministicParser.js';
import { sumNutrition } from './nutritionService.js';
import {
  COMMON_FOOD_UNIT_ALIASES,
  normalizeFoodText,
  normalizeFoodUnit,
  parseFoodTextCandidates,
  tokenOverlapRatio
} from './foodTextCandidates.js';

type ParsedItem = ParseResult['items'][number];

type CandidateItem = {
  rawSegment: string;
  query: string;
  quantity: number;
  unit: string;
  gramsHint: number | null;
  caloriesHintPer100g: number | null;
};

type FatSecretFoodSummary = {
  food_id?: string;
  food_name?: string;
  food_description?: string;
  food_type?: string;
  brand_name?: string;
};

type FatSecretSearchResponse = {
  foods?: {
    food?: FatSecretFoodSummary | FatSecretFoodSummary[];
  };
};

type FatSecretServing = {
  serving_id?: string;
  serving_description?: string;
  measurement_description?: string;
  metric_serving_amount?: string | number;
  metric_serving_unit?: string;
  number_of_units?: string | number;
  calories?: string | number;
  protein?: string | number;
  carbohydrate?: string | number;
  fat?: string | number;
};

type FatSecretFoodDetailsResponse = {
  food?: {
    food_id?: string;
    food_name?: string;
    servings?: {
      serving?: FatSecretServing | FatSecretServing[];
    };
  };
};

type FatSecretDescriptionProfile = {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  referenceQuantity: number;
  referenceUnit: string;
  referenceGrams: number | null;
};

type FatSecretScoredSummary = {
  foodId: string | null;
  name: string;
  description: string;
  score: number;
  contentOverlap: number;
  profile: FatSecretDescriptionProfile | null;
};

type SearchBestFoodResult = {
  accepted: FatSecretScoredSummary | null;
  topCandidate: FatSecretScoredSummary | null;
  rejectionReason: 'semantic_mismatch' | 'below_min_score' | null;
};

type ParsedServing = {
  servingId: string | null;
  unit: string;
  servingUnits: number;
  metricGrams: number | null;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  rawDescription: string;
};

const UNIT_TO_GRAMS: Record<string, number> = {
  g: 1,
  ml: 1,
  oz: 28.3495,
  tsp: 4.7,
  tbsp: 14.2,
  cup: 240,
  slice: 30,
  count: 50,
  serving: 100
};

const AMBIGUOUS_QUANTITY_UNITS = new Set(['count', 'serving']);
const GENERIC_QUERY_TOKENS = new Set([
  'food',
  'meal',
  'dish',
  'item',
  'plate',
  'serving',
  'scoop',
  'slice',
  'cup',
  'count',
  'piece',
  'pieces',
  'small',
  'medium',
  'large',
  'fresh',
  'plain',
  'homemade'
]);
const DESSERT_TOKENS = new Set(['icecream', 'ice', 'cream', 'dessert', 'gelato', 'sundae', 'sorbet', 'pudding']);
const GRAIN_TOKENS = new Set(['rice', 'biryani', 'pilaf']);

const searchCache = new Map<string, { expiresAt: number; result: SearchBestFoodResult }>();
const detailsCache = new Map<string, { expiresAt: number; servings: ParsedServing[] | null }>();

let tokenCache: { token: string; expiresAt: number } | null = null;

function round(value: number, digits = 1): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function clamp01(value: number): number {
  if (value < 0) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return value;
}

function normalizeUnit(value: string): string {
  return normalizeFoodUnit(value, COMMON_FOOD_UNIT_ALIASES, 'count');
}

function isAmbiguousQuantityUnit(unit: string): boolean {
  return AMBIGUOUS_QUANTITY_UNITS.has(unit);
}

function asNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value.replace(/,/g, '').trim());
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return null;
}

function toArray<T>(value: T | T[] | undefined | null): T[] {
  if (!value) {
    return [];
  }
  return Array.isArray(value) ? value : [value];
}

function parseDescriptionProfile(foodDescription: string): FatSecretDescriptionProfile | null {
  if (!foodDescription || !foodDescription.trim()) {
    return null;
  }

  const caloriesMatch = foodDescription.match(/calories:\s*([\d.]+)/i);
  const proteinMatch = foodDescription.match(/protein:\s*([\d.]+)/i);
  const carbsMatch = foodDescription.match(/(?:carb|carbohydrate)s?:\s*([\d.]+)/i);
  const fatMatch = foodDescription.match(/fat:\s*([\d.]+)/i);
  if (!caloriesMatch || !proteinMatch || !carbsMatch || !fatMatch) {
    return null;
  }

  const calories = asNumber(caloriesMatch[1]);
  const protein = asNumber(proteinMatch[1]);
  const carbs = asNumber(carbsMatch[1]);
  const fat = asNumber(fatMatch[1]);
  if (calories === null || protein === null || carbs === null || fat === null) {
    return null;
  }

  const perMatch = foodDescription.match(/^\s*per\s+(.+?)\s*-/i);
  const referenceRaw = perMatch?.[1] || '1 serving';
  const qtyUnitMatch = referenceRaw.match(/(\d+(?:\.\d+)?)\s*([a-z]+)/i);

  let referenceQuantity = 1;
  let referenceUnit = 'serving';
  if (qtyUnitMatch) {
    referenceQuantity = Math.max(0.0001, asNumber(qtyUnitMatch[1]) || 1);
    referenceUnit = normalizeUnit(qtyUnitMatch[2]);
  } else if (/serving/i.test(referenceRaw)) {
    referenceUnit = 'serving';
  }

  const referenceGrams = UNIT_TO_GRAMS[referenceUnit] ? referenceQuantity * UNIT_TO_GRAMS[referenceUnit] : null;
  return {
    calories: Math.max(0, calories),
    protein: Math.max(0, protein),
    carbs: Math.max(0, carbs),
    fat: Math.max(0, fat),
    referenceQuantity,
    referenceUnit,
    referenceGrams
  };
}

function contentTokens(text: string): string[] {
  const normalized = normalizeFoodText(text);
  if (!normalized) {
    return [];
  }
  const tokens = normalized
    .split(/\s+/)
    .map((token) => token.trim())
    .filter((token) => token.length > 2 && !GENERIC_QUERY_TOKENS.has(token));
  return Array.from(new Set(tokens));
}

function overlapRatio(queryTokens: string[], candidateTokens: string[]): number {
  if (queryTokens.length === 0 || candidateTokens.length === 0) {
    return 0;
  }
  const candidateSet = new Set(candidateTokens);
  let overlap = 0;
  for (const token of queryTokens) {
    if (candidateSet.has(token)) {
      overlap += 1;
    }
  }
  return overlap / queryTokens.length;
}

function hasAnyToken(tokens: string[], group: Set<string>): boolean {
  return tokens.some((token) => group.has(token));
}

function semanticMismatchPenalty(query: string, combinedText: string): { penalty: number; contentOverlap: number } {
  const queryTokens = contentTokens(query);
  const candidateTokens = contentTokens(combinedText);
  const contentOverlap = overlapRatio(queryTokens, candidateTokens);

  if (queryTokens.length === 0) {
    return { penalty: 0, contentOverlap: 0 };
  }

  let penalty = 0;
  if (contentOverlap === 0) {
    penalty += 0.55;
  } else if (queryTokens.length >= 2 && contentOverlap < 0.5) {
    penalty += 0.15;
  }

  const queryLooksDessert = hasAnyToken(queryTokens, DESSERT_TOKENS);
  const candidateLooksDessert = hasAnyToken(candidateTokens, DESSERT_TOKENS);
  const candidateLooksGrain = hasAnyToken(candidateTokens, GRAIN_TOKENS);
  if (queryLooksDessert && candidateLooksGrain && !candidateLooksDessert) {
    penalty += 0.25;
  }

  return { penalty, contentOverlap };
}

function minimumAcceptedSummaryScore(query: string): number {
  const tokenCount = contentTokens(query).length;
  if (tokenCount >= 3) {
    return 0.38;
  }
  if (tokenCount === 2) {
    return 0.33;
  }
  return 0.26;
}

function isSummaryAccepted(query: string, summary: FatSecretScoredSummary): boolean {
  const queryTokenCount = contentTokens(query).length;
  const minScore = minimumAcceptedSummaryScore(query);
  return summary.score >= minScore && (summary.contentOverlap > 0 || queryTokenCount <= 1);
}

function evaluateSummaryAcceptance(query: string, summary: FatSecretScoredSummary): SearchBestFoodResult {
  if (isSummaryAccepted(query, summary)) {
    return {
      accepted: summary,
      topCandidate: summary,
      rejectionReason: null
    };
  }

  const queryTokenCount = contentTokens(query).length;
  const semanticMismatch = queryTokenCount > 1 && summary.contentOverlap <= 0;
  return {
    accepted: null,
    topCandidate: summary,
    rejectionReason: semanticMismatch ? 'semantic_mismatch' : 'below_min_score'
  };
}

function scoreSummary(summary: FatSecretFoodSummary, query: string): FatSecretScoredSummary {
  const foodId = typeof summary.food_id === 'string' && summary.food_id.trim() ? summary.food_id.trim() : null;
  const name = (summary.food_name || '').trim();
  const brand = (summary.brand_name || '').trim();
  const description = (summary.food_description || '').trim();
  const profile = parseDescriptionProfile(description);
  const combined = [name, brand].filter(Boolean).join(' ');
  const overlap = tokenOverlapRatio(query, combined || description);
  const phraseBonus = normalizeFoodText(combined || description).includes(normalizeFoodText(query)) ? 0.1 : 0;
  const profileBonus = profile ? 0.05 : 0;
  const mismatch = semanticMismatchPenalty(query, combined || description);
  const score = clamp01(0.85 * overlap + phraseBonus + profileBonus - mismatch.penalty);
  return {
    foodId,
    name: name || query,
    description,
    score,
    contentOverlap: mismatch.contentOverlap,
    profile
  };
}

function scoreServingMatch(candidate: CandidateItem, serving: ParsedServing): number {
  const unitMatch = candidate.unit === serving.unit;
  const descMatch = normalizeFoodText(serving.rawDescription).includes(candidate.unit);
  const metricBonus = serving.metricGrams && serving.metricGrams > 0 ? 0.1 : 0;
  const base = unitMatch ? 0.75 : descMatch ? 0.45 : 0.2;
  return clamp01(base + metricBonus);
}

function parseServing(serving: FatSecretServing): ParsedServing | null {
  const calories = asNumber(serving.calories);
  const protein = asNumber(serving.protein);
  const carbs = asNumber(serving.carbohydrate);
  const fat = asNumber(serving.fat);
  if (calories === null || protein === null || carbs === null || fat === null) {
    return null;
  }

  const servingUnitsRaw = asNumber(serving.number_of_units);
  const servingUnits = servingUnitsRaw && servingUnitsRaw > 0 ? servingUnitsRaw : 1;
  const measurementDescription = (serving.measurement_description || '').trim();
  const servingDescription = (serving.serving_description || '').trim();
  const unit = normalizeUnit(measurementDescription || servingDescription || 'serving');

  const metricAmount = asNumber(serving.metric_serving_amount);
  const metricUnit = normalizeUnit(serving.metric_serving_unit || '');
  let metricGrams: number | null = null;
  if (metricAmount !== null && metricAmount > 0) {
    if (metricUnit === 'g' || metricUnit === 'ml') {
      metricGrams = metricAmount * UNIT_TO_GRAMS[metricUnit];
    } else if (UNIT_TO_GRAMS[metricUnit]) {
      metricGrams = metricAmount * UNIT_TO_GRAMS[metricUnit];
    }
  }

  return {
    servingId: (serving.serving_id || '').trim() || null,
    unit,
    servingUnits,
    metricGrams,
    calories: Math.max(0, calories),
    protein: Math.max(0, protein),
    carbs: Math.max(0, carbs),
    fat: Math.max(0, fat),
    rawDescription: servingDescription || measurementDescription
  };
}

function chooseBestServing(candidate: CandidateItem, servings: ParsedServing[]): { serving: ParsedServing; score: number } | null {
  let best: { serving: ParsedServing; score: number } | null = null;
  for (const serving of servings) {
    const score = scoreServingMatch(candidate, serving);
    if (!best || score > best.score) {
      best = { serving, score };
    }
  }
  return best;
}

function buildCandidatesFromDeterministic(result: ParseResult): CandidateItem[] {
  return result.items.map((item) => ({
    rawSegment: item.name,
    query: item.name,
    quantity: item.quantity > 0 ? item.quantity : 1,
    unit: normalizeUnit(item.unit || 'count'),
    gramsHint: item.grams > 0 ? item.grams : null,
    caloriesHintPer100g: item.grams > 0 ? (item.calories / item.grams) * 100 : null
  }));
}

function buildCandidatesFromText(text: string): CandidateItem[] {
  return parseFoodTextCandidates(text, {
    defaultUnit: 'count',
    unitAliases: COMMON_FOOD_UNIT_ALIASES
  }).map((candidate) => ({
    rawSegment: candidate.rawSegment,
    query: candidate.query,
    quantity: candidate.quantity,
    unit: candidate.unit,
    gramsHint: null,
    caloriesHintPer100g: null
  }));
}

function resolveTargetGrams(candidate: CandidateItem, fallbackGrams: number | null): number {
  if (candidate.gramsHint && candidate.gramsHint > 0) {
    return candidate.gramsHint;
  }
  if (fallbackGrams && fallbackGrams > 0) {
    return fallbackGrams;
  }
  if (UNIT_TO_GRAMS[candidate.unit]) {
    return candidate.quantity * UNIT_TO_GRAMS[candidate.unit];
  }
  return candidate.quantity * 100;
}

function candidateDesiredGramsFromUnit(candidate: CandidateItem): number | null {
  if (candidate.gramsHint && candidate.gramsHint > 0) {
    return candidate.gramsHint;
  }

  // "count"/"serving" are ambiguous; prefer provider-serving metrics instead of fixed gram guesses.
  if (isAmbiguousQuantityUnit(candidate.unit)) {
    return null;
  }

  if (UNIT_TO_GRAMS[candidate.unit]) {
    return candidate.quantity * UNIT_TO_GRAMS[candidate.unit];
  }

  return null;
}

function makeSourceId(summary: FatSecretScoredSummary, servingId: string | null): string {
  const rawId = summary.foodId || normalizeFoodText(summary.name).replace(/\s+/g, '_').slice(0, 40) || 'unknown';
  if (servingId) {
    return `fatsecret_food_${rawId}_serving_${servingId}`;
  }
  return `fatsecret_food_${rawId}`;
}

function buildFatSecretNarrative(params: {
  candidateText: string;
  summary: FatSecretScoredSummary;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  matchConfidence: number;
  servingLabel?: string | null;
}): { foodDescription: string; explanation: string } {
  const name = params.summary.name.trim() || params.candidateText.trim() || 'item';
  const description = params.summary.description.trim();
  const foodDescription = description
    ? `${name} — ${description}`
    : name;

  const servingSentence = params.servingLabel
    ? `Used the Food Database serving “${params.servingLabel}”, scaled to about ${round(params.grams, 1)}g.`
    : `Estimated portion at about ${round(params.grams, 1)}g based on the matched Food Database summary.`;

  const macroSentence = `Estimated roughly ${round(params.calories, 1)} calories, ${round(params.protein, 1)}g protein, ${round(params.carbs, 1)}g carbs, and ${round(params.fat, 1)}g fat.`;
  const confidenceSentence = `Source: Food Database. Match confidence ${round(params.matchConfidence, 2)}.`;
  const sourceSentence = 'Values reflect the closest available Food Database entry.';

  const explanation = [
    `Matched “${params.candidateText.trim()}” to Food Database entry “${name}”.`,
    servingSentence,
    macroSentence,
    confidenceSentence,
    sourceSentence
  ].join(' ');

  return { foodDescription, explanation };
}

function servingOptionLabel(serving: ParsedServing): string {
  const raw = serving.rawDescription.trim();
  if (raw) {
    return raw;
  }
  return `${round(serving.servingUnits, 2)} ${serving.unit}`.trim();
}

function mapServingOptions(summary: FatSecretScoredSummary, servings: ParsedServing[]): ParsedServingOption[] {
  const options = servings.map((serving) => {
    const gramsFallback = UNIT_TO_GRAMS[serving.unit] ? UNIT_TO_GRAMS[serving.unit] * serving.servingUnits : 0;
    const option: ParsedServingOption = {
      servingId: serving.servingId,
      label: servingOptionLabel(serving),
      quantity: round(serving.servingUnits, 2),
      unit: serving.unit,
      grams: round(serving.metricGrams && serving.metricGrams > 0 ? serving.metricGrams : gramsFallback, 1),
      calories: round(serving.calories, 1),
      protein: round(serving.protein, 1),
      carbs: round(serving.carbs, 1),
      fat: round(serving.fat, 1),
      nutritionSourceId: makeSourceId(summary, serving.servingId)
    };
    return option;
  });

  const byLabel = new Set<string>();
  return options.filter((option) => {
    const key = `${option.label.toLowerCase()}::${option.unit}::${option.quantity}`;
    if (byLabel.has(key)) {
      return false;
    }
    byLabel.add(key);
    return true;
  });
}

function buildItemFromServing(
  candidate: CandidateItem,
  summary: FatSecretScoredSummary,
  serving: ParsedServing,
  servingScore: number,
  servingOptions: ParsedServingOption[]
): { item: ParsedItem; score: number } {
  const desiredGrams = candidateDesiredGramsFromUnit(candidate);
  let scale = candidate.quantity;
  if (candidate.unit === serving.unit && serving.servingUnits > 0) {
    scale = candidate.quantity / serving.servingUnits;
  } else if (desiredGrams && serving.metricGrams && serving.metricGrams > 0) {
    scale = desiredGrams / serving.metricGrams;
  } else if (serving.servingUnits > 0) {
    if (isAmbiguousQuantityUnit(candidate.unit) && !candidate.gramsHint) {
      scale = candidate.quantity;
    } else {
      scale = candidate.quantity / serving.servingUnits;
    }
  }
  if (!Number.isFinite(scale) || scale <= 0) {
    scale = 1;
  }

  const grams = resolveTargetGrams(candidate, serving.metricGrams ? serving.metricGrams * scale : null);
  const score = clamp01(0.65 * summary.score + 0.35 * servingScore);
  const narrative = buildFatSecretNarrative({
    candidateText: candidate.rawSegment,
    summary,
    grams,
    calories: serving.calories * scale,
    protein: serving.protein * scale,
    carbs: serving.carbs * scale,
    fat: serving.fat * scale,
    matchConfidence: score,
    servingLabel: servingOptionLabel(serving)
  });

  return {
    item: {
      name: candidate.rawSegment,
      quantity: round(candidate.quantity, 2),
      unit: candidate.unit,
      grams: round(grams, 1),
      calories: round(serving.calories * scale, 1),
      protein: round(serving.protein * scale, 1),
      carbs: round(serving.carbs * scale, 1),
      fat: round(serving.fat * scale, 1),
      matchConfidence: round(score, 3),
      nutritionSourceId: makeSourceId(summary, serving.servingId),
      servingOptions,
      foodDescription: narrative.foodDescription,
      explanation: narrative.explanation
    },
    score
  };
}

function buildItemFromDescription(
  candidate: CandidateItem,
  summary: FatSecretScoredSummary
): { item: ParsedItem; score: number } | null {
  if (!summary.profile) {
    return null;
  }

  const profile = summary.profile;
  const desiredGrams = candidateDesiredGramsFromUnit(candidate);
  let scale = 1;
  if (desiredGrams && profile.referenceGrams && profile.referenceGrams > 0) {
    scale = desiredGrams / profile.referenceGrams;
  } else if (candidate.unit === profile.referenceUnit) {
    scale = candidate.quantity / Math.max(profile.referenceQuantity, 0.0001);
  } else if (isAmbiguousQuantityUnit(candidate.unit) && !candidate.gramsHint) {
    scale = candidate.quantity;
  } else {
    scale = candidate.quantity / Math.max(profile.referenceQuantity, 0.0001);
  }
  if (!Number.isFinite(scale) || scale <= 0) {
    scale = 1;
  }

  const grams = resolveTargetGrams(candidate, profile.referenceGrams && profile.referenceGrams > 0 ? profile.referenceGrams * scale : null);
  const score = clamp01(summary.score * 0.75);
  const narrative = buildFatSecretNarrative({
    candidateText: candidate.rawSegment,
    summary,
    grams,
    calories: profile.calories * scale,
    protein: profile.protein * scale,
    carbs: profile.carbs * scale,
    fat: profile.fat * scale,
    matchConfidence: score,
    servingLabel: summary.profile
      ? `${round(summary.profile.referenceQuantity, 2)} ${summary.profile.referenceUnit}`.trim()
      : null
  });

  return {
    item: {
      name: candidate.rawSegment,
      quantity: round(candidate.quantity, 2),
      unit: candidate.unit,
      grams: round(grams, 1),
      calories: round(profile.calories * scale, 1),
      protein: round(profile.protein * scale, 1),
      carbs: round(profile.carbs * scale, 1),
      fat: round(profile.fat * scale, 1),
      matchConfidence: round(score, 3),
      nutritionSourceId: makeSourceId(summary, null),
      foodDescription: narrative.foodDescription,
      explanation: narrative.explanation
    },
    score
  };
}

function hasFatSecretCredentials(): boolean {
  return Boolean(config.fatsecretClientId && config.fatsecretClientSecret);
}

async function getAccessToken(): Promise<string | null> {
  if (!hasFatSecretCredentials()) {
    return null;
  }

  const now = Date.now();
  if (tokenCache && tokenCache.expiresAt > now + 30_000) {
    return tokenCache.token;
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.fatsecretTimeoutMs);
  try {
    const auth = Buffer.from(`${config.fatsecretClientId}:${config.fatsecretClientSecret}`, 'utf8').toString('base64');
    const body = new URLSearchParams({
      grant_type: 'client_credentials',
      scope: config.fatsecretScope
    });
    const response = await fetch(config.fatsecretOauthUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Authorization: `Basic ${auth}`
      },
      body,
      signal: controller.signal
    });
    if (!response.ok) {
      console.warn('[fatsecret_oauth_failed]', JSON.stringify({ status: response.status }));
      return null;
    }
    const payload = (await response.json()) as { access_token?: string; expires_in?: number };
    const token = (payload.access_token || '').trim();
    if (!token) {
      console.warn('[fatsecret_oauth_failed]', JSON.stringify({ reason: 'missing_access_token' }));
      return null;
    }
    const expiresInSec = payload.expires_in && payload.expires_in > 0 ? payload.expires_in : 3600;
    tokenCache = { token, expiresAt: now + expiresInSec * 1000 };
    return token;
  } catch (err) {
    console.warn('[fatsecret_oauth_failed]', err);
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

async function fatSecretGet(path: string, params: Record<string, string>): Promise<unknown | null> {
  const token = await getAccessToken();
  if (!token) {
    return null;
  }

  const endpoint = new URL(`${config.fatsecretApiBaseUrl.replace(/\/+$/, '')}${path.startsWith('/') ? path : `/${path}`}`);
  endpoint.searchParams.set('format', 'json');
  endpoint.searchParams.set('region', config.fatsecretRegion);
  if (config.fatsecretLanguage) {
    endpoint.searchParams.set('language', config.fatsecretLanguage);
  }
  for (const [key, value] of Object.entries(params)) {
    endpoint.searchParams.set(key, value);
  }

  const requestOnce = async (bearerToken: string): Promise<Response | null> => {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), config.fatsecretTimeoutMs);
    try {
      return await fetch(endpoint, {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${bearerToken}`
        },
        signal: controller.signal
      });
    } catch (err) {
      console.warn('[fatsecret_http_failed]', err);
      return null;
    } finally {
      clearTimeout(timeout);
    }
  };

  let response = await requestOnce(token);
  if (response && response.status === 401) {
    tokenCache = null;
    const refreshed = await getAccessToken();
    if (refreshed) {
      response = await requestOnce(refreshed);
    }
  }

  if (!response || !response.ok) {
    console.warn('[fatsecret_http_failed]', JSON.stringify({ path, status: response?.status || null }));
    return null;
  }

  try {
    return await response.json();
  } catch (err) {
    console.warn('[fatsecret_json_failed]', err);
    return null;
  }
}

async function searchBestFood(query: string): Promise<SearchBestFoodResult> {
  const normalizedQuery = normalizeFoodText(query);
  if (!normalizedQuery) {
    return {
      accepted: null,
      topCandidate: null,
      rejectionReason: null
    };
  }

  const now = Date.now();
  const cached = searchCache.get(normalizedQuery);
  if (cached && cached.expiresAt > now) {
    return cached.result;
  }

  const payload = (await fatSecretGet('/foods/search/v1', {
    search_expression: normalizedQuery,
    max_results: String(config.fatsecretSearchMaxResults)
  })) as FatSecretSearchResponse | null;

  const rows = toArray(payload?.foods?.food);
  const scored = rows
    .map((row) => scoreSummary(row, normalizedQuery))
    .sort((a, b) => b.score - a.score);
  const best = scored[0] || null;
  const result: SearchBestFoodResult = best
    ? evaluateSummaryAcceptance(normalizedQuery, best)
    : {
        accepted: null,
        topCandidate: null,
        rejectionReason: null
      };

  searchCache.set(normalizedQuery, {
    expiresAt: now + 6 * 60 * 60 * 1000,
    result
  });
  return result;
}

async function getFoodServings(foodId: string): Promise<ParsedServing[] | null> {
  const now = Date.now();
  const cached = detailsCache.get(foodId);
  if (cached && cached.expiresAt > now) {
    return cached.servings;
  }

  const payload = (await fatSecretGet('/food/v5', { food_id: foodId })) as FatSecretFoodDetailsResponse | null;
  const rows = toArray(payload?.food?.servings?.serving);
  const servings = rows.map((serving) => parseServing(serving)).filter((value): value is ParsedServing => Boolean(value));
  const resolved = servings.length > 0 ? servings : null;
  detailsCache.set(foodId, { expiresAt: now + 6 * 60 * 60 * 1000, servings: resolved });
  return resolved;
}

export async function tryFatSecretParse(text: string, deterministicResult: ParseResult): Promise<ParseResult | null> {
  if (!hasFatSecretCredentials()) {
    return null;
  }

  const items: ParsedItem[] = [];
  const candidatesFromText = buildCandidatesFromText(text);
  const candidates = candidatesFromText.length > 0 ? candidatesFromText : buildCandidatesFromDeterministic(deterministicResult);
  const totalCandidates = candidates.length || 1;
  let scoreSum = 0;
  let semanticMismatchRejected = false;
  const debugRows: Array<{
    query: string;
    selectedFoodId: string | null;
    selectedName: string | null;
    selectedScore: number | null;
    rejectedReason: string | null;
    usedServingApi: boolean;
  }> = [];

  for (const candidate of candidates.slice(0, 6)) {
    const search = await searchBestFood(candidate.query);
    const summary = search.accepted;
    if (!summary) {
      if (search.rejectionReason === 'semantic_mismatch') {
        semanticMismatchRejected = true;
      }
      debugRows.push({
        query: candidate.query,
        selectedFoodId: search.topCandidate?.foodId || null,
        selectedName: search.topCandidate?.name || null,
        selectedScore: search.topCandidate?.score ?? null,
        rejectedReason: search.rejectionReason,
        usedServingApi: false
      });
      continue;
    }

    let resolved: { item: ParsedItem; score: number } | null = null;
    let usedServingApi = false;

    if (summary.foodId) {
      const servings = await getFoodServings(summary.foodId);
      if (servings && servings.length > 0) {
        const selectedServing = chooseBestServing(candidate, servings);
        if (selectedServing) {
          resolved = buildItemFromServing(
            candidate,
            summary,
            selectedServing.serving,
            selectedServing.score,
            mapServingOptions(summary, servings)
          );
          usedServingApi = true;
        }
      }
    }

    if (!resolved) {
      resolved = buildItemFromDescription(candidate, summary);
    }

    if (!resolved) {
      debugRows.push({
        query: candidate.query,
        selectedFoodId: summary.foodId,
        selectedName: summary.name,
        selectedScore: summary.score,
        rejectedReason: null,
        usedServingApi
      });
      continue;
    }

    items.push(resolved.item);
    scoreSum += resolved.score;
    debugRows.push({
      query: candidate.query,
      selectedFoodId: summary.foodId,
      selectedName: summary.name,
      selectedScore: resolved.score,
      rejectedReason: null,
      usedServingApi
    });
  }

  if (items.length === 0) {
    if (semanticMismatchRejected) {
      return {
        confidence: 0,
        assumptions: [],
        items: [],
        totals: {
          calories: 0,
          protein: 0,
          carbs: 0,
          fat: 0
        }
      };
    }
    return null;
  }

  const coverage = items.length / totalCandidates;
  if (coverage < config.fatsecretMinCoverage) {
    return null;
  }

  const avgScore = scoreSum / items.length;
  const totals = sumNutrition(items);
  const confidence = round(clamp01(0.5 * coverage + 0.5 * avgScore), 3);

  if (config.fatsecretDebugCandidates) {
    console.info(
      '[fatsecret_debug_candidates]',
      JSON.stringify({
        text,
        route: 'fatsecret',
        confidence,
        rows: debugRows
      })
    );
  }

  return {
    confidence,
    assumptions: [],
    items,
    totals: {
      calories: totals.calories,
      protein: totals.protein,
      carbs: totals.carbs,
      fat: totals.fat
    }
  };
}

export const __fatsecretTestUtils = {
  buildCandidatesFromText,
  parseDescriptionProfile,
  normalizeUnit,
  scoreSummaryForTest: (
    query: string,
    summary: { foodName?: string; brandName?: string; foodDescription?: string }
  ): { score: number; contentOverlap: number } => {
    const scored = scoreSummary(
      {
        food_name: summary.foodName,
        brand_name: summary.brandName,
        food_description: summary.foodDescription
      },
      normalizeFoodText(query)
    );
    return {
      score: scored.score,
      contentOverlap: scored.contentOverlap
    };
  },
  isSummaryAcceptedForTest: (query: string, score: number, contentOverlap: number): boolean => {
    const normalizedQuery = normalizeFoodText(query);
    const probe: FatSecretScoredSummary = {
      foodId: null,
      name: query,
      description: '',
      score,
      contentOverlap,
      profile: null
    };
    return isSummaryAccepted(normalizedQuery, probe);
  },
  buildItemFromServingForTest: (
    candidate: {
      rawSegment: string;
      query: string;
      quantity: number;
      unit: string;
      gramsHint: number | null;
      caloriesHintPer100g: number | null;
    },
    serving: {
      servingId: string | null;
      unit: string;
      servingUnits: number;
      metricGrams: number | null;
      calories: number;
      protein: number;
      carbs: number;
      fat: number;
      rawDescription: string;
    }
  ): { item: ParsedItem; assumptions: string[] } => {
    const summary: FatSecretScoredSummary = {
      foodId: 'test_food',
      name: candidate.query,
      description: '',
      score: 1,
      contentOverlap: 1,
      profile: null
    };
    const resolved = buildItemFromServing(candidate as CandidateItem, summary, serving as ParsedServing, 1, []);
    return { item: resolved.item, assumptions: [] };
  }
};
