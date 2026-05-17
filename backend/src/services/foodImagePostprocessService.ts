import type { ParseResult, ParsedItem } from './deterministicParser.js';

export type FoodImagePostprocessContext = {
  extractedText?: string;
  assumptions?: string[];
  imageType?: string;
  visibleComponents?: Array<{ name: string; category?: string; portionHint?: string }>;
  mergeAliasDuplicates?: boolean;
};

type Candidate = {
  item: ParsedItem;
  groupKey: string;
  displayName: string | null;
  score: number;
  index: number;
};

type CompoundCollapse = {
  item: ParsedItem;
  consumedIndexes: Set<number>;
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

function titleCase(value: string): string {
  return value
    .split(' ')
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
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

function sumItems(items: ParsedItem[], field: 'grams' | 'calories' | 'protein' | 'carbs' | 'fat'): number {
  return round(items.reduce((sum, item) => sum + nonNegative(item[field]), 0), 1);
}

function averageConfidence(items: ParsedItem[]): number {
  if (items.length === 0) return 0.75;
  return round(
    items.reduce((sum, item) => sum + Math.min(1, Math.max(0, item.matchConfidence || 0.75)), 0) / items.length,
    2
  );
}

function appendDetectedDetail(explanation: string | undefined, detail: string): string {
  const base = explanation?.trim();
  return base ? `${base} ${detail}` : detail;
}

function mergeNutritionIntoParent(parent: ParsedItem, additions: ParsedItem[], displayName: string): ParsedItem {
  const quantity = Math.max(nonNegative(parent.quantity), 0.0001);
  const grams = round(nonNegative(parent.grams) + sumItems(additions, 'grams'), 1);

  return {
    ...parent,
    name: displayName,
    foodDescription: displayName,
    grams,
    gramsPerUnit: grams > 0 ? round(grams / quantity, 4) : parent.gramsPerUnit,
    calories: round(nonNegative(parent.calories) + sumItems(additions, 'calories'), 1),
    protein: round(nonNegative(parent.protein) + sumItems(additions, 'protein'), 1),
    carbs: round(nonNegative(parent.carbs) + sumItems(additions, 'carbs'), 1),
    fat: round(nonNegative(parent.fat) + sumItems(additions, 'fat'), 1),
    matchConfidence: averageConfidence([parent, ...additions]),
    explanation: appendDetectedDetail(
      parent.explanation,
      'Merged visible toppings into the main dish instead of logging them as separate foods.'
    )
  };
}

function collapsePizzaFragments(items: ParsedItem[]): CompoundCollapse | null {
  const candidates = items
    .map((item, index) => ({ item, index, key: normalizeKey(item.name) }))
    .filter((candidate) => /\bpizza\b/.test(candidate.key));

  if (candidates.length === 0) return null;

  const parent = candidates.sort((left, right) => {
    const specificity = (key: string): number => (/\b(small|medium|large|personal|whole|slice)\b/.test(key) ? 1 : 0);
    return (
      specificity(right.key) - specificity(left.key) ||
      nonNegative(right.item.calories) - nonNegative(left.item.calories) ||
      right.item.matchConfidence - left.item.matchConfidence
    );
  })[0];

  const consumedIndexes = new Set<number>([parent.index]);
  const toppingNames: string[] = [];
  const toppingPattern =
    /\b(cheese|mozzarella|olive|olives|jalapeno|jalapenos|pepperoni|corn|mushroom|mushrooms|onion|onions|pepper|peppers|tomato|tomatoes|sauce|basil|pineapple)\b/;

  items.forEach((item, index) => {
    if (index === parent.index) return;
    const key = normalizeKey(item.name);
    if (/\bpizza\b/.test(key) || toppingPattern.test(key)) {
      consumedIndexes.add(index);
      if (!/\bpizza\b/.test(key)) toppingNames.push(titleCase(key));
    }
  });

  if (consumedIndexes.size <= 1) return null;

  const toppings = Array.from(new Set(toppingNames)).slice(0, 6);
  return {
    consumedIndexes,
    item: {
      ...parent.item,
      name: parent.item.name.trim() || 'Pizza',
      foodDescription: toppings.length ? `${parent.item.name.trim() || 'Pizza'} with ${toppings.join(', ')}` : parent.item.foodDescription,
      explanation: appendDetectedDetail(
        parent.item.explanation,
        toppings.length
          ? `Detected toppings: ${toppings.join(', ')}.`
          : 'Merged duplicate pizza detections into one item.'
      )
    }
  };
}

function bestIndianBowlParent(items: ParsedItem[]): { item: ParsedItem; index: number; displayName: string } | null {
  const candidates = items
    .map((item, index) => ({ item, index, key: normalizeKey(item.name) }))
    .filter((candidate) => /\b(upma|poha|savory bowl|savoury bowl|semolina|rice semolina|cooked semolina)\b/.test(candidate.key));

  if (candidates.length === 0) return null;

  const best = candidates.sort((left, right) => {
    const rank = (key: string): number => {
      if (/\bupma\b/.test(key)) return 5;
      if (/\bpoha\b/.test(key)) return 4;
      if (/\bsemolina\b/.test(key)) return 3;
      if (/\bsavory bowl|savoury bowl\b/.test(key)) return 1;
      return 0;
    };
    return rank(right.key) - rank(left.key) || right.item.matchConfidence - left.item.matchConfidence;
  })[0];

  let displayName = best.item.name.trim() || 'Indian savory bowl';
  if (/\bupma|semolina\b/.test(best.key)) displayName = 'Upma';
  if (/\bpoha\b/.test(best.key)) displayName = 'Poha';
  if (/\bsavory bowl|savoury bowl\b/.test(best.key)) displayName = 'Indian savory bowl';

  return { item: best.item, index: best.index, displayName };
}

function collapseIndianSavoryBowlFragments(
  items: ParsedItem[],
  context?: FoodImagePostprocessContext
): CompoundCollapse | null {
  const text = normalizeKey(`${contextKey(context)} ${items.map((item) => item.name).join(' ')}`);
  if (!containsAny(text, ['upma', 'poha', 'sev', 'semolina', 'savory bowl', 'savoury bowl'])) return null;

  const parent = bestIndianBowlParent(items);
  if (!parent) return null;

  const consumedIndexes = new Set<number>([parent.index]);
  const additions: ParsedItem[] = [];
  let hasSev = false;

  items.forEach((item, index) => {
    if (index === parent.index) return;
    const key = normalizeKey(item.name);
    const isAlias = /\b(upma|poha|savory bowl|savoury bowl|semolina|rice semolina grains|cooked semolina grains|white rice|rice)\b/.test(key);
    const isSev = /\b(sev|bhujiya|namkeen)\b/.test(key);
    const isGarnish = /\b(onion|cilantro|coriander|tomato|curry leaves|herb|herbs)\b/.test(key);

    if (isAlias || isSev || isGarnish) {
      consumedIndexes.add(index);
      if (isSev) {
        hasSev = true;
        additions.push(item);
      }
    }
  });

  if (consumedIndexes.size <= 1) return null;

  const displayName = hasSev ? `${parent.displayName} with sev` : parent.displayName;
  return {
    consumedIndexes,
    item: mergeNutritionIntoParent(parent.item, additions, displayName)
  };
}

function collapseWingsPlatterFragments(items: ParsedItem[]): CompoundCollapse | null {
  const wing = items
    .map((item, index) => ({ item, index, key: normalizeKey(item.name) }))
    .find((candidate) => /\b(chicken\s+)?wings?\b/.test(candidate.key) && !/\bplatter\b/.test(candidate.key));
  if (!wing) return null;

  const consumedIndexes = new Set<number>([wing.index]);
  items.forEach((item, index) => {
    if (index === wing.index) return;
    const key = normalizeKey(item.name);
    if (/\b(chicken\s+)?wings?\s+platter\b/.test(key)) consumedIndexes.add(index);
  });

  if (consumedIndexes.size <= 1) return null;
  return {
    consumedIndexes,
    item: {
      ...wing.item,
      name: wing.item.name.trim() || 'Chicken wings',
      explanation: appendDetectedDetail(wing.item.explanation, 'Merged duplicate wings platter detection into the wings item.')
    }
  };
}

function collapseCompoundDishFragments(items: ParsedItem[], context?: FoodImagePostprocessContext): ParsedItem[] {
  if (items.length <= 1) return items;

  const collapses = [
    collapsePizzaFragments(items),
    collapseIndianSavoryBowlFragments(items, context),
    collapseWingsPlatterFragments(items)
  ].filter((collapse): collapse is CompoundCollapse => collapse !== null);

  if (collapses.length === 0) return items;

  const consumed = new Set<number>();
  const replacements = new Map<number, ParsedItem>();

  collapses.forEach((collapse) => {
    const indexes = [...collapse.consumedIndexes].sort((left, right) => left - right);
    if (indexes.some((index) => consumed.has(index))) return;
    indexes.forEach((index) => consumed.add(index));
    replacements.set(indexes[0], collapse.item);
  });

  return items.flatMap((item, index) => {
    const replacement = replacements.get(index);
    if (replacement) return [replacement];
    if (consumed.has(index)) return [];
    return [item];
  });
}

function shouldDropGenericContainer(item: ParsedItem, allItems: ParsedItem[]): boolean {
  if (allItems.length <= 1) return false;
  const key = normalizeKey(item.name);
  if (!/\b(plate|platter|tray|bowl|meal)\b/.test(key)) return false;
  if (/\b(pizza|protein|smoothie|shake|soup|salad)\b/.test(key)) return false;

  const otherNames = normalizeKey(allItems.filter((candidate) => candidate !== item).map((candidate) => candidate.name).join(' '));
  if (/\b(dinner plate|south indian plate|indian savory bowl|savory bowl|savoury bowl|meal plate|food plate)\b/.test(key)) {
    return otherNames.length > 0;
  }
  if (/\bchicken wings platter\b/.test(key)) {
    return /\bwings?\b/.test(otherNames);
  }
  return false;
}

function canonicalGroupForItem(item: ParsedItem, allItems: ParsedItem[], context?: FoodImagePostprocessContext): {
  groupKey: string;
  displayName: string | null;
} {
  const key = normalizeKey(item.name);
  const contextIsIndianSavory = indianSavoryContext(allItems, context);
  const mergeAliasDuplicates = context?.mergeAliasDuplicates !== false;

  if (
    mergeAliasDuplicates &&
    (/\b(methi|fenugreek)\s+(paratha|flatbread|thepla)\b/.test(key) || key === 'thepla' || key === 'methi thepla')
  ) {
    return { groupKey: 'methi_flatbread', displayName: key.includes('thepla') ? 'Thepla' : 'Methi paratha' };
  }
  if (/\b(green|mint|cilantro|coriander)\s+chutney\b/.test(key) || (key === 'green' && contextIsIndianSavory)) {
    return { groupKey: 'green_chutney', displayName: 'Green chutney' };
  }
  if (
    /\bmango\s+(chutney|pickle|sauce)\b/.test(key) ||
    (key === 'mango' && contextIsIndianSavory) ||
    (key === 'chutney' && /\bmango\s+(chutney|pickle|sauce)\b/.test(contextKey(context)))
  ) {
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
  const compoundCollapsed = collapseCompoundDishFragments(productCollapsed, context);
  const selected = new Map<string, Candidate>();

  compoundCollapsed.forEach((item, index) => {
    if (shouldDropGenericContainer(item, compoundCollapsed)) return;

    const canonical = canonicalGroupForItem(item, compoundCollapsed, context);
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
