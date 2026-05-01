import { pool } from '../db.js';

export type SaveAttemptSource = 'auto' | 'manual' | 'retry' | 'patch' | 'server';

export type SaveAttemptOutcome =
  | 'attempted'
  | 'succeeded'
  | 'failed'
  | 'skipped_no_eligible_state'
  | 'skipped_duplicate';

export type SaveAttemptInput = {
  userId?: string | null;
  parseRequestId?: string | null;
  rowId?: string | null;
  idempotencyKey?: string | null;
  source: SaveAttemptSource;
  outcome: SaveAttemptOutcome;
  errorCode?: string | null;
  latencyMs?: number | null;
  logId?: string | null;
  clientBuild?: string | null;
  backendCommit?: string | null;
  metadata?: Record<string, unknown>;
  createdAt?: Date;
};

function normalizeBlank(value?: string | null): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

export async function recordSaveAttempt(input: SaveAttemptInput): Promise<void> {
  const latencyMs =
    typeof input.latencyMs === 'number' && Number.isFinite(input.latencyMs)
      ? Math.max(0, Math.round(input.latencyMs))
      : null;

  await pool.query(
    `
    INSERT INTO save_attempts (
      user_id,
      parse_request_id,
      row_id,
      idempotency_key,
      source,
      outcome,
      error_code,
      latency_ms,
      log_id,
      client_build,
      backend_commit,
      metadata_json,
      created_at
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb,$13)
    `,
    [
      normalizeBlank(input.userId),
      normalizeBlank(input.parseRequestId),
      normalizeBlank(input.rowId),
      normalizeBlank(input.idempotencyKey),
      input.source,
      input.outcome,
      normalizeBlank(input.errorCode),
      latencyMs,
      normalizeBlank(input.logId),
      normalizeBlank(input.clientBuild),
      normalizeBlank(input.backendCommit),
      JSON.stringify(input.metadata ?? {}),
      input.createdAt ?? new Date()
    ]
  );
}
