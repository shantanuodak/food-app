import { pool } from '../db.js';
import { ensureUserExists } from './userService.js';
import { createHash } from 'node:crypto';
import { ApiError } from '../utils/errors.js';

const ONBOARDING_PROVENANCE_MODE = 'computed_provenance_v1' as const;
export const ONBOARDING_CALCULATOR_VERSION = 'onboarding-target-calculator-v5' as const;

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
  /// V3.1 Phase 5.1 (2026-05-21): when true, the caller has explicitly
  /// confirmed they want to overwrite an existing onboarding_profiles
  /// row. When false/undefined and a row already exists, upsertOnboarding
  /// throws a 409 ApiError so the client can show the
  /// ExistingAccountDetectedView instead of silently clobbering. Added
  /// after Tanmay's 2026-05-21 13:52 UTC profile wipe — see the lesson
  /// note in /Users/shantanuodak/.claude/projects/.../memory/.
  overwriteExisting?: boolean;
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
  calculationMode: 'biometric';
  // V5 (2026-05-31) breakdown intermediates — surfaced so the "How we
  // calculate this" explainer and the iOS/backend parity tests can read the
  // same numbers the calorie target was derived from. Not persisted; the
  // iOS app recomputes these locally for display.
  bmr: number;
  activityMultiplier: number;
  maintenanceCalories: number;
  goalAdjustment: number;
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

/// V3.1 Phase 5: lightweight check used during sign-up to detect when a
/// user re-authenticates with the same Apple/Google identity they used
/// before. iOS calls this right after OAuth succeeds and BEFORE the user
/// commits any new onboarding data. If hasCompletedOnboarding is true,
/// iOS offers the user a choice between continuing with their existing
/// account or applying the freshly-entered onboarding fields to their
/// existing profile. food_logs are never touched in either path.
export async function getOnboardingStatus(userId: string): Promise<{
  hasCompletedOnboarding: boolean;
  mealCount: number;
  createdAt: string | null;
  displayName: string | null;
}> {
  const profileResult = await pool.query<{ created_at: Date }>(
    'SELECT created_at FROM onboarding_profiles WHERE user_id = $1 LIMIT 1',
    [userId]
  );
  const profileRow = profileResult.rows[0];
  const hasCompletedOnboarding = profileRow != null;
  const createdAt = profileRow ? profileRow.created_at.toISOString() : null;

  const mealResult = await pool.query<{ n: string }>(
    'SELECT COUNT(*)::int AS n FROM food_logs WHERE user_id = $1',
    [userId]
  );
  // pg returns COUNT as string; coerce safely.
  const rawN = mealResult.rows[0]?.n;
  const mealCount = typeof rawN === 'number' ? rawN : Number(rawN ?? 0);

  // Bug 2 (2026-05-22): include display_name in /onboarding/status so iOS
  // can populate the Account screen on launch without a separate round
  // trip. The status endpoint is already in the cold-launch path.
  const userResult = await pool.query<{ display_name: string | null }>(
    'SELECT display_name FROM users WHERE id = $1',
    [userId]
  );
  const rawDisplayName = userResult.rows[0]?.display_name;
  const trimmedDisplayName = typeof rawDisplayName === 'string' ? rawDisplayName.trim() : '';
  const displayName = trimmedDisplayName.length > 0 ? trimmedDisplayName : null;

  return {
    hasCompletedOnboarding,
    mealCount: Number.isFinite(mealCount) ? mealCount : 0,
    createdAt,
    displayName
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

/**
 * V5 (2026-05-31) bodyweight-anchored macro split. Replaces the previous
 * fixed 30/40/30 percentage split so the numbers line up with the research
 * the in-app "How we calculate this" explainer cites:
 *   - Protein scales with total bodyweight — 1.8 g/kg during a deficit to
 *     protect lean mass, 1.6 g/kg otherwise (ISSN Position Stand, Jäger 2017,
 *     recommends 1.4–2.0 g/kg for active individuals, higher when cutting).
 *   - Fat is 30% of calories but never below a 0.6 g/kg essential-fat floor.
 *   - Carbs fill whatever calories remain.
 *
 * MUST stay byte-for-byte equivalent to the Swift implementation in
 * `OnboardingCalculator.macroTargets(for:weightKg:goal:)` — the backend test
 * asserts the shared fixtures. Whole-gram macros can't always sum exactly to
 * the calorie target (protein & carbs are 4 kcal/g, fat 9 kcal/g), so the
 * result lands within ~2 kcal; no downstream consumer re-derives calories by
 * summing the target macros (verified 2026-05-31).
 */
export function resolveMacroTargets(
  targetKcal: number,
  weightKg: number,
  goal: OnboardingInput['goal']
): { protein: number; carbs: number; fat: number } {
  const proteinPerKg = goal === 'lose' ? 1.8 : 1.6;
  let protein = Math.max(0, Math.round(weightKg * proteinPerKg));

  const fatFloorGrams = Math.round(weightKg * 0.6);
  let fat = Math.max(Math.round((targetKcal * 0.30) / 9), fatFloorGrams);

  // Heavy person on a low target: protein + fat can exceed the budget. Keep
  // the essential-fat floor, trim any fat above it first, then cap protein so
  // carbs never go negative. (No real profile hits this — DB audit
  // 2026-05-31 — but the calculator must stay total.)
  if (protein * 4 + fat * 9 > targetKcal) {
    const maxFatGrams = Math.max(fatFloorGrams, Math.floor((targetKcal - protein * 4) / 9));
    fat = Math.max(0, Math.min(fat, maxFatGrams));
    if (protein * 4 + fat * 9 > targetKcal) {
      protein = Math.max(0, Math.floor((targetKcal - fat * 9) / 4));
    }
  }

  const carbs = Math.max(0, Math.round((targetKcal - protein * 4 - fat * 9) / 4));

  return { protein, carbs, fat };
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

function resolveActivityMultiplier(input: OnboardingInput): number {
  if (input.activityDetail) {
    switch (input.activityDetail) {
      case 'mostlySitting':
        return 1.2;
      case 'lightlyActive':
        return 1.375;
      case 'moderatelyActive':
        return 1.55;
      case 'veryActive':
        return 1.725;
    }
  }

  switch (input.activityLevel) {
    case 'low':
      return 1.2;
    case 'moderate':
      return 1.375;
    case 'high':
      return 1.725;
  }
}

function resolveDailyDeficitForPace(pace?: OnboardingInput['pace']): number {
  switch (pace) {
    case 'conservative':
      return 250;
    case 'aggressive':
      return 750;
    case 'balanced':
    default:
      return 500;
  }
}

export function calculateOnboardingTargets(input: OnboardingInput): OnboardingTargetCalculation {
  const normalizedInputs = normalizeInputs(input);

  // V5 (2026-05-31): the legacy non-biometric estimate (flat 2200-ish base
  // with a 30/40/30 split) was removed — bodyweight-anchored macros need a
  // real weight. iOS only submits once baseline biometrics are valid
  // (`OnboardingDraft.hasBaselineValues`), and the DB audit on 2026-05-31
  // found 0/23 profiles without biometrics, so this guard is unreachable in
  // practice. We fail loud rather than silently fabricate numbers. The old
  // legacy formula is preserved in the agent memory note, not in code.
  if (!hasBiometricInputs(input)) {
    throw new ApiError(
      400,
      'BIOMETRICS_REQUIRED',
      'Age, sex, height and weight are required to calculate targets.'
    );
  }

  const sexOffset = input.sex === 'male' ? 5 : -161;
  const bmr = (10 * input.weightKg) + (6.25 * input.heightCm) - (5 * input.age) + sexOffset;
  const activityMultiplier = resolveActivityMultiplier(input);
  const minFloor = input.sex === 'male' ? 1500 : 1200;
  const maintenance = Math.max(minFloor, Math.round(bmr * activityMultiplier));
  const paceCalories = resolveDailyDeficitForPace(input.pace);

  let goalAdjustment = 0;
  switch (input.goal) {
    case 'lose':
      goalAdjustment = -paceCalories;
      break;
    case 'gain':
      goalAdjustment = paceCalories;
      break;
    case 'maintain':
      goalAdjustment = 0;
      break;
  }

  const calorieTarget = Math.max(minFloor, maintenance + goalAdjustment);
  const macros = resolveMacroTargets(calorieTarget, input.weightKg, input.goal);

  return {
    calorieTarget,
    protein: macros.protein,
    carbs: macros.carbs,
    fat: macros.fat,
    calculatorVersion: ONBOARDING_CALCULATOR_VERSION,
    normalizedInputs,
    calculationMode: 'biometric',
    bmr: Math.round(bmr),
    activityMultiplier,
    maintenanceCalories: maintenance,
    goalAdjustment
  };
}

export async function upsertOnboarding(input: OnboardingInput): Promise<{ calorieTarget: number; macroTargets: { protein: number; carbs: number; fat: number } }> {
  const targets = calculateOnboardingTargets(input);
  const inputsHash = createHash('sha256').update(JSON.stringify(targets.normalizedInputs)).digest('hex');

  await ensureUserExists(input.userId, {
    authProvider: input.authProvider,
    email: input.userEmail
  });

  // V3.1 Phase 5.1 safety net (2026-05-21): refuse to overwrite an existing
  // onboarding_profiles row with DIFFERENT inputs unless the caller
  // explicitly confirms with `overwriteExisting: true`. Without this, an
  // iOS bug that re-runs the onboarding flow against an established
  // account silently clobbers the user's calorie target, dietary
  // preferences, biometrics, etc. (see Tanmay's incident on 2026-05-21
  // 13:52 UTC where his profile got reset 3 minutes after his last food
  // log). The 409 lets the client route to ExistingAccountDetectedView so
  // the user explicitly confirms the overwrite, or backs out and keeps
  // their data.
  //
  // Idempotent re-submits (same inputs hash) are still allowed without
  // the flag — that preserves the existing contract used by tests + any
  // accidental retry that resends identical values. Only a real
  // value-different clobber attempt gets blocked.
  if (!input.overwriteExisting) {
    const existing = await pool.query<{ onboarding_inputs_hash: string | null }>(
      'SELECT onboarding_inputs_hash FROM onboarding_profiles WHERE user_id = $1',
      [input.userId]
    );
    const existingHash = existing.rows[0]?.onboarding_inputs_hash;
    if (existingHash && existingHash.length > 0 && existingHash !== inputsHash) {
      throw new ApiError(
        409,
        'ONBOARDING_PROFILE_EXISTS',
        'An onboarding profile already exists for this user with different inputs. Pass overwriteExisting=true to replace it.'
      );
    }
  }

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
