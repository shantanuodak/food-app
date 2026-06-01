/**
 * Backfill: recompute macro targets for existing onboarding_profiles using the
 * V5 bodyweight-anchored split (see onboardingService.resolveMacroTargets).
 *
 * Why this exists: changing the macro formula does NOT retrigger a recompute on
 * its own — `onboarding_inputs_hash` is keyed on inputs, not calculator
 * version, so untouched profiles would keep their old 30/40/30 macros until the
 * user next edits their plan. This script applies the new macros to everyone.
 *
 * Safety contract:
 *   - Recomputes ONLY macros, from each row's STORED calorie_target + weight +
 *     goal. calorie_target is never read-modify-written, so it cannot change.
 *     onboarding_inputs_json / onboarding_inputs_hash are left untouched, so the
 *     409 overwrite-guard contract is preserved.
 *   - Dry-run by default. Pass --apply to write. All writes run in a single
 *     transaction (all-or-nothing).
 *   - Only touches rows with full biometrics whose calculator version is not
 *     already v5 (the 2026-05-31 audit found 23/23 profiles have biometrics).
 *
 * Usage:
 *   npx tsx src/scripts/backfillMacrosV5.ts            # dry-run, prints diffs
 *   npx tsx src/scripts/backfillMacrosV5.ts --apply    # writes the changes
 */
import { pool } from '../db.js';
import {
  ONBOARDING_CALCULATOR_VERSION,
  resolveMacroTargets
} from '../services/onboardingService.js';

type Row = {
  user_id: string;
  email: string | null;
  goal: 'lose' | 'maintain' | 'gain';
  weight_kg: string;
  calorie_target: string;
  macro_target_protein: string;
  macro_target_carbs: string;
  macro_target_fat: string;
  onboarding_calculator_version: string | null;
};

async function run(): Promise<void> {
  const apply = process.argv.includes('--apply');
  console.log(`\nMacro V5 backfill — ${apply ? 'APPLY (writing changes)' : 'DRY RUN (no writes)'}\n`);

  const { rows } = await pool.query<Row>(
    `
    SELECT p.user_id, u.email, p.goal, p.weight_kg, p.calorie_target,
           p.macro_target_protein, p.macro_target_carbs, p.macro_target_fat,
           p.onboarding_calculator_version
    FROM onboarding_profiles p
    LEFT JOIN users u ON u.id = p.user_id
    WHERE p.age IS NOT NULL AND p.sex IS NOT NULL
      AND p.height_cm IS NOT NULL AND p.weight_kg IS NOT NULL
      AND p.onboarding_calculator_version IS DISTINCT FROM $1
    ORDER BY p.updated_at DESC
    `,
    [ONBOARDING_CALCULATOR_VERSION]
  );

  console.log(`${rows.length} profile(s) to process (biometric, not yet ${ONBOARDING_CALCULATOR_VERSION}).\n`);

  let changed = 0;
  const updates: Array<{ userId: string; protein: number; carbs: number; fat: number }> = [];

  for (const row of rows) {
    const calorieTarget = Number(row.calorie_target);
    const weightKg = Number(row.weight_kg);
    const macros = resolveMacroTargets(calorieTarget, weightKg, row.goal);

    const oldP = Math.round(Number(row.macro_target_protein));
    const oldC = Math.round(Number(row.macro_target_carbs));
    const oldF = Math.round(Number(row.macro_target_fat));
    const macrosChanged = macros.protein !== oldP || macros.carbs !== oldC || macros.fat !== oldF;
    if (macrosChanged) changed += 1;

    const macroKcal = macros.protein * 4 + macros.carbs * 4 + macros.fat * 9;
    const who = row.email ?? row.user_id;
    console.log(
      `${who.padEnd(34)} ${calorieTarget} kcal  ` +
        `P ${oldP}→${macros.protein}  C ${oldC}→${macros.carbs}  F ${oldF}→${macros.fat}  ` +
        `(Σmacro ${macroKcal}, Δ${macroKcal - calorieTarget >= 0 ? '+' : ''}${macroKcal - calorieTarget})` +
        `${macrosChanged ? '' : '  [unchanged]'}`
    );

    updates.push({ userId: row.user_id, protein: macros.protein, carbs: macros.carbs, fat: macros.fat });
  }

  console.log(`\n${changed} row(s) with macro changes out of ${rows.length}.\n`);

  if (!apply) {
    console.log('Dry run — nothing written. Re-run with --apply to commit.\n');
    await pool.end();
    return;
  }

  if (updates.length === 0) {
    console.log('Nothing to apply.\n');
    await pool.end();
    return;
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const u of updates) {
      await client.query(
        `
        UPDATE onboarding_profiles
        SET macro_target_protein = $1,
            macro_target_carbs = $2,
            macro_target_fat = $3,
            onboarding_calculator_version = $4,
            onboarding_computed_at = NOW(),
            updated_at = NOW()
        WHERE user_id = $5
        `,
        [u.protein, u.carbs, u.fat, ONBOARDING_CALCULATOR_VERSION, u.userId]
      );
    }
    await client.query('COMMIT');
    console.log(`Applied ${updates.length} update(s). calorie_target and onboarding_inputs_hash were not touched.\n`);
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }

  await pool.end();
}

run().catch(async (err) => {
  console.error('Backfill failed', err);
  await pool.end();
  process.exit(1);
});
