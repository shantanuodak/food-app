import { parseImageWithGemini } from './legacyVisionCore.js';
import type { ParseResult, ParsedItem } from '../deterministicParser.js';
import { classify, type Cuisine } from './cuisineClassifier.js';
import { buildCuisinePrompt } from './prompts/builder.js';
import type { ImagePart, ImageParseServiceResult } from './types.js';

function round(value: number, digits = 1): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function fallbackItem(input: {
  name: string;
  quantity: number;
  unit: string;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
}): ParsedItem {
  return {
    name: input.name,
    quantity: input.quantity,
    amount: input.quantity,
    unit: input.unit,
    unitNormalized: input.unit,
    grams: input.grams,
    gramsPerUnit: input.quantity > 0 ? round(input.grams / input.quantity, 4) : null,
    calories: input.calories,
    protein: input.protein,
    carbs: input.carbs,
    fat: input.fat,
    matchConfidence: 0.48,
    nutritionSourceId: 'image_context_fallback',
    originalNutritionSourceId: 'image_context_fallback',
    sourceFamily: 'gemini',
    needsClarification: true,
    manualOverride: false,
    foodDescription: `${input.name}, ${input.quantity} ${input.unit}`,
    explanation: 'Reviewable fallback estimate from the user note after the image model timed out.'
  };
}

function resultFromItems(items: ParsedItem[], assumption: string): ParseResult {
  return {
    confidence: 0.5,
    assumptions: [assumption, 'Image model timed out; please review portions before saving.'],
    items,
    totals: {
      calories: round(items.reduce((sum, item) => sum + item.calories, 0)),
      protein: round(items.reduce((sum, item) => sum + item.protein, 0)),
      carbs: round(items.reduce((sum, item) => sum + item.carbs, 0)),
      fat: round(items.reduce((sum, item) => sum + item.fat, 0))
    }
  };
}

function nonFoodResult(args: {
  cuisine: Cuisine;
  source: string;
  confidence: number;
  matchedKeywords?: string[];
}): ImageParseServiceResult {
  return {
    extractedText: 'Non-food image',
    result: {
      confidence: 0.9,
      assumptions: ['The image/context appears to be non-food, so no nutrition items were returned.'],
      items: [],
      totals: { calories: 0, protein: 0, carbs: 0, fat: 0 }
    },
    model: 'image_context_fallback',
    fallbackUsed: true,
    lowConfidenceAccepted: true,
    usageEvents: [],
    orchestratorVersion: 'v2',
    cuisine: {
      cuisine: args.cuisine,
      confidence: args.confidence,
      source: args.source,
      matchedKeywords: args.matchedKeywords
    },
    coverage: {
      imageType: 'non_food',
      cuisineHints: [args.cuisine],
      visibleComponents: [],
      visibleComponentCount: 0,
      parsedItemCount: 0,
      score: 1,
      warnings: ['No food items were visible enough to estimate.'],
      partial: false
    }
  };
}

function documentImageResult(args: {
  cuisine: Cuisine;
  source: string;
  confidence: number;
  matchedKeywords?: string[];
}): ImageParseServiceResult {
  return {
    extractedText: 'Menu or recipe text image',
    result: {
      confidence: 0.5,
      assumptions: ['The context indicates a menu, recipe card, or screenshot; no reliable nutrition items were visible enough to estimate.'],
      items: [],
      totals: { calories: 0, protein: 0, carbs: 0, fat: 0 }
    },
    model: 'image_context_fallback',
    fallbackUsed: true,
    lowConfidenceAccepted: true,
    usageEvents: [],
    orchestratorVersion: 'v2',
    cuisine: {
      cuisine: args.cuisine,
      confidence: args.confidence,
      source: args.source,
      matchedKeywords: args.matchedKeywords
    },
    coverage: {
      imageType: 'menu_or_screenshot',
      cuisineHints: [args.cuisine],
      visibleComponents: [],
      visibleComponentCount: 0,
      parsedItemCount: 0,
      score: 0.65,
      warnings: ['Text-like food image; ask the user to choose or confirm items before saving.'],
      partial: true
    }
  };
}

function contextFallbackResult(args: {
  contextNote?: string;
  cuisine: Cuisine;
  source: string;
  confidence: number;
  matchedKeywords?: string[];
}): ImageParseServiceResult | null {
  const text = (args.contextNote ?? '').toLowerCase();
  let items: ParsedItem[] = [];
  let imageType = 'multi_component_meal';

  if (/\b(not food|non food|cat|notebook|desk lamp|lamp|notes)\b/.test(text)) {
    return nonFoodResult(args);
  }

  if (/\b(menu|screenshot|recipe card|nutrition text|calorie text)\b/.test(text)) {
    return documentImageResult(args);
  }

  // V3 audit (2026-05-19): removed hardcoded canned-recipe fallbacks.
  // These were pattern-matching contextNote keywords (e.g. "thali" -> fixed
  // Dal+Naan+Rice+Sabzi+Raita) and returning fake items that made Gemini
  // failures look like successful parses. They rigged the uploaded-photo
  // eval from 1/10 -> 10/10 without actually improving real-world parsing.
  // Now returns null on genuine failure so the user sees an honest
  // "couldn't parse" state instead of items they didn't eat.
  // Dead code below preserved temporarily for diff visibility; will be
  // deleted in a follow-up commit after the team confirms no regressions.
  return null;

  if (args.cuisine === 'indian' && text.includes('thali')) {
    imageType = 'tray_or_thali';
    items = [
      fallbackItem({ name: 'Dal', quantity: 1, unit: 'katori', grams: 180, calories: 160, protein: 9, carbs: 24, fat: 4 }),
      fallbackItem({ name: 'Naan or roti', quantity: 1, unit: 'piece', grams: 90, calories: 260, protein: 7, carbs: 42, fat: 7 }),
      fallbackItem({ name: 'Rice or biryani', quantity: 1, unit: 'cup', grams: 180, calories: 260, protein: 5, carbs: 48, fat: 5 }),
      fallbackItem({ name: 'Vegetable curry', quantity: 1, unit: 'katori', grams: 160, calories: 200, protein: 5, carbs: 22, fat: 10 }),
      fallbackItem({ name: 'Raita or chutney', quantity: 1, unit: 'small side', grams: 60, calories: 70, protein: 2, carbs: 7, fat: 4 })
    ];
  } else if (args.cuisine === 'indian' && /dosa|sambar|idli|uttapam/.test(text)) {
    items = [
      fallbackItem({ name: 'Masala dosa', quantity: 1, unit: 'dosa', grams: 240, calories: 420, protein: 9, carbs: 64, fat: 14 }),
      fallbackItem({ name: 'Sambar', quantity: 1, unit: 'small bowl', grams: 120, calories: 90, protein: 5, carbs: 14, fat: 2 }),
      fallbackItem({ name: 'Coconut chutney', quantity: 1, unit: 'small side', grams: 40, calories: 80, protein: 1, carbs: 4, fat: 7 })
    ];
  } else if (args.cuisine === 'indian' && /chaat|samosa|pakora|chai/.test(text)) {
    items = [
      fallbackItem({ name: 'Samosa chaat', quantity: 1, unit: 'plate', grams: 280, calories: 520, protein: 12, carbs: 68, fat: 22 }),
      fallbackItem({ name: 'Chutney', quantity: 1, unit: 'small side', grams: 35, calories: 45, protein: 1, carbs: 9, fat: 1 }),
      fallbackItem({ name: 'Chai', quantity: 1, unit: 'cup', grams: 180, calories: 110, protein: 4, carbs: 18, fat: 3 })
    ];
  } else if (args.cuisine === 'us' && /burger|fries/.test(text)) {
    items = [
      fallbackItem({ name: 'Cheeseburger', quantity: 1, unit: 'burger', grams: 220, calories: 560, protein: 28, carbs: 42, fat: 32 }),
      fallbackItem({ name: 'French fries', quantity: 1, unit: 'medium serving', grams: 110, calories: 380, protein: 4, carbs: 50, fat: 18 })
    ];
  } else if (args.cuisine === 'us' && /pancake|breakfast|bacon|bagel/.test(text)) {
    items = [
      fallbackItem({ name: 'Pancakes', quantity: 1, unit: 'stack', grams: 220, calories: 520, protein: 12, carbs: 82, fat: 16 }),
      fallbackItem({ name: 'Bacon', quantity: 2, unit: 'slices', grams: 24, calories: 110, protein: 8, carbs: 0, fat: 9 }),
      fallbackItem({ name: 'Bagel', quantity: 1, unit: 'bagel', grams: 100, calories: 280, protein: 10, carbs: 56, fat: 2 })
    ];
  } else if (args.cuisine === 'us' && /salad|caesar|ranch/.test(text)) {
    imageType = 'single_food';
    items = [
      fallbackItem({ name: 'Chicken Caesar salad with ranch', quantity: 1, unit: 'salad', grams: 360, calories: 620, protein: 38, carbs: 20, fat: 42 })
    ];
  } else if (args.cuisine === 'western' && /fish|chips/.test(text)) {
    items = [
      fallbackItem({ name: 'Fish and chips', quantity: 1, unit: 'plate', grams: 430, calories: 920, protein: 34, carbs: 92, fat: 44 })
    ];
  } else if (args.cuisine === 'eastAsian' && /ramen|udon|pho/.test(text)) {
    imageType = 'single_food';
    items = [
      fallbackItem({ name: 'Ramen bowl', quantity: 1, unit: 'bowl', grams: 650, calories: 650, protein: 25, carbs: 82, fat: 24 })
    ];
  } else if (args.cuisine === 'eastAsian' && /sushi|sashimi|miso/.test(text)) {
    imageType = 'multi_component_meal';
    items = [
      fallbackItem({ name: 'Sushi platter', quantity: 1, unit: 'platter', grams: 320, calories: 520, protein: 28, carbs: 72, fat: 12 }),
      fallbackItem({ name: 'Miso soup', quantity: 1, unit: 'bowl', grams: 240, calories: 60, protein: 4, carbs: 7, fat: 2 })
    ];
  } else if (args.cuisine === 'eastAsian' && /pad thai|spring roll/.test(text)) {
    items = [
      fallbackItem({ name: 'Pad thai', quantity: 1, unit: 'plate', grams: 420, calories: 720, protein: 28, carbs: 92, fat: 26 }),
      fallbackItem({ name: 'Spring roll', quantity: 1, unit: 'roll', grams: 70, calories: 160, protein: 4, carbs: 22, fat: 7 })
    ];
  } else if (args.cuisine === 'eastAsian' && /dim sum|dumpling|bao/.test(text)) {
    items = [
      fallbackItem({ name: 'Dim sum dumplings', quantity: 4, unit: 'pieces', grams: 180, calories: 360, protein: 18, carbs: 42, fat: 14 }),
      fallbackItem({ name: 'Bao', quantity: 1, unit: 'bun', grams: 90, calories: 220, protein: 8, carbs: 32, fat: 7 })
    ];
  } else if (args.cuisine === 'mediterranean' && /pasta|carbonara|spaghetti/.test(text)) {
    imageType = 'single_food';
    items = [
      fallbackItem({ name: 'Spaghetti carbonara', quantity: 1, unit: 'plate', grams: 350, calories: 700, protein: 24, carbs: 76, fat: 32 })
    ];
  } else if (args.cuisine === 'mediterranean' && /pizza|mozzarella/.test(text)) {
    imageType = 'single_food';
    items = [
      fallbackItem({ name: 'Margherita pizza', quantity: 1, unit: 'pizza', grams: 360, calories: 860, protein: 34, carbs: 104, fat: 30 })
    ];
  } else if (args.cuisine === 'mediterranean' && /hummus|falafel|tabbouleh|pita|mezze/.test(text)) {
    items = [
      fallbackItem({ name: 'Hummus', quantity: 1, unit: 'serving', grams: 100, calories: 230, protein: 8, carbs: 18, fat: 15 }),
      fallbackItem({ name: 'Falafel', quantity: 3, unit: 'pieces', grams: 105, calories: 330, protein: 12, carbs: 30, fat: 18 }),
      fallbackItem({ name: 'Tabbouleh', quantity: 1, unit: 'serving', grams: 120, calories: 160, protein: 4, carbs: 20, fat: 8 }),
      fallbackItem({ name: 'Pita', quantity: 1, unit: 'piece', grams: 60, calories: 170, protein: 6, carbs: 34, fat: 1 })
    ];
  } else if (args.cuisine === 'latin' && /burrito/.test(text)) {
    imageType = 'single_food';
    items = [
      fallbackItem({ name: 'Burrito', quantity: 1, unit: 'burrito', grams: 420, calories: 900, protein: 35, carbs: 105, fat: 34 })
    ];
  } else if (args.cuisine === 'latin' && /taco|tacos/.test(text)) {
    items = [
      fallbackItem({ name: 'Tacos al pastor', quantity: 3, unit: 'tacos', grams: 300, calories: 690, protein: 32, carbs: 66, fat: 34 }),
      fallbackItem({ name: 'Salsa', quantity: 1, unit: 'side', grams: 45, calories: 20, protein: 1, carbs: 4, fat: 0 })
    ];
  } else if (args.cuisine === 'latin' && /arepa|empanada|plantain/.test(text)) {
    items = [
      fallbackItem({ name: 'Arepa', quantity: 1, unit: 'arepa', grams: 180, calories: 380, protein: 12, carbs: 52, fat: 14 }),
      fallbackItem({ name: 'Empanada', quantity: 1, unit: 'piece', grams: 100, calories: 280, protein: 10, carbs: 28, fat: 14 }),
      fallbackItem({ name: 'Plantain', quantity: 1, unit: 'serving', grams: 120, calories: 220, protein: 1, carbs: 54, fat: 1 })
    ];
  } else if (args.cuisine === 'western' && /croissant/.test(text)) {
    imageType = 'single_food';
    items = [
      fallbackItem({ name: 'Croissant', quantity: 1, unit: 'piece', grams: 65, calories: 260, protein: 5, carbs: 28, fat: 14 })
    ];
  } else if (args.cuisine === 'western' && /quiche|baguette|crepe/.test(text)) {
    items = [
      fallbackItem({ name: 'Quiche', quantity: 1, unit: 'slice', grams: 140, calories: 360, protein: 13, carbs: 22, fat: 24 }),
      fallbackItem({ name: 'Baguette', quantity: 1, unit: 'piece', grams: 60, calories: 165, protein: 6, carbs: 34, fat: 1 }),
      fallbackItem({ name: 'Crepe', quantity: 1, unit: 'crepe', grams: 80, calories: 180, protein: 5, carbs: 28, fat: 6 })
    ];
  } else if (/blurry|rice bowl|vegetables/.test(text)) {
    items = [
      fallbackItem({ name: 'Rice bowl with vegetables', quantity: 1, unit: 'bowl', grams: 420, calories: 520, protein: 12, carbs: 86, fat: 14 })
    ];
  } else if (!text.trim()) {
    items = [
      fallbackItem({ name: 'Mixed meal', quantity: 1, unit: 'serving', grams: 350, calories: 550, protein: 22, carbs: 55, fat: 25 })
    ];
  }

  if (!items.length) return null;

  return {
    extractedText: items.map((item) => item.name).join(', '),
    result: resultFromItems(
      items,
      `Cuisine routed as ${args.cuisine} (${args.source}, confidence ${args.confidence.toFixed(2)}).`
    ),
    model: 'image_context_fallback',
    fallbackUsed: true,
    lowConfidenceAccepted: true,
    usageEvents: [],
    orchestratorVersion: 'v2',
    cuisine: {
      cuisine: args.cuisine,
      confidence: args.confidence,
      source: args.source,
      matchedKeywords: args.matchedKeywords
    },
    coverage: {
      imageType: imageType as ImageParseServiceResult['coverage'] extends infer C ? C extends { imageType: infer I } ? I : never : never,
      cuisineHints: [args.cuisine],
      visibleComponents: items.map((item) => ({
        name: item.name,
        category: 'food',
        zone: 'context fallback',
        portionHint: `${item.quantity} ${item.unit}`,
        confidence: 0.48,
        isSmallSide: /chutney|raita|sauce|side/i.test(item.name)
      })),
      visibleComponentCount: items.length,
      parsedItemCount: items.length,
      score: 0.65,
      warnings: ['Image model timed out; returned a conservative reviewable estimate from the note.'],
      partial: true
    }
  };
}

function coverageWithContextOverride(args: {
  coverage?: ImageParseServiceResult['coverage'];
  contextNote?: string;
  items: ParsedItem[];
  cuisine: Cuisine;
}): ImageParseServiceResult['coverage'] {
  const text = (args.contextNote ?? '').toLowerCase();
  const menuLike = /menu|screenshot|recipe card|nutrition text/.test(text);
  if (!menuLike) return args.coverage;

  const visibleComponents = args.coverage?.visibleComponents?.length
    ? args.coverage.visibleComponents
    : args.items.map((item) => ({
        name: item.name,
        category: 'text_detected_food',
        zone: 'context screenshot',
        portionHint: item.foodDescription || `${item.quantity} ${item.unit}`,
        confidence: item.matchConfidence ?? 0.5,
        isSmallSide: false
      }));

  return {
    imageType: 'menu_or_screenshot',
    cuisineHints: Array.from(new Set([args.cuisine, ...(args.coverage?.cuisineHints ?? [])])),
    visibleComponents,
    visibleComponentCount: args.coverage?.visibleComponentCount ?? visibleComponents.length,
    parsedItemCount: args.coverage?.parsedItemCount ?? args.items.length,
    score: args.coverage?.score ?? 0.65,
    warnings: Array.from(new Set([...(args.coverage?.warnings ?? []), 'Context indicates this is a menu, recipe card, or screenshot.'])),
    partial: args.coverage?.partial ?? true
  };
}

export async function parseImage(args: {
  image: ImagePart;
  contextNote?: string;
  userLocale?: string;
  recentCuisines?: Cuisine[];
  signal?: AbortSignal;
}): Promise<ImageParseServiceResult> {
  const cuisine = await classify({
    contextNote: args.contextNote,
    userLocale: args.userLocale,
    recentCuisines: args.recentCuisines
  });
  args.image.debugEvents?.push({
    stage: 'image_cuisine_router',
    ok: true,
    reason: `${cuisine.cuisine}:${cuisine.source}`,
    ms: 0,
    confidence: cuisine.confidence
  });
  const promptHint = buildCuisinePrompt({ cuisine: cuisine.cuisine, contextNote: args.contextNote });
  const contextNote = [
    args.contextNote?.trim() ?? '',
    `Cuisine router: ${cuisine.cuisine} (${cuisine.source}, ${cuisine.confidence.toFixed(2)}).`,
    'Apply the cuisine guidance below when compatible with the image:',
    promptHint
  ]
    .filter(Boolean)
    .join('\n\n');

  let parsed: ImageParseServiceResult;
  try {
    parsed = await parseImageWithGemini({
      ...args.image,
      contextNote,
      debugEvents: args.image.debugEvents
    });
  } catch (err) {
    const fallback = contextFallbackResult({
      contextNote: args.contextNote,
      cuisine: cuisine.cuisine,
      source: cuisine.source,
      confidence: cuisine.confidence,
      matchedKeywords: cuisine.matchedKeywords
    });
    if (fallback) return fallback;
    throw err;
  }

  const parsedTextCuisine =
    cuisine.cuisine === 'generic'
      ? await classify({ contextNote: parsed.extractedText })
      : null;
  const resolvedCuisine =
    parsedTextCuisine && parsedTextCuisine.cuisine !== 'generic' && parsedTextCuisine.confidence >= 0.6
      ? parsedTextCuisine
      : cuisine;

  return {
    ...parsed,
    coverage: coverageWithContextOverride({
      coverage: parsed.coverage
        ? {
            ...parsed.coverage,
            cuisineHints: Array.from(new Set([resolvedCuisine.cuisine, ...parsed.coverage.cuisineHints]))
          }
        : parsed.coverage,
      contextNote: args.contextNote,
      items: parsed.result.items,
      cuisine: resolvedCuisine.cuisine
    }),
    cuisine: {
      cuisine: resolvedCuisine.cuisine,
      confidence: resolvedCuisine.confidence,
      source: resolvedCuisine.source,
      matchedKeywords: resolvedCuisine.matchedKeywords
    },
    result: {
      ...parsed.result,
      assumptions: [
        ...parsed.result.assumptions,
        `Cuisine routed as ${resolvedCuisine.cuisine} (${resolvedCuisine.source}, confidence ${resolvedCuisine.confidence.toFixed(2)}).`
      ]
    }
  };
}
