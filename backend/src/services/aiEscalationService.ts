import { z } from 'zod';
import type { ParseResult } from './deterministicParser.js';
import { generateGeminiJson } from './geminiFlashClient.js';

type EscalationOutput = {
  result: ParseResult;
  model: string;
  inputTokens: number;
  outputTokens: number;
  estimatedCostUsd: number;
};

const parseItemSchema = z.object({
  name: z.string(),
  quantity: z.number().nonnegative(),
  amount: z.number().nonnegative().optional(),
  unit: z.string(),
  unitNormalized: z.string().min(1).optional(),
  grams: z.number().nonnegative(),
  gramsPerUnit: z.number().nonnegative().nullable().optional(),
  calories: z.number().nonnegative(),
  protein: z.number().nonnegative(),
  carbs: z.number().nonnegative(),
  fat: z.number().nonnegative(),
  matchConfidence: z.number().min(0).max(1),
  nutritionSourceId: z.string(),
  needsClarification: z.boolean().optional(),
  manualOverride: z.boolean().optional(),
  sourceFamily: z.enum(['cache', 'gemini', 'manual']).optional(),
  originalNutritionSourceId: z.string().optional(),
  foodDescription: z.string().optional(),
  explanation: z.string().optional()
});

const parseResultSchema = z.object({
  confidence: z.number().min(0).max(1),
  assumptions: z.array(z.string()),
  items: z.array(parseItemSchema),
  totals: z.object({
    calories: z.number().nonnegative(),
    protein: z.number().nonnegative(),
    carbs: z.number().nonnegative(),
    fat: z.number().nonnegative()
  })
});

function normalizeForEscalation(text: string): string {
  return text
    .replace(/\+/g, ', ')
    .replace(/\bw\/\b/gi, ' with ')
    .replace(/\begs\b/gi, 'eggs')
    .replace(/\bcofee\b/gi, 'coffee')
    .replace(/\bchkn\b/gi, 'chicken')
    .replace(/\bcaf[eé]\b/gi, 'cafe')
    .replace(/\s+/g, ' ')
    .trim();
}

export function buildGeminiEscalationPrompt(inputText: string): string {
  return [
    'You are a nutrition parsing assistant for food logging.',
    'Return strict JSON only. No markdown, no explanation.',
    'Output must match this shape exactly:',
    '{"confidence":number,"assumptions":string[],"items":[{"name":string,"quantity":number,"unit":string,"grams":number,"calories":number,"protein":number,"carbs":number,"fat":number,"matchConfidence":number,"nutritionSourceId":string,"foodDescription":string,"explanation":string}],"totals":{"calories":number,"protein":number,"carbs":number,"fat":number}}',
    'Rules:',
    '- all numeric fields are non-negative',
    '- confidence and matchConfidence are in [0,1]',
    '- totals are sums of item values rounded to 1 decimal',
    '- keep food names and portions practical for meal logging',
    '- input may contain spelling mistakes; infer the intended common food item',
    '- preserve user-entered order of food mentions',
    '- for recognizable branded or chain restaurant items, use the official label/menu serving when possible',
    '- for generic foods, use USDA-style common serving estimates',
    '- when quantity is missing, assume one practical serving',
    '- default servings: egg=1 large, banana=1 medium, apple=1 medium, bread=1 slice, rice/pasta=1 cooked cup, milk=1 cup, oil=1 tbsp, bar/package/menu item=1 labeled serving',
    '- set matchConfidence based on food identity and portion confidence, not JSON validity',
    '- use matchConfidence 0.9-1.0 for exact clear matches, 0.7-0.89 for reasonable common estimates, 0.4-0.69 for ambiguous portions or typo recovery',
    '- calories and macros must be realistic and internally consistent; check calories roughly agree with macros using 4 kcal/g protein, 4 kcal/g carbs, and 9 kcal/g fat',
    '- if uncertain, still return a best-guess item with a lower matchConfidence',
    '- assumptions must always be an empty array',
    '- avoid zero-calorie outputs unless the item is truly near-zero',
    '- for each item, include a short foodDescription and one short user-facing explanation sentence',
    '- do not include chain-of-thought or step-by-step reasoning; keep explanations user-friendly',
    '',
    `User meal text: ${inputText}`
  ].join('\n');
}

async function tryGeminiEscalation(
  inputText: string,
  opts: { modelName: string; estimatedCostUsd: number }
): Promise<EscalationOutput | null> {
  const response = await generateGeminiJson({
    model: opts.modelName,
    prompt: buildGeminiEscalationPrompt(inputText),
    temperature: 0.1
  });

  if (!response) {
    return null;
  }

  try {
    const candidate = JSON.parse(response.jsonText) as unknown;
    const validated = parseResultSchema.parse(candidate);
    return {
      result: {
        ...validated,
        assumptions: []
      },
      model: response.usage.model,
      inputTokens: response.usage.inputTokens,
      outputTokens: response.usage.outputTokens,
      estimatedCostUsd: opts.estimatedCostUsd
    };
  } catch (err) {
    console.warn('Gemini escalation JSON parsing/validation failed', err);
    return null;
  }
}

export async function runEscalationParse(
  inputText: string,
  opts: { modelName: string; estimatedCostUsd: number }
): Promise<EscalationOutput> {
  const gemini = await tryGeminiEscalation(inputText, opts);
  if (gemini) {
    return gemini;
  }

  const expanded = normalizeForEscalation(inputText);
  if (expanded && expanded !== inputText) {
    const normalizedGemini = await tryGeminiEscalation(expanded, opts);
    if (normalizedGemini) {
      return normalizedGemini;
    }
  }

  const fallbackResult = {
    confidence: 0,
    assumptions: [],
    items: [],
    totals: {
      calories: 0,
      protein: 0,
      carbs: 0,
      fat: 0
    }
  } satisfies ParseResult;
  const validated = parseResultSchema.parse(fallbackResult);

  const inputTokens = Math.max(40, Math.ceil(inputText.length / 4));
  const outputTokens = Math.max(80, Math.ceil(JSON.stringify(validated).length / 4));

  return {
    result: validated,
    model: 'mock-local-escalation-v2',
    inputTokens,
    outputTokens,
    estimatedCostUsd: 0
  };
}
