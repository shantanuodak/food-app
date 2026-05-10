import { describe, expect, test } from 'vitest';
import { scoreMacro, scoreNutrition } from '../src/services/benchmarkScoringService.js';

describe('benchmark scoring', () => {
  test('scores exact macro matches as 100', () => {
    expect(scoreMacro(400, 400)).toBe(100);
  });

  test('scores percentage error against the reference value', () => {
    expect(scoreMacro(400, 350)).toBe(87.5);
  });

  test('handles zero references without divide-by-zero', () => {
    expect(scoreMacro(0, 0)).toBe(100);
    expect(scoreMacro(0, 20)).toBe(0);
  });

  test('computes weighted overall nutrition score and label', () => {
    const score = scoreNutrition(
      { calories: 400, protein: 20, carbs: 40, fat: 10 },
      { calories: 350, protein: 18, carbs: 42, fat: 9 }
    );

    expect(score.calories).toBe(87.5);
    expect(score.protein).toBe(90);
    expect(score.carbs).toBe(95);
    expect(score.fat).toBe(90);
    expect(score.overall).toBe(90);
    expect(score.label).toBe('strong');
  });

  test('marks parser errors as failed even if numbers are present', () => {
    const score = scoreNutrition(
      { calories: 400, protein: 20, carbs: 40, fat: 10 },
      { calories: 400, protein: 20, carbs: 40, fat: 10 },
      { hasError: true }
    );

    expect(score.overall).toBe(100);
    expect(score.label).toBe('failed');
  });
});
