import { describe, expect, test } from 'vitest';
import {
  buildGeminiFallbackPrompt,
  buildGeminiFallbackPromptTemplate
} from '../src/services/aiNormalizerService.js';
import { buildGeminiEscalationPrompt } from '../src/services/aiEscalationService.js';
import type { ParseResult } from '../src/services/deterministicParser.js';

const baseline: ParseResult = {
  confidence: 0.55,
  assumptions: [],
  items: [
    {
      name: 'Generic food',
      quantity: 1,
      unit: 'serving',
      grams: 100,
      calories: 100,
      protein: 5,
      carbs: 10,
      fat: 3,
      matchConfidence: 0.5,
      nutritionSourceId: 'seed_generic_food'
    }
  ],
  totals: {
    calories: 100,
    protein: 5,
    carbs: 10,
    fat: 3
  }
};

describe('AI nutrition prompt templates', () => {
  test('default prompt version is bumped for the accuracy prompt revision', async () => {
    const { config } = await import('../src/config.js');

    expect(config.parsePromptVersion).toBe('gemini-2.5-flash:v3');
  });

  test('fallback template avoids conflicting segment instructions', () => {
    const template = buildGeminiFallbackPromptTemplate();

    expect(template).toContain('return exactly one item per input segment');
    expect(template).toContain('do not split, merge, add, or drop segments');
    expect(template).not.toContain('joined by "and", "&", or "with"');
  });

  test('fallback prompt treats deterministic baseline as replaceable hint', () => {
    const prompt = buildGeminiFallbackPrompt('1 cup butter panner masala', baseline);

    expect(prompt).toContain('use the baseline parse only as a hint');
    expect(prompt).toContain('hint only; improve or replace inaccurate values');
    expect(prompt).toContain('default servings: egg=1 large');
    expect(prompt).toContain('4 kcal/g protein');
    expect(prompt).toContain('one short user-facing explanation sentence');
  });

  test('escalation prompt mirrors accuracy rules from fallback prompt', () => {
    const prompt = buildGeminiEscalationPrompt('Big Mac');

    expect(prompt).toContain('official label/menu serving');
    expect(prompt).toContain('USDA-style common serving estimates');
    expect(prompt).toContain('set matchConfidence based on food identity and portion confidence');
    expect(prompt).toContain('avoid zero-calorie outputs unless the item is truly near-zero');
    expect(prompt).toContain('one short user-facing explanation sentence');
  });
});
