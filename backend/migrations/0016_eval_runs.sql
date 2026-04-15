-- Eval run history: persists results from on-demand golden set eval runs
CREATE TABLE IF NOT EXISTS eval_runs (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  run_type     TEXT        NOT NULL DEFAULT 'golden_set',
  run_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  total_cases  INT         NOT NULL,
  passed       INT         NOT NULL,
  failed       INT         NOT NULL,
  pass_rate    FLOAT       NOT NULL,
  duration_ms  INT         NOT NULL DEFAULT 0,
  results_json JSONB       NOT NULL
);

CREATE INDEX IF NOT EXISTS eval_runs_run_at_idx ON eval_runs (run_at DESC);
