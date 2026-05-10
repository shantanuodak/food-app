export type NutritionValues = {
  calories: number | null | undefined;
  protein: number | null | undefined;
  carbs: number | null | undefined;
  fat: number | null | undefined;
};

export type BenchmarkScores = {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  overall: number;
  label: 'strong' | 'reasonable' | 'needs_review' | 'failed';
};

const WEIGHTS = {
  calories: 0.4,
  protein: 0.25,
  carbs: 0.2,
  fat: 0.15
} as const;

function finiteNumber(value: number | null | undefined): number | null {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : null;
}

function round(value: number, digits = 1): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

export function scoreMacro(referenceValue: number | null | undefined, actualValue: number | null | undefined): number {
  const reference = finiteNumber(referenceValue);
  const actual = finiteNumber(actualValue);
  if (reference === null || actual === null || actual < 0) return 0;
  if (reference <= 0) {
    return actual <= 1 ? 100 : 0;
  }
  const absoluteErrorPct = Math.abs(actual - reference) / reference;
  return round(Math.max(0, 100 * (1 - absoluteErrorPct)));
}

export function labelForScore(score: number, hasError = false): BenchmarkScores['label'] {
  if (hasError || score < 50) return 'failed';
  if (score >= 90) return 'strong';
  if (score >= 75) return 'reasonable';
  return 'needs_review';
}

export function scoreNutrition(
  reference: NutritionValues,
  actual: NutritionValues,
  options: { hasError?: boolean } = {}
): BenchmarkScores {
  const calories = scoreMacro(reference.calories, actual.calories);
  const protein = scoreMacro(reference.protein, actual.protein);
  const carbs = scoreMacro(reference.carbs, actual.carbs);
  const fat = scoreMacro(reference.fat, actual.fat);
  const overall = round(
    calories * WEIGHTS.calories +
      protein * WEIGHTS.protein +
      carbs * WEIGHTS.carbs +
      fat * WEIGHTS.fat
  );

  return {
    calories,
    protein,
    carbs,
    fat,
    overall,
    label: labelForScore(overall, options.hasError)
  };
}
