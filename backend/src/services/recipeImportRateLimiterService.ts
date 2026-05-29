import { config } from '../config.js';

// Per-user, per-lane fixed-window rate limiter for the recipe endpoints.
// Recipe import does expensive work (outbound page fetches; a paid Groq
// transcription for the audio lane), so without this an authenticated user
// could turn the server into a fetch/scraping proxy or run up Groq cost.
// Mirrors parseRateLimiterService but keys buckets by `${lane}:${userId}` so
// each lane has an independent budget.

export type RecipeRateLane = 'url' | 'audio' | 'save';

type RecipeBucket = {
  windowStartMs: number;
  count: number;
};

const buckets = new Map<string, RecipeBucket>();
let lastPruneAtMs = 0;

function sanitizeWindowMs(): number {
  return Math.max(1_000, config.recipeRateLimitWindowMs);
}

function maxRequestsForLane(lane: RecipeRateLane): number {
  switch (lane) {
    case 'audio':
      return Math.max(1, config.recipeAudioImportRateLimitMax);
    case 'save':
      return Math.max(1, config.recipeSaveRateLimitMax);
    case 'url':
    default:
      return Math.max(1, config.recipeUrlImportRateLimitMax);
  }
}

function pruneBuckets(nowMs: number): void {
  const windowMs = sanitizeWindowMs();
  if (nowMs - lastPruneAtMs < windowMs) {
    return;
  }
  lastPruneAtMs = nowMs;
  for (const [key, bucket] of buckets.entries()) {
    if (nowMs - bucket.windowStartMs >= windowMs) {
      buckets.delete(key);
    }
  }
}

export function checkRecipeImportRateLimit(
  userId: string,
  lane: RecipeRateLane,
  nowMs: number = Date.now()
): { allowed: boolean; retryAfterSeconds: number } {
  if (!config.recipeRateLimitEnabled) {
    return { allowed: true, retryAfterSeconds: 0 };
  }

  pruneBuckets(nowMs);

  const windowMs = sanitizeWindowMs();
  const maxRequests = maxRequestsForLane(lane);
  const key = `${lane}:${userId}`;
  const existing = buckets.get(key);
  if (!existing || nowMs - existing.windowStartMs >= windowMs) {
    buckets.set(key, { windowStartMs: nowMs, count: 1 });
    return { allowed: true, retryAfterSeconds: 0 };
  }

  if (existing.count < maxRequests) {
    existing.count += 1;
    return { allowed: true, retryAfterSeconds: 0 };
  }

  const retryAfterMs = Math.max(0, windowMs - (nowMs - existing.windowStartMs));
  return {
    allowed: false,
    retryAfterSeconds: Math.max(1, Math.ceil(retryAfterMs / 1000))
  };
}

export function resetRecipeImportRateLimitStateForTests(): void {
  buckets.clear();
  lastPruneAtMs = 0;
}
