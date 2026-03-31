import { afterEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };
const originalFetch = globalThis.fetch;

afterEach(() => {
  vi.resetModules();
  process.env = { ...baseEnv };
  globalThis.fetch = originalFetch;
});

describe('gemini circuit breaker', () => {
  test('opens circuit after configured number of 429 responses', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.GEMINI_API_KEY = 'test-key';
    process.env.GEMINI_CIRCUIT_BREAKER_ENABLED = 'true';
    process.env.GEMINI_CIRCUIT_BREAKER_CONSECUTIVE_429 = '2';
    process.env.GEMINI_CIRCUIT_BREAKER_COOLDOWN_MS = '30000';
    process.env.GEMINI_RETRY_MAX_ATTEMPTS = '1';
    process.env.GEMINI_ABORT_RETRY_COUNT = '0';

    let fetchCalls = 0;
    globalThis.fetch = vi.fn(async () => {
      fetchCalls += 1;
      return new Response('rate limited', { status: 429 });
    }) as typeof fetch;

    const module = await import('../src/services/geminiFlashClient.js');
    module.resetGeminiCircuitBreakerStateForTests();

    const first = await module.generateGeminiJson({
      model: 'gemini-2.5-flash',
      prompt: 'test',
      temperature: 0.1
    });
    expect(first).toBeNull();
    expect(module.getGeminiCircuitBreakerStateForTests().consecutive429).toBe(1);

    const second = await module.generateGeminiJson({
      model: 'gemini-2.5-flash',
      prompt: 'test',
      temperature: 0.1
    });
    expect(second).toBeNull();
    expect(module.getGeminiCircuitBreakerStateForTests().openedUntilMs).toBeGreaterThan(Date.now());

    const third = await module.generateGeminiJson({
      model: 'gemini-2.5-flash',
      prompt: 'test',
      temperature: 0.1
    });
    expect(third).toBeNull();
    expect(fetchCalls).toBe(2);
  });
});
