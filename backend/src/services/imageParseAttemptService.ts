import { pool } from '../db.js';

export type ImageParseAttemptInput = {
  userId?: string | null;
  clientAttemptId: string;
  parseRequestId?: string | null;
  outcome: 'succeeded' | 'failed';
  errorCode?: string | null;
  prepMs?: number | null;
  requestMs?: number | null;
  totalMs?: number | null;
  backendMs?: number | null;
  imageBytes?: number | null;
  mimeType?: string | null;
  visionModel?: string | null;
  fallbackUsed?: boolean | null;
  clientBuild?: string | null;
  source?: 'drawer' | 'quick_camera';
  metadata?: Record<string, unknown>;
};

function normalizeBlank(value?: string | null): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function normalizeNonNegativeInt(value?: number | null): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return null;
  }
  return Math.max(0, Math.round(value));
}

export async function recordImageParseAttempt(input: ImageParseAttemptInput): Promise<void> {
  await pool.query(
    `
    INSERT INTO image_parse_attempts (
      user_id,
      client_attempt_id,
      parse_request_id,
      outcome,
      error_code,
      prep_ms,
      request_ms,
      total_ms,
      backend_ms,
      image_bytes,
      mime_type,
      vision_model,
      fallback_used,
      client_build,
      source,
      metadata_json,
      created_at
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16::jsonb,NOW())
    ON CONFLICT (client_attempt_id, user_id)
    DO UPDATE SET
      parse_request_id = COALESCE(EXCLUDED.parse_request_id, image_parse_attempts.parse_request_id),
      outcome = EXCLUDED.outcome,
      error_code = EXCLUDED.error_code,
      prep_ms = EXCLUDED.prep_ms,
      request_ms = EXCLUDED.request_ms,
      total_ms = EXCLUDED.total_ms,
      backend_ms = EXCLUDED.backend_ms,
      image_bytes = EXCLUDED.image_bytes,
      mime_type = EXCLUDED.mime_type,
      vision_model = EXCLUDED.vision_model,
      fallback_used = EXCLUDED.fallback_used,
      client_build = EXCLUDED.client_build,
      source = EXCLUDED.source,
      metadata_json = EXCLUDED.metadata_json,
      created_at = NOW()
    `,
    [
      normalizeBlank(input.userId),
      input.clientAttemptId,
      normalizeBlank(input.parseRequestId),
      input.outcome,
      normalizeBlank(input.errorCode),
      normalizeNonNegativeInt(input.prepMs),
      normalizeNonNegativeInt(input.requestMs),
      normalizeNonNegativeInt(input.totalMs),
      normalizeNonNegativeInt(input.backendMs),
      normalizeNonNegativeInt(input.imageBytes),
      normalizeBlank(input.mimeType),
      normalizeBlank(input.visionModel),
      input.fallbackUsed ?? null,
      normalizeBlank(input.clientBuild),
      input.source ?? 'drawer',
      JSON.stringify(input.metadata ?? {})
    ]
  );
}
