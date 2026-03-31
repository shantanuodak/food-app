-- Onboarding biometric fields for calculator parity
-- Date: 2026-03-15

ALTER TABLE onboarding_profiles
  ADD COLUMN IF NOT EXISTS age INTEGER,
  ADD COLUMN IF NOT EXISTS sex TEXT,
  ADD COLUMN IF NOT EXISTS height_cm NUMERIC(6,2),
  ADD COLUMN IF NOT EXISTS weight_kg NUMERIC(6,2),
  ADD COLUMN IF NOT EXISTS pace TEXT,
  ADD COLUMN IF NOT EXISTS activity_detail TEXT;

ALTER TABLE onboarding_profiles
  DROP CONSTRAINT IF EXISTS onboarding_profiles_age_check;

ALTER TABLE onboarding_profiles
  ADD CONSTRAINT onboarding_profiles_age_check
  CHECK (age IS NULL OR (age >= 13 AND age <= 90));

ALTER TABLE onboarding_profiles
  DROP CONSTRAINT IF EXISTS onboarding_profiles_sex_check;

ALTER TABLE onboarding_profiles
  ADD CONSTRAINT onboarding_profiles_sex_check
  CHECK (sex IS NULL OR sex IN ('female', 'male', 'other'));

ALTER TABLE onboarding_profiles
  DROP CONSTRAINT IF EXISTS onboarding_profiles_height_cm_check;

ALTER TABLE onboarding_profiles
  ADD CONSTRAINT onboarding_profiles_height_cm_check
  CHECK (height_cm IS NULL OR (height_cm >= 122 AND height_cm <= 218));

ALTER TABLE onboarding_profiles
  DROP CONSTRAINT IF EXISTS onboarding_profiles_weight_kg_check;

ALTER TABLE onboarding_profiles
  ADD CONSTRAINT onboarding_profiles_weight_kg_check
  CHECK (weight_kg IS NULL OR (weight_kg >= 35 AND weight_kg <= 227));

ALTER TABLE onboarding_profiles
  DROP CONSTRAINT IF EXISTS onboarding_profiles_pace_check;

ALTER TABLE onboarding_profiles
  ADD CONSTRAINT onboarding_profiles_pace_check
  CHECK (pace IS NULL OR pace IN ('conservative', 'balanced', 'aggressive'));

ALTER TABLE onboarding_profiles
  DROP CONSTRAINT IF EXISTS onboarding_profiles_activity_detail_check;

ALTER TABLE onboarding_profiles
  ADD CONSTRAINT onboarding_profiles_activity_detail_check
  CHECK (
    activity_detail IS NULL OR
    activity_detail IN ('mostlySitting', 'lightlyActive', 'moderatelyActive', 'veryActive')
  );
