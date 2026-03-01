export type FoodSegmentSplitMode = 'balanced' | 'aggressive' | 'conservative';

const CONJUNCTION_SPLIT_REGEX = /\s+(?:and)\s+|\s*&\s*|\s*\+\s*/i;
const CONJUNCTION_GLOBAL_REGEX = /\s+(?:and)\s+|\s*&\s*|\s*\+\s*/gi;
const QUANTITY_REGEX = /\b\d+(?:\.\d+)?\b/;
const UNIT_REGEX =
  /\b(cup|cups|oz|ounce|ounces|g|gram|grams|kg|ml|tsp|tbsp|tablespoon|tablespoons|teaspoon|teaspoons|slice|slices|piece|pieces|serving|servings|can|cans|bottle|bottles|lb|lbs|pound|pounds)\b/i;

const PROTECTED_PHRASES = new Set([
  'mac and cheese',
  'fish and chips',
  'peanut butter and jelly',
  'cookies and cream',
  'ham and cheese',
  'salt and pepper',
  'half and half',
  'surf and turf'
]);

const DISH_HINT_TOKENS = new Set([
  'sandwich',
  'burger',
  'pizza',
  'pasta',
  'salad',
  'bowl',
  'wrap',
  'taco',
  'burrito',
  'omelet',
  'omelette',
  'soup',
  'stew',
  'curry',
  'risotto',
  'noodles',
  'ramen',
  'lasagna'
]);

function normalize(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}

function tokenCount(text: string): number {
  return normalize(text).split(' ').filter(Boolean).length;
}

function containsProtectedPhrase(segment: string): boolean {
  const normalized = normalize(segment);
  for (const phrase of PROTECTED_PHRASES) {
    if (normalized.includes(phrase)) {
      return true;
    }
  }
  return false;
}

function hasDishHint(segment: string): boolean {
  const tokens = normalize(segment).split(' ').filter(Boolean);
  return tokens.some((token) => DISH_HINT_TOKENS.has(token));
}

function hasQuantityOrUnit(segment: string): boolean {
  return QUANTITY_REGEX.test(segment) || UNIT_REGEX.test(segment);
}

function shouldSplitConjunctionBalanced(segment: string, parts: string[]): boolean {
  if (parts.length < 2) {
    return false;
  }
  if (containsProtectedPhrase(segment)) {
    return false;
  }
  if (hasDishHint(segment)) {
    return false;
  }

  const explicitAmountInPart = parts.some((part) => hasQuantityOrUnit(part));
  if (explicitAmountInPart) {
    return true;
  }

  // Allow simple list-style phrases such as "eggs and toast".
  const allShortParts = parts.every((part) => tokenCount(part) > 0 && tokenCount(part) <= 3);
  return allShortParts;
}

function shouldSplitConjunctionConservative(segment: string, parts: string[]): boolean {
  if (parts.length < 2) {
    return false;
  }
  if (containsProtectedPhrase(segment)) {
    return false;
  }
  // Conservative mode requires explicit quantity/unit signal.
  return parts.some((part) => hasQuantityOrUnit(part));
}

function splitOneSegment(segment: string, mode: FoodSegmentSplitMode): string[] {
  const trimmed = segment.trim();
  if (!trimmed) {
    return [];
  }

  if (!CONJUNCTION_SPLIT_REGEX.test(trimmed)) {
    return [trimmed];
  }

  const parts = trimmed
    .split(CONJUNCTION_GLOBAL_REGEX)
    .map((part) => part.trim())
    .filter(Boolean);

  if (parts.length < 2) {
    return [trimmed];
  }

  if (mode === 'aggressive') {
    return parts;
  }

  if (mode === 'conservative') {
    return shouldSplitConjunctionConservative(trimmed, parts) ? parts : [trimmed];
  }

  return shouldSplitConjunctionBalanced(trimmed, parts) ? parts : [trimmed];
}

export function splitFoodTextSegments(inputText: string, mode: FoodSegmentSplitMode = 'balanced'): string[] {
  const baseSegments = inputText
    .split(/[,\n;]+/)
    .map((segment) => segment.trim())
    .filter(Boolean);

  if (baseSegments.length === 0) {
    return [];
  }

  return baseSegments.flatMap((segment) => splitOneSegment(segment, mode));
}
