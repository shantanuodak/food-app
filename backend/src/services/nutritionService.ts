export type NutritionProfile = {
  baseUnit: string;
  gramsPerBaseUnit: number;
  caloriesPerBaseUnit: number;
  proteinPerBaseUnit: number;
  carbsPerBaseUnit: number;
  fatPerBaseUnit: number;
};

export type NutritionCalculation = {
  resolvedUnit: string;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
};

type NutritionItem = {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
};

const GRAMS_PER_UNIT: Record<string, number> = {
  g: 1,
  oz: 28.3495,
  tsp: 4.7,
  tbsp: 14.2,
  cup: 240,
  slice: 30
};

function round(value: number, digits = 1): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function validateNonNegative(name: string, value: number): void {
  if (value < 0) {
    throw new Error(`Invalid negative ${name}: ${value}`);
  }
}

export function calculateNutrition(profile: NutritionProfile, quantity: number, unit: string): NutritionCalculation {
  validateNonNegative('quantity', quantity);
  validateNonNegative('gramsPerBaseUnit', profile.gramsPerBaseUnit);
  validateNonNegative('caloriesPerBaseUnit', profile.caloriesPerBaseUnit);
  validateNonNegative('proteinPerBaseUnit', profile.proteinPerBaseUnit);
  validateNonNegative('carbsPerBaseUnit', profile.carbsPerBaseUnit);
  validateNonNegative('fatPerBaseUnit', profile.fatPerBaseUnit);

  const normalizedUnit = unit.toLowerCase();
  const unitToGrams = GRAMS_PER_UNIT[normalizedUnit];
  const resolvedUnit = unitToGrams ? normalizedUnit : profile.baseUnit;

  const grams = unitToGrams ? quantity * unitToGrams : quantity * profile.gramsPerBaseUnit;
  const baseQuantity = profile.gramsPerBaseUnit > 0 ? grams / profile.gramsPerBaseUnit : 0;

  const calories = baseQuantity * profile.caloriesPerBaseUnit;
  const protein = baseQuantity * profile.proteinPerBaseUnit;
  const carbs = baseQuantity * profile.carbsPerBaseUnit;
  const fat = baseQuantity * profile.fatPerBaseUnit;

  return {
    resolvedUnit,
    grams: round(grams, 1),
    calories: round(calories, 1),
    protein: round(protein, 1),
    carbs: round(carbs, 1),
    fat: round(fat, 1)
  };
}

export function sumNutrition(items: NutritionItem[]): NutritionItem {
  const totals = items.reduce(
    (acc, item) => {
      validateNonNegative('item calories', item.calories);
      validateNonNegative('item protein', item.protein);
      validateNonNegative('item carbs', item.carbs);
      validateNonNegative('item fat', item.fat);

      acc.calories += item.calories;
      acc.protein += item.protein;
      acc.carbs += item.carbs;
      acc.fat += item.fat;
      return acc;
    },
    { calories: 0, protein: 0, carbs: 0, fat: 0 }
  );

  return {
    calories: round(totals.calories, 1),
    protein: round(totals.protein, 1),
    carbs: round(totals.carbs, 1),
    fat: round(totals.fat, 1)
  };
}

