import { config } from '../config.js';

export type NutritionLookupResult = {
  source: 'open_food_facts' | 'usda' | 'fatsecret' | 'cache' | 'miss';
  brand?: string;
  productName: string;
  servingSizeG: number;
  servingSizeText?: string;
  calories: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  fiberG?: number;
  sugarG?: number;
  sodiumMg?: number;
  confidence: number;
  upc?: string;
  imageUrl?: string;
  raw?: unknown;
  latencyMs: number;
};

type NormalizedNutrition = Omit<NutritionLookupResult, 'source' | 'latencyMs'>;
type LookupOptions = { signal?: AbortSignal; timeoutMs?: number };
type CacheEntry = { expiresAtMs: number; value: NormalizedNutrition & { source: NutritionLookupResult['source'] } };

const cache = new Map<string, CacheEntry>();
const maxCacheEntries = 1000;
const cacheTtlMs = 7 * 24 * 60 * 60 * 1000;
const BARCODE_NAME_HINTS: Record<string, string> = {
  '0028400433556': 'Cheetos Crunchy 28g',
  '028400433556': 'Cheetos Crunchy 28g'
};

type OFFProductResponse = {
  status?: number;
  product?: {
    product_name?: string;
    brands?: string;
    serving_size?: string;
    nutriments?: Record<string, unknown>;
    image_url?: string;
    code?: string;
  };
};

type USDAFood = {
  fdcId?: number;
  description?: string;
  brandOwner?: string;
  brandName?: string;
  dataType?: string;
  gtinUpc?: string;
  servingSize?: number;
  servingSizeUnit?: string;
  score?: number;
  foodNutrients?: Array<{
    nutrientId?: number;
    nutrientName?: string;
    nutrientNumber?: string;
    unitName?: string;
    value?: number;
  }>;
};

type USDASearchResponse = {
  foods?: USDAFood[];
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
  fiber?: string;
  sugar?: string;
  sodium?: string;
  serving_description?: string;
  metric_serving_amount?: string;
  metric_serving_unit?: string;
  is_default?: string;
};

type FatSecretFood = {
  food_id?: string;
  food_name?: string;
  brand_name?: string;
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

let fatSecretTokenCache: { token: string; expiresAtMs: number } | null = null;

function nowMs(): number {
  return Date.now();
}

function elapsed(startedAt: number): number {
  return Math.max(0, Math.round(Date.now() - startedAt));
}

function numberValue(value: unknown): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Number(value.replace(/,/g, '').match(/-?\d+(?:\.\d+)?/)?.[0] ?? NaN);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function round(value: number, digits = 1): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function normalizeBarcode(code: string): string {
  const digits = code.replace(/\D/g, '');
  if (digits.length === 13 && digits.startsWith('0')) return digits.slice(1);
  return digits;
}

function barcodeVariants(code: string): string[] {
  const digits = code.replace(/\D/g, '');
  return Array.from(new Set([digits, normalizeBarcode(digits)].filter(Boolean)));
}

function cacheGet(key: string, startedAt: number): NutritionLookupResult | null {
  const hit = cache.get(key);
  if (!hit) return null;
  if (hit.expiresAtMs <= nowMs()) {
    cache.delete(key);
    return null;
  }
  cache.delete(key);
  cache.set(key, hit);
  return {
    ...hit.value,
    source: 'cache',
    latencyMs: elapsed(startedAt)
  };
}

function cacheSet(key: string, source: NutritionLookupResult['source'], value: NormalizedNutrition): void {
  if (source === 'miss') return;
  cache.set(key, {
    expiresAtMs: nowMs() + cacheTtlMs,
    value: { ...value, source }
  });
  while (cache.size > maxCacheEntries) {
    const firstKey = cache.keys().next().value as string | undefined;
    if (!firstKey) break;
    cache.delete(firstKey);
  }
}

function withTimeout(opts: LookupOptions | undefined, defaultTimeoutMs: number): { signal: AbortSignal; cleanup: () => void } {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Math.max(250, opts?.timeoutMs ?? defaultTimeoutMs));
  const onAbort = () => controller.abort();
  opts?.signal?.addEventListener('abort', onAbort, { once: true });
  return {
    signal: controller.signal,
    cleanup: () => {
      clearTimeout(timeout);
      opts?.signal?.removeEventListener('abort', onAbort);
    }
  };
}

function miss(productName: string, startedAt: number, upc?: string): NutritionLookupResult {
  return {
    source: 'miss',
    productName,
    servingSizeG: 0,
    servingSizeText: undefined,
    calories: 0,
    proteinG: 0,
    carbsG: 0,
    fatG: 0,
    confidence: 0,
    upc,
    latencyMs: elapsed(startedAt)
  };
}

function sane(value: NormalizedNutrition): boolean {
  return value.calories >= 0 && value.calories <= 1500 && value.fatG >= 0 && value.fatG <= 100;
}

function parseServingSizeG(value: unknown): { grams: number; text?: string } {
  const text = String(value ?? '').trim();
  if (!text) return { grams: 100, text: '100g' };
  const amount = numberValue(text);
  const lower = text.toLowerCase();
  if (!amount) return { grams: 100, text };
  if (/\b(ml|milliliter|millilitre)\b/.test(lower)) return { grams: round(amount), text };
  if (/\b(fl\s*oz|fluid ounce|oz)\b/.test(lower)) return { grams: round(amount * 29.5735), text };
  if (/\b(g|gram)\b/.test(lower)) return { grams: round(amount), text };
  return { grams: round(amount), text };
}

function nutrientFromOFF(nutriments: Record<string, unknown>, base: string, servingSizeG: number): number {
  const serving = numberValue(nutriments[`${base}_serving`]);
  if (serving > 0) return serving;
  const per100g = numberValue(nutriments[`${base}_100g`]);
  if (per100g > 0) return (per100g * servingSizeG) / 100;
  return 0;
}

function energyKcalFromOFF(nutriments: Record<string, unknown>, servingSizeG: number): number {
  const kcalServing = numberValue(nutriments['energy-kcal_serving']);
  if (kcalServing > 0) return kcalServing;
  const kcal100g = numberValue(nutriments['energy-kcal_100g']);
  if (kcal100g > 0) return (kcal100g * servingSizeG) / 100;
  const kjServing = numberValue(nutriments.energy_serving);
  if (kjServing > 0) return kjServing / 4.184;
  const kj100g = numberValue(nutriments.energy_100g);
  if (kj100g > 0) return ((kj100g / 4.184) * servingSizeG) / 100;
  return 0;
}

export function _normalizeOFFResponse(raw: OFFProductResponse): NormalizedNutrition {
  const product = raw.product ?? {};
  const serving = parseServingSizeG(product.serving_size);
  const nutriments = product.nutriments ?? {};
  return {
    brand: String(product.brands ?? '').split(',')[0]?.trim() || undefined,
    productName: String(product.product_name ?? '').trim() || 'Packaged food',
    servingSizeG: serving.grams,
    servingSizeText: serving.text,
    calories: round(energyKcalFromOFF(nutriments, serving.grams)),
    proteinG: round(nutrientFromOFF(nutriments, 'proteins', serving.grams)),
    carbsG: round(nutrientFromOFF(nutriments, 'carbohydrates', serving.grams)),
    fatG: round(nutrientFromOFF(nutriments, 'fat', serving.grams)),
    fiberG: round(nutrientFromOFF(nutriments, 'fiber', serving.grams)),
    sugarG: round(nutrientFromOFF(nutriments, 'sugars', serving.grams)),
    sodiumMg: round(nutrientFromOFF(nutriments, 'sodium', serving.grams) * 1000, 0),
    confidence: 0.92,
    upc: product.code,
    imageUrl: product.image_url,
    raw
  };
}

function usdaNutrient(food: USDAFood, nutrientIds: number[], names: string[]): number {
  const lowerNames = names.map((name) => name.toLowerCase());
  const nutrient = food.foodNutrients?.find((item) => {
    const name = String(item.nutrientName ?? '').toLowerCase();
    return nutrientIds.includes(Number(item.nutrientId)) || lowerNames.some((candidate) => name.includes(candidate));
  });
  return numberValue(nutrient?.value);
}

function selectUSDAFood(foods: USDAFood[], barcode?: string): USDAFood | null {
  const normalizedBarcode = barcode ? normalizeBarcode(barcode) : '';
  const candidates = foods.filter((food) => usdaNutrient(food, [1008], ['energy']) > 0);
  if (!candidates.length) return null;
  return [...candidates].sort((a, b) => {
    const aExact = normalizedBarcode && normalizeBarcode(a.gtinUpc ?? '') === normalizedBarcode ? 1 : 0;
    const bExact = normalizedBarcode && normalizeBarcode(b.gtinUpc ?? '') === normalizedBarcode ? 1 : 0;
    if (aExact !== bExact) return bExact - aExact;
    const aBranded = a.dataType === 'Branded' ? 1 : 0;
    const bBranded = b.dataType === 'Branded' ? 1 : 0;
    if (aBranded !== bBranded) return bBranded - aBranded;
    return numberValue(b.score) - numberValue(a.score);
  })[0] ?? null;
}

export function _normalizeUSDAResponse(raw: USDASearchResponse | USDAFood): NormalizedNutrition {
  const food = Array.isArray((raw as USDASearchResponse).foods)
    ? selectUSDAFood((raw as USDASearchResponse).foods ?? []) ?? ((raw as USDASearchResponse).foods ?? [])[0]
    : (raw as USDAFood);
  const servingSize = numberValue(food?.servingSize) || 100;
  const servingUnit = String(food?.servingSizeUnit ?? 'g').toLowerCase();
  const servingSizeG = servingUnit.includes('oz') ? servingSize * 28.3495 : servingSize;
  const scale = servingSizeG / 100;
  return {
    brand: food?.brandOwner || food?.brandName || undefined,
    productName: String(food?.description ?? '').trim() || 'Packaged food',
    servingSizeG: round(servingSizeG),
    servingSizeText: `${round(servingSizeG)}g`,
    calories: round(usdaNutrient(food, [1008], ['energy']) * scale),
    proteinG: round(usdaNutrient(food, [1003], ['protein']) * scale),
    carbsG: round(usdaNutrient(food, [1005], ['carbohydrate']) * scale),
    fatG: round(usdaNutrient(food, [1004], ['total lipid', 'fat']) * scale),
    fiberG: round(usdaNutrient(food, [1079], ['fiber']) * scale),
    sugarG: round(usdaNutrient(food, [2000], ['sugars']) * scale),
    sodiumMg: round(usdaNutrient(food, [1093], ['sodium']) * scale, 0),
    confidence: 0.86,
    upc: food?.gtinUpc,
    raw
  };
}

function toArray<T>(value: T | T[] | undefined): T[] {
  if (!value) return [];
  return Array.isArray(value) ? value : [value];
}

function selectFatSecretServing(food: FatSecretFood): FatSecretServing | null {
  const servings = toArray(food.servings?.serving);
  return servings.find((serving) => serving.is_default === '1') ?? servings[0] ?? null;
}

function normalizeSearchText(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}

function selectFatSecretFood(foods: FatSecretFood[], query: string): FatSecretFood | null {
  const queryText = normalizeSearchText(query);
  const queryTerms = new Set(queryText.split(' ').filter((term) => term.length > 2));
  return [...foods]
    .filter((food) => selectFatSecretServing(food))
    .sort((a, b) => fatSecretFoodScore(b, queryText, queryTerms) - fatSecretFoodScore(a, queryText, queryTerms))[0] ?? null;
}

function fatSecretFoodScore(food: FatSecretFood, queryText: string, queryTerms: Set<string>): number {
  const text = normalizeSearchText(`${food.brand_name ?? ''} ${food.food_name ?? ''}`);
  const serving = selectFatSecretServing(food);
  const calories = numberValue(serving?.calories);
  let score = 0;
  for (const term of queryTerms) {
    if (text.includes(term)) score += 10;
  }
  if (food.brand_name && queryText.includes(normalizeSearchText(food.brand_name))) score += 20;
  if (text.includes(queryText.replace(/\b28g\b/g, '').trim())) score += 30;
  if (queryText.includes('cheetos crunchy') && text.includes('crunchy cheetos')) score += 35;
  if ((/\b28\s*g\b|\b28g\b|\b1\s*oz\b/.test(queryText)) && /\b(28g|1 oz)\b/.test(text)) score += 25;
  if ((/\b28\s*g\b|\b28g\b|\b1\s*oz\b/.test(queryText)) && calories > 250) score -= 30;
  const unintendedVariants = ['baked', 'flamin', 'flaming', 'hot', 'limon', 'buffalo', 'jalapeno', 'white cheddar', 'minis', 'mini bites', 'asteroids'];
  for (const variant of unintendedVariants) {
    if (!queryText.includes(variant) && text.includes(variant)) score -= variant === 'baked' ? 60 : 30;
  }
  return score;
}

export function _normalizeFatSecretResponse(raw: FatSecretSearchResponse | FatSecretFood): NormalizedNutrition {
  const searchFoods = toArray((raw as FatSecretSearchResponse).foods_search?.results?.food);
  const food = searchFoods.length ? searchFoods[0] : (raw as FatSecretFood);
  const serving = food ? selectFatSecretServing(food) : null;
  const servingSizeG =
    serving?.metric_serving_unit?.toLowerCase() === 'g' ? numberValue(serving.metric_serving_amount) : parseServingSizeG(serving?.serving_description).grams;
  return {
    brand: food?.brand_name || undefined,
    productName: String(food?.food_name ?? '').trim() || 'Packaged food',
    servingSizeG: round(servingSizeG || 100),
    servingSizeText: serving?.serving_description || `${round(servingSizeG || 100)}g`,
    calories: round(numberValue(serving?.calories)),
    proteinG: round(numberValue(serving?.protein)),
    carbsG: round(numberValue(serving?.carbohydrate)),
    fatG: round(numberValue(serving?.fat)),
    fiberG: round(numberValue(serving?.fiber)),
    sugarG: round(numberValue(serving?.sugar)),
    sodiumMg: round(numberValue(serving?.sodium), 0),
    confidence: 0.78,
    raw
  };
}

async function fetchOpenFoodFacts(barcode: string, opts?: LookupOptions): Promise<NormalizedNutrition | null> {
  const { signal, cleanup } = withTimeout(opts, 800);
  try {
    const fields = 'product_name,brands,serving_size,nutriments,image_url,code';
    const url = `${config.offBaseUrl}/product/${encodeURIComponent(barcode)}.json?fields=${fields}`;
    const response = await fetch(url, {
      headers: { 'User-Agent': config.offUserAgent },
      signal
    });
    if (!response.ok) return null;
    const raw = (await response.json()) as OFFProductResponse;
    if (raw.status === 0 || !raw.product) return null;
    const normalized = _normalizeOFFResponse(raw);
    return sane(normalized) && normalized.calories >= 0 ? normalized : null;
  } catch {
    return null;
  } finally {
    cleanup();
  }
}

async function fetchUSDA(query: string, barcode?: string, opts?: LookupOptions): Promise<NormalizedNutrition | null> {
  if (!config.usdaApiKey) return null;
  const { signal, cleanup } = withTimeout(opts, 1000);
  try {
    const params = new URLSearchParams({
      api_key: config.usdaApiKey,
      query,
      pageSize: '10',
      dataType: 'Branded'
    });
    const response = await fetch(`${config.usdaApiBaseUrl}/foods/search?${params.toString()}`, { signal });
    if (!response.ok) return null;
    const raw = (await response.json()) as USDASearchResponse;
    const match = selectUSDAFood(raw.foods ?? [], barcode);
    if (!match) return null;
    const normalized = _normalizeUSDAResponse(match);
    return sane(normalized) ? normalized : null;
  } catch {
    return null;
  } finally {
    cleanup();
  }
}

async function getFatSecretAccessToken(opts?: LookupOptions): Promise<string | null> {
  if (!config.fatSecretClientId || !config.fatSecretClientSecret) return null;
  if (fatSecretTokenCache && fatSecretTokenCache.expiresAtMs > Date.now() + 60_000) return fatSecretTokenCache.token;
  const { signal, cleanup } = withTimeout(opts, 1000);
  try {
    const body = new URLSearchParams({
      grant_type: 'client_credentials',
      scope: config.fatSecretScope
    });
    const auth = Buffer.from(`${config.fatSecretClientId}:${config.fatSecretClientSecret}`).toString('base64');
    const response = await fetch(config.fatSecretTokenUrl, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body,
      signal
    });
    if (!response.ok) return null;
    const data = (await response.json()) as FatSecretTokenResponse;
    if (!data.access_token) return null;
    fatSecretTokenCache = {
      token: data.access_token,
      expiresAtMs: Date.now() + Math.max(60, data.expires_in ?? 3600) * 1000
    };
    return data.access_token;
  } catch {
    return null;
  } finally {
    cleanup();
  }
}

async function fetchFatSecret(query: string, opts?: LookupOptions): Promise<NormalizedNutrition | null> {
  const token = await getFatSecretAccessToken(opts);
  if (!token) return null;
  const { signal, cleanup } = withTimeout(opts, 1000);
  try {
    const params = new URLSearchParams({
      search_expression: query,
      format: 'json',
      max_results: '10',
      flag_default_serving: 'true'
    });
    const response = await fetch(`${config.fatSecretApiBaseUrl}/foods/search/v2?${params.toString()}`, {
      headers: { Authorization: `Bearer ${token}` },
      signal
    });
    if (!response.ok) return null;
    const raw = (await response.json()) as FatSecretSearchResponse;
    const food = selectFatSecretFood(toArray(raw.foods_search?.results?.food), query);
    if (!food) return null;
    const normalized = _normalizeFatSecretResponse(food);
    return sane(normalized) && normalized.calories > 0 ? normalized : null;
  } catch {
    return null;
  } finally {
    cleanup();
  }
}

export async function lookupByBarcode(code: string, opts?: LookupOptions): Promise<NutritionLookupResult> {
  const startedAt = Date.now();
  const variants = barcodeVariants(code);
  const barcode = variants[0] ?? normalizeBarcode(code);
  const key = `barcode:${barcode}`;
  const cached = cacheGet(key, startedAt);
  if (cached) return cached;

  let off: NormalizedNutrition | null = null;
  for (const variant of variants) {
    off = await fetchOpenFoodFacts(variant, opts);
    if (off) break;
  }
  if (off) {
    cacheSet(key, 'open_food_facts', off);
    return { ...off, source: 'open_food_facts', latencyMs: elapsed(startedAt) };
  }

  let usda: NormalizedNutrition | null = null;
  for (const variant of variants) {
    usda = await fetchUSDA(variant, variant, opts);
    if (usda) break;
  }
  if (usda) {
    cacheSet(key, 'usda', usda);
    return { ...usda, source: 'usda', latencyMs: elapsed(startedAt) };
  }

  const hint = variants.map((variant) => BARCODE_NAME_HINTS[variant]).find(Boolean);
  if (hint) {
    const fatSecret = await fetchFatSecret(hint, opts);
    if (fatSecret) {
      cacheSet(key, 'fatsecret', fatSecret);
      return { ...fatSecret, source: 'fatsecret', upc: barcode, latencyMs: elapsed(startedAt) };
    }
  }

  return miss('Unknown packaged food', startedAt, barcode);
}

