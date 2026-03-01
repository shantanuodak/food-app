-- Timezone support and row-level security scaffolding
-- Date: 2026-02-21

ALTER TABLE onboarding_profiles
  ADD COLUMN IF NOT EXISTS timezone TEXT;

UPDATE onboarding_profiles
SET timezone = 'UTC'
WHERE timezone IS NULL
   OR btrim(timezone) = '';

ALTER TABLE onboarding_profiles
  ALTER COLUMN timezone SET DEFAULT 'UTC';

ALTER TABLE onboarding_profiles
  ALTER COLUMN timezone SET NOT NULL;

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_log_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE parse_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE log_save_idempotency ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_cost_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'users'
      AND policyname = 'users_self_access'
  ) THEN
    CREATE POLICY users_self_access
      ON users
      FOR ALL
      USING (
        current_user = 'postgres'
        OR id::text = current_setting('request.jwt.claim.sub', true)
      )
      WITH CHECK (
        current_user = 'postgres'
        OR id::text = current_setting('request.jwt.claim.sub', true)
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
      AND tablename = 'onboarding_profiles'
      AND policyname = 'onboarding_profiles_user_isolation'
  ) THEN
    CREATE POLICY onboarding_profiles_user_isolation
      ON onboarding_profiles
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
      AND tablename = 'food_logs'
      AND policyname = 'food_logs_user_isolation'
  ) THEN
    CREATE POLICY food_logs_user_isolation
      ON food_logs
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
      AND tablename = 'food_log_items'
      AND policyname = 'food_log_items_user_isolation'
  ) THEN
    CREATE POLICY food_log_items_user_isolation
      ON food_log_items
      FOR ALL
      USING (
        current_user = 'postgres'
        OR EXISTS (
          SELECT 1
          FROM food_logs fl
          WHERE fl.id = food_log_items.food_log_id
            AND fl.user_id::text = current_setting('request.jwt.claim.sub', true)
        )
      )
      WITH CHECK (
        current_user = 'postgres'
        OR EXISTS (
          SELECT 1
          FROM food_logs fl
          WHERE fl.id = food_log_items.food_log_id
            AND fl.user_id::text = current_setting('request.jwt.claim.sub', true)
        )
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
      AND tablename = 'parse_requests'
      AND policyname = 'parse_requests_user_isolation'
  ) THEN
    CREATE POLICY parse_requests_user_isolation
      ON parse_requests
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
      AND tablename = 'log_save_idempotency'
      AND policyname = 'log_save_idempotency_user_isolation'
  ) THEN
    CREATE POLICY log_save_idempotency_user_isolation
      ON log_save_idempotency
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
      AND tablename = 'ai_cost_events'
      AND policyname = 'ai_cost_events_user_isolation'
  ) THEN
    CREATE POLICY ai_cost_events_user_isolation
      ON ai_cost_events
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
