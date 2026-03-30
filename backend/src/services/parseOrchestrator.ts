import { config } from '../config.js';
import { ApiError } from '../utils/errors.js';
import { getBudgetSnapshotForUser, writeAiCostEvent } from './aiCostService.js';
import { getEffectiveFeatureFlags } from './adminFeatureFlagsService.js';
import { buildParseCacheDebugInfo, type ParseCacheDebugInfo } from './parseCacheService.js';
import { runPrimaryParsePipeline } from './parsePipelineService.js';
import { checkParseRateLimit } from './parseRateLimiterService.js';
import { createParseRequest } from './parseRequestService.js';
import type { ParseDecisionResult } from './parseDecisionTypes.js';
import { getOnboardingParsePreferences } from './onboardingService.js';
import { splitFoodTextSegments } from './foodTextSegmentation.js';

type ParseAuthContext = {
  userId: string;
  authProvider?: string;
  email?: string | null;
};

export type PrimaryParseOrchestratorInput = {
  text: string;
  requestId: string;
  auth: ParseAuthContext;
  locale?: string | null;
};

export type PrimaryParseOrchestratorOutput = ParseDecisionResult & {
  budget: {
    dailyLimitUsd: number;
    dailyUsedTodayUsd: number;
    userSoftCapUsd: number;
    userUsedTodayUsd: number;
    userSoftCapExceeded: boolean;
    fallbackAllowed: boolean;
  };
  cacheDebug?: ParseCacheDebugInfo;
  retryAfterSeconds?: number;
};

function roundedUsd(value: number): number {
  return Math.round(value * 1000) / 1000;
}

function normalizeAuthProvider(value: string | undefined): 'dev' | 'supabase' | undefined {
  if (value === 'dev' || value === 'supabase') {
    return value;
  }
  return undefined;
}

function routeForPersistence(route: ParseDecisionResult['route']): 'cache' | 'fatsecret' | 'gemini' {
  if (route === 'cache' || route === 'fatsecret' || route === 'gemini') {
    return route;
  }
  return 'gemini';
}

function normalizeLocale(rawLocale: string | null | undefined): string {
  const normalized = (rawLocale || '').trim().toLowerCase();
  if (!normalized) {
    return 'en-us';
  }
  return normalized.replace(/[^a-z0-9-]/g, '');
}

function canUseFallback(
  budget: {
    dailyBudgetUsd: number;
    userSoftCapUsd: number;
    globalUsedTodayUsd: number;
    userUsedTodayUsd: number;
    globalBudgetExceeded: boolean;
    userSoftCapExceeded: boolean;
  }
): boolean {
  if (budget.globalBudgetExceeded || budget.userSoftCapExceeded) {
    return false;
  }
  const remainingDailyUsd = budget.dailyBudgetUsd - budget.globalUsedTodayUsd;
  return remainingDailyUsd >= config.aiFallbackCostUsd;
}

export async function executePrimaryParse(input: PrimaryParseOrchestratorInput): Promise<PrimaryParseOrchestratorOutput> {
  const userId = input.auth.userId;
  const rateLimit = checkParseRateLimit(userId);
  if (!rateLimit.allowed) {
    const error = new ApiError(429, 'RATE_LIMITED', 'Too many parse requests. Please retry shortly.');
    // Preserve current route-level behavior where Retry-After is surfaced.
    (error as ApiError & { retryAfterSeconds?: number }).retryAfterSeconds = rateLimit.retryAfterSeconds;
    throw error;
  }

  const budgetBefore = await getBudgetSnapshotForUser({
    userId,
    dailyBudgetUsd: config.aiDailyBudgetUsd,
    userSoftCapUsd: config.aiUserSoftCapUsd
  });
  const featureFlags = await getEffectiveFeatureFlags(userId);
  const fallbackAllowed = config.aiFallbackEnabled && featureFlags.geminiEnabled && canUseFallback(budgetBefore);
  const preferences = await getOnboardingParsePreferences(userId);
  const locale = normalizeLocale(input.locale);
  const units = (preferences.units || 'unknown').toLowerCase();
  const segmentCount = splitFoodTextSegments(input.text).length;
  const effectivePromptVersion = segmentCount > 1 ? config.parsePromptVersion : config.parsePromptVersion.replace(':v2', ':v1');
  const cacheScope = [
    `user=${userId}`,
    `cachev=${config.parseCacheSchemaVersion}`,
    `parser=${config.parseVersion}`,
    `routev=${config.parseProviderRouteVersion}`,
    `prompt=${effectivePromptVersion}`,
    `locale=${locale}`,
    `units=${units}`,
    'primary'
  ].join('|');
  const cacheDebug = config.debugParseCacheKey ? buildParseCacheDebugInfo(input.text, cacheScope) : undefined;

  const pipeline = await runPrimaryParsePipeline(input.text, {
    allowFallback: fallbackAllowed,
    cacheScope,
    featureFlags,
    userId,
    budget: budgetBefore
  });

  let budget = budgetBefore;
  if (pipeline.fallbackUsed && pipeline.fallbackUsage) {
    await writeAiCostEvent({
      userId,
      requestId: input.requestId,
      feature: 'parse_fallback',
      model: pipeline.fallbackUsage.model,
      inputTokens: pipeline.fallbackUsage.inputTokens,
      outputTokens: pipeline.fallbackUsage.outputTokens,
      estimatedCostUsd: pipeline.fallbackUsage.estimatedCostUsd
    });
    budget = await getBudgetSnapshotForUser({
      userId,
      dailyBudgetUsd: config.aiDailyBudgetUsd,
      userSoftCapUsd: config.aiUserSoftCapUsd
    });
  }

  await createParseRequest({
    requestId: input.requestId,
    userId,
    rawText: input.text,
    needsClarification: pipeline.needsClarification,
    cacheHit: pipeline.cacheHit,
    primaryRoute: routeForPersistence(pipeline.route),
    authProvider: normalizeAuthProvider(input.auth.authProvider),
    email: input.auth.email
  });

  return {
    ...pipeline,
    budget: {
      dailyLimitUsd: budget.dailyBudgetUsd,
      dailyUsedTodayUsd: roundedUsd(budget.globalUsedTodayUsd),
      userSoftCapUsd: budget.userSoftCapUsd,
      userUsedTodayUsd: roundedUsd(budget.userUsedTodayUsd),
      userSoftCapExceeded: budget.userSoftCapExceeded,
      fallbackAllowed
    },
    cacheDebug
  };
}
