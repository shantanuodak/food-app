-- Client/server image parse timing telemetry.
-- Captures both successful and failed photo parse attempts so production
-- dashboard debugging can distinguish image prep, upload/request, backend AI,
-- save delay, and client-visible total duration.

CREATE TABLE IF NOT EXISTS image_parse_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    client_attempt_id TEXT NOT NULL,
    parse_request_id TEXT,
    outcome TEXT NOT NULL CHECK (outcome IN ('succeeded', 'failed')),
    error_code TEXT,
    prep_ms INTEGER CHECK (prep_ms IS NULL OR prep_ms >= 0),
    request_ms INTEGER CHECK (request_ms IS NULL OR request_ms >= 0),
    total_ms INTEGER CHECK (total_ms IS NULL OR total_ms >= 0),
    backend_ms INTEGER CHECK (backend_ms IS NULL OR backend_ms >= 0),
    image_bytes INTEGER CHECK (image_bytes IS NULL OR image_bytes >= 0),
    mime_type TEXT,
    vision_model TEXT,
    fallback_used BOOLEAN,
    client_build TEXT,
    source TEXT NOT NULL DEFAULT 'drawer' CHECK (source IN ('drawer', 'quick_camera')),
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_image_parse_attempts_created_at
    ON image_parse_attempts(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_image_parse_attempts_parse_request
    ON image_parse_attempts(parse_request_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_image_parse_attempts_user_created
    ON image_parse_attempts(user_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_image_parse_attempts_client_attempt
    ON image_parse_attempts(client_attempt_id, user_id);
