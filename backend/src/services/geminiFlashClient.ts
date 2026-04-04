import { config } from '../config.js';

export type GeminiUsage = {
  model: string;
  inputTokens: number;
  outputTokens: number;
};

export type GeminiFailureReason =
  | 'gemini_timeout'
  | 'gemini_rate_limited'
  | 'gemini_http_error'
  | 'gemini_empty_response'
  | 'gemini_network_error';

type GeminiFailure = {
  failureReason: GeminiFailureReason;
};

type GeminiSuccess = {
  jsonText: string;
  usage: GeminiUsage;
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
): Promise<GeminiSuccess | GeminiFailure | null> {
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
        const failureReason: GeminiFailureReason = response.status === 429 ? 'gemini_rate_limited' : 'gemini_http_error';
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
        return { failureReason };
      }

      const payload = (await response.json()) as GeminiResponse;
      const jsonText = extractCandidateText(payload);
      if (!jsonText) {
        console.warn('Gemini API returned no text candidate');
        return { failureReason: 'gemini_empty_response' };
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
      const failureReason: GeminiFailureReason = isAbortLikeError(err) ? 'gemini_timeout' : 'gemini_network_error';

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
      return { failureReason };
    } finally {
      clearTimeout(timeout);
    }
  }

  return null;
}

// ---------------------------------------------------------------------------
// Streaming variant — uses streamGenerateContent + SSE from Google
// ---------------------------------------------------------------------------

export type StreamItemCallback = (itemJson: string, index: number) => void;

/**
 * Streams a Gemini JSON response, emitting each complete JSON object as it
 * arrives. The full accumulated JSON text is returned at the end, identical
 * to the non-streaming path.
 */
export async function streamGeminiJson(
  options: GenerateOptions,
  onItem: StreamItemCallback,
  signal?: AbortSignal
): Promise<GeminiSuccess | GeminiFailure | null> {
  if (!config.geminiApiKey) return null;
  if (isCircuitOpen(Date.now())) return null;

  const model = options.model;
  const endpoint = `${config.geminiApiBaseUrl}/models/${encodeURIComponent(model)}:streamGenerateContent?key=${encodeURIComponent(
    config.geminiApiKey
  )}&alt=sse`;

  const timeoutMs = Math.max(1_000, config.geminiTimeoutMs);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  // Chain caller's abort signal if provided
  if (signal) {
    signal.addEventListener('abort', () => controller.abort(), { once: true });
  }

  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: options.prompt }] }],
        generationConfig: {
          temperature: options.temperature ?? 0.1,
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
      console.warn('Gemini streaming request failed', response.status, body);
      return { failureReason: response.status === 429 ? 'gemini_rate_limited' : 'gemini_http_error' };
    }

    // Read the SSE stream
    const reader = response.body?.getReader();
    if (!reader) {
      return { failureReason: 'gemini_empty_response' };
    }

    const decoder = new TextDecoder();
    let accumulated = '';
    let emittedCount = 0;
    let lastUsageMetadata: GeminiResponse['usageMetadata'] | undefined;

    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });

      // Process complete SSE events (separated by double newlines)
      const events = buffer.split('\n\n');
      buffer = events.pop() ?? ''; // Keep incomplete last chunk

      for (const event of events) {
        const dataLine = event
          .split('\n')
          .find((line) => line.startsWith('data: '));
        if (!dataLine) continue;

        const jsonStr = dataLine.slice(6); // Remove 'data: ' prefix
        try {
          const chunk = JSON.parse(jsonStr) as GeminiResponse;

          // Extract text from this chunk
          const text = chunk.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
          accumulated += text;

          // Track usage metadata (last chunk usually has it)
          if (chunk.usageMetadata) {
            lastUsageMetadata = chunk.usageMetadata;
          }

          // Try to extract complete JSON objects from accumulated text
          const newItems = extractCompleteJsonObjects(accumulated, emittedCount);
          for (const item of newItems) {
            onItem(item.json, emittedCount);
            emittedCount += 1;
          }
        } catch {
          // Partial JSON or non-JSON line — skip
        }
      }
    }

    if (!accumulated) {
      return { failureReason: 'gemini_empty_response' };
    }

    const usage = extractUsage(lastUsageMetadata);
    resetCircuitBreakerAfterSuccess();

    return {
      jsonText: accumulated,
      usage: { model, inputTokens: usage.inputTokens, outputTokens: usage.outputTokens }
    };
  } catch (err) {
    clearRateLimitStreakOnNon429Failure();
    if (signal?.aborted) return null; // Caller cancelled — not an error
    const failureReason: GeminiFailureReason = isAbortLikeError(err) ? 'gemini_timeout' : 'gemini_network_error';
    console.warn('Gemini streaming call failed', err);
    return { failureReason };
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * Extract complete JSON objects from an accumulating JSON array string.
 * Tracks brace depth to find boundaries of `{...}` objects within `[{...},{...}]`.
 */
function extractCompleteJsonObjects(
  text: string,
  alreadyEmitted: number
): Array<{ json: string }> {
  const results: Array<{ json: string }> = [];
  let depth = 0;
  let inString = false;
  let escape = false;
  let objectStart = -1;
  let objectCount = 0;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];

    if (escape) {
      escape = false;
      continue;
    }

    if (ch === '\\' && inString) {
      escape = true;
      continue;
    }

    if (ch === '"') {
      inString = !inString;
      continue;
    }

    if (inString) continue;

    if (ch === '{') {
      if (depth === 0) objectStart = i;
      depth += 1;
    } else if (ch === '}') {
      depth -= 1;
      if (depth === 0 && objectStart >= 0) {
        objectCount += 1;
        if (objectCount > alreadyEmitted) {
          results.push({ json: text.slice(objectStart, i + 1) });
        }
        objectStart = -1;
      }
    }
  }

  return results;
}

export async function generateGeminiJson(
  options: GenerateOptions
): Promise<GeminiSuccess | null> {
  const result = await performGeminiJsonRequest(options.model, [{ text: options.prompt }], options.temperature ?? 0.1);
  return result && 'jsonText' in result ? result : null;
}

export async function generateGeminiJsonWithDiagnostics(
  options: GenerateOptions
): Promise<GeminiSuccess | GeminiFailure | null> {
  return performGeminiJsonRequest(options.model, [{ text: options.prompt }], options.temperature ?? 0.1);
}

export async function generateGeminiMultimodalJson(
  options: GenerateMultimodalOptions
): Promise<GeminiSuccess | null> {
  const result = await performGeminiJsonRequest(options.model, options.parts, options.temperature ?? 0.1);
  return result && 'jsonText' in result ? result : null;
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
