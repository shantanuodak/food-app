import type { ParseResult, ParsedItem } from '../deterministicParser.js';
import type { ImageParseServiceResult } from './types.js';
import { lookupByBarcode, type NutritionLookupResult } from '../nutritionDatabaseService.js';

function round(value: number, digits = 1): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function quantityHint(contextNote?: string): number {
  const text = (contextNote ?? '').toLowerCase();
  const wordMap: Record<string, number> = { two: 2, three: 3, four: 4, five: 5 };
  const match = text.match(/\b(\d+|two|three|four|five)\s+(?:of these|cans?|bottles?|bars?|pieces?|servings?)\b/i);
  if (!match) return 1;
  const raw = match[1].toLowerCase();
  const parsed = wordMap[raw] ?? Number(raw);
  return Number.isFinite(parsed) && parsed > 0 ? Math.min(parsed, 12) : 1;
}

function itemFromLookup(lookup: NutritionLookupResult, quantity: number): ParsedItem {
  const grams = round(lookup.servingSizeG * quantity);
  const name = [lookup.brand, lookup.productName].filter(Boolean).join(' ').trim() || lookup.productName;
  return {
    name,
    quantity,
    amount: quantity,
    unit: lookup.servingSizeText || 'serving',
    unitNormalized: lookup.servingSizeText || 'serving',
    grams,
    gramsPerUnit: lookup.servingSizeG || null,
    calories: round(lookup.calories * quantity),
    protein: round(lookup.proteinG * quantity),
    carbs: round(lookup.carbsG * quantity),
    fat: round(lookup.fatG * quantity),
    matchConfidence: lookup.confidence,
    nutritionSourceId: `${lookup.source}:${lookup.upc ?? lookup.productName}`.slice(0, 120),
    originalNutritionSourceId: `${lookup.source}:${lookup.upc ?? lookup.productName}`.slice(0, 120),
    sourceFamily: 'cache',
    needsClarification: false,
    manualOverride: false,
    foodDescription: `${name}, ${quantity} ${lookup.servingSizeText || 'serving'}`,
    explanation: `Matched barcode nutrition from ${lookup.source.replace(/_/g, ' ')}.`
  };
}

function resultFromLookup(lookup: NutritionLookupResult, quantity: number): ParseResult {
  const item = itemFromLookup(lookup, quantity);
  return {
    confidence: lookup.confidence,
    assumptions: [
      `Barcode lookup via ${lookup.source.replace(/_/g, ' ')}.`,
      quantity > 1 ? `Applied quantity hint: ${quantity} servings/items.` : ''
    ].filter(Boolean),
    items: [item],
    totals: {
      calories: item.calories,
      protein: item.protein,
      carbs: item.carbs,
      fat: item.fat
    }
  };
}

export async function lookupBarcode(args: {
  code: string;
  symbology?: string;
  contextNote?: string;
  signal?: AbortSignal;
  timeoutMs?: number;
}): Promise<ImageParseServiceResult & { lookup: NutritionLookupResult; fallback?: 'image' }> {
  const lookup = await lookupByBarcode(args.code, { signal: args.signal, timeoutMs: args.timeoutMs ?? 800 });
  if (lookup.source === 'miss') {
    return {
      extractedText: `Barcode ${args.code}`,
      result: { confidence: 0, assumptions: ['Barcode was not found.'], items: [], totals: { calories: 0, protein: 0, carbs: 0, fat: 0 } },
      model: 'nutrition_database',
      fallbackUsed: false,
      lowConfidenceAccepted: false,
      usageEvents: [],
      orchestratorVersion: 'v2',
      lookup,
      fallback: 'image'
    };
  }

  const quantity = quantityHint(args.contextNote);
  return {
    extractedText: [lookup.brand, lookup.productName].filter(Boolean).join(' ') || `Barcode ${args.code}`,
    result: resultFromLookup(lookup, quantity),
    model: 'nutrition_database',
    fallbackUsed: false,
    lowConfidenceAccepted: false,
    usageEvents: [],
    orchestratorVersion: 'v2',
    lookup
  };
}
