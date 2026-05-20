import { afterEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };

afterEach(() => {
  vi.resetModules();
  process.env = { ...baseEnv };
});

describe('cuisineClassifier', () => {
  test.each([
    ['chicken tikka thali with dal and naan', 'indian', 0.85],
    ['masala dosa with sambar and chutney', 'indian', 0.85],
    ['rajma chawal with roti and achaar', 'indian', 0.85],
    ['paneer biryani raita and papad', 'indian', 0.85],
    ['double cheeseburger and fries with ranch', 'us', 0.85],
    ['pancake breakfast with bacon and bagel', 'us', 0.85],
    ['chicken caesar salad with club sandwich', 'us', 0.85],
    ['pepperoni pizza slice with ranch', 'us', 0.72],
    ['fish and chips with yorkshire pudding', 'western', 0.72],
    ['croissant baguette and quiche', 'western', 0.85],
    ['schnitzel with sauerkraut and bratwurst', 'western', 0.85],
    ['ramen with miso and gyoza', 'eastAsian', 0.85],
    ['pad thai with chicken and spring roll', 'eastAsian', 0.72],
    ['bibimbap with kimchi and bulgogi', 'eastAsian', 0.85],
    ['pho with banh mi and spring roll', 'eastAsian', 0.85],
    ['spaghetti carbonara with focaccia', 'mediterranean', 0.72],
    ['hummus falafel tabbouleh and pita', 'mediterranean', 0.85],
    ['shawarma gyro tzatziki and baklava', 'mediterranean', 0.85],
    ['margherita pizza with mozzarella', 'mediterranean', 0.72],
    ['chicken burrito bowl with salsa guacamole and queso fresco', 'latin', 0.85],
    ['arepa empanada and plantain', 'latin', 0.85],
    ['ceviche with tostones and chimichurri', 'latin', 0.85],
    ['tacos with mole salsa and refried beans', 'latin', 0.85]
  ])('routes "%s" to %s', async (contextNote, expectedCuisine, minConfidence) => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    const { classify } = await import('../src/services/imageParse/cuisineClassifier.js');
    const result = await classify({ contextNote });
    expect(result.cuisine).toBe(expectedCuisine);
    expect(result.confidence).toBeGreaterThanOrEqual(minConfidence);
    expect(result.source).toBe('keywords');
  });

  test('uses Latin tiebreaker for authentic signals', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    const { classify } = await import('../src/services/imageParse/cuisineClassifier.js');
    const result = await classify({ contextNote: 'chicken burrito bowl with salsa guacamole and queso fresco' });
    expect(result.cuisine).toBe('latin');
  });

  test('uses US tiebreaker for Tex-Mex with US signals', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    const { classify } = await import('../src/services/imageParse/cuisineClassifier.js');
    const result = await classify({ contextNote: 'burrito bowl with fries and ranch' });
    expect(result.cuisine).toBe('us');
  });

  test('uses Indian locale as a free signal', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    const { classify } = await import('../src/services/imageParse/cuisineClassifier.js');
    const result = await classify({ contextNote: '', userLocale: 'en-IN' });
    expect(result.cuisine).toBe('indian');
    expect(result.source).toBe('locale');
    expect(result.confidence).toBeGreaterThanOrEqual(0.68);
  });

  test('uses recent history when context is weak', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    const { classify } = await import('../src/services/imageParse/cuisineClassifier.js');
    const result = await classify({
      contextNote: '',
      recentCuisines: ['western', 'western', 'western', 'western', 'generic']
    });
    expect(result.cuisine).toBe('western');
    expect(result.source).toBe('history');
    expect(result.confidence).toBe(0.7);
  });

  test('defaults to generic without usable context', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    const { classify } = await import('../src/services/imageParse/cuisineClassifier.js');
    const result = await classify({ contextNote: '' });
    expect(result.cuisine).toBe('generic');
    expect(result.confidence).toBe(0.3);
  });
});
