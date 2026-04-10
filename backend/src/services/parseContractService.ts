import type { ParseResult, ParsedItem } from './deterministicParser.js';
import { sumNutrition } from './nutritionService.js';
import type { ParsePipelineRoute } from './parsePipelineService.js';

export type SourceFamily = 'cache' | 'deterministic' | 'gemini' | 'manual';

const SOURCE_ORDER: SourceFamily[] = ['cache', 'deterministic', 'gemini', 'manual'];

const UNIT_ALIASES: Record<string, string> = {
  count: 'count',
  piece: 'count',
  pieces: 'count',
  serving: 'serving',
  servings: 'serving',
  cup: 'cup',
  cups: 'cup',
  slice: 'slice',
  slices: 'slice',
  tsp: 'tsp',
  teaspoon: 'tsp',
  teaspoons: 'tsp',
  tbsp: 'tbsp',
  tablespoon: 'tbsp',
  tablespoons: 'tbsp',
  g: 'g',
  gram: 'g',
  grams: 'g',
  ml: 'ml',
  milliliter: 'ml',
  milliliters: 'ml',
  oz: 'oz',
  ounce: 'oz',
  ounces: 'oz',
  lb: 'lb',
  lbs: 'lb',
  pound: 'lb',
  pounds: 'lb'
};

function round(value: number, digits = 3): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function asFiniteNonNegative(value: unknown): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    return null;
  }
  return value;
}

function normalizeUnit(value: string | undefined): string {
  const normalized = (value || '').trim().toLowerCase();
  if (!normalized) {
    return 'count';
  }
  return UNIT_ALIASES[normalized] || normalized;
}

function inferSourceFamily(item: ParsedItem, route: ParsePipelineRoute): SourceFamily {
  if (item.manualOverride || item.manualOverrideMeta?.enabled) {
    return 'manual';
  }

  const sourceId = (item.nutritionSourceId || '').toLowerCase();
  if (sourceId.includes('gemini')) {
    return 'gemini';
  }
  if (sourceId.includes('manual')) {
    return 'manual';
  }
  if (sourceId.includes('cache')) {
    return 'cache';
  }
  if (sourceId.includes('seed_') || sourceId.includes('deterministic')) {
    return 'deterministic';
  }

  if (route === 'deterministic') return 'deterministic';
  if (route === 'gemini') return 'gemini';
  return 'cache';
}

function shouldClarifyItem(item: ParsedItem): boolean {
  if (item.manualOverride || item.manualOverrideMeta?.enabled) {
    return false;
  }

  const hasInvalidCoreValue =
    asFiniteNonNegative(item.quantity) === null ||
    asFiniteNonNegative(item.grams) === null ||
    asFiniteNonNegative(item.calories) === null ||
    asFiniteNonNegative(item.protein) === null ||
    asFiniteNonNegative(item.carbs) === null ||
    asFiniteNonNegative(item.fat) === null;
  if (hasInvalidCoreValue) {
    return true;
  }

  const lowConfidence = (item.matchConfidence || 0) < 0.7;
  const missingSource = !item.nutritionSourceId || !item.nutritionSourceId.trim();
  return lowConfidence || missingSource;
}

function normalizeItem(item: ParsedItem, route: ParsePipelineRoute): ParsedItem {
  const quantity = asFiniteNonNegative(item.quantity) ?? asFiniteNonNegative(item.amount) ?? 0;
  const normalizedUnit = normalizeUnit(item.unitNormalized || item.unit);
  const grams = asFiniteNonNegative(item.grams) ?? 0;
  const gramsPerUnit = quantity > 0 ? round(grams / quantity, 4) : null;
  const sourceFamily = inferSourceFamily(item, route);
  const needsClarification = shouldClarifyItem(item);

  return {
    ...item,
    quantity,
    unit: normalizeUnit(item.unit),
    grams,
    calories: asFiniteNonNegative(item.calories) ?? 0,
    protein: asFiniteNonNegative(item.protein) ?? 0,
    carbs: asFiniteNonNegative(item.carbs) ?? 0,
    fat: asFiniteNonNegative(item.fat) ?? 0,
    amount: quantity,
    unitNormalized: normalizedUnit,
    gramsPerUnit,
    needsClarification,
    manualOverride: item.manualOverride ?? item.manualOverrideMeta?.enabled ?? false,
    sourceFamily,
    originalNutritionSourceId: item.originalNutritionSourceId || item.nutritionSourceId || ''
  };
}

export function normalizeParseResultContract(result: ParseResult, route: ParsePipelineRoute): ParseResult {
  const items = result.items.map((item) => normalizeItem(item, route));
  const totals = sumNutrition(items);
  return {
    ...result,
    items,
    totals
  };
}

export function collectSourcesUsed(items: ParsedItem[], route: ParsePipelineRoute, cacheHit: boolean): SourceFamily[] {
  const families = new Set<SourceFamily>();
  if (route === 'cache' || cacheHit) {
    families.add('cache');
  }
  for (const item of items) {
    families.add(inferSourceFamily(item, route));
  }
  return SOURCE_ORDER.filter((family) => families.has(family));
}
