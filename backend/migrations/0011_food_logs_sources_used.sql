-- Store mixed-source attribution at log level
-- Date: 2026-02-28

ALTER TABLE food_logs
  ADD COLUMN IF NOT EXISTS parse_sources_used_json JSONB;

UPDATE food_logs
SET parse_sources_used_json = COALESCE(parse_sources_used_json, '[]'::jsonb)
WHERE parse_sources_used_json IS NULL;

ALTER TABLE food_logs
  ALTER COLUMN parse_sources_used_json SET DEFAULT '[]'::jsonb;

ALTER TABLE food_logs
  ALTER COLUMN parse_sources_used_json SET NOT NULL;
