-- Hydration logging
-- Date: 2026-05-24
--
-- Water is tracked separately from food logs so zero-calorie hydration
-- entries do not pollute nutrition totals, food streaks, or saved meals.

CREATE TABLE IF NOT EXISTS hydration_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    daily_goal_ml INTEGER NOT NULL CHECK (daily_goal_ml >= 250 AND daily_goal_ml <= 10000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS hydration_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    logged_at TIMESTAMPTZ NOT NULL,
    raw_text TEXT NOT NULL,
    amount_ml NUMERIC(10,2) NOT NULL CHECK (amount_ml > 0 AND amount_ml <= 10000),
    input_amount NUMERIC(10,3),
    input_unit TEXT,
    source TEXT NOT NULL DEFAULT 'text' CHECK (source IN ('text', 'voice', 'quick_add', 'manual')),
    confidence NUMERIC(4,3) NOT NULL DEFAULT 1 CHECK (confidence >= 0 AND confidence <= 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hydration_logs_user_logged_at
    ON hydration_logs(user_id, logged_at DESC);

ALTER TABLE hydration_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE hydration_logs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'hydration_preferences'
      AND policyname = 'hydration_preferences_user_isolation'
  ) THEN
    CREATE POLICY hydration_preferences_user_isolation
      ON hydration_preferences
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

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'hydration_logs'
      AND policyname = 'hydration_logs_user_isolation'
  ) THEN
    CREATE POLICY hydration_logs_user_isolation
      ON hydration_logs
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
