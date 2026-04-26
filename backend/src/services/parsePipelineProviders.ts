import { getParseCache } from './parseCacheService.js';
import { tryCheapAIFallbackDetailed } from './aiNormalizerService.js';
import type { ParseProvider } from './parseDecisionTypes.js';
import { isValidParseResultShape, resultUsesRetiredProvider, shouldAcceptCachedResult } from './parsePipelineResultUtils.js';
import { config } from '../config.js';

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
