-- Client auth/session diagnostics queued on-device and flushed after auth.
-- These rows are diagnostic-only; they must never participate in user-facing
-- auth, onboarding, or nutrition state.

CREATE TABLE IF NOT EXISTS auth_diagnostic_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_event_id UUID NOT NULL,
    event_name TEXT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    app_launch_id UUID,
    client_build TEXT,
    app_version TEXT,
    os_version TEXT,
    device_model TEXT,
    provider TEXT,
    user_id_hint UUID,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, client_event_id)
);

ALTER TABLE auth_diagnostic_events ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_auth_diagnostic_events_user_created
    ON auth_diagnostic_events(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_diagnostic_events_event_created
    ON auth_diagnostic_events(event_name, created_at DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'auth_diagnostic_events'
      AND policyname = 'auth_diagnostic_events_backend_only'
  ) THEN
    CREATE POLICY auth_diagnostic_events_backend_only
      ON auth_diagnostic_events
      FOR ALL
      USING (current_user = 'postgres')
      WITH CHECK (current_user = 'postgres');
  END IF;
END
$$;
