import type { PoolClient } from 'pg';
import { pool } from '../db.js';
import { ApiError } from '../utils/errors.js';
import { getSaveIdempotencyRecord, insertSaveIdempotencyRecord, payloadHash } from './idempotencyService.js';
import { buildHealthSyncContract, type HealthSyncContract } from './healthSyncContractService.js';
import { ensureUserExists } from './userService.js';

type LogItemInput = {
  foodName: string;
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
  sourceFamily?: 'cache' | 'fatsecret' | 'gemini' | 'manual';
  needsClarification?: boolean;
  manualOverrideMeta?: { enabled: boolean; reason?: string; editedFields: string[] } | null;
  matchConfidence: number;
};

type SaveLogInput = {
  userId: string;
  authProvider?: string | null;
  userEmail?: string | null;
  rawText: string;
  loggedAt: string;
  mealType?: string;
  imageRef?: string;
  inputKind?: 'text' | 'image' | 'voice' | 'manual';
  confidence: number;
  totals: {
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
  };
  sourcesUsed?: Array<'cache' | 'fatsecret' | 'gemini' | 'manual'>;
  items: LogItemInput[];
};

type SaveLogResponse = { logId: string; status: 'saved'; healthSync: HealthSyncContract };

function withHealthSync(userId: string, logId: string, response?: Partial<SaveLogResponse> | null): SaveLogResponse {
  const status = response?.status === 'saved' ? 'saved' : 'saved';
  const healthSync =
    response?.healthSync &&
    typeof response.healthSync.healthWriteKey === 'string' &&
    response.healthSync.healthWriteKey.trim().length > 0
      ? response.healthSync
      : buildHealthSyncContract(userId, logId);

  return {
    logId,
    status,
    healthSync
  };
}

export async function saveFoodLog(input: SaveLogInput): Promise<SaveLogResponse> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await ensureUserExists(
      input.userId,
      {
        authProvider: input.authProvider,
        email: input.userEmail
      },
      client
    );

    const logInsert = await client.query<{ id: string }>(
      `
      INSERT INTO food_logs (
        user_id, logged_at, meal_type, raw_text,
        total_calories, total_protein_g, total_carbs_g, total_fat_g,
        parse_confidence, parse_sources_used_json, image_ref, input_kind, created_at, updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, $11, $12, NOW(), NOW())
      RETURNING id
      `,
      [
        input.userId,
        input.loggedAt,
        input.mealType ?? null,
        input.rawText,
        input.totals.calories,
        input.totals.protein,
        input.totals.carbs,
        input.totals.fat,
        input.confidence,
        JSON.stringify(input.sourcesUsed || []),
        input.imageRef ?? null,
        input.inputKind ?? 'text'
      ]
    );

    const logId = logInsert.rows[0]?.id;
    if (!logId) {
      throw new Error('Failed to create food log record');
    }

    for (const item of input.items) {
      await client.query(
        `
        INSERT INTO food_log_items (
          food_log_id, food_name, quantity, amount, unit, unit_normalized, grams, grams_per_unit,
          calories, protein_g, carbs_g, fat_g,
          nutrition_source_id, original_nutrition_source_id, source_family,
          needs_clarification, manual_override_json, match_confidence
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17::jsonb,$18)
        `,
        [
          logId,
          item.foodName,
          item.quantity,
          item.amount ?? item.quantity,
          item.unit,
          item.unitNormalized ?? item.unit,
          item.grams,
          item.gramsPerUnit ?? null,
          item.calories,
          item.protein,
          item.carbs,
          item.fat,
          item.nutritionSourceId,
          item.originalNutritionSourceId ?? item.nutritionSourceId,
          item.sourceFamily ?? null,
          item.needsClarification ?? false,
          item.manualOverrideMeta ? JSON.stringify(item.manualOverrideMeta) : null,
          item.matchConfidence
        ]
      );
    }

    await client.query('COMMIT');
    return withHealthSync(input.userId, logId);
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

export async function saveFoodLogStrict(input: {
  userId: string;
  authProvider?: string | null;
  userEmail?: string | null;
  idempotencyKey: string;
  payload: unknown;
  log: SaveLogInput;
}): Promise<SaveLogResponse> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Transaction lock per (user, key) to avoid duplicate save races.
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1), hashtext($2))', [input.userId, input.idempotencyKey]);

    const requestedPayloadHash = payloadHash(input.payload);
    const existing = await getSaveIdempotencyRecord(client, input.userId, input.idempotencyKey);
    if (existing) {
      if (existing.payloadHash !== requestedPayloadHash) {
        throw new ApiError(409, 'IDEMPOTENCY_CONFLICT', 'Idempotency key reused with different payload');
      }
      await client.query('COMMIT');
      return withHealthSync(input.userId, existing.logId, existing.responseJson as Partial<SaveLogResponse>);
    }

    await ensureUserExists(
      input.userId,
      {
        authProvider: input.authProvider,
        email: input.userEmail
      },
      client
    );

    const logInsert = await client.query<{ id: string }>(
      `
      INSERT INTO food_logs (
        user_id, logged_at, meal_type, raw_text,
        total_calories, total_protein_g, total_carbs_g, total_fat_g,
        parse_confidence, parse_sources_used_json, image_ref, input_kind, created_at, updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, $11, $12, NOW(), NOW())
      RETURNING id
      `,
      [
        input.log.userId,
        input.log.loggedAt,
        input.log.mealType ?? null,
        input.log.rawText,
        input.log.totals.calories,
        input.log.totals.protein,
        input.log.totals.carbs,
        input.log.totals.fat,
        input.log.confidence,
        JSON.stringify(input.log.sourcesUsed || []),
        input.log.imageRef ?? null,
        input.log.inputKind ?? 'text'
      ]
    );

    const logId = logInsert.rows[0]?.id;
    if (!logId) {
      throw new Error('Failed to create food log record');
    }

    for (const item of input.log.items) {
      await client.query(
        `
        INSERT INTO food_log_items (
          food_log_id, food_name, quantity, amount, unit, unit_normalized, grams, grams_per_unit,
          calories, protein_g, carbs_g, fat_g,
          nutrition_source_id, original_nutrition_source_id, source_family,
          needs_clarification, manual_override_json, match_confidence
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17::jsonb,$18)
        `,
        [
          logId,
          item.foodName,
          item.quantity,
          item.amount ?? item.quantity,
          item.unit,
          item.unitNormalized ?? item.unit,
          item.grams,
          item.gramsPerUnit ?? null,
          item.calories,
          item.protein,
          item.carbs,
          item.fat,
          item.nutritionSourceId,
          item.originalNutritionSourceId ?? item.nutritionSourceId,
          item.sourceFamily ?? null,
          item.needsClarification ?? false,
          item.manualOverrideMeta ? JSON.stringify(item.manualOverrideMeta) : null,
          item.matchConfidence
        ]
      );
    }

    const response = withHealthSync(input.userId, logId);
    await insertSaveIdempotencyRecord(client, {
      userId: input.userId,
      idempotencyKey: input.idempotencyKey,
      payloadHash: requestedPayloadHash,
      logId,
      responseJson: response
    });

    await client.query('COMMIT');
    return response;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
