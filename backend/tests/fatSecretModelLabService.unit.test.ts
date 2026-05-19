import { describe, expect, test } from 'vitest';
import { starterFatSecretModelLabCases } from '../src/services/fatSecretModelLabService.js';

describe('fatSecretModelLabService', () => {
  test('builds dashboard-only starter text cases capped by the requested limit', () => {
    const cases = starterFatSecretModelLabCases(3);

    expect(cases).toHaveLength(3);
    expect(cases[0]).toMatchObject({
      kind: 'text',
      inputText: 'black coffee 1 cup',
      fatSecretQuery: 'black coffee 1 cup',
      servingHint: 'black coffee 1 cup'
    });
    expect(cases.every((item) => item.kind === 'text')).toBe(true);
  });
});
