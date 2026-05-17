import type { ParseResult, ParsedItem } from './deterministicParser.js';

export type FoodImagePostprocessContext = {
  extractedText?: string;
  assumptions?: string[];
  imageType?: string;
  visibleComponents?: Array<{ name: string; category?: string; portionHint?: string }>;
};

type Candidate = {
  item: ParsedItem;
  groupKey: string;
  displayName: string | null;
  score: number;
  index: number;
};

const PRODUCT_WORDS = new Set([
  'bar',
  'bars',
  'bottle',
  'can',
  'carton',
  'drink',
  'shake',
  'beverage',
  'soda',
  'cola',
  'coke',
  'water',
  'protein',
  'rxbar',
  'quest',
  'chobani',
  'premier',
  'fairlife',
  'ensure',
  'boost',
  'poppi',
  'spindrift',
  'waterloo'
]);

const FLAVOR_FRAGMENT_KEYS = new Set([
  'berry',
  'berries',
  'mixed berry',
  'mixed berries',
  'vanilla',
  'mixed berry vanilla',
  'fruit',
  'fruits',
  'flavor',
  'flavored',
  'flavoured',
  'greek yogurt',
  'yogurt',
  'curd'
]);

function round(value: number, digits = 1): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function nonNegative(value: number): number {
  return Number.isFinite(value) && value > 0 ? value : 0;
}

function normalizeKey(value: string): string {
  return value
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/\b(bati)\b/g, 'baati')
    .replace(/\b(daal)\b/g, 'dal')
    .replace(/\b(aloo)\b/g, 'potato')
    .replace(/\b(green sauce|mint sauce|cilantro sauce)\b/g, 'green chutney')
    .replace(/\b(red onion|onion slices|sliced onions)\b/g, 'onion')
    .replace(/\b(protien)\b/g, 'protein')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function words(key: string): Set<string> {
  return new Set(key.split(' ').filter(Boolean));
}

function containsAny(key: string, values: string[]): boolean {
  return values.some((value) => key.includes(value));
}

function contextKey(context?: FoodImagePostprocessContext): string {
  return normalizeKey(
    [
      context?.extractedText ?? '',
      context?.imageType ?? '',
      ...(context?.assumptions ?? []),
      ...(context?.visibleComponents ?? []).flatMap((component) => [
        component.name,
        component.category ?? '',
        component.portionHint ?? ''
      ])
    ].join(' ')
  );
}

function indianSavoryContext(items: ParsedItem[], context?: FoodImagePostprocessContext): boolean {
  const text = normalizeKey(`${contextKey(context)} ${items.map((item) => item.name).join(' ')}`);
  return containsAny(text, [
    'thali',
    'tray',
    'dal',
    'baati',
    'bati',
    'sabzi',
    'chutney',
    'paratha',
    'thepla',
    'roti',
    'chapati',
    'curry',
    'onion',
    'pickle'
  ]);
}

function productScore(item: ParsedItem, context?: FoodImagePostprocessContext): number {
  const key = normalizeKey(`${item.name} ${item.unit} ${item.foodDescription ?? ''} ${item.explanation ?? ''} ${contextKey(context)}`);
  const tokenSet = words(key);
  let score = 0;

  for (const token of tokenSet) {
    if (PRODUCT_WORDS.has(token)) score += 12;
  }
  if (/\bprotein\s+(drink|shake|beverage)\b/.test(key)) score += 80;
  if (/\b(protein|nutrition|energy|snack)\s+bar\b/.test(key)) score += 75;
  if (/\b(rxbar|quest|chobani|premier protein|fairlife|ensure|boost)\b/.test(key)) score += 45;
  if (/\b(diet coke|coca cola|cola|soda|poppi|spindrift|waterloo|sparkling water)\b/.test(key)) score += 55;
  if (/\b(bottle|can|bar|carton|package|packaged|nutrition facts|nutrition label)\b/.test(key)) score += 25;
  if (/\b(smoothie|milkshake)\b/.test(key)) score += 20;

  return score;
}

function isLikelyProductParent(item: ParsedItem, context?: FoodImagePostprocessContext): boolean {
  return productScore(item, context) >= 70;
}

function fragmentCoveredByProduct(fragment: ParsedItem, product: ParsedItem): boolean {
  const fragmentKey = normalizeKey(fragment.name);
  const productKey = normalizeKey(`${product.name} ${product.foodDescription ?? ''}`);
  if (!fragmentKey || !productKey) return false;
  if (productKey.includes(fragmentKey) || fragmentKey.includes(productKey)) return true;
  if (FLAVOR_FRAGMENT_KEYS.has(fragmentKey)) return true;

  const fragmentWords = [...words(fragmentKey)].filter((word) => word.length > 2);
  if (fragmentWords.length > 0 && fragmentWords.every((word) => productKey.includes(word))) {
    return true;
  }

  if (/\b(protein|drink|shake|bar|bottle|can)\b/.test(productKey)) {
    return /\b(berry|berries|vanilla|chocolate|strawberry|yogurt|greek yogurt|fruit)\b/.test(fragmentKey);
  }

  return false;
}

function unrelatedToProduct(item: ParsedItem, product: ParsedItem): boolean {
  const key = normalizeKey(item.name);
  if (!key) return false;
  if (fragmentCoveredByProduct(item, product)) return false;
  return !/\b(label|nutrition facts|package|packaged|bottle|can|bar|drink|shake)\b/.test(key);
}

function collapseSingleProductFragments(items: ParsedItem[], context?: FoodImagePostprocessContext): ParsedItem[] {
  if (items.length <= 1) return items;

  const products = items
    .map((item, index) => ({ item, index, score: productScore(item, context) }))
    .filter((candidate) => candidate.score >= 70)
    .sort((left, right) => right.score - left.score || right.item.matchConfidence - left.item.matchConfidence);

  if (products.length === 0) return items;

  const best = products[0];
  const unrelated = items.filter((item, index) => index !== best.index && unrelatedToProduct(item, best.item));

  // If there is a clearly separate food next to the product, keep the full meal.
  if (unrelated.length > 0) return items;

  return [
    {
      ...best.item,
      name: best.item.name.trim(),
      foodDescription: best.item.foodDescription || best.item.name,
      explanation:
        best.item.explanation ||
        'Treated the visible packaged product as one item instead of splitting flavor words into ingredients.'
    }
  ];
}

function canonicalGroupForItem(item: ParsedItem, allItems: ParsedItem[], context?: FoodImagePostprocessContext): {
  groupKey: string;
  displayName: string | null;
} {
  const key = normalizeKey(item.name);
  const contextIsIndianSavory = indianSavoryContext(allItems, context);

  if (/\b(methi|fenugreek)\s+(paratha|flatbread|thepla)\b/.test(key) || key === 'thepla' || key === 'methi thepla') {
    return { groupKey: 'methi_flatbread', displayName: key.includes('thepla') ? 'Thepla' : 'Methi paratha' };
  }
  if (/\b(green|mint|cilantro|coriander)\s+chutney\b/.test(key) || (key === 'green' && contextIsIndianSavory)) {
    return { groupKey: 'green_chutney', displayName: 'Green chutney' };
  }
  if (/\bmango\s+(chutney|pickle|sauce)\b/.test(key) || (key === 'mango' && contextIsIndianSavory)) {
    return { groupKey: 'mango_chutney', displayName: 'Mango chutney' };
  }
  if (/\bpotato\s+(sabzi|curry|vegetable|vegetables)\b/.test(key) || (key === 'potato' && contextIsIndianSavory)) {
    return { groupKey: 'potato_sabzi', displayName: 'Potato sabzi' };
  }
  if (key === 'churma' || /\b(churma|dry chutney|chutney powder)\s*(powder)?\b/.test(key)) {
    return { groupKey: 'churma_powder', displayName: 'Churma powder' };
  }
  if (/\b(red|sliced)?\s*onion\b/.test(key)) {
    return { groupKey: 'onion', displayName: 'Onion' };
  }
  if (/\b(dal|lentil curry)\b/.test(key)) {
    return { groupKey: 'dal', displayName: key === 'dal' ? 'Dal' : null };
  }
  if (/\bbaati\b/.test(key)) {
    return { groupKey: 'baati', displayName: 'Baati' };
  }
  if (/\bmixed\s+vegetables?\b|\bvegetable\s+sabzi\b/.test(key)) {
    return { groupKey: 'mixed_vegetables', displayName: 'Mixed vegetables' };
  }

  return { groupKey: key, displayName: null };
}

function itemSpecificityScore(item: ParsedItem, displayName: string | null, context?: FoodImagePostprocessContext): number {
  const key = normalizeKey(item.name);
  let score = key.length;
  score += Math.min(1, Math.max(0, item.matchConfidence || 0)) * 20;
  score += productScore(item, context) / 10;
  score += item.calories > 0 || item.protein > 0 || item.carbs > 0 || item.fat > 0 ? 10 : 0;
  if (displayName && normalizeKey(item.name) === normalizeKey(displayName)) score += 8;
  if (/\b(chutney|sabzi|powder|paratha|flatbread|thepla|baati|protein drink|protein bar)\b/.test(key)) score += 12;
  if (/^(green|red|white|brown|yellow|mango|potato|chutney|sauce|vegetable|vegetables)$/.test(key)) score -= 40;
  return score;
}

function rebuildTotals(items: ParsedItem[]): ParseResult['totals'] {
  return {
    calories: round(items.reduce((sum, item) => sum + nonNegative(item.calories), 0), 1),
    protein: round(items.reduce((sum, item) => sum + nonNegative(item.protein), 0), 1),
    carbs: round(items.reduce((sum, item) => sum + nonNegative(item.carbs), 0), 1),
    fat: round(items.reduce((sum, item) => sum + nonNegative(item.fat), 0), 1)
  };
}

export function postProcessFoodImageResult(result: ParseResult, context?: FoodImagePostprocessContext): ParseResult {
  if (result.items.length <= 0) return result;

  const productCollapsed = collapseSingleProductFragments(result.items, context);
  const selected = new Map<string, Candidate>();

  productCollapsed.forEach((item, index) => {
    const canonical = canonicalGroupForItem(item, productCollapsed, context);
    if (!canonical.groupKey || canonical.groupKey.length < 3) return;

    const candidate: Candidate = {
      item,
      groupKey: canonical.groupKey,
      displayName: canonical.displayName,
      score: itemSpecificityScore(item, canonical.displayName, context),
      index
    };
    const existing = selected.get(candidate.groupKey);
    if (!existing || candidate.score > existing.score) {
      selected.set(candidate.groupKey, candidate);
    }
  });

  const items = [...selected.values()]
    .sort((left, right) => left.index - right.index)
    .map(({ item, displayName }) => {
      if (!displayName || normalizeKey(displayName) === normalizeKey(item.name)) {
        return item;
      }
      return {
        ...item,
        name: displayName,
        foodDescription: item.foodDescription && normalizeKey(item.foodDescription) !== normalizeKey(item.name)
          ? item.foodDescription
          : displayName
      };
    });

  if (items.length === 0) return result;

  return {
    ...result,
    items,
    totals: rebuildTotals(items)
  };
}
