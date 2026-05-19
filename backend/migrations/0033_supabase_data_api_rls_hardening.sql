-- Supabase Data API hardening for public-schema tables.
-- Date: 2026-05-18
--
-- The iOS app uses Supabase directly for Auth/Storage, while table reads and
-- writes go through the backend. Keep public-schema tables protected if they
-- are reachable through Supabase's generated REST/GraphQL APIs.

REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM anon, authenticated;

ALTER TABLE benchmark_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE benchmark_public_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE benchmark_run_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE benchmark_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE eval_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE health_activity_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE image_parse_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public_roadmap_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE save_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE waitlist_signups ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  target_table TEXT;
  target_tables TEXT[] := ARRAY[
    'benchmark_cases',
    'benchmark_public_snapshots',
    'benchmark_run_results',
    'benchmark_runs',
    'eval_runs',
    'health_activity_snapshots',
    'image_parse_attempts',
    'notification_deliveries',
    'notification_devices',
    'notification_preferences',
    'notification_templates',
    'parse_cache',
    'public_roadmap_items',
    'save_attempts',
    'schema_migrations',
    'user_feedback',
    'waitlist_signups'
  ];
BEGIN
  FOREACH target_table IN ARRAY target_tables LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = target_table
        AND policyname = target_table || '_backend_only'
    ) THEN
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR ALL USING (current_user = %L) WITH CHECK (current_user = %L)',
        target_table || '_backend_only',
        target_table,
        'postgres',
        'postgres'
      );
    END IF;
  END LOOP;
END
$$;
