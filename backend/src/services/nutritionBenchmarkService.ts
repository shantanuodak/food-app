import { config } from '../config.js';

export type BenchmarkConfidence = 'high' | 'medium' | 'low';
export type BenchmarkSourceType = 'usda_fdc' | 'curated' | 'curated_fallback';

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
};

export type ResolvedBenchmark = {
  range: CaloriesRange;
  sourceType: BenchmarkSourceType;
  sourceLabel: string;
  confidence: BenchmarkConfidence;
  notes: string;
  reference?: string;
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

const DEFAULT_DATA_TYPES = ['Foundation', 'SR Legacy', 'Survey (FNDDS)', 'Branded'];

export async function resolveNutritionBenchmark(spec?: BenchmarkSpec): Promise<ResolvedBenchmark> {
  if (!spec) {
    return {
      range: { min: 0, max: 99999 },
      sourceType: 'curated',
      sourceLabel: 'No benchmark',
      confidence: 'low',
      notes: 'No expected calorie benchmark is configured for this case.'
    };
  }

  if (spec.usda && config.usdaApiKey) {
    const usda = await resolveUsdaBenchmark(spec);
    if (usda) return usda;
  }

  return {
    range: spec.range,
    sourceType: spec.usda && config.usdaApiKey ? 'curated_fallback' : 'curated',
    sourceLabel: spec.source.label,
    confidence: spec.source.confidence,
    notes: spec.source.notes,
    reference: spec.usda && config.usdaApiKey
      ? `USDA lookup unavailable; using curated fallback. Query: ${spec.usda.query}`
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
