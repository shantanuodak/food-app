CREATE TABLE IF NOT EXISTS benchmark_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  input_text TEXT NOT NULL,
  display_name TEXT,
  category TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  reference_source_type TEXT NOT NULL,
  reference_source_label TEXT NOT NULL,
  reference_source_url TEXT,
  reference_notes TEXT,
  serving_notes TEXT,
  reference_calories NUMERIC NOT NULL,
  reference_protein NUMERIC NOT NULL DEFAULT 0,
  reference_carbs NUMERIC NOT NULL DEFAULT 0,
  reference_fat NUMERIC NOT NULL DEFAULT 0,
  reference_tolerance_pct NUMERIC NOT NULL DEFAULT 0.20,
  reference_min_tolerance_calories NUMERIC NOT NULL DEFAULT 15,
  mfp_item_name TEXT,
  mfp_calories NUMERIC,
  mfp_protein NUMERIC,
  mfp_carbs NUMERIC,
  mfp_fat NUMERIC,
  mfp_notes TEXT,
  mfp_collected_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS benchmark_cases_status_idx ON benchmark_cases (status);
CREATE INDEX IF NOT EXISTS benchmark_cases_category_idx ON benchmark_cases (category);
CREATE INDEX IF NOT EXISTS benchmark_cases_active_idx ON benchmark_cases (is_active);

CREATE TABLE IF NOT EXISTS benchmark_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  run_label TEXT,
  parser_version TEXT,
  prompt_version TEXT,
  cache_mode TEXT NOT NULL DEFAULT 'cached',
  case_count INT NOT NULL DEFAULT 0,
  food_app_score NUMERIC NOT NULL DEFAULT 0,
  mfp_score NUMERIC,
  category_scores_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  summary_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS benchmark_runs_run_at_idx ON benchmark_runs (run_at DESC);

CREATE TABLE IF NOT EXISTS benchmark_run_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL REFERENCES benchmark_runs(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES benchmark_cases(id) ON DELETE CASCADE,
  food_app_route TEXT,
  food_app_calories NUMERIC,
  food_app_protein NUMERIC,
  food_app_carbs NUMERIC,
  food_app_fat NUMERIC,
  food_app_items_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  food_app_explanation TEXT,
  food_app_confidence NUMERIC,
  calorie_score NUMERIC NOT NULL DEFAULT 0,
  protein_score NUMERIC NOT NULL DEFAULT 0,
  carbs_score NUMERIC NOT NULL DEFAULT 0,
  fat_score NUMERIC NOT NULL DEFAULT 0,
  food_app_overall_score NUMERIC NOT NULL DEFAULT 0,
  mfp_overall_score NUMERIC,
  result_label TEXT NOT NULL DEFAULT 'needs_review',
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS benchmark_run_results_run_id_idx ON benchmark_run_results (run_id);
CREATE INDEX IF NOT EXISTS benchmark_run_results_case_id_idx ON benchmark_run_results (case_id);

CREATE TABLE IF NOT EXISTS benchmark_public_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL REFERENCES benchmark_runs(id),
  title TEXT NOT NULL,
  summary TEXT NOT NULL,
  visible_categories TEXT[] NOT NULL DEFAULT '{}',
  is_active BOOLEAN NOT NULL DEFAULT FALSE,
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS benchmark_public_snapshots_one_active_idx
  ON benchmark_public_snapshots (is_active)
  WHERE is_active = TRUE;
