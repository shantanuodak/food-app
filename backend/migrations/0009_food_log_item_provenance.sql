-- Food log item provenance fields for manual overrides and deterministic schema v2
-- Date: 2026-02-28

ALTER TABLE food_log_items
  ADD COLUMN IF NOT EXISTS amount NUMERIC(10,3);

ALTER TABLE food_log_items
  ADD COLUMN IF NOT EXISTS unit_normalized TEXT;

ALTER TABLE food_log_items
  ADD COLUMN IF NOT EXISTS grams_per_unit NUMERIC(12,6);

ALTER TABLE food_log_items
  ADD COLUMN IF NOT EXISTS original_nutrition_source_id TEXT;

ALTER TABLE food_log_items
  ADD COLUMN IF NOT EXISTS source_family TEXT;

ALTER TABLE food_log_items
  ADD COLUMN IF NOT EXISTS needs_clarification BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE food_log_items
  ADD COLUMN IF NOT EXISTS manual_override_json JSONB;

UPDATE food_log_items
SET
  amount = COALESCE(amount, quantity),
  unit_normalized = COALESCE(NULLIF(unit_normalized, ''), unit),
  grams_per_unit = COALESCE(grams_per_unit, CASE WHEN quantity > 0 THEN grams / quantity ELSE NULL END),
  original_nutrition_source_id = COALESCE(NULLIF(original_nutrition_source_id, ''), nutrition_source_id)
WHERE amount IS NULL
   OR unit_normalized IS NULL
   OR original_nutrition_source_id IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'food_log_items_source_family_check'
  ) THEN
    ALTER TABLE food_log_items
      ADD CONSTRAINT food_log_items_source_family_check
      CHECK (source_family IS NULL OR source_family IN ('cache', 'fatsecret', 'gemini', 'manual'));
  END IF;
END
$$;
