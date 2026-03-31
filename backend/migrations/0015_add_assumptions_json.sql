-- Persist parse-time assumptions on food logs (FR-DATA-006)
ALTER TABLE food_logs
  ADD COLUMN IF NOT EXISTS assumptions_json JSONB NOT NULL DEFAULT '[]'::jsonb;
