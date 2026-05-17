import type { PoolClient } from 'pg';
import { pool } from '../db.js';
import { ensureUserExists } from './userService.js';
import { saveFoodLog } from './logService.js';
import { ApiError } from '../utils/errors.js';

export type SavedMealItemInput = {
  name: string;
  quantity: number;
  amount?: number;
  unit: string;
  unitNormalized?: string;
  grams: number;
  gramsPerUnit?: number | null;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  nutritionSourceId: string;
  originalNutritionSourceId?: string;
  sourceFamily?: string;
  matchConfidence: number;
  needsClarification?: boolean | null;
  manualOverride?: unknown;
};

export type SavedMealPayloadInput = {
  rawText: string;
  loggedAt?: string;
  inputKind?: string | null;
  imageRef?: string | null;
  confidence: number;
  totals: {
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
  };
  sourcesUsed?: string[] | null;
  assumptions?: string[] | null;
  items: SavedMealItemInput[];
};

export type SavedMealCollection = {
  id: string;
  name: string;
  mealCount: number;
  createdAt: string;
  updatedAt: string;
};

export type SavedMeal = {
  id: string;
  collectionId: string;
  collectionName: string;
  name: string;
  rawText: string;
  inputKind: string | null;
  totals: {
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
  };
  itemCount: number;
  mealPayload: SavedMealPayloadInput;
  createdAt: string;
  updatedAt: string;
};

type AuthContext = {
  authProvider?: string | null;
  userEmail?: string | null;
};

function toNumber(value: unknown): number {
  const num = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function iso(value: Date | string): string {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

async function ensureDefaultCollection(
  userId: string,
  auth: AuthContext,
  client: PoolClient
): Promise<{ id: string; name: string }> {
  await ensureUserExists(userId, { authProvider: auth.authProvider, email: auth.userEmail }, client);
  const result = await client.query<{ id: string; name: string }>(
    `
    INSERT INTO saved_meal_collections (user_id, name)
    VALUES ($1, 'Favorites')
    ON CONFLICT (user_id, name) DO UPDATE SET updated_at = saved_meal_collections.updated_at
    RETURNING id, name
    `,
    [userId]
  );
  return result.rows[0]!;
}

export async function listSavedMeals(userId: string, auth: AuthContext = {}): Promise<{
  collections: SavedMealCollection[];
  meals: SavedMeal[];
}> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await ensureDefaultCollection(userId, auth, client);

    const collectionsResult = await client.query<{
      id: string;
      name: string;
      meal_count: number | string;
      created_at: Date;
      updated_at: Date;
    }>(
      `
      SELECT c.id, c.name, COUNT(m.id)::int AS meal_count, c.created_at, c.updated_at
      FROM saved_meal_collections c
      LEFT JOIN saved_meals m ON m.collection_id = c.id
      WHERE c.user_id = $1
      GROUP BY c.id
      ORDER BY c.updated_at DESC, c.created_at DESC
      `,
      [userId]
    );

    const mealsResult = await client.query<{
      id: string;
      collection_id: string;
      collection_name: string;
      name: string;
      raw_text: string;
      input_kind: string | null;
      total_calories: string;
      total_protein_g: string;
      total_carbs_g: string;
      total_fat_g: string;
      meal_payload_json: SavedMealPayloadInput;
      created_at: Date;
      updated_at: Date;
    }>(
      `
      SELECT
        m.id,
        m.collection_id,
        c.name AS collection_name,
        m.name,
        m.raw_text,
        m.input_kind,
        m.total_calories,
        m.total_protein_g,
        m.total_carbs_g,
        m.total_fat_g,
        m.meal_payload_json,
        m.created_at,
        m.updated_at
      FROM saved_meals m
      JOIN saved_meal_collections c ON c.id = m.collection_id
      WHERE m.user_id = $1
      ORDER BY m.updated_at DESC, m.created_at DESC
      `,
      [userId]
    );

    await client.query('COMMIT');
    return {
      collections: collectionsResult.rows.map((row) => ({
        id: row.id,
        name: row.name,
        mealCount: toNumber(row.meal_count),
        createdAt: iso(row.created_at),
        updatedAt: iso(row.updated_at)
      })),
      meals: mealsResult.rows.map((row) => ({
        id: row.id,
        collectionId: row.collection_id,
        collectionName: row.collection_name,
        name: row.name,
        rawText: row.raw_text,
        inputKind: row.input_kind,
        totals: {
          calories: toNumber(row.total_calories),
          protein: toNumber(row.total_protein_g),
          carbs: toNumber(row.total_carbs_g),
          fat: toNumber(row.total_fat_g)
        },
        itemCount: Array.isArray(row.meal_payload_json?.items) ? row.meal_payload_json.items.length : 0,
        mealPayload: row.meal_payload_json,
        createdAt: iso(row.created_at),
        updatedAt: iso(row.updated_at)
      }))
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function createSavedMealCollection(
  userId: string,
  name: string,
  auth: AuthContext = {}
): Promise<SavedMealCollection> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await ensureUserExists(userId, { authProvider: auth.authProvider, email: auth.userEmail }, client);
    const result = await client.query<{
      id: string;
      name: string;
      created_at: Date;
      updated_at: Date;
    }>(
      `
      INSERT INTO saved_meal_collections (user_id, name)
      VALUES ($1, $2)
      ON CONFLICT (user_id, name) DO UPDATE SET updated_at = NOW()
      RETURNING id, name, created_at, updated_at
      `,
      [userId, name]
    );
    await client.query('COMMIT');
    const row = result.rows[0]!;
    return {
      id: row.id,
      name: row.name,
      mealCount: 0,
      createdAt: iso(row.created_at),
      updatedAt: iso(row.updated_at)
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function createSavedMeal(input: {
  userId: string;
  auth?: AuthContext;
  collectionId?: string | null;
  collectionName?: string | null;
  name: string;
  mealPayload: SavedMealPayloadInput;
}): Promise<SavedMeal> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const fallbackCollection = await ensureDefaultCollection(input.userId, input.auth ?? {}, client);

    let collection = fallbackCollection;
    if (input.collectionId) {
      const existing = await client.query<{ id: string; name: string }>(
        `SELECT id, name FROM saved_meal_collections WHERE id = $1 AND user_id = $2`,
        [input.collectionId, input.userId]
      );
      if (existing.rows[0]) {
        collection = existing.rows[0];
      }
    } else if (input.collectionName?.trim()) {
      const created = await client.query<{ id: string; name: string }>(
        `
        INSERT INTO saved_meal_collections (user_id, name)
        VALUES ($1, $2)
        ON CONFLICT (user_id, name) DO UPDATE SET updated_at = NOW()
        RETURNING id, name
        `,
        [input.userId, input.collectionName.trim()]
      );
      collection = created.rows[0]!;
    }

    const totals = input.mealPayload.totals;
    const inserted = await client.query<{
      id: string;
      collection_id: string;
      name: string;
      raw_text: string;
      input_kind: string | null;
      total_calories: string;
      total_protein_g: string;
      total_carbs_g: string;
      total_fat_g: string;
      meal_payload_json: SavedMealPayloadInput;
      created_at: Date;
      updated_at: Date;
    }>(
      `
      INSERT INTO saved_meals (
        user_id, collection_id, name, raw_text, input_kind,
        total_calories, total_protein_g, total_carbs_g, total_fat_g,
        meal_payload_json
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb)
      RETURNING id, collection_id, name, raw_text, input_kind, total_calories,
        total_protein_g, total_carbs_g, total_fat_g, meal_payload_json, created_at, updated_at
      `,
      [
        input.userId,
        collection.id,
        input.name,
        input.mealPayload.rawText,
        input.mealPayload.inputKind ?? null,
        totals.calories,
        totals.protein,
        totals.carbs,
        totals.fat,
        JSON.stringify(input.mealPayload)
      ]
    );

    await client.query(`UPDATE saved_meal_collections SET updated_at = NOW() WHERE id = $1`, [collection.id]);
    await client.query('COMMIT');

    const row = inserted.rows[0]!;
    return {
      id: row.id,
      collectionId: row.collection_id,
      collectionName: collection.name,
      name: row.name,
      rawText: row.raw_text,
      inputKind: row.input_kind,
      totals: {
        calories: toNumber(row.total_calories),
        protein: toNumber(row.total_protein_g),
        carbs: toNumber(row.total_carbs_g),
        fat: toNumber(row.total_fat_g)
      },
      itemCount: Array.isArray(row.meal_payload_json?.items) ? row.meal_payload_json.items.length : 0,
      mealPayload: row.meal_payload_json,
      createdAt: iso(row.created_at),
      updatedAt: iso(row.updated_at)
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function logSavedMeal(input: {
  userId: string;
  auth?: AuthContext;
  savedMealId: string;
  loggedAt: string;
}): Promise<{ logId: string; status: 'saved'; healthSync: unknown }> {
  const result = await pool.query<{
    meal_payload_json: SavedMealPayloadInput;
    name: string;
  }>(
    `SELECT meal_payload_json, name FROM saved_meals WHERE id = $1 AND user_id = $2`,
    [input.savedMealId, input.userId]
  );
  const row = result.rows[0];
  if (!row) {
    throw new ApiError(404, 'SAVED_MEAL_NOT_FOUND', 'Saved meal not found');
  }

  const payload = row.meal_payload_json;
  return saveFoodLog({
    userId: input.userId,
    authProvider: input.auth?.authProvider,
    userEmail: input.auth?.userEmail,
    rawText: payload.rawText || row.name,
    loggedAt: input.loggedAt,
    inputKind: 'text',
    confidence: payload.confidence,
    totals: payload.totals,
    sourcesUsed: payload.sourcesUsed?.filter((source): source is 'cache' | 'gemini' | 'manual' =>
      source === 'cache' || source === 'gemini' || source === 'manual'
    ),
    assumptions: payload.assumptions ?? [],
    items: payload.items.map((item) => ({
      foodName: item.name,
      quantity: item.quantity,
      amount: item.amount,
      unit: item.unit,
      unitNormalized: item.unitNormalized,
      grams: item.grams,
      gramsPerUnit: item.gramsPerUnit,
      calories: item.calories,
      protein: item.protein,
      carbs: item.carbs,
      fat: item.fat,
      nutritionSourceId: item.nutritionSourceId,
      originalNutritionSourceId: item.originalNutritionSourceId,
      sourceFamily:
        item.sourceFamily === 'cache' || item.sourceFamily === 'gemini' || item.sourceFamily === 'manual'
          ? item.sourceFamily
          : undefined,
      matchConfidence: item.matchConfidence,
      needsClarification: false
    }))
  });
}
