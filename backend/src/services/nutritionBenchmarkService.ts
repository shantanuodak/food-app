import { config } from '../config.js';

export type BenchmarkConfidence = 'high' | 'medium' | 'low';
export type BenchmarkProvider = 'usda' | 'fatsecret' | 'curated';
export type BenchmarkSourceType = 'usda_fdc' | 'fatsecret' | 'curated' | 'curated_fallback';

export type CaloriesRange = {
  min: number;
  max: number;
};

export type BenchmarkSpec = {
  range: CaloriesRange;
  source: {
    type: 'curated';
    label: string;
    confidence: BenchmarkConfidence;
    notes: string;
  };
  usda?: {
    query: string;
    grams: number;
    tolerancePct?: number;
    minToleranceCalories?: number;
    dataTypes?: string[];
  };
  fatSecret?: {
    query: string;
    servingHint?: string;
    tolerancePct?: number;
    minToleranceCalories?: number;
  };
};

export type ResolvedBenchmark = {
  range: CaloriesRange;
  hasUsableRange: boolean;
  sourceType: BenchmarkSourceType;
  sourceLabel: string;
  confidence: BenchmarkConfidence;
  notes: string;
  reference?: string;
};

type BenchmarkResolveOptions = {
  providers?: BenchmarkProvider[];
};

type UsdaFoodNutrient = {
  nutrientId?: number;
  nutrientName?: string;
  nutrientNumber?: string;
  unitName?: string;
  value?: number;
};

type UsdaFoodSearchItem = {
  fdcId?: number;
  description?: string;
  dataType?: string;
  foodNutrients?: UsdaFoodNutrient[];
};

type UsdaSearchResponse = {
  foods?: UsdaFoodSearchItem[];
};

type FatSecretTokenResponse = {
  access_token?: string;
  expires_in?: number;
};

type FatSecretServing = {
  calories?: string;
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

const DEFAULT_DATA_TYPES = ['Foundation', 'SR Legacy', 'Survey (FNDDS)', 'Branded'];
let fatSecretTokenCache: { token: string; expiresAtMs: number } | null = null;

export async function resolveNutritionBenchmark(
  spec?: BenchmarkSpec,
  options: BenchmarkResolveOptions = {}
): Promise<ResolvedBenchmark> {
  const providers = options.providers ?? ['usda', 'fatsecret', 'curated'];
  if (!spec) {
    return {
      range: { min: 0, max: 99999 },
      hasUsableRange: false,
      sourceType: 'curated',
      sourceLabel: 'No benchmark',
      confidence: 'low',
      notes: 'No expected calorie benchmark is configured for this case.'
    };
  }

  if (providers.includes('usda') && spec.usda && config.usdaApiKey) {
    const usda = await resolveUsdaBenchmark(spec);
    if (usda) return usda;
  }

  if (
    providers.includes('fatsecret') &&
    spec.fatSecret &&
    config.fatSecretClientId &&
    config.fatSecretClientSecret
  ) {
    const fatSecret = await resolveFatSecretBenchmark(spec);
    if (fatSecret) return fatSecret;
  }

  if (!providers.includes('curated')) {
    return {
      range: { min: 0, max: 99999 },
      hasUsableRange: false,
      sourceType: 'curated_fallback',
      sourceLabel: 'No enabled benchmark',
      confidence: 'low',
      notes: 'No enabled benchmark provider returned a usable calorie range.'
    };
  }

  const failedProviders = [
    spec.usda && config.usdaApiKey && providers.includes('usda') ? `USDA query: ${spec.usda.query}` : '',
    spec.fatSecret && config.fatSecretClientId && config.fatSecretClientSecret && providers.includes('fatsecret')
      ? `FatSecret query: ${spec.fatSecret.query}`
      : ''
  ].filter(Boolean);

  return {
    range: spec.range,
    hasUsableRange: true,
    sourceType: failedProviders.length ? 'curated_fallback' : 'curated',
    sourceLabel: spec.source.label,
    confidence: spec.source.confidence,
    notes: spec.source.notes,
    reference: failedProviders.length
      ? `External lookup unavailable; using SnapCalorie curated fallback. ${failedProviders.join(' · ')}`
      : undefined
  };
}

async function resolveUsdaBenchmark(spec: BenchmarkSpec): Promise<ResolvedBenchmark | null> {
  if (!spec.usda) return null;

  const params = new URLSearchParams({
    api_key: config.usdaApiKey,
    query: spec.usda.query,
    pageSize: '5'
  });
  for (const dataType of spec.usda.dataTypes ?? DEFAULT_DATA_TYPES) {
    params.append('dataType', dataType);
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Math.max(1000, config.usdaTimeoutMs));

  try {
    const response = await fetch(`${config.usdaApiBaseUrl}/foods/search?${params.toString()}`, {
      signal: controller.signal
    });
    if (!response.ok) return null;

    const data = (await response.json()) as UsdaSearchResponse;
    const match = selectUsdaFood(data.foods ?? []);
    if (!match) return null;

    const energyPer100g = findKcalPer100g(match);
    if (!Number.isFinite(energyPer100g) || energyPer100g <= 0) return null;

    const expectedCalories = (energyPer100g * spec.usda.grams) / 100;
    const tolerancePct = spec.usda.tolerancePct ?? 0.25;
    const minToleranceCalories = spec.usda.minToleranceCalories ?? 15;
    const tolerance = Math.max(minToleranceCalories, expectedCalories * tolerancePct);

    return {
      range: {
        min: Math.max(0, Math.floor(expectedCalories - tolerance)),
        max: Math.ceil(expectedCalories + tolerance)
      },
      hasUsableRange: true,
      sourceType: 'usda_fdc',
      sourceLabel: 'USDA FoodData Central',
      confidence: 'high',
      notes: `${spec.usda.grams}g estimate from USDA match "${match.description ?? spec.usda.query}".`,
      reference: match.fdcId ? `FDC ID ${match.fdcId}` : undefined
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function selectUsdaFood(foods: UsdaFoodSearchItem[]): UsdaFoodSearchItem | null {
  const withEnergy = foods.filter((food) => findKcalPer100g(food) > 0);
  if (!withEnergy.length) return null;

  const priority = ['Foundation', 'SR Legacy', 'Survey (FNDDS)', 'Branded'];
  return [...withEnergy].sort((a, b) => {
    const aRank = priority.indexOf(a.dataType ?? '');
    const bRank = priority.indexOf(b.dataType ?? '');
    return (aRank === -1 ? 99 : aRank) - (bRank === -1 ? 99 : bRank);
  })[0] ?? null;
}

function findKcalPer100g(food: UsdaFoodSearchItem): number {
  const nutrient = food.foodNutrients?.find((item) => {
    const unit = (item.unitName ?? '').toUpperCase();
    const name = (item.nutrientName ?? '').toLowerCase();
    return unit === 'KCAL' && (item.nutrientId === 1008 || item.nutrientNumber === '208' || name === 'energy');
  });
  return Number(nutrient?.value ?? 0);
}

async function resolveFatSecretBenchmark(spec: BenchmarkSpec): Promise<ResolvedBenchmark | null> {
  if (!spec.fatSecret) return null;

  const token = await getFatSecretAccessToken();
  if (!token) return null;

  const params = new URLSearchParams({
    search_expression: spec.fatSecret.query,
    format: 'json',
    max_results: '5',
    flag_default_serving: 'true'
  });

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Math.max(1000, config.fatSecretTimeoutMs));

  try {
    const response = await fetch(`${config.fatSecretApiBaseUrl}/foods/search/v2?${params.toString()}`, {
      headers: { Authorization: `Bearer ${token}` },
      signal: controller.signal
    });
    if (!response.ok) return null;

    const data = (await response.json()) as FatSecretSearchResponse;
    const food = toArray(data.foods_search?.results?.food)[0];
    if (!food) return null;

    const serving = selectFatSecretServing(food, spec.fatSecret.servingHint ?? spec.fatSecret.query);
    const calories = Number(serving?.calories ?? 0);
    if (!Number.isFinite(calories) || calories <= 0) return null;

    const scale = servingScale(spec.fatSecret.servingHint ?? spec.fatSecret.query, serving);
    const expectedCalories = calories * scale;
    const tolerancePct = spec.fatSecret.tolerancePct ?? 0.35;
    const minToleranceCalories = spec.fatSecret.minToleranceCalories ?? 40;
    const tolerance = Math.max(minToleranceCalories, expectedCalories * tolerancePct);

    return {
      range: {
        min: Math.max(0, Math.floor(expectedCalories - tolerance)),
        max: Math.ceil(expectedCalories + tolerance)
      },
      hasUsableRange: true,
      sourceType: 'fatsecret',
      sourceLabel: 'FatSecret',
      confidence: 'medium',
      notes: `FatSecret match "${food.food_name ?? spec.fatSecret.query}" using serving "${serving?.serving_description ?? 'default'}".`,
      reference: food.food_id ? `Food ID ${food.food_id}` : undefined
    };
  } catch {
    return null;
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
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function selectFatSecretServing(food: FatSecretFood, hint: string): FatSecretServing | null {
  const servings = toArray(food.servings?.serving);
  if (!servings.length) return null;
  const normalizedHint = normalize(hint);
  const hinted = servings.find((serving) => normalize(serving.serving_description).includes(unitWord(normalizedHint)));
  if (hinted) return hinted;
  return servings.find((serving) => serving.is_default === '1') ?? servings[0] ?? null;
}

function servingScale(hint: string, serving: FatSecretServing | null): number {
  if (!serving) return 1;
  const amount = Number(hint.match(/\b(\d+(?:\.\d+)?)\b/)?.[1] ?? 1);
  const hintUnit = unitWord(normalize(hint));
  const servingUnit = unitWord(normalize(serving.serving_description ?? serving.measurement_description ?? ''));
  if (hintUnit && servingUnit && hintUnit === servingUnit) {
    const servingAmount = Number(serving.number_of_units ?? 1);
    return Math.max(0.1, amount / (Number.isFinite(servingAmount) && servingAmount > 0 ? servingAmount : 1));
  }
  return 1;
}

function unitWord(text: string): string {
  if (/\boz|ounce|ounces\b/.test(text)) return 'oz';
  if (/\bcup|cups\b/.test(text)) return 'cup';
  if (/\bslice|slices\b/.test(text)) return 'slice';
  if (/\bpiece|pieces\b/.test(text)) return 'piece';
  if (/\bbowl|bowls\b/.test(text)) return 'bowl';
  if (/\bplate|plates\b/.test(text)) return 'plate';
  if (/\bserving|servings\b/.test(text)) return 'serving';
  if (/\bglass|glasses\b/.test(text)) return 'glass';
  if (/\bbottle|bottles\b/.test(text)) return 'bottle';
  return '';
}

function normalize(value: string | undefined): string {
  return (value ?? '').toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}

function toArray<T>(value: T | T[] | undefined): T[] {
  if (!value) return [];
  return Array.isArray(value) ? value : [value];
}
