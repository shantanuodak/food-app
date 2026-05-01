-- Persist save-attempt telemetry for parse/save debugging.
-- This table is append-only diagnostics; it does not participate in user-facing
-- nutrition state or idempotency semantics.

CREATE TABLE IF NOT EXISTS save_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    parse_request_id TEXT,
    row_id TEXT,
    idempotency_key TEXT,
    source TEXT NOT NULL CHECK (source IN ('auto', 'manual', 'retry', 'patch', 'server')),
    outcome TEXT NOT NULL CHECK (
        outcome IN (
            'attempted',
            'succeeded',
            'failed',
            'skipped_no_eligible_state',
            'skipped_duplicate'
        )
    ),
    error_code TEXT,
    latency_ms INTEGER CHECK (latency_ms IS NULL OR latency_ms >= 0),
    log_id UUID,
    client_build TEXT,
    backend_commit TEXT,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_save_attempts_parse_created_at
    ON save_attempts(parse_request_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_save_attempts_user_created_at
    ON save_attempts(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_save_attempts_created_at
    ON save_attempts(created_at DESC);
