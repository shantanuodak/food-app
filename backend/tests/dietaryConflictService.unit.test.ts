import { describe, expect, test } from 'vitest';
import { detectDietaryConflicts } from '../src/services/dietaryConflictService.js';

describe('detectDietaryConflicts', () => {
  test('vegetarian + ham sandwich → 1 diet warning', () => {
    const flags = detectDietaryConflicts({
      itemNames: ['Ham sandwich'],
      dietPreference: 'vegetarian',
      allergies: []
    });
    expect(flags).toHaveLength(1);
    expect(flags[0]).toMatchObject({
      itemName: 'Ham sandwich',
      rule: 'diet',
      ruleKey: 'vegetarian',
      severity: 'warning'
    });
    expect(flags[0].matchedToken).toBe('ham');
  });

  test('peanut allergy + peanut butter toast → 1 critical allergy flag', () => {
    const flags = detectDietaryConflicts({
      itemNames: ['Peanut butter toast'],
      dietPreference: null,
      allergies: ['peanuts']
    });
    expect(flags).toHaveLength(1);
    expect(flags[0]).toMatchObject({
      rule: 'allergy',
      ruleKey: 'peanuts',
      severity: 'critical'
    });
  });

  test('vegan + tofu stir fry → 0 flags', () => {
    const flags = detectDietaryConflicts({
      itemNames: ['Tofu stir fry'],
      dietPreference: 'vegan',
      allergies: []
    });
    expect(flags).toHaveLength(0);
  });

  test('no profile (null + empty) → 0 flags', () => {
    const flags = detectDietaryConflicts({
      itemNames: ['Bacon double cheeseburger'],
      dietPreference: null,
      allergies: []
    });
    expect(flags).toHaveLength(0);
  });

  test('no_preference is treated as no diet rule', () => {
    const flags = detectDietaryConflicts({
      itemNames: ['Cheeseburger'],
      dietPreference: 'no_preference',
      allergies: []
    });
    expect(flags).toHaveLength(0);
  });

  test('case-insensitive matching', () => {
    const flags = detectDietaryConflicts({
      itemNames: ['PORK CHOP'],
      dietPreference: 'vegetarian',
      allergies: []
    });
    expect(flags).toHaveLength(1);
    expect(flags[0].matchedToken).toBe('pork');
  });

  test('one item triggers multiple rules → multiple flags', () => {
    // Vegetarian (warning) + peanut allergy (critical) on a single item
    const flags = detectDietaryConflicts({
      itemNames: ['Chicken peanut satay'],
      dietPreference: 'vegetarian',
      allergies: ['peanuts']
    });
    expect(flags).toHaveLength(2);
    const severities = flags.map((f) => f.severity).sort();
    expect(severities).toEqual(['critical', 'warning']);
  });

  test('multi-key diet preference (comma separated)', () => {
    // User picked vegetarian + gluten_free
    const flags = detectDietaryConflicts({
      itemNames: ['Bacon pasta'],
      dietPreference: 'vegetarian,gluten_free',
      allergies: []
    });
    // bacon → vegetarian; pasta → gluten_free
    expect(flags).toHaveLength(2);
    const ruleKeys = flags.map((f) => f.ruleKey).sort();
    expect(ruleKeys).toEqual(['gluten_free', 'vegetarian']);
  });

  test('aspirational preferences (high_protein, mediterranean) produce no flags', () => {
    const flags = detectDietaryConflicts({
      itemNames: ['Cheeseburger', 'French fries'],
      dietPreference: 'high_protein,mediterranean',
      allergies: []
    });
    expect(flags).toHaveLength(0);
  });

  test('shellfish allergy + lobster roll → critical', () => {
    const flags = detectDietaryConflicts({
      itemNames: ['Lobster roll'],
      dietPreference: null,
      allergies: ['shellfish']
    });
    expect(flags).toHaveLength(1);
    expect(flags[0].severity).toBe('critical');
  });

  test('empty item list → no flags', () => {
    const flags = detectDietaryConflicts({
      itemNames: [],
      dietPreference: 'vegetarian',
      allergies: ['peanuts']
    });
    expect(flags).toHaveLength(0);
  });
});
