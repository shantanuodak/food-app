import { describe, expect, test } from 'vitest';
import { resolveThinkingBudget } from '../src/services/geminiThinkingConfig.js';

describe('gemini thinking config', () => {
  test('keeps -1 as dynamic thinking budget', () => {
    expect(resolveThinkingBudget('-1')).toBe(-1);
  });

  test('maps named presets and disabled mode', () => {
    expect(resolveThinkingBudget('off')).toBe(0);
    expect(resolveThinkingBudget('low')).toBe(256);
    expect(resolveThinkingBudget('medium')).toBe(1024);
    expect(resolveThinkingBudget('high')).toBe(4096);
  });

  test('omits auto-like and invalid values', () => {
    expect(resolveThinkingBudget('auto')).toBeUndefined();
    expect(resolveThinkingBudget('default')).toBeUndefined();
    expect(resolveThinkingBudget('nonsense')).toBeUndefined();
  });
});
