import type { ParseResult } from './deterministicParser.js';
import { buildParseCacheDebugInfo, getParseCache, setParseCache } from './parseCacheService.js';
import { tryCheapAIFallbackDetailed, type AICallUsage, type AIFallbackFailureReason } from './aiNormalizerService.js';
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
  | 'gemini_timeout'
  | 'gemini_rate_limited'
  | 'gemini_http_error'
  | 'gemini_empty_response'
  | 'gemini_network_error'
  | 'gemini_invalid_response';

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

function resultUsesRetiredProvider(result: ParseResult): boolean {
  return result.items.some((item) => {
    const nutritionSourceId = item.nutritionSourceId.trim().toLowerCase();
    const originalNutritionSourceId = (item.originalNutritionSourceId || '').trim().toLowerCase();
    const sourceFamily = (item.sourceFamily || '').trim().toLowerCase();

    return (
      nutritionSourceId.includes('fatsecret') ||
      nutritionSourceId.includes('deterministic') ||
      nutritionSourceId.includes('seed_') ||
      originalNutritionSourceId.includes('fatsecret') ||
      originalNutritionSourceId.includes('deterministic') ||
      originalNutritionSourceId.includes('seed_') ||
      sourceFamily === 'fatsecret' ||
      sourceFamily === 'deterministic'
    );
  });
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
    if (route === 'deterministic') return 'deterministic_estimate';
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

  if (route === 'deterministic') return 'deterministic_estimate';
  if (route === 'fatsecret') return 'fatsecret_estimate';
  if (route === 'gemini') return 'gemini_estimate';
  return 'cache_estimate';
}

function sanitizeResultSources(result: ParseResult, route: ParsePipelineRoute): ParseResult {
  if (result.items.length === 0) {
    return result;
  }

  return {
    ...result,
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
  sourcesUsed: Array<'cache' | 'deterministic' | 'fatsecret' | 'gemini' | 'manual'>;
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
  let geminiExecuted = false;
  let geminiReturnedNoResult = false;
  let geminiCircuitWasOpen = false;
  let geminiEnabledForRequest = false;
  let geminiFailureReason: UnresolvedReason | null = null;

  for (const provider of providers) {
    const providerEnabled = provider.isEnabled(context);
    if (provider.name === 'gemini') {
      geminiEnabledForRequest = providerEnabled;
    }
    if (!providerEnabled) {
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
      if (provider.name === 'gemini') {
        geminiReturnedNoResult = true;
        geminiCircuitWasOpen = isGeminiCircuitOpenForDiagnostics();
      }
      continue;
    }

    if (provider.name === 'gemini' && !attempt.accepted) {
      geminiReturnedNoResult = true;
      geminiCircuitWasOpen = isGeminiCircuitOpenForDiagnostics();
      const rejectionReason = attempt.rejectionReason as AIFallbackFailureReason | undefined;
      if (rejectionReason) {
        geminiFailureReason = rejectionReason;
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

    if (provider.name === 'gemini') {
      result = attempt.result;
      route = 'gemini';
      fallbackUsed = attempt.fallbackUsed ?? true;
      fallbackModel = attempt.fallbackModel ?? null;
      fallbackUsage = attempt.fallbackUsage ?? null;
      break;
    }
  }

  if (route === 'unresolved') {
    const reasons: UnresolvedReason[] = [];
    if (!geminiEnabledForRequest) {
      reasons.push('gemini_not_executed');
    } else if (!geminiExecuted || geminiReturnedNoResult) {
      reasons.push(geminiCircuitWasOpen ? 'gemini_circuit_open' : (geminiFailureReason ?? 'gemini_request_failed'));
    }
    logUnresolvedRoute(text, context, reasons);
    return {
      result: normalizeParseResultContract(ensureItemExplanations(sanitizeResultSources(result, route), route), route),
      route,
      cacheHit,
      sourcesUsed: collectSourcesUsed(result.items, route, cacheHit),
      reasonCodes: reasons,
      fallbackUsed,
      fallbackModel,
      fallbackUsage
    };
  }

  result = sanitizeResultSources(result, route);
  result = ensureItemExplanations(result, route);
  result = normalizeParseResultContract(result, route);
  const sourcesUsed = collectSourcesUsed(result.items, route, cacheHit);
  const reasonCodes: string[] = [];

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

        if (resultUsesRetiredProvider(cached.result)) {
          console.info(
            '[parse_cache_skip]',
            JSON.stringify({
              reason: 'retired_provider_cached_result',
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

function createGeminiProvider(): ParseProvider {
  return {
    name: 'gemini',
    isEnabled: (context) => context.featureFlags.geminiEnabled && context.allowFallback && config.aiFallbackEnabled,
    async parse({ text, baseline }) {
      const fallbackAttempt = await tryCheapAIFallbackDetailed(text, baseline);
      if (!fallbackAttempt.output) {
        return {
          result: baseline,
          accepted: false,
          rejectionReason: fallbackAttempt.failureReason
        };
      }

      return {
        result: fallbackAttempt.output.result,
        accepted: true,
        fallbackUsed: true,
        fallbackModel: fallbackAttempt.output.usage.model,
        fallbackUsage: fallbackAttempt.output.usage
      };
    }
  };
}

export function createDefaultParseProviders(): ParseProvider[] {
  return [createCacheProvider(), createGeminiProvider()];
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

function combineParseResults(results: ParseResult[]): ParseResult {
  const items = results.flatMap((r) => r.items);
  const confidence = results.length > 0 ? Math.min(...results.map((r) => r.confidence)) : 0;
  const totals = {
    calories: Math.round(items.reduce((s, i) => s + i.calories, 0) * 10) / 10,
    protein: Math.round(items.reduce((s, i) => s + i.protein, 0) * 10) / 10,
    carbs: Math.round(items.reduce((s, i) => s + i.carbs, 0) * 10) / 10,
    fat: Math.round(items.reduce((s, i) => s + i.fat, 0) * 10) / 10
  };
  return { confidence, assumptions: [], items, totals };
}

/**
 * Segment-aware pipeline: checks cache per segment, calls Gemini only
 * for segments that are not cached, then merges everything together.
 * Falls back to the standard single-text pipeline for single-segment input.
 */
export async function runSegmentAwareParsePipeline(
  text: string,
  options?: Parameters<typeof runPrimaryParsePipeline>[1]
): Promise<ParsePipelineOutput> {
  const segments = splitFoodTextSegments(text);

  if (segments.length <= 1) {
    return runPrimaryParsePipeline(text, options);
  }

  const cacheScope = options?.cacheScope ?? 'global';

  // Check cache for every segment in parallel
  const cacheChecks = await Promise.all(
    segments.map(async (seg) => {
      const cached = await getParseCache(seg, cacheScope);
      if (cached && shouldAcceptCachedResultPublic(cached.result)) {
        return { seg, result: cached.result, fromCache: true };
      }
      return { seg, result: null as ParseResult | null, fromCache: false };
    })
  );

  const allCached = cacheChecks.every((c) => c.fromCache);

  // Full cache hit across all segments
  if (allCached) {
    const combined = combineParseResults(cacheChecks.map((c) => c.result as ParseResult));
    const clarification = computeClarificationState(text, combined);
    return {
      result: combined,
      route: 'cache',
      cacheHit: true,
      sourcesUsed: collectSourcesUsed(combined.items, 'cache', true),
      reasonCodes: [],
      fallbackUsed: false,
      fallbackModel: null,
      fallbackUsage: null,
      needsClarification: clarification.needsClarification,
      clarificationQuestions: clarification.clarificationQuestions
    };
  }

  // Partial cache hit: only call Gemini for the uncached segments
  const uncachedSegments = cacheChecks.filter((c) => !c.fromCache).map((c) => c.seg);
  const uncachedText = uncachedSegments.join('\n');

  let uncachedOutput = await runPrimaryParsePipeline(uncachedText, options);

  // If Gemini returned fewer items than segments (coverage gap), fall back to
  // one call per missing segment so nothing gets silently dropped
  if (uncachedOutput.result.items.length < uncachedSegments.length) {
    const perSegmentResults: ParseResult[] = [];
    for (const seg of uncachedSegments) {
      const segOutput = await runPrimaryParsePipeline(seg, options);
      perSegmentResults.push(segOutput.result);
      if (segOutput.result.items.length > 0 && !segOutput.cacheHit) {
        setParseCache(seg, segOutput.result, cacheScope).catch(() => {});
      }
    }
    const combined = combineParseResults(perSegmentResults);
    uncachedOutput = { ...uncachedOutput, result: combined, cacheHit: false };
  } else if (uncachedOutput.result.items.length > 0 && !uncachedOutput.cacheHit) {
    // Full item count matched — cache each segment individually for future reuse
    for (const seg of uncachedSegments) {
      const segItem = uncachedOutput.result.items.find(
        (item) => item.name.toLowerCase().includes(seg.toLowerCase().replace(/^\d+\s*/, ''))
      );
      if (segItem) {
        const segResult: ParseResult = {
          confidence: segItem.matchConfidence,
          assumptions: [],
          items: [segItem],
          totals: {
            calories: segItem.calories,
            protein: segItem.protein,
            carbs: segItem.carbs,
            fat: segItem.fat
          }
        };
        setParseCache(seg, segResult, cacheScope).catch(() => {});
      }
    }
  }

  // Merge cached segment results with freshly-parsed ones
  const cachedResults = cacheChecks.filter((c) => c.fromCache).map((c) => c.result as ParseResult);
  const merged = combineParseResults([...cachedResults, uncachedOutput.result]);
  const clarification = computeClarificationState(text, merged);

  return {
    ...uncachedOutput,
    result: merged,
    route: cachedResults.length > 0 ? 'gemini' : uncachedOutput.route,
    cacheHit: false,
    sourcesUsed: collectSourcesUsed(merged.items, uncachedOutput.route, false),
    needsClarification: clarification.needsClarification,
    clarificationQuestions: clarification.clarificationQuestions
  };
}

// Expose shouldAcceptCachedResult for use in segment pipeline
function shouldAcceptCachedResultPublic(result: ParseResult): boolean {
  return shouldAcceptCachedResult(result);
}
