import { pool } from '../db.js';
import { ensureUserExists } from './userService.js';
import { createHash } from 'node:crypto';

type OnboardingInput = {
  userId: string;
  authProvider?: string | null;
  userEmail?: string | null;
  goal: 'lose' | 'maintain' | 'gain';
  dietPreference: string;
  allergies: string[];
  units: 'metric' | 'imperial';
  activityLevel: 'low' | 'moderate' | 'high';
  timezone: string;
};

const ONBOARDING_PROVENANCE_MODE = 'computed_provenance_v1' as const;

export type OnboardingProvenance = {
  mode: string;
  inputsHash: string;
  calculatorVersion: string;
  computedAt: string;
  inputs: Record<string, unknown>;
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

function resolveMacroTargets(calorieTarget: number): { protein: number; carbs: number; fat: number } {
  const desiredProtein = (calorieTarget * 0.25) / 4;
  const desiredCarbs = (calorieTarget * 0.4) / 4;
  const desiredFat = (calorieTarget * 0.35) / 9;

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

function targetsFor(input: OnboardingInput): { calorieTarget: number; protein: number; carbs: number; fat: number } {
  const base = input.activityLevel === 'high' ? 2500 : input.activityLevel === 'moderate' ? 2200 : 1900;
  const adjusted = input.goal === 'lose' ? base - 350 : input.goal === 'gain' ? base + 300 : base;
  const macros = resolveMacroTargets(adjusted);

  return {
    calorieTarget: adjusted,
    protein: macros.protein,
    carbs: macros.carbs,
    fat: macros.fat
  };
}

export async function upsertOnboarding(input: OnboardingInput): Promise<{ calorieTarget: number; macroTargets: { protein: number; carbs: number; fat: number } }> {
  const targets = targetsFor(input);
  const normalizedInputs = {
    goal: input.goal,
    dietPreference: input.dietPreference.trim(),
    allergies: input.allergies.map((entry) => entry.trim()).filter(Boolean),
    units: input.units,
    activityLevel: input.activityLevel,
    timezone: input.timezone.trim()
  };
  const calculatorVersion = 'onboarding-target-calculator-v2';
  const inputsHash = createHash('sha256').update(JSON.stringify(normalizedInputs)).digest('hex');

  await ensureUserExists(input.userId, {
    authProvider: input.authProvider,
    email: input.userEmail
  });

  await pool.query(
    `
    INSERT INTO onboarding_profiles (
      user_id, goal, diet_preference, allergies_json, units, activity_level, timezone,
      calorie_target, macro_target_protein, macro_target_carbs, macro_target_fat,
      onboarding_inputs_json, onboarding_inputs_hash, onboarding_calculator_version, onboarding_provenance_mode, onboarding_computed_at,
      created_at, updated_at
    )
    VALUES ($1,$2,$3,$4::jsonb,$5,$6,$7,$8,$9,$10,$11,$12::jsonb,$13,$14,$15,NOW(),NOW(),NOW())
    ON CONFLICT (user_id)
    DO UPDATE SET
      goal = EXCLUDED.goal,
      diet_preference = EXCLUDED.diet_preference,
      allergies_json = EXCLUDED.allergies_json,
      units = EXCLUDED.units,
      activity_level = EXCLUDED.activity_level,
      timezone = EXCLUDED.timezone,
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
      targets.calorieTarget,
      targets.protein,
      targets.carbs,
      targets.fat,
      JSON.stringify(normalizedInputs),
      inputsHash,
      calculatorVersion,
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
