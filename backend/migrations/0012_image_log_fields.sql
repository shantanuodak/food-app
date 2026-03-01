-- Image logging support and AI image cost feature tracking
-- Date: 2026-03-01

ALTER TABLE food_logs
  ADD COLUMN IF NOT EXISTS image_ref TEXT;

ALTER TABLE food_logs
  ADD COLUMN IF NOT EXISTS input_kind TEXT;

UPDATE food_logs
SET input_kind = COALESCE(NULLIF(input_kind, ''), 'text')
WHERE input_kind IS NULL OR input_kind = '';

ALTER TABLE food_logs
  ALTER COLUMN input_kind SET DEFAULT 'text';

ALTER TABLE food_logs
  ALTER COLUMN input_kind SET NOT NULL;

ALTER TABLE food_logs
  DROP CONSTRAINT IF EXISTS food_logs_input_kind_check;

ALTER TABLE food_logs
  ADD CONSTRAINT food_logs_input_kind_check
  CHECK (input_kind IN ('text', 'image', 'voice', 'manual'));

ALTER TABLE ai_cost_events
  DROP CONSTRAINT IF EXISTS ai_cost_events_feature_check;

ALTER TABLE ai_cost_events
  ADD CONSTRAINT ai_cost_events_feature_check
  CHECK (feature IN ('parse_fallback', 'escalation', 'enrichment', 'parse_image_primary', 'parse_image_fallback'));
