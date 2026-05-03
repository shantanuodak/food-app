import type { PoolClient } from 'pg';
import { pool } from '../db.js';
import { ApiError } from '../utils/errors.js';
import {
  getSaveIdempotencyRecord,
  hasSavedPayloadHashForLog,
  insertSaveIdempotencyRecord,
  payloadHash
} from './idempotencyService.js';
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
  sourceFamily?: 'cache' | 'gemini' | 'manual';
  needsClarification?: boolean;
  manualOverrideMeta?: { enabled: boolean; reason?: string; editedFields: string[] } | null;
  matchConfidence: number;
};

type SaveLogInput = {
  userId: string;
  authProvider?: string | null;
  userEmail?: string | null;
  parseRequestId?: string | null;
  parseVersion?: string | null;
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
  sourcesUsed?: Array<'cache' | 'gemini' | 'manual'>;
  assumptions?: string[];
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

const insertFoodLogText = `
  INSERT INTO food_logs (
    user_id, logged_at, meal_type, raw_text,
    total_calories, total_protein_g, total_carbs_g, total_fat_g,
    parse_confidence, parse_sources_used_json, assumptions_json, image_ref, input_kind,
    parse_request_id, parse_version, created_at, updated_at
  )
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, $11::jsonb, $12, $13, $14, $15, NOW(), NOW())
  RETURNING id
`;

const insertFoodLogItemText = `
  INSERT INTO food_log_items (
    food_log_id, food_name, quantity, amount, unit, unit_normalized, grams, grams_per_unit,
    calories, protein_g, carbs_g, fat_g,
    nutrition_source_id, original_nutrition_source_id, source_family,
    needs_clarification, manual_override_json, match_confidence
  )
  VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17::jsonb,$18)
`;

const selectExistingLogByParseRequestText = `
  SELECT id
  FROM food_logs
  WHERE user_id = $1
    AND parse_request_id = $2
  ORDER BY created_at ASC
  LIMIT 1
  FOR UPDATE
`;

const selectOwnedLogForUpdateText = `SELECT id FROM food_logs WHERE id = $1 AND user_id = $2 FOR UPDATE`;

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

    const logInsert = await client.query<{ id: string }>({
      name: 'insert-food-log-v1',
      text: insertFoodLogText,
      values: [
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
        JSON.stringify(input.assumptions || []),
        input.imageRef ?? null,
        input.inputKind ?? 'text',
        input.parseRequestId ?? null,
        input.parseVersion ?? null
      ]
    });

    const logId = logInsert.rows[0]?.id;
    if (!logId) {
      throw new Error('Failed to create food log record');
    }

    for (const item of input.items) {
      await client.query({
        name: 'insert-food-log-item-v1',
        text: insertFoodLogItemText,
        values: [
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
      });
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
    const normalizedParseRequestId = input.log.parseRequestId?.trim() || null;
    if (normalizedParseRequestId) {
      // Serialize saves for the same parse request even when callers use different
      // idempotency keys. This closes duplicate-write races at the source.
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1), hashtext($2))', [
        input.userId,
        `parse_request:${normalizedParseRequestId}`
      ]);
    }

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

    if (normalizedParseRequestId) {
      const existingByParse = await client.query<{ id: string }>({
        name: 'select-existing-log-by-parse-request-v1',
        text: selectExistingLogByParseRequestText,
        values: [input.userId, normalizedParseRequestId]
      });
      const existingLogId = existingByParse.rows[0]?.id;
      if (existingLogId) {
        const isMatchingReplay = await hasSavedPayloadHashForLog(client, {
          userId: input.userId,
          logId: existingLogId,
          payloadHash: requestedPayloadHash
        });
        if (!isMatchingReplay) {
          throw new ApiError(
            409,
            'IDEMPOTENCY_CONFLICT',
            'parseRequestId already saved with a different payload'
          );
        }
        const response = withHealthSync(input.userId, existingLogId);
        await insertSaveIdempotencyRecord(client, {
          userId: input.userId,
          idempotencyKey: input.idempotencyKey,
          payloadHash: requestedPayloadHash,
          logId: existingLogId,
          responseJson: response
        });
        await client.query('COMMIT');
        return response;
      }
    }

    const logInsert = await client.query<{ id: string }>({
      name: 'insert-food-log-v1',
      text: insertFoodLogText,
      values: [
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
        JSON.stringify(input.log.assumptions || []),
        input.log.imageRef ?? null,
        input.log.inputKind ?? 'text',
        normalizedParseRequestId,
        input.log.parseVersion ?? null
      ]
    });

    const logId = logInsert.rows[0]?.id;
    if (!logId) {
      throw new Error('Failed to create food log record');
    }

    for (const item of input.log.items) {
      await client.query({
        name: 'insert-food-log-item-v1',
        text: insertFoodLogItemText,
        values: [
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
      });
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

type UpdateLogInput = {
  logId: string;
  userId: string;
  parseRequestId?: string | null;
  parseVersion?: string | null;
  rawText: string;
  loggedAt?: string;
  mealType?: string;
  imageRef?: string | null;
  inputKind?: 'text' | 'image' | 'voice' | 'manual';
  confidence: number;
  totals: {
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
  };
  sourcesUsed?: Array<'cache' | 'gemini' | 'manual'>;
  assumptions?: string[];
  items: LogItemInput[];
};

type UpdateLogResponse = { logId: string; status: 'updated'; healthSync: HealthSyncContract };
type DeleteLogResponse = { logId: string; status: 'deleted'; healthSync: HealthSyncContract };

/**
 * Replace the items and totals of an existing food_log. Used by PATCH
 * /v1/logs/:id to persist in-place edits (e.g. the client-side quantity
 * fast path). The caller must have already verified the log belongs to the
 * user.
 *
 * The update deletes all existing food_log_items and re-inserts the new set
 * inside a transaction; daily totals on `food_logs` are overwritten from
 * `input.totals`. `loggedAt` is only updated when provided (quantity edits
 * typically keep the original timestamp).
 */
export async function updateFoodLog(input: UpdateLogInput): Promise<UpdateLogResponse> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Verify ownership and existence in the same transaction.
    const ownerCheck = await client.query<{ id: string }>({
      name: 'select-owned-log-for-update-v1',
      text: selectOwnedLogForUpdateText,
      values: [input.logId, input.userId]
    });
    if (ownerCheck.rowCount === 0) {
      throw new ApiError(404, 'LOG_NOT_FOUND', 'Food log not found');
    }

    // Overwrite the header row.
    await client.query(
      `
      UPDATE food_logs SET
        raw_text = $1,
        total_calories = $2,
        total_protein_g = $3,
        total_carbs_g = $4,
        total_fat_g = $5,
        parse_confidence = $6,
        parse_sources_used_json = $7::jsonb,
        assumptions_json = $8::jsonb,
        image_ref = COALESCE($9, image_ref),
        input_kind = COALESCE($10, input_kind),
        meal_type = COALESCE($11, meal_type),
        logged_at = COALESCE($12::timestamptz, logged_at),
        parse_request_id = COALESCE($13, parse_request_id),
        parse_version = COALESCE($14, parse_version),
        updated_at = NOW()
      WHERE id = $15 AND user_id = $16
      `,
      [
        input.rawText,
        input.totals.calories,
        input.totals.protein,
        input.totals.carbs,
        input.totals.fat,
        input.confidence,
        JSON.stringify(input.sourcesUsed || []),
        JSON.stringify(input.assumptions || []),
        input.imageRef ?? null,
        input.inputKind ?? null,
        input.mealType ?? null,
        input.loggedAt ?? null,
        input.parseRequestId ?? null,
        input.parseVersion ?? null,
        input.logId,
        input.userId
      ]
    );

    // Replace items wholesale — simpler and safer than diffing.
    await client.query(`DELETE FROM food_log_items WHERE food_log_id = $1`, [input.logId]);

    for (const item of input.items) {
      await client.query({
        name: 'insert-food-log-item-v1',
        text: insertFoodLogItemText,
        values: [
          input.logId,
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
      });
    }

    await client.query('COMMIT');
    return {
      logId: input.logId,
      status: 'updated',
      healthSync: buildHealthSyncContract(input.userId, input.logId)
    };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * Lightweight update for image_ref only — used by the iOS post-save image
 * upload path. Image upload is decoupled from save (so a missing storage
 * bucket / network blip / 401 on Supabase Storage never blocks nutrition
 * data from landing). After the food_log row is persisted with image_ref
 * NULL, the client retries the upload in the background and calls this
 * endpoint to attach the resulting object path.
 */
export async function updateFoodLogImageRef(input: {
  logId: string;
  userId: string;
  imageRef: string | null;
}): Promise<{ logId: string; imageRef: string | null }> {
  const result = await pool.query<{ id: string; image_ref: string | null }>(
    `UPDATE food_logs
       SET image_ref = $1, updated_at = NOW()
     WHERE id = $2 AND user_id = $3
     RETURNING id, image_ref`,
    [input.imageRef, input.logId, input.userId]
  );
  if (result.rowCount === 0) {
    throw new ApiError(404, 'LOG_NOT_FOUND', 'Food log not found');
  }
  return { logId: result.rows[0].id, imageRef: result.rows[0].image_ref };
}

export async function deleteFoodLog(input: { logId: string; userId: string }): Promise<DeleteLogResponse> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const ownerCheck = await client.query<{ id: string }>({
      name: 'select-owned-log-for-update-v1',
      text: selectOwnedLogForUpdateText,
      values: [input.logId, input.userId]
    });
    if (ownerCheck.rowCount === 0) {
      throw new ApiError(404, 'LOG_NOT_FOUND', 'Food log not found');
    }

    // food_log_items are removed by the existing ON DELETE CASCADE constraint.
    await client.query(`DELETE FROM food_logs WHERE id = $1 AND user_id = $2`, [input.logId, input.userId]);

    await client.query('COMMIT');
    return {
      logId: input.logId,
      status: 'deleted',
      healthSync: buildHealthSyncContract(input.userId, input.logId, 'delete')
    };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
