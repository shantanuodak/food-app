import type { ParseResult } from './deterministicParser.js';
import { buildParseCacheDebugInfo, getParseCache, setParseCache } from './parseCacheService.js';
import { tryCheapAIFallback, type AICallUsage } from './aiNormalizerService.js';
import { tryFatSecretParse } from './fatsecretParserService.js';
import { isGeminiCircuitOpenForDiagnostics } from './geminiFlashClient.js';
import { buildClarificationQuestions } from './clarificationService.js';
import { splitFoodTextSegments } from './foodTextSegmentation.js';
import { collectSourcesUsed, normalizeParseResultContract } from './parseContractService.js';
import type {
  ParseDecisionContext,
  ParseDecisionResult,
  ParsePipelineRoute as ParseRoute,
  ParseProvider
} from './parseDecisionTypes.js';
import { config } from '../config.js';

export type ParsePipelineRoute = ParseRoute;
export type ParsePipelineOutput = ParseDecisionResult;
export type { ParseDecisionContext, ParseProvider };

const inFlightParses = new Map<string, Promise<ParsePipelineOutput>>();
type UnresolvedReason =
  | 'gemini_not_executed'
  | 'gemini_request_failed'
  | 'gemini_circuit_open'
  | 'fatsecret_semantic_mismatch'
  | 'fatsecret_unavailable_or_rejected';

function createEmptyParseResult(_text: string): ParseResult {
  return {
    confidence: 0,
    assumptions: [],
    items: [],
    totals: {
      calories: 0,
      protein: 0,
      carbs: 0,
      fat: 0
    }
  };
}

function isValidParseResultShape(value: unknown): value is ParseResult {
  if (!value || typeof value !== 'object') {
    return false;
  }
  const candidate = value as Partial<ParseResult>;
  return (
    typeof candidate.confidence === 'number' &&
    Number.isFinite(candidate.confidence) &&
    Array.isArray(candidate.items) &&
    Array.isArray(candidate.assumptions) &&
    Boolean(candidate.totals) &&
    typeof candidate.totals?.calories === 'number' &&
    typeof candidate.totals?.protein === 'number' &&
    typeof candidate.totals?.carbs === 'number' &&
    typeof candidate.totals?.fat === 'number'
  );
}

function hasUnresolvedSignal(text: string, result: ParseResult): boolean {
  if (result.items.length === 0) {
    return true;
  }

  const segmentCount = splitFoodTextSegments(text).length;
  const coverageGap = segmentCount > 0 && result.items.length < segmentCount;
  return coverageGap;
}

function normalizeNutritionSourceId(rawSourceId: string, route: ParsePipelineRoute): string {
  const trimmed = rawSourceId.trim();
  if (!trimmed) {
    if (route === 'fatsecret') return 'fatsecret_estimate';
    if (route === 'gemini') return 'gemini_estimate';
    return 'cache_estimate';
  }

  const normalized = trimmed.toLowerCase();
  if (
    normalized.includes('fatsecret') ||
    normalized.includes('gemini') ||
    normalized.includes('manual') ||
    normalized.includes('cache')
  ) {
    return trimmed;
  }

  if (route === 'fatsecret') return 'fatsecret_estimate';
  if (route === 'gemini') return 'gemini_estimate';
  return 'cache_estimate';
}

function sanitizeResultSources(result: ParseResult, route: ParsePipelineRoute): ParseResult {
  if (result.items.length === 0) {
    return {
      ...result,
      assumptions: []
    };
  }

  return {
    ...result,
    assumptions: [],
    items: result.items.map((item) => ({
      ...item,
      nutritionSourceId: normalizeNutritionSourceId(item.nutritionSourceId, route)
    }))
  };
}

function ensureItemExplanations(result: ParseResult, route: ParsePipelineRoute): ParseResult {
  if (result.items.length === 0) {
    return result;
  }

  const fallbackExplanation =
    route === 'gemini'
      ? 'AI estimate provided based on the entered text.'
      : 'Nutrition estimate provided based on the matched data source.';

  return {
    ...result,
    items: result.items.map((item) => {
      const foodDescription = item.foodDescription && item.foodDescription.trim().length > 0 ? item.foodDescription : item.name;
      const explanation = item.explanation && item.explanation.trim().length > 0 ? item.explanation : fallbackExplanation;
      return {
        ...item,
        foodDescription,
        explanation
      };
    })
  };
}

function computeClarificationState(text: string, result: ParseResult): { needsClarification: boolean; clarificationQuestions: string[] } {
  const itemNeedsClarification = result.items.filter((item) => item.needsClarification === true);
  const unresolved = hasUnresolvedSignal(text, result);
  const needsClarification =
    itemNeedsClarification.length > 0 ||
    result.items.length === 0 ||
    result.confidence < config.aiFallbackConfidenceMin ||
    (unresolved && result.confidence < config.aiFallbackConfidenceMax);

  if (!needsClarification) {
    return { needsClarification: false, clarificationQuestions: [] };
  }

  const questions = buildClarificationQuestions(text, result);
  if (questions.length > 0) {
    if (itemNeedsClarification.length > 0) {
      const itemLabel = itemNeedsClarification
        .map((item) => item.name.trim())
        .filter(Boolean)
        .slice(0, 3)
        .join(', ');
      questions.unshift(
        itemLabel
          ? `Please confirm quantity or serving details for: ${itemLabel}.`
          : 'Please confirm quantity or serving details for unresolved items.'
      );
    }
    return { needsClarification: true, clarificationQuestions: Array.from(new Set(questions)) };
  }

  return {
    needsClarification: true,
    clarificationQuestions: ['Please list each food with quantity, for example: "2 eggs, 1 slice toast".']
  };
}

function shouldAcceptCachedResult(result: ParseResult): boolean {
  return result.items.length > 0 || result.confidence >= config.parseCacheMinConfidence;
}

function logUnresolvedRoute(text: string, context: ParseDecisionContext, reasons: UnresolvedReason[]): void {
  const cacheDebug = buildParseCacheDebugInfo(text, context.cacheScope);
  const safeReasons = reasons.length > 0 ? reasons : ['gemini_request_failed'];
  console.warn(
    '[parse_route_unresolved]',
    JSON.stringify({
      reasons: safeReasons,
      cacheScope: context.cacheScope,
      textHash: cacheDebug.textHash,
      segmentCount: splitFoodTextSegments(text).length,
      geminiEnabled: context.featureFlags.geminiEnabled && context.allowFallback && config.aiFallbackEnabled,
      fatsecretEnabled: context.featureFlags.fatsecretEnabled && config.fatsecretEnabled
    })
  );
}

async function runProviders(text: string, context: ParseDecisionContext, providers: ParseProvider[]): Promise<{
  result: ParseResult;
  route: ParsePipelineRoute;
  cacheHit: boolean;
  sourcesUsed: Array<'cache' | 'fatsecret' | 'gemini' | 'manual'>;
  reasonCodes: string[];
  fallbackUsed: boolean;
  fallbackModel: string | null;
  fallbackUsage: AICallUsage | null;
}> {
  let result: ParseResult = createEmptyParseResult(text);
  let route: ParsePipelineRoute = 'unresolved';
  let cacheHit = false;
  let fallbackUsed = false;
  let fallbackModel: string | null = null;
  let fallbackUsage: AICallUsage | null = null;
  let fatSecretCandidate: ParseResult | null = null;
  let fatsecretUnavailableOrRejected = false;
  const fatsecretRejectionCodes = new Set<string>();
  let geminiExecuted = false;
  let geminiReturnedNoResult = false;
  let geminiCircuitWasOpen = false;
  let geminiEnabledForRequest = false;

  for (const provider of providers) {
    const providerEnabled = provider.isEnabled(context);
    if (provider.name === 'gemini') {
      geminiEnabledForRequest = providerEnabled;
    }
    if (!providerEnabled) {
      if (provider.name === 'fatsecret') {
        fatsecretUnavailableOrRejected = true;
      }
      continue;
    }
    if (provider.name === 'gemini') {
      geminiExecuted = true;
    }

    const attempt = await provider.parse({
      text,
      baseline: result,
      context
    });
    if (!attempt) {
      if (provider.name === 'fatsecret') {
        fatsecretUnavailableOrRejected = true;
      }
      if (provider.name === 'gemini') {
        geminiReturnedNoResult = true;
        geminiCircuitWasOpen = isGeminiCircuitOpenForDiagnostics();
      }
      continue;
    }

    if (provider.name === 'cache') {
      if (!attempt.accepted) {
        continue;
      }
      result = attempt.result;
      route = 'cache';
      cacheHit = attempt.cacheHit ?? true;
      break;
    }

    if (provider.name === 'fatsecret') {
      if (attempt.result.items.length > 0) {
        fatSecretCandidate = attempt.result;
      }
      if (attempt.accepted) {
        result = attempt.result;
        route = 'fatsecret';
        break;
      }
      fatsecretUnavailableOrRejected = true;
      if (attempt.rejectionReason) {
        fatsecretRejectionCodes.add(attempt.rejectionReason);
      }
      continue;
    }

    if (provider.name === 'gemini') {
      if (!attempt.accepted) {
        geminiReturnedNoResult = true;
        geminiCircuitWasOpen = isGeminiCircuitOpenForDiagnostics();
        continue;
      }
      result = attempt.result;
      route = 'gemini';
      fallbackUsed = attempt.fallbackUsed ?? true;
      fallbackModel = attempt.fallbackModel ?? null;
      fallbackUsage = attempt.fallbackUsage ?? null;
      break;
    }
  }

  // If Gemini returned empty and FatSecret had non-empty output, keep FatSecret as a safety net.
  if (route !== 'fatsecret' && fatSecretCandidate && result.items.length === 0) {
    result = fatSecretCandidate;
    route = 'fatsecret';
  }

  if (route === 'unresolved') {
    const reasons: UnresolvedReason[] = [];
    if (fatsecretRejectionCodes.has('FATSECRET_SEMANTIC_MISMATCH')) {
      reasons.push('fatsecret_semantic_mismatch');
    }
    if (fatsecretUnavailableOrRejected) {
      reasons.push('fatsecret_unavailable_or_rejected');
    }
    if (!geminiEnabledForRequest) {
      reasons.push('gemini_not_executed');
    } else if (!geminiExecuted || geminiReturnedNoResult) {
      reasons.push(geminiCircuitWasOpen ? 'gemini_circuit_open' : 'gemini_request_failed');
    }
    logUnresolvedRoute(text, context, reasons);
  }

  result = sanitizeResultSources(result, route);
  result = ensureItemExplanations(result, route);
  result = normalizeParseResultContract(result, route);
  const sourcesUsed = collectSourcesUsed(result.items, route, cacheHit);
  const reasonCodes = Array.from(fatsecretRejectionCodes);

  return {
    result,
    route,
    cacheHit,
    sourcesUsed,
    reasonCodes,
    fallbackUsed,
    fallbackModel,
    fallbackUsage
  };
}

function createCacheProvider(): ParseProvider {
  return {
    name: 'cache',
    isEnabled: () => true,
    async parse({ text, context }) {
      try {
        const cached = await getParseCache(text, context.cacheScope);
        if (!cached) {
          return null;
        }

        if (!isValidParseResultShape(cached.result)) {
          console.warn(
            '[parse_cache_skip]',
            JSON.stringify({
              reason: 'invalid_cached_result_shape',
              cacheScope: context.cacheScope,
              textHash: cached.textHash
            })
          );
          return null;
        }

        if (!shouldAcceptCachedResult(cached.result)) {
          console.info(
            '[parse_cache_skip]',
            JSON.stringify({
              reason: 'low_quality_cached_result',
              confidence: cached.result.confidence,
              itemCount: cached.result.items.length,
              cacheScope: context.cacheScope,
              minConfidence: config.parseCacheMinConfidence
            })
          );
          return null;
        }

        return {
          result: cached.result,
          accepted: true,
          cacheHit: true
        };
      } catch (err) {
        console.warn('Parse cache read failed; continuing without cache', err);
        return null;
      }
    }
  };
}

function createFatSecretProvider(): ParseProvider {
  return {
    name: 'fatsecret',
    isEnabled: (context) =>
      context.featureFlags.fatsecretEnabled && config.fatsecretEnabled && Boolean(config.fatsecretClientId && config.fatsecretClientSecret),
    async parse({ text, baseline }) {
      const candidate = await tryFatSecretParse(text, baseline);
      if (!candidate) {
        return null;
      }
      if (candidate.items.length === 0) {
        return {
          result: candidate,
          accepted: false,
          rejectionReason: 'FATSECRET_NO_MATCH'
        };
      }

      const accepted = candidate.confidence >= config.fatsecretMinConfidence;
      return {
        result: candidate,
        accepted,
        rejectionReason: accepted ? undefined : 'FATSECRET_LOW_CONFIDENCE'
      };
    }
  };
}

function createGeminiProvider(): ParseProvider {
  return {
    name: 'gemini',
    isEnabled: (context) => context.featureFlags.geminiEnabled && context.allowFallback && config.aiFallbackEnabled,
    async parse({ text, baseline }) {
      const fallback = await tryCheapAIFallback(text, baseline);
      if (!fallback) {
        return null;
      }

      return {
        result: fallback.result,
        accepted: true,
        fallbackUsed: true,
        fallbackModel: fallback.usage.model,
        fallbackUsage: fallback.usage
      };
    }
  };
}

export function createDefaultParseProviders(): ParseProvider[] {
  return [createCacheProvider(), createFatSecretProvider(), createGeminiProvider()];
}

export async function runPrimaryParsePipeline(
  text: string,
  options?: {
    allowFallback?: boolean;
    cacheScope?: string;
    featureFlags?: { geminiEnabled?: boolean; fatsecretEnabled?: boolean };
    userId?: string;
    budget?: ParseDecisionContext['budget'];
  }
): Promise<ParsePipelineOutput> {
  const context: ParseDecisionContext = {
    userId: options?.userId || 'unknown',
    featureFlags: {
      geminiEnabled: options?.featureFlags?.geminiEnabled ?? Boolean(config.geminiApiKey),
      fatsecretEnabled: options?.featureFlags?.fatsecretEnabled ?? true
    },
    budget: options?.budget,
    cacheScope: options?.cacheScope || 'global',
    allowFallback: options?.allowFallback ?? true
  };

  const inFlightKey = buildParseCacheDebugInfo(text, context.cacheScope).textHash;
  const existing = inFlightParses.get(inFlightKey);
  if (existing) {
    console.info('[parse_dedupe_hit]', JSON.stringify({ cacheScope: context.cacheScope, textHash: inFlightKey }));
    const deduped = await existing;
    return {
      ...deduped,
      cacheHit: true,
      route: 'cache',
      sourcesUsed: Array.from(new Set(['cache', ...deduped.sourcesUsed])),
      reasonCodes: deduped.reasonCodes
    };
  }

  const pipelinePromise = (async (): Promise<ParsePipelineOutput> => {
    const providers = createDefaultParseProviders();
    const outcome = await runProviders(text, context, providers);

    if (!outcome.cacheHit) {
      const shouldCache = shouldAcceptCachedResult(outcome.result);
      if (shouldCache) {
        try {
          await setParseCache(text, outcome.result, context.cacheScope);
        } catch (err) {
          console.warn('Parse cache write failed; continuing', err);
        }
      } else {
        console.info(
          '[parse_cache_skip]',
          JSON.stringify({
            reason: 'low_quality_parse_result',
            confidence: outcome.result.confidence,
            itemCount: outcome.result.items.length,
            cacheScope: context.cacheScope,
            minConfidence: config.parseCacheMinConfidence
          })
        );
      }
    }

    const clarification = computeClarificationState(text, outcome.result);
    return {
      ...outcome,
      needsClarification: clarification.needsClarification,
      clarificationQuestions: clarification.clarificationQuestions
    };
  })();

  inFlightParses.set(inFlightKey, pipelinePromise);
  try {
    return await pipelinePromise;
  } finally {
    if (inFlightParses.get(inFlightKey) === pipelinePromise) {
      inFlightParses.delete(inFlightKey);
    }
  }
}
