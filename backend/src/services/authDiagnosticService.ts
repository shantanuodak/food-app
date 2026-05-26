import { pool } from '../db.js';

export type AuthDiagnosticEventInput = {
  clientEventId: string;
  eventName: string;
  occurredAt: Date;
  appLaunchId?: string | null;
  clientBuild?: string | null;
  appVersion?: string | null;
  osVersion?: string | null;
  deviceModel?: string | null;
  provider?: string | null;
  userIdHint?: string | null;
  metadata?: Record<string, string>;
};

function normalizeBlank(value?: string | null): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function normalizeMetadata(metadata: Record<string, string> | undefined): Record<string, string> {
  const normalized: Record<string, string> = {};
  for (const [key, value] of Object.entries(metadata ?? {})) {
    const cleanKey = key.trim().slice(0, 80);
    if (!cleanKey) continue;
    normalized[cleanKey] = String(value).slice(0, 500);
  }
  return normalized;
}

export async function recordAuthDiagnosticEvents(userId: string, events: AuthDiagnosticEventInput[]): Promise<number> {
  if (events.length === 0) {
    return 0;
  }

  let accepted = 0;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const event of events) {
      const result = await client.query(
        `
        INSERT INTO auth_diagnostic_events (
          user_id,
          client_event_id,
          event_name,
          occurred_at,
          app_launch_id,
          client_build,
          app_version,
          os_version,
          device_model,
          provider,
          user_id_hint,
          metadata_json
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb)
        ON CONFLICT (user_id, client_event_id) DO NOTHING
        `,
        [
          userId,
          event.clientEventId,
          event.eventName,
          event.occurredAt,
          normalizeBlank(event.appLaunchId),
          normalizeBlank(event.clientBuild),
          normalizeBlank(event.appVersion),
          normalizeBlank(event.osVersion),
          normalizeBlank(event.deviceModel),
          normalizeBlank(event.provider),
          normalizeBlank(event.userIdHint),
          JSON.stringify(normalizeMetadata(event.metadata))
        ]
      );
      accepted += result.rowCount ?? 0;
    }
    await client.query('COMMIT');
    return accepted;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
