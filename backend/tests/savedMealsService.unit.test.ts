import { afterEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };

afterEach(() => {
  vi.resetModules();
  vi.restoreAllMocks();
  process.env = { ...baseEnv };
});

describe('savedMealsService.createSavedMeal', () => {
  test('rejects an unknown collection id instead of silently saving into Favorites', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const query = vi
      .fn()
      .mockResolvedValueOnce(undefined)
      .mockResolvedValueOnce({ rows: [{ id: 'favorites-id', name: 'Favorites' }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce(undefined);
    const release = vi.fn();

    vi.doMock('../src/db.js', () => ({
      pool: {
        connect: vi.fn(async () => ({ query, release }))
      }
    }));
    vi.doMock('../src/services/userService.js', () => ({
      ensureUserExists: vi.fn(async () => undefined)
    }));
    vi.doMock('../src/services/logService.js', () => ({
      saveFoodLog: vi.fn()
    }));

    const { createSavedMeal } = await import('../src/services/savedMealsService.js');

    await expect(
      createSavedMeal({
        userId: '11111111-1111-1111-1111-111111111111',
        collectionId: '22222222-2222-2222-2222-222222222222',
        name: 'Lunch template',
        mealPayload: {
          rawText: 'rice bowl',
          confidence: 0.9,
          totals: { calories: 500, protein: 20, carbs: 60, fat: 15 },
          items: [
            {
              name: 'Rice bowl',
              quantity: 1,
              unit: 'bowl',
              grams: 300,
              calories: 500,
              protein: 20,
              carbs: 60,
              fat: 15,
              nutritionSourceId: 'manual',
              matchConfidence: 0.9
            }
          ]
        }
      })
    ).rejects.toMatchObject({
      statusCode: 404,
      code: 'SAVED_MEAL_COLLECTION_NOT_FOUND'
    });

    expect(query).toHaveBeenNthCalledWith(4, 'ROLLBACK');
    expect(query).toHaveBeenCalledTimes(4);
    expect(release).toHaveBeenCalledTimes(1);
  });
});
