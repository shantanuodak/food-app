import { createHash } from 'node:crypto';
import type { PoolClient } from 'pg';
import { pool } from '../db.js';

export function payloadHash(value: unknown): string {
  const encoded = JSON.stringify(value);
  return createHash('sha256').update(encoded).digest('hex');
}

export async function getSaveIdempotencyRecord(
  client: PoolClient,
  userId: string,
  idempotencyKey: string
): Promise<{ payloadHash: string; responseJson: unknown; logId: string } | null> {
  const result = await client.query<{
    payload_hash: string;
    response_json: unknown;
    log_id: string;
  }>(
    `
    SELECT payload_hash, response_json, log_id
    FROM log_save_idempotency
    WHERE user_id = $1
      AND idempotency_key = $2
    `,
    [userId, idempotencyKey]
  );

  const row = result.rows[0];
  if (!row) {
    return null;
  }

  return {
    payloadHash: row.payload_hash,
    responseJson: row.response_json,
    logId: row.log_id
  };
}

export async function getSaveIdempotencyRecordForUser(
  userId: string,
  idempotencyKey: string
): Promise<{ payloadHash: string; responseJson: unknown; logId: string } | null> {
  const result = await pool.query<{
    payload_hash: string;
    response_json: unknown;
    log_id: string;
  }>(
    `
    SELECT payload_hash, response_json, log_id
    FROM log_save_idempotency
    WHERE user_id = $1
      AND idempotency_key = $2
    `,
    [userId, idempotencyKey]
  );

  const row = result.rows[0];
  if (!row) {
    return null;
  }

  return {
    payloadHash: row.payload_hash,
    responseJson: row.response_json,
    logId: row.log_id
  };
}

export async function insertSaveIdempotencyRecord(
  client: PoolClient,
  input: {
    userId: string;
    idempotencyKey: string;
    payloadHash: string;
    logId: string;
    responseJson: unknown;
  }
): Promise<void> {
  await client.query(
    `
    INSERT INTO log_save_idempotency (
      idempotency_key, user_id, payload_hash, log_id, response_json, created_at
    )
    VALUES ($1,$2,$3,$4,$5::jsonb,NOW())
    `,
    [input.idempotencyKey, input.userId, input.payloadHash, input.logId, JSON.stringify(input.responseJson)]
  );
}
