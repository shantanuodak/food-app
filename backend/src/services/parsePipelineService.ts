import type { ParseResult } from './deterministicParser.js';
import { buildParseCacheDebugInfo, getParseCache, setParseCache } from './parseCacheService.js';
import type { AICallUsage, AIFallbackFailureReason } from './aiNormalizerService.js';
import { isGeminiCircuitOpenForDiagnostics } from './geminiFlashClient.js';
import { splitFoodTextSegments } from './foodTextSegmentation.js';
import { collectSourcesUsed, normalizeParseResultContract } from './parseContractService.js';
import { computeClarificationState } from './parseClarificationState.js';
import { createDefaultParseProviders } from './parsePipelineProviders.js';
import {
  combineParseResults,
  createEmptyParseResult,
  ensureItemExplanations,
  sanitizeResultSources,
  shouldAcceptCachedResult
} from './parsePipelineResultUtils.js';
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
      geminiEnabled: context.featureFlags.geminiEnabled && context.allowFallback && config.aiFallbackEnabled
    })
  );
}

async function runProviders(text: string, context: ParseDecisionContext, providers: ParseProvider[]): Promise<{
  result: ParseResult;
  route: ParsePipelineRoute;
  cacheHit: boolean;
  sourcesUsed: Array<'cache' | 'deterministic' | 'gemini' | 'manual'>;
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

export async function runPrimaryParsePipeline(
  text: string,
  options?: {
    allowFallback?: boolean;
    cacheScope?: string;
    featureFlags?: { geminiEnabled?: boolean };
    userId?: string;
    budget?: ParseDecisionContext['budget'];
  }
): Promise<ParsePipelineOutput> {
  const context: ParseDecisionContext = {
    userId: options?.userId || 'unknown',
    featureFlags: {
      geminiEnabled: options?.featureFlags?.geminiEnabled ?? Boolean(config.geminiApiKey)
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
      if (cached && shouldAcceptCachedResult(cached.result)) {
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

/**
 * Streaming variant of the segment-aware pipeline.
 * Emits each parsed item via onItem() as soon as it's available (cache or Gemini stream).
 * Falls back to the non-streaming pipeline if streaming is not possible.
 */
export async function runSegmentAwareParsePipelineStreaming(
  text: string,
  options?: Parameters<typeof runPrimaryParsePipeline>[1] & {
    signal?: AbortSignal;
    onItem?: (item: Record<string, unknown>, index: number) => void;
  }
): Promise<ParsePipelineOutput> {
  const onItem = options?.onItem;

  // If no streaming callback, fall back to non-streaming
  if (!onItem) {
    return runSegmentAwareParsePipeline(text, options);
  }

  const segments = splitFoodTextSegments(text);

  if (segments.length <= 1) {
    // Single segment — run normal pipeline, emit items from result
    const result = await runPrimaryParsePipeline(text, options);
    let itemIndex = 0;
    for (const item of result.result.items) {
      if (options?.signal?.aborted) break;
      onItem(item as unknown as Record<string, unknown>, itemIndex++);
    }
    return result;
  }

  const cacheScope = options?.cacheScope ?? 'global';

  // Check cache per segment in parallel
  const cacheChecks = await Promise.all(
    segments.map(async (seg) => {
      const cached = await getParseCache(seg, cacheScope);
      if (cached && shouldAcceptCachedResult(cached.result)) {
        return { seg, result: cached.result, fromCache: true };
      }
      return { seg, result: null as ParseResult | null, fromCache: false };
    })
  );

  // Emit cached items immediately
  let itemIndex = 0;
  for (const check of cacheChecks) {
    if (check.fromCache && check.result) {
      for (const item of check.result.items) {
        if (options?.signal?.aborted) break;
        onItem(item as unknown as Record<string, unknown>, itemIndex++);
      }
    }
  }

  const allCached = cacheChecks.every((c) => c.fromCache);
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

  // Parse uncached segments
  const uncachedSegments = cacheChecks.filter((c) => !c.fromCache).map((c) => c.seg);
  const uncachedText = uncachedSegments.join('\n');

  const uncachedOutput = await runPrimaryParsePipeline(uncachedText, options);

  // Emit freshly parsed items
  for (const item of uncachedOutput.result.items) {
    if (options?.signal?.aborted) break;
    onItem(item as unknown as Record<string, unknown>, itemIndex++);
  }

  // Cache new segments
  if (uncachedOutput.result.items.length > 0 && !uncachedOutput.cacheHit) {
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

  // Merge everything
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
