-- Onboarding provenance contract fields
-- Date: 2026-02-28

ALTER TABLE onboarding_profiles
  ADD COLUMN IF NOT EXISTS onboarding_inputs_json JSONB;

ALTER TABLE onboarding_profiles
  ADD COLUMN IF NOT EXISTS onboarding_inputs_hash TEXT;

ALTER TABLE onboarding_profiles
  ADD COLUMN IF NOT EXISTS onboarding_calculator_version TEXT;

ALTER TABLE onboarding_profiles
  ADD COLUMN IF NOT EXISTS onboarding_computed_at TIMESTAMPTZ;

UPDATE onboarding_profiles
SET
  onboarding_inputs_json = COALESCE(onboarding_inputs_json, '{}'::jsonb),
  onboarding_inputs_hash = COALESCE(onboarding_inputs_hash, ''),
  onboarding_calculator_version = COALESCE(onboarding_calculator_version, 'onboarding-target-calculator-v2'),
  onboarding_computed_at = COALESCE(onboarding_computed_at, NOW())
WHERE onboarding_inputs_json IS NULL
   OR onboarding_inputs_hash IS NULL
   OR onboarding_calculator_version IS NULL
   OR onboarding_computed_at IS NULL;

ALTER TABLE onboarding_profiles
  ALTER COLUMN onboarding_inputs_json SET DEFAULT '{}'::jsonb;

ALTER TABLE onboarding_profiles
  ALTER COLUMN onboarding_inputs_hash SET DEFAULT '';

ALTER TABLE onboarding_profiles
  ALTER COLUMN onboarding_calculator_version SET DEFAULT 'onboarding-target-calculator-v2';

ALTER TABLE onboarding_profiles
  ALTER COLUMN onboarding_computed_at SET DEFAULT NOW();

ALTER TABLE onboarding_profiles
  ALTER COLUMN onboarding_inputs_json SET NOT NULL;

ALTER TABLE onboarding_profiles
  ALTER COLUMN onboarding_inputs_hash SET NOT NULL;

ALTER TABLE onboarding_profiles
  ALTER COLUMN onboarding_calculator_version SET NOT NULL;

ALTER TABLE onboarding_profiles
  ALTER COLUMN onboarding_computed_at SET NOT NULL;
