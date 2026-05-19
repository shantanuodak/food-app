import { config } from '../config.js';
import { parseFoodText } from './deterministicParser.js';
import { tryGeminiPrimaryParse } from './aiNormalizerService.js';
import { listBenchmarkCases, type BenchmarkCase } from './accuracyBenchmarkService.js';
import { scoreNutrition, type BenchmarkScores, type NutritionValues } from './benchmarkScoringService.js';
import { lookupFatSecretReference, type FatSecretReference } from './fatSecretModelLabService.js';

export type ModelComparisonTruthMode = 'strict' | 'expanded' | 'all';

export type ModelComparisonRunOptions = {
  truthMode?: ModelComparisonTruthMode;
  category?: string | null;
  maxCases?: number;
  targetScore?: number;
  runLabel?: string | null;
  onProgress?: (casesDone: number, totalCases: number) => void;
};

export type ModelComparisonPrediction = {
  ok: boolean;
  model: string | null;
  totals: NutritionValues;
  score: BenchmarkScores;
  confidence: number | null;
  items: Array<{
    name: string;
    calories: number | null;
    protein: number | null;
    carbs: number | null;
    fat: number | null;
  }>;
  source: string;
  error: string | null;
};

export type ModelComparisonCaseResult = {
  caseId: string;
  inputText: string;
  displayName: string | null;
  category: string;
  truth: {
    sourceType: string;
    sourceLabel: string;
    sourceUrl: string | null;
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
  };
  geminiOnly: ModelComparisonPrediction;
  geminiFatSecret: ModelComparisonPrediction & {
    fatSecretMatches: FatSecretReference[];
    matchedItemCount: number;
  };
  delta: number;
  winner: 'gemini_only' | 'gemini_fatsecret' | 'tie';
};

export type ModelComparisonRunResult = {
  runLabel: string | null;
  startedAt: string;
  finishedAt: string;
  truthMode: ModelComparisonTruthMode;
  targetScore: number;
  availableReviewedCases: number;
  selectedCases: number;
  excludedCases: number;
  geminiOnlyScore: number;
  geminiFatSecretScore: number;
  delta: number;
  geminiOnlyPassCount: number;
  geminiFatSecretPassCount: number;
  winnerCounts: Record<ModelComparisonCaseResult['winner'], number>;
  sourceMix: Record<string, number>;
  weakCases: Array<{
    inputText: string;
    category: string;
    geminiOnlyScore: number;
    geminiFatSecretScore: number;
    delta: number;
  }>;
  results: ModelComparisonCaseResult[];
};

const rejectedTruthUrlPatterns = ['fatsecret.com', 'myfitnesspal.com'];
const rejectedTruthLabelPatterns = ['fatsecret', 'myfitnesspal', 'gemini'];

export function isBenchmarkCaseAllowedForModelComparison(
  benchmarkCase: Pick<BenchmarkCase, 'referenceSourceType' | 'referenceSourceLabel' | 'referenceSourceUrl'>,
  truthMode: ModelComparisonTruthMode
): boolean {
  if (truthMode === 'all') return true;

  const url = (benchmarkCase.referenceSourceUrl ?? '').toLowerCase();
  const label = benchmarkCase.referenceSourceLabel.toLowerCase();
  if (rejectedTruthUrlPatterns.some((pattern) => url.includes(pattern))) return false;
  if (rejectedTruthLabelPatterns.some((pattern) => label.includes(pattern))) return false;
  if (benchmarkCase.referenceSourceType === 'curated_manual') return false;

  if (truthMode === 'expanded') {
    return true;
  }

  return (
    benchmarkCase.referenceSourceType === 'usda' ||
    benchmarkCase.referenceSourceType === 'official_brand' ||
    benchmarkCase.referenceSourceType === 'official_restaurant'
  );
}

export async function runModelComparison(options: ModelComparisonRunOptions = {}): Promise<ModelComparisonRunResult> {
  const startedAt = new Date().toISOString();
  const truthMode = options.truthMode ?? 'expanded';
  const targetScore = clampNumber(options.targetScore ?? 85, 0, 100);
  const maxCases = Math.max(1, Math.min(options.maxCases ?? 25, 100));
  const reviewedCases = await listBenchmarkCases({
    status: 'reviewed',
    activeOnly: true,
    category: options.category ?? undefined
  });
  const selectedCases = reviewedCases
    .filter((benchmarkCase) => isBenchmarkCaseAllowedForModelComparison(benchmarkCase, truthMode))
    .slice(0, maxCases);

  const results: ModelComparisonCaseResult[] = [];
  for (const benchmarkCase of selectedCases) {
    const result = await compareOneCase(benchmarkCase);
    results.push(result);
    options.onProgress?.(results.length, selectedCases.length);
  }

  const geminiOnlyScore = round(average(results.map((result) => result.geminiOnly.score.overall)) ?? 0);
  const geminiFatSecretScore = round(average(results.map((result) => result.geminiFatSecret.score.overall)) ?? 0);
  const winnerCounts: Record<ModelComparisonCaseResult['winner'], number> = {
    gemini_only: 0,
    gemini_fatsecret: 0,
    tie: 0
  };
  const sourceMix: Record<string, number> = {};
  for (const result of results) {
    winnerCounts[result.winner] += 1;
    sourceMix[result.truth.sourceType] = (sourceMix[result.truth.sourceType] ?? 0) + 1;
  }

  return {
    runLabel: options.runLabel ?? null,
    startedAt,
    finishedAt: new Date().toISOString(),
    truthMode,
    targetScore,
    availableReviewedCases: reviewedCases.length,
    selectedCases: selectedCases.length,
    excludedCases: reviewedCases.length - selectedCases.length,
    geminiOnlyScore,
    geminiFatSecretScore,
    delta: round(geminiFatSecretScore - geminiOnlyScore),
    geminiOnlyPassCount: results.filter((result) => result.geminiOnly.score.overall >= targetScore).length,
    geminiFatSecretPassCount: results.filter((result) => result.geminiFatSecret.score.overall >= targetScore).length,
    winnerCounts,
    sourceMix,
    weakCases: results
      .filter((result) => result.geminiOnly.score.overall < targetScore || result.geminiFatSecret.score.overall < targetScore)
      .map((result) => ({
        inputText: result.inputText,
        category: result.category,
        geminiOnlyScore: result.geminiOnly.score.overall,
        geminiFatSecretScore: result.geminiFatSecret.score.overall,
        delta: result.delta
      })),
    results
  };
}

async function compareOneCase(benchmarkCase: BenchmarkCase): Promise<ModelComparisonCaseResult> {
  const reference = referenceValues(benchmarkCase);
  const geminiOnly = await runGeminiOnlyPrediction(benchmarkCase.inputText, reference);
  const geminiFatSecret = await runGeminiFatSecretPrediction(benchmarkCase.inputText, reference, geminiOnly);
  const delta = round(geminiFatSecret.score.overall - geminiOnly.score.overall);
  const winner = Math.abs(delta) < 0.1
    ? 'tie'
    : delta > 0
      ? 'gemini_fatsecret'
      : 'gemini_only';

  return {
    caseId: benchmarkCase.id,
    inputText: benchmarkCase.inputText,
    displayName: benchmarkCase.displayName,
    category: benchmarkCase.category,
    truth: {
      sourceType: benchmarkCase.referenceSourceType,
      sourceLabel: benchmarkCase.referenceSourceLabel,
      sourceUrl: benchmarkCase.referenceSourceUrl,
      ...reference
    },
    geminiOnly,
    geminiFatSecret,
    delta,
    winner
  };
}

async function runGeminiOnlyPrediction(inputText: string, reference: NutritionValues): Promise<ModelComparisonPrediction> {
  try {
    const baseline = parseFoodText(inputText);
    const output = await tryGeminiPrimaryParse(inputText, baseline, {
      timeoutMs: config.geminiTimeoutMs,
      maxAttempts: config.geminiRetryMaxAttempts
    });
    if (!output) {
      throw new Error('Gemini returned no parse.');
    }
    const totals = output.result.totals;
    return {
      ok: true,
      model: output.usage.model,
      totals,
      score: scoreNutrition(reference, totals),
      confidence: output.result.confidence,
      items: output.result.items.map((item) => ({
        name: item.name,
        calories: finiteNumber(item.calories),
        protein: finiteNumber(item.protein),
        carbs: finiteNumber(item.carbs),
        fat: finiteNumber(item.fat)
      })),
      source: 'gemini',
      error: null
    };
  } catch (err) {
    return failedPrediction(reference, 'gemini', err);
  }
}

async function runGeminiFatSecretPrediction(
  inputText: string,
  reference: NutritionValues,
  geminiOnly: ModelComparisonPrediction
): Promise<ModelComparisonPrediction & { fatSecretMatches: FatSecretReference[]; matchedItemCount: number }> {
  const matches: FatSecretReference[] = [];
  try {
    const candidateItems = geminiOnly.items.length > 0
      ? geminiOnly.items
      : [{ name: inputText, calories: null, protein: null, carbs: null, fat: null }];

    for (const item of candidateItems.slice(0, 6)) {
      const query = item.name || inputText;
      const servingHint = [inputText, item.name].filter(Boolean).join(' ');
      const fatSecret = await lookupFatSecretReference(query, servingHint);
      if (fatSecret) {
        matches.push(fatSecret);
      }
    }

    if (!matches.length) {
      return {
        ...geminiOnly,
        source: 'gemini_fatsecret_no_match',
        fatSecretMatches: [],
        matchedItemCount: 0
      };
    }

    const totals = sumFatSecretMatches(matches);
    const decision = shouldAdoptFatSecretForModelComparison(inputText, geminiOnly, matches, totals);
    if (!decision.adopt) {
      return {
        ...geminiOnly,
        source: decision.source,
        fatSecretMatches: matches,
        matchedItemCount: matches.length
      };
    }

    return {
      ok: true,
      model: geminiOnly.model,
      totals,
      score: scoreNutrition(reference, totals),
      confidence: geminiOnly.confidence,
      items: matches.map((match) => ({
        name: match.foodName,
        calories: match.calories,
        protein: match.protein,
        carbs: match.carbs,
        fat: match.fat
      })),
      source: 'gemini_fatsecret',
      error: null,
      fatSecretMatches: matches,
      matchedItemCount: matches.length
    };
  } catch (err) {
    return {
      ...geminiOnly,
      source: 'gemini_fatsecret_error',
      error: err instanceof Error ? err.message : String(err),
      fatSecretMatches: matches,
      matchedItemCount: matches.length
    };
  }
}

export function shouldAdoptFatSecretForModelComparison(
  inputText: string,
  geminiOnly: Pick<ModelComparisonPrediction, 'ok' | 'totals' | 'confidence'>,
  matches: FatSecretReference[],
  fatSecretTotals: NutritionValues
): { adopt: boolean; source: string } {
  if (!matches.length) return { adopt: false, source: 'gemini_fatsecret_no_match' };
  if (!geminiOnly.ok) return { adopt: true, source: 'gemini_fatsecret' };

  const normalizedInput = normalize(inputText);
  const geminiCalories = finiteNumber(geminiOnly.totals.calories);
  const fatSecretCalories = finiteNumber(fatSecretTotals.calories);
  const calorieGap = relativeDifference(geminiCalories, fatSecretCalories);
  const commercialMatch = matches.some((match) => hasCommercialMatch(normalizedInput, match));
  const explicitServing = hasExplicitServing(normalizedInput);
  const servingAligned = matches.every((match) => servingMatchesInput(normalizedInput, normalize(match.servingDescription)));
  const preparedFood = isPreparedFood(normalizedInput);

  if (isCompositeSingleMatchRisk(normalizedInput, matches)) {
    return { adopt: false, source: 'gemini_fatsecret_fallback_composite_match' };
  }

  if (!hasMeaningfulFoodOverlap(normalizedInput, matches)) {
    return { adopt: false, source: 'gemini_fatsecret_fallback_token_mismatch' };
  }

  if (commercialMatch) {
    if (calorieGap !== null && calorieGap > 0.35) {
      return { adopt: false, source: 'gemini_fatsecret_fallback_calorie_gap' };
    }
    if (explicitServing && !servingAligned && calorieGap !== null && calorieGap > 0.2) {
      return { adopt: false, source: 'gemini_fatsecret_fallback_serving_mismatch' };
    }
    return { adopt: true, source: 'gemini_fatsecret' };
  }

  if (isSimpleWholeFood(normalizedInput) && (geminiOnly.confidence ?? 0) >= 0.7) {
    return { adopt: false, source: 'gemini_fatsecret_fallback_simple_food' };
  }

  if (calorieGap !== null && calorieGap <= 0.12) {
    return { adopt: false, source: 'gemini_fatsecret_fallback_similar_calories' };
  }

  if (!commercialMatch && preparedFood && calorieGap !== null && calorieGap <= 0.3) {
    return { adopt: false, source: 'gemini_fatsecret_fallback_similar_calories' };
  }

  if (explicitServing && servingAligned && preparedFood && (calorieGap === null || calorieGap <= 0.45)) {
    return { adopt: true, source: 'gemini_fatsecret' };
  }

  return { adopt: false, source: 'gemini_fatsecret_fallback_low_trust' };
}

function failedPrediction(reference: NutritionValues, source: string, err: unknown): ModelComparisonPrediction {
  const totals = { calories: null, protein: null, carbs: null, fat: null };
  return {
    ok: false,
    model: null,
    totals,
    score: scoreNutrition(reference, totals, { hasError: true }),
    confidence: null,
    items: [],
    source,
    error: err instanceof Error ? err.message : String(err)
  };
}

function referenceValues(benchmarkCase: BenchmarkCase): NutritionValues & {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
} {
  return {
    calories: benchmarkCase.referenceCalories,
    protein: benchmarkCase.referenceProtein,
    carbs: benchmarkCase.referenceCarbs,
    fat: benchmarkCase.referenceFat
  };
}

function sumFatSecretMatches(matches: FatSecretReference[]): NutritionValues {
  return {
    calories: round(matches.reduce((sum, match) => sum + match.calories, 0)),
    protein: round(matches.reduce((sum, match) => sum + match.protein, 0)),
    carbs: round(matches.reduce((sum, match) => sum + match.carbs, 0)),
    fat: round(matches.reduce((sum, match) => sum + match.fat, 0))
  };
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

function relativeDifference(a: number | null, b: number | null): number | null {
  if (a === null || b === null || a <= 0 || b <= 0) return null;
  return Math.abs(a - b) / Math.max(a, b);
}

function hasCommercialMatch(normalizedInput: string, match: FatSecretReference): boolean {
  const normalizedBrand = normalize(match.brandName);
  if (normalizedBrand && normalizedInput.includes(normalizedBrand)) return true;

  const normalizedName = normalize(match.foodName);
  const commercialTokens = ['chobani', 'clif', 'tasty bite', 'mcdonald', 'mcdonalds', 'subway', 'chipotle'];
  return commercialTokens.some((token) => normalizedInput.includes(token) && normalizedName.includes(token));
}

function servingMatchesInput(normalizedInput: string, normalizedServing: string): boolean {
  const inputUnit = servingUnit(normalizedInput);
  if (!inputUnit) return true;
  return servingUnit(normalizedServing) === inputUnit || normalizedServing.includes(inputUnit);
}

function servingUnit(text: string): string {
  if (/\b(?:fl\s*oz|oz|ounce|ounces)\b/.test(text)) return 'oz';
  if (/(?:\b\d+(?:\.\d+)?\s*g\b|\b(?:gram|grams|g)\b)/.test(text)) return 'g';
  if (/\b(?:cup|cups)\b/.test(text)) return 'cup';
  if (/\b(?:slice|slices)\b/.test(text)) return 'slice';
  if (/\b(?:piece|pieces)\b/.test(text)) return 'piece';
  if (/\b(?:small|medium|large)\b/.test(text)) return text.match(/\b(small|medium|large)\b/)?.[1] ?? '';
  if (/\b(?:bar|bars)\b/.test(text)) return 'bar';
  if (/\b(?:sandwich|sandwiches|sub|subs)\b/.test(text)) return 'sandwich';
  if (/\b(?:burger|burgers)\b/.test(text)) return 'burger';
  if (/\b(?:bowl|bowls)\b/.test(text)) return 'bowl';
  if (/\b(?:serving|servings)\b/.test(text)) return 'serving';
  return '';
}

function hasExplicitServing(normalizedInput: string): boolean {
  return Boolean(servingUnit(normalizedInput) || /\b\d+(?:\.\d+)?\b/.test(normalizedInput));
}

function isSimpleWholeFood(normalizedInput: string): boolean {
  return [
    /\bapple\b/,
    /\bbanana\b/,
    /\balmonds?\b/,
    /\bwhite rice\b/,
    /\bcooked rice\b/,
    /\bcooked white rice\b/
  ].some((pattern) => pattern.test(normalizedInput));
}

function isPreparedFood(normalizedInput: string): boolean {
  return [
    /\bpizza\b/,
    /\bsandwich\b/,
    /\bburger\b/,
    /\bburrito\b/,
    /\btaco\b/,
    /\bquesadilla\b/,
    /\bfries\b/,
    /\bnuggets?\b/,
    /\bwings?\b/,
    /\bgrilled cheese\b/,
    /\broti\b/,
    /\brotis\b/,
    /\bchanna masala\b/,
    /\bmadras lentils\b/
  ].some((pattern) => pattern.test(normalizedInput));
}

function isCompositeSingleMatchRisk(normalizedInput: string, matches: FatSecretReference[]): boolean {
  if (matches.length !== 1) return false;
  if (!/\bwith\b/.test(normalizedInput) || significantTokens(normalizedInput).length < 6) return false;

  const matchedText = normalize(`${matches[0].brandName ?? ''} ${matches[0].foodName}`);
  const dishTerms = ['bowl', 'sandwich', 'burrito', 'burger', 'pizza', 'salad', 'wrap', 'plate', 'meal'];
  const requestedDishTerms = dishTerms.filter((term) => normalizedInput.includes(term));
  return requestedDishTerms.length > 0 && requestedDishTerms.every((term) => !matchedText.includes(term));
}

function hasMeaningfulFoodOverlap(normalizedInput: string, matches: FatSecretReference[]): boolean {
  const inputTokens = significantFoodTokens(normalizedInput);
  if (!inputTokens.length) return true;
  return matches.every((match) => {
    const matchTokens = significantFoodTokens(normalize(`${match.brandName ?? ''} ${match.foodName}`));
    return inputTokens.some((inputToken) => matchTokens.some((matchToken) => foodTokensMatch(inputToken, matchToken)));
  });
}

function foodTokensMatch(left: string, right: string): boolean {
  return singularize(left) === singularize(right);
}

function singularize(token: string): string {
  return token.endsWith('s') && token.length > 3 ? token.slice(0, -1) : token;
}

function significantTokens(normalizedInput: string): string[] {
  const ignored = new Set(['a', 'an', 'the', 'of', 'and', 'with', 'one', 'two', 'three', '1', '2', '3']);
  return normalizedInput.split(/\s+/).filter((token) => token && !ignored.has(token));
}

function significantFoodTokens(normalizedInput: string): string[] {
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
    'plain',
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
  return normalizedInput
    .split(/\s+/)
    .filter((token) => token && !ignored.has(token) && !/^\d+(?:\.\d+)?(?:g|oz)?$/.test(token));
}

function normalize(value: string | undefined | null): string {
  return (value ?? '').toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}
