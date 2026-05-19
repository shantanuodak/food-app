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

describe('savedMealsService.deleteSavedMeal', () => {
  test('deletes a saved meal owned by the user and updates the collection timestamp', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const query = vi
      .fn()
      .mockResolvedValueOnce({
        rows: [{ id: '33333333-3333-3333-3333-333333333333', collection_id: '44444444-4444-4444-4444-444444444444' }]
      })
      .mockResolvedValueOnce({ rows: [] });

    vi.doMock('../src/db.js', () => ({
      pool: { query }
    }));
    vi.doMock('../src/services/userService.js', () => ({
      ensureUserExists: vi.fn(async () => undefined)
    }));
    vi.doMock('../src/services/logService.js', () => ({
      saveFoodLog: vi.fn()
    }));

    const { deleteSavedMeal } = await import('../src/services/savedMealsService.js');

    await expect(
      deleteSavedMeal('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333')
    ).resolves.toEqual({
      id: '33333333-3333-3333-3333-333333333333',
      status: 'deleted'
    });

    expect(query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('DELETE FROM saved_meals'),
      ['33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111']
    );
    expect(query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('UPDATE saved_meal_collections'),
      ['44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111']
    );
  });

  test('returns not found when the saved meal is missing or owned by another user', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const query = vi.fn().mockResolvedValueOnce({ rows: [] });

    vi.doMock('../src/db.js', () => ({
      pool: { query }
    }));
    vi.doMock('../src/services/userService.js', () => ({
      ensureUserExists: vi.fn(async () => undefined)
    }));
    vi.doMock('../src/services/logService.js', () => ({
      saveFoodLog: vi.fn()
    }));

    const { deleteSavedMeal } = await import('../src/services/savedMealsService.js');

    await expect(
      deleteSavedMeal('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333')
    ).rejects.toMatchObject({
      statusCode: 404,
      code: 'SAVED_MEAL_NOT_FOUND'
    });

    expect(query).toHaveBeenCalledTimes(1);
  });
});
