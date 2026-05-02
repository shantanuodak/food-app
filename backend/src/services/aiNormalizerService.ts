import { z } from 'zod';
import { config } from '../config.js';
import type { ParseResult } from './deterministicParser.js';
import { generateGeminiJsonWithDiagnostics, type GeminiFailureReason } from './geminiFlashClient.js';
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

export type AIFallbackFailureReason = GeminiFailureReason | 'gemini_invalid_response';

type FallbackAttemptResult = {
  output: FallbackOutput | null;
  failureReason?: AIFallbackFailureReason;
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
  sourceFamily: z.enum(['cache', 'deterministic', 'gemini', 'manual']).optional(),
  originalNutritionSourceId: z.string().optional(),
  foodDescription: z.string().optional(),
  explanation: z.string().optional()
});

export const parseResultSchema = z.object({
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

const GEMINI_FALLBACK_DYNAMIC_RULES_TOKEN = '{{DYNAMIC_RULES}}';
const GEMINI_FALLBACK_RUNTIME_CONTEXT_TOKEN = '{{RUNTIME_CONTEXT}}';

export function buildGeminiFallbackPromptTemplate(): string {
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
    GEMINI_FALLBACK_DYNAMIC_RULES_TOKEN,
    '- each segment is a separate food item even if joined by "and", "&", or "with"; never merge two segments into one item',
    '- if uncertain about a segment, still return a best-guess item with a lower matchConfidence',
    '- assumptions must always be an empty array',
    '- avoid zero-calorie outputs unless the item is truly near-zero',
    '- for each item, include a short foodDescription and a 3-5 sentence explanation of how you interpreted the item and estimated nutrition',
    '- do not include chain-of-thought or step-by-step reasoning; keep explanations user-friendly',
    '',
    GEMINI_FALLBACK_RUNTIME_CONTEXT_TOKEN
  ].join('\n');
}

function buildGeminiFallbackDynamicRule(inputText: string): string {
  const segments = splitFoodTextSegments(inputText);
  return `- you MUST return exactly ${segments.length} item(s) — one per input segment, in the same order`;
}

export function buildGeminiFallbackRuntimeContext(inputText: string, initialResult: ParseResult): string {
  const segments = splitFoodTextSegments(inputText);
  return [
    `Input segments (${segments.length}): ${JSON.stringify(segments)}`,
    `User meal text: ${inputText}`,
    `Current baseline parse (improve if possible): ${JSON.stringify(initialResult)}`
  ].join('\n');
}

export function renderGeminiFallbackPrompt(
  promptTemplate: string,
  inputText: string,
  initialResult: ParseResult
): string {
  const dynamicRule = buildGeminiFallbackDynamicRule(inputText);
  const runtimeContext = buildGeminiFallbackRuntimeContext(inputText, initialResult);
  const normalizedTemplate = promptTemplate.trim();

  if (!normalizedTemplate) {
    return [dynamicRule, runtimeContext].join('\n\n');
  }

  if (
    normalizedTemplate.includes(GEMINI_FALLBACK_DYNAMIC_RULES_TOKEN) ||
    normalizedTemplate.includes(GEMINI_FALLBACK_RUNTIME_CONTEXT_TOKEN)
  ) {
    return normalizedTemplate
      .replaceAll(GEMINI_FALLBACK_DYNAMIC_RULES_TOKEN, dynamicRule)
      .replaceAll(GEMINI_FALLBACK_RUNTIME_CONTEXT_TOKEN, runtimeContext);
  }

  return [normalizedTemplate, dynamicRule, runtimeContext].join('\n\n');
}

export function buildGeminiFallbackPrompt(inputText: string, initialResult: ParseResult): string {
  return renderGeminiFallbackPrompt(buildGeminiFallbackPromptTemplate(), inputText, initialResult);
}

async function tryGeminiFallback(inputText: string, initialResult: ParseResult): Promise<FallbackAttemptResult> {
  if (!config.geminiApiKey) {
    return { output: null };
  }

  let response: Awaited<ReturnType<typeof generateGeminiJsonWithDiagnostics>>;
  try {
    response = await generateGeminiJsonWithDiagnostics({
      model: config.aiFallbackModelName || config.geminiFlashModel,
      prompt: buildGeminiFallbackPrompt(inputText, initialResult),
      temperature: 0.1
    });
  } catch (err) {
    console.warn('Gemini fallback request failed', err);
    return { output: null, failureReason: 'gemini_network_error' };
  }

  if (!response) {
    return { output: null };
  }

  if ('failureReason' in response) {
    return {
      output: null,
      failureReason: response.failureReason
    };
  }

  try {
    const candidate = JSON.parse(response.jsonText) as unknown;
    const validated = parseResultSchema.parse(candidate);

    return {
      output: {
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
      },
    };
  } catch (err) {
    console.warn('Gemini fallback JSON parsing/validation failed', err);
    return { output: null, failureReason: 'gemini_invalid_response' };
  }
}

export async function tryGeminiPrimaryParse(inputText: string, initialResult: ParseResult): Promise<FallbackOutput | null> {
  return (await tryGeminiFallback(inputText, initialResult)).output;
}

export async function tryCheapAIFallbackDetailed(
  inputText: string,
  initialResult: ParseResult
): Promise<FallbackAttemptResult> {
  if (!config.aiFallbackEnabled) {
    return { output: null };
  }

  return tryGeminiFallback(inputText, initialResult);
}

export async function tryCheapAIFallback(inputText: string, initialResult: ParseResult): Promise<FallbackOutput | null> {
  return (await tryCheapAIFallbackDetailed(inputText, initialResult)).output;
}
