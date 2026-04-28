import { pool } from '../db.js';
import { ensureUserExists } from './userService.js';
import { createHash } from 'node:crypto';

const ONBOARDING_PROVENANCE_MODE = 'computed_provenance_v1' as const;
const ONBOARDING_CALCULATOR_VERSION = 'onboarding-target-calculator-v3' as const;

export type OnboardingInput = {
  userId: string;
  authProvider?: string | null;
  userEmail?: string | null;
  goal: 'lose' | 'maintain' | 'gain';
  dietPreference: string;
  allergies: string[];
  units: 'metric' | 'imperial';
  activityLevel: 'low' | 'moderate' | 'high';
  age?: number;
  sex?: 'female' | 'male' | 'other';
  heightCm?: number;
  weightKg?: number;
  pace?: 'conservative' | 'balanced' | 'aggressive';
  activityDetail?: 'mostlySitting' | 'lightlyActive' | 'moderatelyActive' | 'veryActive';
  timezone: string;
};

export type OnboardingProvenance = {
  mode: string;
  inputsHash: string;
  calculatorVersion: string;
  computedAt: string;
  inputs: Record<string, unknown>;
};

export type OnboardingProfile = {
  goal: 'lose' | 'maintain' | 'gain';
  dietPreference: string;
  allergies: string[];
  units: 'metric' | 'imperial';
  activityLevel: 'low' | 'moderate' | 'high';
  timezone: string;
  age: number | null;
  sex: 'female' | 'male' | 'other' | null;
  heightCm: number | null;
  weightKg: number | null;
  pace: 'conservative' | 'balanced' | 'aggressive' | null;
  activityDetail: 'mostlySitting' | 'lightlyActive' | 'moderatelyActive' | 'veryActive' | null;
  calorieTarget: number;
  macroTargets: {
    protein: number;
    carbs: number;
    fat: number;
  };
  updatedAt: string;
};

export type OnboardingTargetCalculation = {
  calorieTarget: number;
  protein: number;
  carbs: number;
  fat: number;
  calculatorVersion: string;
  normalizedInputs: Record<string, unknown>;
  calculationMode: 'biometric' | 'legacy';
};

export async function getOnboardingParsePreferences(userId: string): Promise<{ units: 'metric' | 'imperial' | null; timezone: string | null }> {
  const result = await pool.query<{ units: 'metric' | 'imperial' | null; timezone: string | null }>(
    `
    SELECT units, timezone
    FROM onboarding_profiles
    WHERE user_id = $1
    `,
    [userId]
  );

  const row = result.rows[0];
  if (!row) {
    return { units: null, timezone: null };
  }

  return {
    units: row.units || null,
    timezone: row.timezone || null
  };
}

/**
 * Reads diet preference + allergies for a user. Returned in the form
 * the parse pipeline / dietary conflict service expects:
 * - `dietPreference`: the comma-separated string iOS already serializes
 *   (`"vegetarian,gluten_free"` or `"no_preference"`); null if no profile yet.
 * - `allergies`: array of rawValue strings (e.g. `["peanuts", "shellfish"]`).
 */
export async function getDietAndAllergies(userId: string): Promise<{
  dietPreference: string | null;
  allergies: string[];
}> {
  const result = await pool.query<{ diet_preference: string | null; allergies_json: string[] | null }>(
    `
    SELECT diet_preference, allergies_json
    FROM onboarding_profiles
    WHERE user_id = $1
    `,
    [userId]
  );
  const row = result.rows[0];
  if (!row) {
    return { dietPreference: null, allergies: [] };
  }
  return {
    dietPreference: row.diet_preference || null,
    allergies: Array.isArray(row.allergies_json) ? row.allergies_json : []
  };
}

export async function getOnboardingProvenance(userId: string): Promise<OnboardingProvenance | null> {
  const result = await pool.query<{
    onboarding_provenance_mode: string;
    onboarding_inputs_hash: string;
    onboarding_calculator_version: string;
    onboarding_computed_at: Date;
    onboarding_inputs_json: Record<string, unknown>;
  }>(
    `
    SELECT
      onboarding_provenance_mode,
      onboarding_inputs_hash,
      onboarding_calculator_version,
      onboarding_computed_at,
      onboarding_inputs_json
    FROM onboarding_profiles
    WHERE user_id = $1
    `,
    [userId]
  );

  const row = result.rows[0];
  if (!row) {
    return null;
  }

  return {
    mode: row.onboarding_provenance_mode || ONBOARDING_PROVENANCE_MODE,
    inputsHash: row.onboarding_inputs_hash,
    calculatorVersion: row.onboarding_calculator_version,
    computedAt: row.onboarding_computed_at.toISOString(),
    inputs: row.onboarding_inputs_json || {}
  };
}

export async function getOnboardingProfile(userId: string): Promise<OnboardingProfile | null> {
  const result = await pool.query<{
    goal: 'lose' | 'maintain' | 'gain';
    diet_preference: string;
    allergies_json: string[] | null;
    units: 'metric' | 'imperial';
    activity_level: 'low' | 'moderate' | 'high';
    timezone: string;
    age: number | null;
    sex: 'female' | 'male' | 'other' | null;
    height_cm: string | null;
    weight_kg: string | null;
    pace: 'conservative' | 'balanced' | 'aggressive' | null;
    activity_detail: 'mostlySitting' | 'lightlyActive' | 'moderatelyActive' | 'veryActive' | null;
    calorie_target: string;
    macro_target_protein: string;
    macro_target_carbs: string;
    macro_target_fat: string;
    updated_at: Date;
  }>(
    `
    SELECT
      goal,
      diet_preference,
      allergies_json,
      units,
      activity_level,
      timezone,
      age,
      sex,
      height_cm,
      weight_kg,
      pace,
      activity_detail,
      calorie_target,
      macro_target_protein,
      macro_target_carbs,
      macro_target_fat,
      updated_at
    FROM onboarding_profiles
    WHERE user_id = $1
    `,
    [userId]
  );

  const row = result.rows[0];
  if (!row) {
    return null;
  }

  return {
    goal: row.goal,
    dietPreference: row.diet_preference,
    allergies: Array.isArray(row.allergies_json) ? row.allergies_json : [],
    units: row.units,
    activityLevel: row.activity_level,
    timezone: row.timezone,
    age: row.age,
    sex: row.sex,
    heightCm: row.height_cm === null ? null : Number(row.height_cm),
    weightKg: row.weight_kg === null ? null : Number(row.weight_kg),
    pace: row.pace,
    activityDetail: row.activity_detail,
    calorieTarget: Number(row.calorie_target),
    macroTargets: {
      protein: Number(row.macro_target_protein),
      carbs: Number(row.macro_target_carbs),
      fat: Number(row.macro_target_fat)
    },
    updatedAt: row.updated_at.toISOString()
  };
}

function resolveMacroTargets(calorieTarget: number): { protein: number; carbs: number; fat: number } {
  const desiredProtein = (calorieTarget * 0.30) / 4;
  const desiredCarbs = (calorieTarget * 0.4) / 4;
  const desiredFat = (calorieTarget * 0.30) / 9;

  const baseProtein = Math.max(0, Math.round(desiredProtein));
  const baseCarbs = Math.max(0, Math.round(desiredCarbs));
  const baseFat = Math.max(0, Math.round(desiredFat));

  let best: { protein: number; carbs: number; fat: number; score: number } | null = null;

  for (let protein = Math.max(0, baseProtein - 18); protein <= baseProtein + 18; protein += 1) {
    for (let carbs = Math.max(0, baseCarbs - 24); carbs <= baseCarbs + 24; carbs += 1) {
      const remainingCalories = calorieTarget - 4 * protein - 4 * carbs;
      if (remainingCalories < 0 || remainingCalories % 9 !== 0) {
        continue;
      }

      const fat = remainingCalories / 9;
      if (fat < 0) {
        continue;
      }

      const score =
        (protein - desiredProtein) ** 2 +
        (carbs - desiredCarbs) ** 2 +
        (fat - desiredFat) ** 2;

      if (!best || score < best.score) {
        best = { protein, carbs, fat, score };
      }
    }
  }

  if (best) {
    return {
      protein: best.protein,
      carbs: best.carbs,
      fat: best.fat
    };
  }

  return {
    protein: baseProtein,
    carbs: baseCarbs,
    fat: baseFat
  };
}

function roundTo(value: number, digits: number): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function hasBiometricInputs(
  input: OnboardingInput
): input is OnboardingInput & Required<Pick<OnboardingInput, 'age' | 'sex' | 'heightCm' | 'weightKg'>> {
  return (
    typeof input.age === 'number' &&
    typeof input.heightCm === 'number' &&
    typeof input.weightKg === 'number' &&
    (input.sex === 'female' || input.sex === 'male' || input.sex === 'other')
  );
}

function normalizeInputs(input: OnboardingInput): Record<string, unknown> {
  return {
    goal: input.goal,
    dietPreference: input.dietPreference.trim(),
    allergies: input.allergies.map((entry) => entry.trim()).filter(Boolean),
    units: input.units,
    activityLevel: input.activityLevel,
    timezone: input.timezone.trim(),
    age: input.age ?? null,
    sex: input.sex ?? null,
    heightCm: typeof input.heightCm === 'number' ? roundTo(input.heightCm, 2) : null,
    weightKg: typeof input.weightKg === 'number' ? roundTo(input.weightKg, 2) : null,
    pace: input.pace ?? null,
    activityDetail: input.activityDetail ?? null
  };
}

function resolveActivityAdjustment(input: OnboardingInput): number {
  if (input.activityDetail) {
    switch (input.activityDetail) {
      case 'mostlySitting':
        return -80;
      case 'lightlyActive':
        return 0;
      case 'moderatelyActive':
        return 120;
      case 'veryActive':
        return 240;
    }
  }

  switch (input.activityLevel) {
    case 'low':
      return -80;
    case 'moderate':
      return 0;
    case 'high':
      return 240;
  }
}

function resolvePaceAdjustment(pace?: OnboardingInput['pace']): number {
  switch (pace) {
    case 'conservative':
      return 80;
    case 'aggressive':
      return -120;
    case 'balanced':
    default:
      return 0;
  }
}

export function calculateOnboardingTargets(input: OnboardingInput): OnboardingTargetCalculation {
  const normalizedInputs = normalizeInputs(input);

  if (hasBiometricInputs(input)) {
    const sexOffset = input.sex === 'male' ? 5 : -161;
    const bmr = (10 * input.weightKg) + (6.25 * input.heightCm) - (5 * input.age) + sexOffset;
    const maintenance = Math.max(1200, Math.round(bmr * 1.2));
    let calorieTarget = maintenance;

    switch (input.goal) {
      case 'lose':
        calorieTarget -= 350;
        break;
      case 'gain':
        calorieTarget += 280;
        break;
      case 'maintain':
        break;
    }

    calorieTarget += resolveActivityAdjustment(input);
    calorieTarget += resolvePaceAdjustment(input.pace);
    calorieTarget = Math.max(1200, calorieTarget);

    const macros = resolveMacroTargets(calorieTarget);
    return {
      calorieTarget,
      protein: macros.protein,
      carbs: macros.carbs,
      fat: macros.fat,
      calculatorVersion: ONBOARDING_CALCULATOR_VERSION,
      normalizedInputs,
      calculationMode: 'biometric'
    };
  }

  const base = input.activityLevel === 'high' ? 2500 : input.activityLevel === 'moderate' ? 2200 : 1900;
  const adjusted = input.goal === 'lose' ? base - 350 : input.goal === 'gain' ? base + 300 : base;
  const macros = resolveMacroTargets(adjusted);

  return {
    calorieTarget: adjusted,
    protein: macros.protein,
    carbs: macros.carbs,
    fat: macros.fat,
    calculatorVersion: ONBOARDING_CALCULATOR_VERSION,
    normalizedInputs,
    calculationMode: 'legacy'
  };
}

export async function upsertOnboarding(input: OnboardingInput): Promise<{ calorieTarget: number; macroTargets: { protein: number; carbs: number; fat: number } }> {
  const targets = calculateOnboardingTargets(input);
  const inputsHash = createHash('sha256').update(JSON.stringify(targets.normalizedInputs)).digest('hex');

  await ensureUserExists(input.userId, {
    authProvider: input.authProvider,
    email: input.userEmail
  });

  await pool.query(
    `
    INSERT INTO onboarding_profiles (
      user_id, goal, diet_preference, allergies_json, units, activity_level, timezone, age, sex, height_cm, weight_kg, pace, activity_detail,
      calorie_target, macro_target_protein, macro_target_carbs, macro_target_fat,
      onboarding_inputs_json, onboarding_inputs_hash, onboarding_calculator_version, onboarding_provenance_mode, onboarding_computed_at,
      created_at, updated_at
    )
    VALUES ($1,$2,$3,$4::jsonb,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18::jsonb,$19,$20,$21,NOW(),NOW(),NOW())
    ON CONFLICT (user_id)
    DO UPDATE SET
      goal = EXCLUDED.goal,
      diet_preference = EXCLUDED.diet_preference,
      allergies_json = EXCLUDED.allergies_json,
      units = EXCLUDED.units,
      activity_level = EXCLUDED.activity_level,
      timezone = EXCLUDED.timezone,
      age = EXCLUDED.age,
      sex = EXCLUDED.sex,
      height_cm = EXCLUDED.height_cm,
      weight_kg = EXCLUDED.weight_kg,
      pace = EXCLUDED.pace,
      activity_detail = EXCLUDED.activity_detail,
      calorie_target = EXCLUDED.calorie_target,
      macro_target_protein = EXCLUDED.macro_target_protein,
      macro_target_carbs = EXCLUDED.macro_target_carbs,
      macro_target_fat = EXCLUDED.macro_target_fat,
      onboarding_inputs_json = EXCLUDED.onboarding_inputs_json,
      onboarding_inputs_hash = EXCLUDED.onboarding_inputs_hash,
      onboarding_calculator_version = EXCLUDED.onboarding_calculator_version,
      onboarding_provenance_mode = EXCLUDED.onboarding_provenance_mode,
      onboarding_computed_at = NOW(),
      updated_at = NOW()
    `,
    [
      input.userId,
      input.goal,
      input.dietPreference,
      JSON.stringify(input.allergies),
      input.units,
      input.activityLevel,
      input.timezone,
      input.age ?? null,
      input.sex ?? null,
      typeof input.heightCm === 'number' ? roundTo(input.heightCm, 2) : null,
      typeof input.weightKg === 'number' ? roundTo(input.weightKg, 2) : null,
      input.pace ?? null,
      input.activityDetail ?? null,
      targets.calorieTarget,
      targets.protein,
      targets.carbs,
      targets.fat,
      JSON.stringify(targets.normalizedInputs),
      inputsHash,
      targets.calculatorVersion,
      ONBOARDING_PROVENANCE_MODE
    ]
  );

  return {
    calorieTarget: targets.calorieTarget,
    macroTargets: {
      protein: targets.protein,
      carbs: targets.carbs,
      fat: targets.fat
    }
  };
}
