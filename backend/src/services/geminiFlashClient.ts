import { config } from '../config.js';

export type GeminiUsage = {
  model: string;
  inputTokens: number;
  outputTokens: number;
};

type GenerateOptions = {
  model: string;
  prompt: string;
  temperature?: number;
};

type MultimodalPart =
  | {
      text: string;
    }
  | {
      inlineData: {
        mimeType: string;
        data: string;
      };
    };

type GenerateMultimodalOptions = {
  model: string;
  parts: MultimodalPart[];
  temperature?: number;
};

type GeminiCandidate = {
  content?: {
    parts?: Array<{
      text?: string;
    }>;
  };
};

type GeminiResponse = {
  candidates?: GeminiCandidate[];
  usageMetadata?: {
    promptTokenCount?: number;
    candidatesTokenCount?: number;
    totalTokenCount?: number;
  };
};

type CircuitBreakerState = {
  consecutive429: number;
  openedUntilMs: number;
};

function isAbortLikeError(err: unknown): boolean {
  if (err instanceof DOMException && err.name === 'AbortError') {
    return true;
  }
  if (err instanceof Error) {
    const name = err.name.toLowerCase();
    const message = err.message.toLowerCase();
    return name.includes('abort') || message.includes('aborted') || message.includes('aborterror');
  }
  return false;
}

const geminiCircuitBreaker: CircuitBreakerState = {
  consecutive429: 0,
  openedUntilMs: 0
};

function resetCircuitBreakerAfterSuccess(): void {
  geminiCircuitBreaker.consecutive429 = 0;
  geminiCircuitBreaker.openedUntilMs = 0;
}

function markRateLimitFailure(nowMs: number): void {
  if (!config.geminiCircuitBreakerEnabled) {
    return;
  }
  geminiCircuitBreaker.consecutive429 += 1;
  const threshold = Math.max(1, config.geminiCircuitBreakerConsecutive429);
  if (geminiCircuitBreaker.consecutive429 >= threshold) {
    const cooldownMs = Math.max(1_000, config.geminiCircuitBreakerCooldownMs);
    geminiCircuitBreaker.openedUntilMs = nowMs + cooldownMs;
    console.warn(
      '[gemini_circuit_breaker_open]',
      JSON.stringify({
        threshold,
        consecutive429: geminiCircuitBreaker.consecutive429,
        cooldownMs
      })
    );
  }
}

function clearRateLimitStreakOnNon429Failure(): void {
  if (!config.geminiCircuitBreakerEnabled) {
    return;
  }
  geminiCircuitBreaker.consecutive429 = 0;
}

function isCircuitOpen(nowMs: number): boolean {
  return config.geminiCircuitBreakerEnabled && geminiCircuitBreaker.openedUntilMs > nowMs;
}

function safeNumber(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function extractUsage(usageMetadata: GeminiResponse['usageMetadata']): { inputTokens: number; outputTokens: number } {
  const promptTokenCount = safeNumber(usageMetadata?.promptTokenCount);
  const candidatesTokenCount = safeNumber(usageMetadata?.candidatesTokenCount);
  const totalTokenCount = safeNumber(usageMetadata?.totalTokenCount);

  const inputTokens = promptTokenCount > 0 ? promptTokenCount : Math.max(0, totalTokenCount - candidatesTokenCount);
  const outputTokens = candidatesTokenCount > 0 ? candidatesTokenCount : Math.max(0, totalTokenCount - inputTokens);

  return {
    inputTokens,
    outputTokens
  };
}

function extractCandidateText(response: GeminiResponse): string | null {
  const first = response.candidates?.[0];
  if (!first?.content?.parts || first.content.parts.length === 0) {
    return null;
  }

  const text = first.content.parts
    .map((part) => part.text || '')
    .join('')
    .trim();

  return text || null;
}

function isRetryableStatus(status: number): boolean {
  return status === 429 || status === 500 || status === 502 || status === 503 || status === 504;
}

function jitterDelay(baseMs: number, jitterMs: number): number {
  if (jitterMs <= 0) {
    return baseMs;
  }
  const delta = Math.floor(Math.random() * jitterMs);
  return baseMs + delta;
}

function computeRetryDelayMs(attempt: number): number {
  const baseDelay = Math.max(50, config.geminiRetryBaseDelayMs);
  const maxDelay = Math.max(baseDelay, config.geminiRetryMaxDelayMs);
  const expDelay = Math.min(maxDelay, baseDelay * 2 ** Math.max(0, attempt - 1));
  return jitterDelay(expDelay, Math.max(0, config.geminiRetryJitterMs));
}

async function sleep(ms: number): Promise<void> {
  if (ms <= 0) return;
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function performGeminiJsonRequest(
  model: string,
  parts: MultimodalPart[],
  temperature = 0.1
): Promise<{ jsonText: string; usage: GeminiUsage } | null> {
  if (!config.geminiApiKey) {
    return null;
  }
  const nowMs = Date.now();
  if (isCircuitOpen(nowMs)) {
    return null;
  }

  const endpoint = `${config.geminiApiBaseUrl}/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(
    config.geminiApiKey
  )}`;

  const maxAttempts = Math.max(1, config.geminiRetryMaxAttempts, config.geminiAbortRetryCount + 1);
  const timeoutMs = Math.max(1_000, config.geminiTimeoutMs);

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          contents: [
            {
              role: 'user',
              parts
            }
          ],
          generationConfig: {
            temperature,
            responseMimeType: 'application/json'
          }
        }),
        signal: controller.signal
      });

      if (!response.ok) {
        const body = await response.text().catch(() => '');
        const now = Date.now();
        if (response.status === 429) {
          markRateLimitFailure(now);
        } else {
          clearRateLimitStreakOnNon429Failure();
        }
        const retryable = isRetryableStatus(response.status);
        console.warn('Gemini API request failed', response.status, body);
        if (retryable && attempt < maxAttempts) {
          const delayMs = computeRetryDelayMs(attempt);
          console.warn('[gemini_retry]', JSON.stringify({ attempt, maxAttempts, delayMs, status: response.status }));
          await sleep(delayMs);
          continue;
        }
        return null;
      }

      const payload = (await response.json()) as GeminiResponse;
      const jsonText = extractCandidateText(payload);
      if (!jsonText) {
        console.warn('Gemini API returned no text candidate');
        return null;
      }

      const usage = extractUsage(payload.usageMetadata);
      resetCircuitBreakerAfterSuccess();
      return {
        jsonText,
        usage: {
          model,
          inputTokens: usage.inputTokens,
          outputTokens: usage.outputTokens
        }
      };
    } catch (err) {
      clearRateLimitStreakOnNon429Failure();

      if (attempt < maxAttempts) {
        const delayMs = computeRetryDelayMs(attempt);
        console.warn(
          '[gemini_retry]',
          JSON.stringify({
            attempt,
            maxAttempts,
            timeoutMs,
            delayMs,
            abortLike: isAbortLikeError(err)
          })
        );
        await sleep(delayMs);
        continue;
      }

      console.warn('Gemini API call failed; falling back', err);
      return null;
    } finally {
      clearTimeout(timeout);
    }
  }

  return null;
}

export async function generateGeminiJson(options: GenerateOptions): Promise<{ jsonText: string; usage: GeminiUsage } | null> {
  return performGeminiJsonRequest(options.model, [{ text: options.prompt }], options.temperature ?? 0.1);
}

export async function generateGeminiMultimodalJson(
  options: GenerateMultimodalOptions
): Promise<{ jsonText: string; usage: GeminiUsage } | null> {
  return performGeminiJsonRequest(options.model, options.parts, options.temperature ?? 0.1);
}

export function isGeminiCircuitOpenForDiagnostics(nowMs = Date.now()): boolean {
  return isCircuitOpen(nowMs);
}

export function getGeminiCircuitRetryAfterSeconds(nowMs = Date.now()): number | null {
  if (!isCircuitOpen(nowMs)) {
    return null;
  }

  const remainingMs = geminiCircuitBreaker.openedUntilMs - nowMs;
  if (remainingMs <= 0) {
    return null;
  }

  return Math.max(1, Math.ceil(remainingMs / 1000));
}

export function getGeminiCircuitBreakerStateForTests(): CircuitBreakerState {
  return {
    consecutive429: geminiCircuitBreaker.consecutive429,
    openedUntilMs: geminiCircuitBreaker.openedUntilMs
  };
}

export function resetGeminiCircuitBreakerStateForTests(): void {
  geminiCircuitBreaker.consecutive429 = 0;
  geminiCircuitBreaker.openedUntilMs = 0;
}
