-- Health activity snapshots from Apple Health (steps, active energy)
CREATE TABLE IF NOT EXISTS health_activity_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  steps NUMERIC(10, 0) NOT NULL DEFAULT 0,
  active_energy_kcal NUMERIC(10, 2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_health_activity_user_date
  ON health_activity_snapshots (user_id, date DESC);
