import { z } from 'zod';
import { config } from '../config.js';
import type { ParseResult } from './deterministicParser.js';
import { generateGeminiJson } from './geminiFlashClient.js';
import { splitFoodTextSegments } from './foodTextSegmentation.js';

export type AICallUsage = {
  model: string;
  inputTokens: number;
  outputTokens: number;
  estimatedCostUsd: number;
};

type FallbackOutput = {
  result: ParseResult;
  usage: AICallUsage;
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
  sourceFamily: z.enum(['cache', 'fatsecret', 'gemini', 'manual']).optional(),
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

function buildGeminiFallbackPrompt(inputText: string, initialResult: ParseResult): string {
  const segments = splitFoodTextSegments(inputText);

  return [
    'You are a nutrition parsing assistant.',
    'Return strict JSON only. No markdown, no explanation.',
    'Output must match this shape exactly:',
    '{"confidence":number,"assumptions":string[],"items":[{"name":string,"quantity":number,"unit":string,"grams":number,"calories":number,"protein":number,"carbs":number,"fat":number,"matchConfidence":number,"nutritionSourceId":string,"foodDescription":string,"explanation":string}],"totals":{"calories":number,"protein":number,"carbs":number,"fat":number}}',
    'Rules:',
    '- all numeric fields are non-negative',
    '- confidence and matchConfidence are in [0,1]',
    '- totals are sums of item values rounded to 1 decimal',
    '- keep items practical for meal logging',
    '- input may contain spelling mistakes; infer the intended common food item',
    '- preserve user-entered order of food mentions',
    '- when input is a list, avoid dropping lines; return a best-guess item for each food mention',
    '- if uncertain, still return a reasonable estimate',
    '- assumptions must always be an empty array',
    '- avoid zero-calorie outputs unless the item is truly near-zero',
    '- for each item, include a short foodDescription and a 3-5 sentence explanation of how you interpreted the item and estimated nutrition',
    '- do not include chain-of-thought or step-by-step reasoning; keep explanations user-friendly',
    '',
    `Input segments (${segments.length}): ${JSON.stringify(segments)}`,
    `User meal text: ${inputText}`,
    `Current baseline parse (improve if possible): ${JSON.stringify(initialResult)}`
  ].join('\n');
}

async function tryGeminiFallback(inputText: string, initialResult: ParseResult): Promise<FallbackOutput | null> {
  if (!config.geminiApiKey) {
    return null;
  }

  let response: Awaited<ReturnType<typeof generateGeminiJson>>;
  try {
    response = await generateGeminiJson({
      model: config.aiFallbackModelName || config.geminiFlashModel,
      prompt: buildGeminiFallbackPrompt(inputText, initialResult),
      temperature: 0.1
    });
  } catch (err) {
    console.warn('Gemini fallback request failed', err);
    return null;
  }

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
      usage: {
        model: response.usage.model,
        inputTokens: response.usage.inputTokens,
        outputTokens: response.usage.outputTokens,
        estimatedCostUsd: config.aiFallbackCostUsd
      }
    };
  } catch (err) {
    console.warn('Gemini fallback JSON parsing/validation failed', err);
    return null;
  }
}

export async function tryGeminiPrimaryParse(inputText: string, initialResult: ParseResult): Promise<FallbackOutput | null> {
  return tryGeminiFallback(inputText, initialResult);
}

export async function tryCheapAIFallback(inputText: string, initialResult: ParseResult): Promise<FallbackOutput | null> {
  if (!config.aiFallbackEnabled) {
    return null;
  }

  const geminiResult = await tryGeminiFallback(inputText, initialResult);
  return geminiResult;
}
