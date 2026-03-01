import { splitFoodTextSegments } from './foodTextSegmentation.js';

export type ParsedFoodTextCandidate = {
  rawSegment: string;
  query: string;
  quantity: number;
  unit: string;
};

export const COMMON_FOOD_UNIT_ALIASES: Record<string, string> = {
  g: 'g',
  gram: 'g',
  grams: 'g',
  ml: 'ml',
  milliliter: 'ml',
  milliliters: 'ml',
  oz: 'oz',
  ounce: 'oz',
  ounces: 'oz',
  tsp: 'tsp',
  teaspoon: 'tsp',
  teaspoons: 'tsp',
  tbsp: 'tbsp',
  tablespoon: 'tbsp',
  tablespoons: 'tbsp',
  cup: 'cup',
  cups: 'cup',
  slice: 'slice',
  slices: 'slice',
  serving: 'serving',
  servings: 'serving',
  count: 'count',
  piece: 'count',
  pieces: 'count'
};

export function normalizeFoodText(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}

export function normalizeFoodUnit(
  value: string,
  aliases: Record<string, string> = COMMON_FOOD_UNIT_ALIASES,
  defaultUnit = 'count'
): string {
  const cleaned = normalizeFoodText(value);
  if (!cleaned) {
    return defaultUnit;
  }
  const first = cleaned.split(' ')[0] || cleaned;
  return aliases[first] || first;
}

export function tokenOverlapRatio(left: string, right: string): number {
  const leftTokens = new Set(normalizeFoodText(left).split(' ').filter(Boolean));
  const rightTokens = new Set(normalizeFoodText(right).split(' ').filter(Boolean));
  if (leftTokens.size === 0 || rightTokens.size === 0) {
    return 0;
  }

  let hits = 0;
  for (const token of leftTokens) {
    if (rightTokens.has(token)) {
      hits += 1;
    }
  }
  return hits / leftTokens.size;
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

export function parseFoodTextCandidates(
  text: string,
  options?: {
    defaultUnit?: string;
    unitAliases?: Record<string, string>;
  }
): ParsedFoodTextCandidate[] {
  const defaultUnit = options?.defaultUnit || 'count';
  const unitAliases = options?.unitAliases || COMMON_FOOD_UNIT_ALIASES;
  const segments = splitFoodTextSegments(text);

  return segments.map((segment) => {
    const normalized = normalizeFoodText(segment);
    const tokens = normalized.split(' ').filter(Boolean);
    let quantity = 1;
    let unit = defaultUnit;
    let start = 0;
    let end = tokens.length;

    const compactUnit = (token: string): { quantity: number; unit: string } | null => {
      const match = token.match(/^(\d+(?:\.\d+)?)([a-z]+)$/);
      if (!match) {
        return null;
      }
      const parsedQuantity = asNumber(match[1]);
      const parsedUnit = unitAliases[match[2]];
      if (!parsedQuantity || parsedQuantity <= 0 || !parsedUnit) {
        return null;
      }
      return { quantity: parsedQuantity, unit: parsedUnit };
    };

    if (start < end && /^\d+(?:\.\d+)?$/.test(tokens[start])) {
      quantity = Number(tokens[start]);
      start += 1;
      if (start < end && unitAliases[tokens[start]]) {
        unit = unitAliases[tokens[start]];
        start += 1;
      }
    } else if (start < end) {
      const compact = compactUnit(tokens[start]);
      if (compact) {
        quantity = compact.quantity;
        unit = compact.unit;
        start += 1;
      }
    }

    if (start < end) {
      if (end - start >= 2 && /^\d+(?:\.\d+)?$/.test(tokens[end - 2]) && unitAliases[tokens[end - 1]]) {
        quantity = Number(tokens[end - 2]);
        unit = unitAliases[tokens[end - 1]];
        end -= 2;
      } else {
        const compact = compactUnit(tokens[end - 1]);
        if (compact) {
          quantity = compact.quantity;
          unit = compact.unit;
          end -= 1;
        }
      }
    }

    const queryTokens = tokens.slice(start, end);
    const query = queryTokens.join(' ').trim() || normalized;
    return {
      rawSegment: segment,
      query,
      quantity: Number.isFinite(quantity) && quantity > 0 ? quantity : 1,
      unit
    };
  });
}
