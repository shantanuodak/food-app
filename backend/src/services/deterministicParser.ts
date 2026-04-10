import { calculateNutrition, sumNutrition } from './nutritionService.js';

type FoodEntry = {
  key: string;
  aliases: string[];
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  unit: string;
  gramsPerUnit: number;
};

export type ParsedItemManualOverride = {
  enabled: boolean;
  reason?: string;
  editedFields: string[];
};

export type ParsedItem = {
  name: string;
  quantity: number;
  unit: string;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  matchConfidence: number;
  nutritionSourceId: string;
  servingOptions?: ParsedServingOption[];
  foodDescription?: string;
  explanation?: string;
  amount?: number;
  unitNormalized?: string;
  gramsPerUnit?: number | null;
  needsClarification?: boolean;
  manualOverride?: boolean;
  manualOverrideMeta?: ParsedItemManualOverride;
  sourceFamily?: 'cache' | 'deterministic' | 'gemini' | 'manual';
  originalNutritionSourceId?: string;
};

const FOOD_DATABASE: FoodEntry[] = [
  { key: 'egg', aliases: ['egg', 'eggs'], calories: 72, protein: 6.3, carbs: 0.6, fat: 4.8, unit: 'count', gramsPerUnit: 50 },
  { key: 'toast', aliases: ['toast', 'bread', 'slice toast', 'bread slice'], calories: 80, protein: 3.0, carbs: 14.0, fat: 1.0, unit: 'slice', gramsPerUnit: 30 },
  { key: 'butter', aliases: ['butter', 'salted butter', 'unsalted butter'], calories: 34, protein: 0.0, carbs: 0.0, fat: 3.8, unit: 'tsp', gramsPerUnit: 4.7 },
  { key: 'coffee', aliases: ['coffee', 'black coffee'], calories: 2, protein: 0.3, carbs: 0.0, fat: 0.0, unit: 'cup', gramsPerUnit: 240 },
  { key: 'rice', aliases: ['rice', 'white rice', 'brown rice'], calories: 206, protein: 4.3, carbs: 45.0, fat: 0.4, unit: 'cup', gramsPerUnit: 158 },
  { key: 'chicken', aliases: ['chicken', 'chicken breast', 'grilled chicken'], calories: 165, protein: 31.0, carbs: 0.0, fat: 3.6, unit: '100g', gramsPerUnit: 100 }
];

const UNIT_ALIASES: Record<string, string> = {
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
  oz: 'oz',
  ounce: 'oz',
  ounces: 'oz',
  count: 'count'
};

export type ParsedServingOption = {
  servingId: string | null;
  label: string;
  quantity: number;
  unit: string;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  nutritionSourceId: string;
};

export type ParseResult = {
  confidence: number;
  assumptions: string[];
  items: ParsedItem[];
  totals: {
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
  };
};

export type ConfidenceComponents = {
  matchQuality: number;
  quantityUnitQuality: number;
  portionPlausibility: number;
  coverage: number;
};

type SegmentParse = {
  quantity: number;
  normalizedUnit: string | null;
  foodText: string;
  quantityScore: number;
  unitScore: number;
};

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

function normalizeText(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}

function tokenize(value: string): string[] {
  const normalized = normalizeText(value);
  return normalized ? normalized.split(' ') : [];
}

function levenshtein(a: string, b: string): number {
  if (a === b) {
    return 0;
  }
  const rows = a.length + 1;
  const cols = b.length + 1;
  const matrix: number[][] = Array.from({ length: rows }, () => Array(cols).fill(0));

  for (let i = 0; i < rows; i += 1) {
    matrix[i][0] = i;
  }
  for (let j = 0; j < cols; j += 1) {
    matrix[0][j] = j;
  }

  for (let i = 1; i < rows; i += 1) {
    for (let j = 1; j < cols; j += 1) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      matrix[i][j] = Math.min(
        matrix[i - 1][j] + 1,
        matrix[i][j - 1] + 1,
        matrix[i - 1][j - 1] + cost
      );
    }
  }

  return matrix[rows - 1][cols - 1];
}

function similarityByEditDistance(a: string, b: string): number {
  const left = normalizeText(a);
  const right = normalizeText(b);
  if (!left || !right) {
    return 0;
  }
  const distance = levenshtein(left, right);
  const maxLength = Math.max(left.length, right.length);
  return clamp01(1 - distance / maxLength);
}

function similarityByTokenOverlap(a: string, b: string): number {
  const aTokens = new Set(tokenize(a));
  const bTokens = new Set(tokenize(b));
  if (aTokens.size === 0 || bTokens.size === 0) {
    return 0;
  }

  let intersection = 0;
  for (const token of aTokens) {
    if (bTokens.has(token)) {
      intersection += 1;
    }
  }

  const union = aTokens.size + bTokens.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

function extractSegment(raw: string): SegmentParse {
  const cleaned = normalizeText(raw);
  const tokens = cleaned.split(' ').filter(Boolean);

  let quantity = 1;
  let quantityScore = 0.7;
  let unitScore = 0.8;
  let idx = 0;

  if (tokens[idx] && /^\d+(?:\.\d+)?$/.test(tokens[idx])) {
    quantity = Number(tokens[idx]);
    quantityScore = quantity > 0 ? 1 : 0;
    idx += 1;
  }

  let normalizedUnit: string | null = null;
  if (tokens[idx] && UNIT_ALIASES[tokens[idx]]) {
    normalizedUnit = UNIT_ALIASES[tokens[idx]];
    unitScore = 1;
    idx += 1;
  } else if (tokens[idx] && /^(cup|cups|slice|slices|tsp|tbsp|gram|grams|g|oz|ounce|ounces)$/.test(tokens[idx])) {
    unitScore = 0.4;
    idx += 1;
  }

  const foodText = tokens.slice(idx).join(' ').trim();
  if (!foodText) {
    return {
      quantity,
      normalizedUnit,
      foodText: cleaned,
      quantityScore,
      unitScore: 0.2
    };
  }

  return {
    quantity,
    normalizedUnit,
    foodText,
    quantityScore,
    unitScore
  };
}

function findBestFoodMatch(foodText: string): { entry: FoodEntry; score: number } | null {
  let best: { entry: FoodEntry; score: number } | null = null;

  for (const entry of FOOD_DATABASE) {
    for (const alias of entry.aliases) {
      const tokenScore = similarityByTokenOverlap(foodText, alias);
      const editScore = similarityByEditDistance(foodText, alias);
      const substringBonus = normalizeText(alias).includes(normalizeText(foodText)) || normalizeText(foodText).includes(normalizeText(alias)) ? 1 : 0;
      const score = clamp01(0.45 * tokenScore + 0.45 * editScore + 0.1 * substringBonus);

      if (!best || score > best.score) {
        best = { entry, score };
      }
    }
  }

  if (!best || best.score < 0.45) {
    return null;
  }

  return best;
}

function portionPlausibility(quantity: number, grams: number): number {
  if (quantity <= 0) {
    return 0;
  }
  if (grams > 1500 || quantity > 20) {
    return 0.35;
  }
  if (grams > 900 || quantity > 10) {
    return 0.65;
  }
  return 1;
}

export function calculateDeterministicConfidence(components: ConfidenceComponents): number {
  const m = clamp01(components.matchQuality);
  const q = clamp01(components.quantityUnitQuality);
  const p = clamp01(components.portionPlausibility);
  const c = clamp01(components.coverage);
  return round(clamp01(0.45 * m + 0.25 * q + 0.15 * p + 0.15 * c), 3);
}

export function parseFoodText(text: string): ParseResult {
  const assumptions: string[] = [];
  const items: ParsedItem[] = [];

  const segments = text
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);

  let parseQualitySum = 0;
  let portionScoreSum = 0;
  let matchScoreSum = 0;

  for (const segment of segments) {
    const parsed = extractSegment(segment);
    const parseQuality = clamp01((parsed.quantityScore + parsed.unitScore) / 2);
    parseQualitySum += parseQuality;

    const bestMatch = findBestFoodMatch(parsed.foodText);
    if (!bestMatch) {
      assumptions.push(`No confident nutrition match for: ${segment}`);
      continue;
    }

    const chosenUnit = parsed.normalizedUnit || bestMatch.entry.unit;
    const nutrition = calculateNutrition(
      {
        baseUnit: bestMatch.entry.unit,
        gramsPerBaseUnit: bestMatch.entry.gramsPerUnit,
        caloriesPerBaseUnit: bestMatch.entry.calories,
        proteinPerBaseUnit: bestMatch.entry.protein,
        carbsPerBaseUnit: bestMatch.entry.carbs,
        fatPerBaseUnit: bestMatch.entry.fat
      },
      parsed.quantity,
      chosenUnit
    );

    if (nutrition.resolvedUnit !== chosenUnit) {
      assumptions.push(`Used default unit ${nutrition.resolvedUnit} for ${bestMatch.entry.key}`);
    } else if (parsed.normalizedUnit && parsed.normalizedUnit !== bestMatch.entry.unit) {
      assumptions.push(`Converted ${parsed.normalizedUnit} for ${bestMatch.entry.key}`);
    }

    const pScore = portionPlausibility(parsed.quantity, nutrition.grams);
    portionScoreSum += pScore;
    matchScoreSum += bestMatch.score;

    items.push({
      name: bestMatch.entry.key,
      quantity: parsed.quantity,
      unit: nutrition.resolvedUnit,
      grams: nutrition.grams,
      calories: nutrition.calories,
      protein: nutrition.protein,
      carbs: nutrition.carbs,
      fat: nutrition.fat,
      matchConfidence: round(bestMatch.score, 3),
      nutritionSourceId: `seed_${bestMatch.entry.key}`
    });
  }

  const totals = sumNutrition(items);

  const segmentCount = segments.length || 1;
  const matchedCount = items.length;

  const m = clamp01(matchScoreSum / segmentCount);
  const q = clamp01(parseQualitySum / segmentCount);
  const p = matchedCount === 0 ? 0 : clamp01(portionScoreSum / matchedCount);
  const c = clamp01(matchedCount / segmentCount);

  const confidence = calculateDeterministicConfidence({
    matchQuality: m,
    quantityUnitQuality: q,
    portionPlausibility: p,
    coverage: c
  });

  return {
    confidence,
    assumptions,
    items,
    totals: {
      calories: totals.calories,
      protein: totals.protein,
      carbs: totals.carbs,
      fat: totals.fat
    }
  };
}
