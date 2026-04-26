import type { ParseResult } from './deterministicParser.js';
import { splitFoodTextSegments } from './foodTextSegmentation.js';
import type { ParsePipelineRoute } from './parseDecisionTypes.js';
import { config } from '../config.js';

export function createEmptyParseResult(_text: string): ParseResult {
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

export function isValidParseResultShape(value: unknown): value is ParseResult {
  if (!value || typeof value !== 'object') {
    return false;
  }
  const candidate = value as Partial<ParseResult>;
  return (
    typeof candidate.confidence === 'number' &&
    Number.isFinite(candidate.confidence) &&
    Array.isArray(candidate.items) &&
    Array.isArray(candidate.assumptions) &&
    Boolean(candidate.totals) &&
    typeof candidate.totals?.calories === 'number' &&
    typeof candidate.totals?.protein === 'number' &&
    typeof candidate.totals?.carbs === 'number' &&
    typeof candidate.totals?.fat === 'number'
  );
}

export function resultUsesRetiredProvider(result: ParseResult): boolean {
  return result.items.some((item) => {
    const nutritionSourceId = item.nutritionSourceId.trim().toLowerCase();
    const originalNutritionSourceId = (item.originalNutritionSourceId || '').trim().toLowerCase();
    const sourceFamily = (item.sourceFamily || '').trim().toLowerCase();

    return (
      nutritionSourceId.includes('fatsecret') ||
      nutritionSourceId.includes('deterministic') ||
      nutritionSourceId.includes('seed_') ||
      originalNutritionSourceId.includes('fatsecret') ||
      originalNutritionSourceId.includes('deterministic') ||
      originalNutritionSourceId.includes('seed_') ||
      sourceFamily === 'fatsecret' ||
      sourceFamily === 'deterministic'
    );
  });
}

export function hasUnresolvedSignal(text: string, result: ParseResult): boolean {
  if (result.items.length === 0) {
    return true;
  }

  const segmentCount = splitFoodTextSegments(text).length;
  const coverageGap = segmentCount > 0 && result.items.length < segmentCount;
  return coverageGap;
}

function normalizeNutritionSourceId(rawSourceId: string, route: ParsePipelineRoute): string {
  const trimmed = rawSourceId.trim();
  if (!trimmed) {
    if (route === 'deterministic') return 'deterministic_estimate';
    if (route === 'gemini') return 'gemini_estimate';
    return 'cache_estimate';
  }

  const normalized = trimmed.toLowerCase();
  if (normalized.includes('gemini') || normalized.includes('manual') || normalized.includes('cache')) {
    return trimmed;
  }

  if (route === 'deterministic') return 'deterministic_estimate';
  if (route === 'gemini') return 'gemini_estimate';
  return 'cache_estimate';
}

export function sanitizeResultSources(result: ParseResult, route: ParsePipelineRoute): ParseResult {
  if (result.items.length === 0) {
    return result;
  }

  return {
    ...result,
    items: result.items.map((item) => ({
      ...item,
      nutritionSourceId: normalizeNutritionSourceId(item.nutritionSourceId, route)
    }))
  };
}

export function ensureItemExplanations(result: ParseResult, route: ParsePipelineRoute): ParseResult {
  if (result.items.length === 0) {
    return result;
  }

  const fallbackExplanation =
    route === 'gemini'
      ? 'AI estimate provided based on the entered text.'
      : 'Nutrition estimate provided based on the matched data source.';

  return {
    ...result,
    items: result.items.map((item) => {
      const foodDescription = item.foodDescription && item.foodDescription.trim().length > 0 ? item.foodDescription : item.name;
      const explanation = item.explanation && item.explanation.trim().length > 0 ? item.explanation : fallbackExplanation;
      return {
        ...item,
        foodDescription,
        explanation
      };
    })
  };
}

export function shouldAcceptCachedResult(result: ParseResult): boolean {
  return result.items.length > 0 || result.confidence >= config.parseCacheMinConfidence;
}

export function combineParseResults(results: ParseResult[]): ParseResult {
  const items = results.flatMap((r) => r.items);
  const confidence = results.length > 0 ? Math.min(...results.map((r) => r.confidence)) : 0;
  const totals = {
    calories: Math.round(items.reduce((s, i) => s + i.calories, 0) * 10) / 10,
    protein: Math.round(items.reduce((s, i) => s + i.protein, 0) * 10) / 10,
    carbs: Math.round(items.reduce((s, i) => s + i.carbs, 0) * 10) / 10,
    fat: Math.round(items.reduce((s, i) => s + i.fat, 0) * 10) / 10
  };
  return { confidence, assumptions: [], items, totals };
}
