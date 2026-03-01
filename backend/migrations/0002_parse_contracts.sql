-- Parse provenance and save idempotency contracts
-- Date: 2026-02-16

CREATE TABLE IF NOT EXISTS parse_requests (
    request_id TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parse_version TEXT NOT NULL,
    raw_text TEXT NOT NULL,
    needs_clarification BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_parse_requests_user_created_at
    ON parse_requests(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS log_save_idempotency (
    idempotency_key TEXT NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    payload_hash TEXT NOT NULL,
    log_id UUID NOT NULL REFERENCES food_logs(id) ON DELETE CASCADE,
    response_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (idempotency_key, user_id)
);

CREATE INDEX IF NOT EXISTS idx_log_save_idempotency_user_created_at
    ON log_save_idempotency(user_id, created_at DESC);

