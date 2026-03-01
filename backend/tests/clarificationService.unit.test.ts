import { describe, expect, test } from 'vitest';
import { buildClarificationQuestions } from '../src/services/clarificationService.js';
import type { ParseResult } from '../src/services/deterministicParser.js';

function baseResult(overrides?: Partial<ParseResult>): ParseResult {
  return {
    confidence: 0.2,
    assumptions: [],
    items: [],
    totals: {
      calories: 0,
      protein: 0,
      carbs: 0,
      fat: 0
    },
    ...overrides
  };
}

describe('clarification question segmentation', () => {
  test('generates item-level clarification for conjunction input', () => {
    const questions = buildClarificationQuestions('2 eggs and toast', baseResult());
    expect(questions.length).toBeGreaterThan(0);
    const joined = questions.join(' ').toLowerCase();
    expect(joined.includes('2 eggs') || joined.includes('eggs')).toBe(true);
  });

  test('does not split protected dish phrases in clarification', () => {
    const questions = buildClarificationQuestions('mac and cheese', baseResult());
    const joined = questions.join(' ').toLowerCase();
    expect(joined.includes('mac and cheese')).toBe(true);
  });
});
