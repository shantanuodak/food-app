import { afterEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };

afterEach(() => {
  vi.unstubAllGlobals();
  vi.resetModules();
  process.env = { ...baseEnv };
});

function jsonResponse(payload: unknown, ok = true, status = 200): Response {
  return {
    ok,
    status,
    json: async () => payload,
    text: async () => JSON.stringify(payload)
  } as Response;
}

describe('nutritionDatabaseService', () => {
  test('normalizes Open Food Facts per-serving values', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    const nds = await import('../src/services/nutritionDatabaseService.js');
    const normalized = nds._normalizeOFFResponse({
      status: 1,
      product: {
        code: '0049000028911',
        product_name: 'Diet Coke',
        brands: 'Coca-Cola',
        serving_size: '12 fl oz',
        nutriments: {
          'energy-kcal_serving': 0,
          proteins_serving: 0,
          carbohydrates_serving: 0,
          fat_serving: 0,
          sodium_serving: 0.04
        }
      }
    });

    expect(normalized.productName).toBe('Diet Coke');
    expect(normalized.brand).toBe('Coca-Cola');
    expect(normalized.servingSizeG).toBeGreaterThan(350);
    expect(normalized.calories).toBe(0);
    expect(normalized.sodiumMg).toBe(40);
  });

  test('looks up barcode through OFF and returns cache on second call', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        status: 1,
        product: {
          code: '0028400433556',
          product_name: 'Cheetos Crunchy',
          brands: 'Cheetos',
          serving_size: '28 g',
          nutriments: {
            'energy-kcal_serving': 160,
            proteins_serving: 2,
            carbohydrates_serving: 15,
            fat_serving: 10
          }
        }
      })
    );
    vi.stubGlobal('fetch', fetchMock);

    const nds = await import('../src/services/nutritionDatabaseService.js');
    const first = await nds.lookupByBarcode('0028400433556');
    const second = await nds.lookupByBarcode('0028400433556');

    expect(first.source).toBe('open_food_facts');
    expect(first.calories).toBe(160);
    expect(second.source).toBe('cache');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  test('falls through to USDA when OFF misses', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.USDA_API_KEY = 'test-usda-key';
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse({ status: 0 }))
      .mockResolvedValueOnce(jsonResponse({ status: 0 }))
      .mockResolvedValueOnce(
        jsonResponse({
          foods: [
            {
              description: 'BRANDED GRANOLA BAR',
              brandOwner: 'Kind',
              dataType: 'Branded',
              gtinUpc: '0602652176800',
              servingSize: 40,
              servingSizeUnit: 'g',
              score: 900,
              foodNutrients: [
                { nutrientId: 1008, nutrientName: 'Energy', unitName: 'KCAL', value: 500 },
                { nutrientId: 1003, nutrientName: 'Protein', unitName: 'G', value: 10 },
                { nutrientId: 1005, nutrientName: 'Carbohydrate, by difference', unitName: 'G', value: 50 },
                { nutrientId: 1004, nutrientName: 'Total lipid (fat)', unitName: 'G', value: 25 }
              ]
            }
          ]
        })
      );
    vi.stubGlobal('fetch', fetchMock);

    const nds = await import('../src/services/nutritionDatabaseService.js');
    const result = await nds.lookupByBarcode('0602652176800');

    expect(result.source).toBe('usda');
    expect(result.calories).toBe(200);
    expect(result.productName).toContain('GRANOLA BAR');
  });

  test('uses FatSecret fallback without preferring unintended Cheetos variants', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.USDA_API_KEY = '';
    process.env.FATSECRET_CLIENT_ID = 'test-fatsecret-id';
    process.env.FATSECRET_CLIENT_SECRET = 'test-fatsecret-secret';
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse({ status: 0 }))
      .mockResolvedValueOnce(jsonResponse({ status: 0 }))
      .mockResolvedValueOnce(jsonResponse({ access_token: 'token', expires_in: 3600 }))
      .mockResolvedValueOnce(
        jsonResponse({
          foods_search: {
            results: {
              food: [
                {
                  food_name: 'Baked! Cheetos Crunchy Cheese Flavored Snacks',
                  brand_name: 'Cheetos',
                  servings: { serving: { calories: '130', carbohydrate: '20', protein: '2', fat: '5', serving_description: '34 pieces' } }
                },
                {
                  food_name: 'Crunchy Buffalo',
                  brand_name: 'Cheetos',
                  servings: { serving: { calories: '150', carbohydrate: '16', protein: '2', fat: '10', serving_description: '13 pieces' } }
                },
                {
                  food_name: 'Crunchy Cheetos (1 oz)',
                  brand_name: 'Cheetos',
                  servings: { serving: { calories: '160', carbohydrate: '15', protein: '2', fat: '10', serving_description: '1 package' } }
                }
              ]
            }
          }
        })
      );
    vi.stubGlobal('fetch', fetchMock);

    const nds = await import('../src/services/nutritionDatabaseService.js');
    const result = await nds.lookupByBarcode('0028400433556');

    expect(result.source).toBe('fatsecret');
    expect(result.productName).toBe('Crunchy Cheetos (1 oz)');
    expect(result.calories).toBe(160);
  });

  test('returns miss for unknown barcode', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    vi.stubGlobal('fetch', vi.fn(async () => jsonResponse({ status: 0 })));
    const nds = await import('../src/services/nutritionDatabaseService.js');
    const result = await nds.lookupByBarcode('0000000000000');
    expect(result.source).toBe('miss');
    expect(result.confidence).toBe(0);
  });
});
