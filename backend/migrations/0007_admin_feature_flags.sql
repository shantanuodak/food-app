-- Admin feature flags and user admin role
-- Date: 2026-02-28

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS admin_feature_flags (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    gemini_enabled BOOLEAN NOT NULL,
    fatsecret_enabled BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE admin_feature_flags ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'admin_feature_flags'
      AND policyname = 'admin_feature_flags_user_isolation'
  ) THEN
    CREATE POLICY admin_feature_flags_user_isolation
      ON admin_feature_flags
      FOR ALL
      USING (
        current_user = 'postgres'
        OR user_id::text = current_setting('request.jwt.claim.sub', true)
      )
      WITH CHECK (
        current_user = 'postgres'
        OR user_id::text = current_setting('request.jwt.claim.sub', true)
      );
  END IF;
END
$$;
