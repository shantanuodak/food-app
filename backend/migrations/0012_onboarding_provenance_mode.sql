-- Explicit onboarding provenance mode contract
-- Date: 2026-02-28

ALTER TABLE onboarding_profiles
  ADD COLUMN IF NOT EXISTS onboarding_provenance_mode TEXT;

UPDATE onboarding_profiles
SET onboarding_provenance_mode = COALESCE(NULLIF(onboarding_provenance_mode, ''), 'computed_provenance_v1')
WHERE onboarding_provenance_mode IS NULL
   OR onboarding_provenance_mode = '';

ALTER TABLE onboarding_profiles
  ALTER COLUMN onboarding_provenance_mode SET DEFAULT 'computed_provenance_v1';

ALTER TABLE onboarding_profiles
  ALTER COLUMN onboarding_provenance_mode SET NOT NULL;
