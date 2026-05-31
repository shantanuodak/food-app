import { config } from '../config.js';

type ParseBucket = {
  windowStartMs: number;
  count: number;
};

const buckets = new Map<string, ParseBucket>();
let lastPruneAtMs = 0;
let maxBuckets = 100_000;

function sanitizeWindowMs(): number {
  return Math.max(1_000, config.parseRateLimitWindowMs);
}

function sanitizeMaxRequests(): number {
  return Math.max(1, config.parseRateLimitMaxRequests);
}

function pruneBuckets(nowMs: number): void {
  const windowMs = sanitizeWindowMs();
  if (nowMs - lastPruneAtMs < windowMs) {
    return;
  }
  lastPruneAtMs = nowMs;
  for (const [userId, bucket] of buckets.entries()) {
    if (nowMs - bucket.windowStartMs >= windowMs) {
      buckets.delete(userId);
    }
  }
}

function enforceBucketCap(): void {
  // Memory safety valve. pruneBuckets is time-gated, so under a flood of
  // distinct user IDs the Map could grow unbounded between prunes. Map keeps
  // insertion order, so the first key is the oldest-tracked — evict FIFO.
  while (buckets.size > maxBuckets) {
    const oldest = buckets.keys().next().value as string | undefined;
    if (oldest === undefined) {
      break;
    }
    buckets.delete(oldest);
  }
}

export function checkParseRateLimit(
  userId: string,
  nowMs: number = Date.now()
): { allowed: boolean; retryAfterSeconds: number } {
  if (!config.parseRateLimitEnabled) {
    return { allowed: true, retryAfterSeconds: 0 };
  }

  pruneBuckets(nowMs);

  const windowMs = sanitizeWindowMs();
  const maxRequests = sanitizeMaxRequests();
  const existing = buckets.get(userId);
  if (!existing || nowMs - existing.windowStartMs >= windowMs) {
    buckets.set(userId, { windowStartMs: nowMs, count: 1 });
    enforceBucketCap();
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

export function resetParseRateLimitStateForTests(): void {
  buckets.clear();
  lastPruneAtMs = 0;
  maxBuckets = 100_000;
}

export function setParseRateLimitMaxBucketsForTests(value: number): void {
  maxBuckets = value;
}

export function getParseRateLimitBucketCountForTests(): number {
  return buckets.size;
}
