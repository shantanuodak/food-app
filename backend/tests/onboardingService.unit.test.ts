import { afterEach, describe, expect, test, vi } from 'vitest';
import { createHash } from 'node:crypto';

const baseEnv = { ...process.env };

afterEach(() => {
  vi.resetModules();
  vi.restoreAllMocks();
  process.env = { ...baseEnv };
});

async function loadOnboardingService() {
  process.env.NODE_ENV = 'test';
  process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
  return import('../src/services/onboardingService.js');
}

// Whole-gram macros (protein & carbs at 4 kcal/g, fat at 9 kcal/g) can't always
// sum exactly to the calorie target, so the V5 split lands within a couple kcal.
function macroKcal(result: { protein: number; carbs: number; fat: number }): number {
  return result.protein * 4 + result.carbs * 4 + result.fat * 9;
}

describe('onboarding target calculator (V5 bodyweight-anchored macros)', () => {
  test('biometric path: Mifflin calories unchanged, macros follow bodyweight', async () => {
    const { calculateOnboardingTargets } = await loadOnboardingService();

    const result = calculateOnboardingTargets({
      userId: 'u1',
      goal: 'lose',
      dietPreference: 'none',
      allergies: [],
      units: 'metric',
      activityLevel: 'moderate',
      timezone: 'UTC',
      age: 30,
      sex: 'male',
      heightCm: 170,
      weightKg: 70,
      pace: 'balanced',
      activityDetail: 'lightlyActive'
    });

    expect(result.calculationMode).toBe('biometric');
    expect(result.calculatorVersion).toBe('onboarding-target-calculator-v5');

    // Calorie pipeline is unchanged from v4.
    expect(result.bmr).toBe(1618); // round(1617.5)
    expect(result.activityMultiplier).toBe(1.375);
    expect(result.maintenanceCalories).toBe(2224); // round(1617.5 * 1.375)
    expect(result.goalAdjustment).toBe(-500);
    expect(result.calorieTarget).toBe(1724);

    // Macros: protein = round(70 * 1.8), fat = max(30%/9, 0.6 g/kg), carbs = rest.
    expect(result.protein).toBe(126);
    expect(result.fat).toBe(57);
    expect(result.carbs).toBe(177);
    expect(Math.abs(macroKcal(result) - result.calorieTarget)).toBeLessThanOrEqual(3);

    expect(result.normalizedInputs).toMatchObject({
      age: 30,
      sex: 'male',
      heightCm: 170,
      weightKg: 70,
      pace: 'balanced',
      activityDetail: 'lightlyActive'
    });
  });

  test('acceptance case: 93 kg male, lightly active, lose, balanced', async () => {
    const { calculateOnboardingTargets } = await loadOnboardingService();

    const result = calculateOnboardingTargets({
      userId: 'u1',
      goal: 'lose',
      dietPreference: 'none',
      allergies: [],
      units: 'metric',
      activityLevel: 'moderate',
      timezone: 'UTC',
      age: 32,
      sex: 'male',
      heightCm: 183,
      weightKg: 93,
      pace: 'balanced',
      activityDetail: 'lightlyActive'
    });

    expect(result.bmr).toBe(1919); // round(1918.75)
    expect(result.maintenanceCalories).toBe(2638);
    expect(result.goalAdjustment).toBe(-500);
    expect(result.calorieTarget).toBe(2138);
    expect(result.protein).toBe(167); // round(93 * 1.8)
    expect(result.carbs).toBe(208);
    expect(result.fat).toBe(71);
    expect(Math.abs(macroKcal(result) - result.calorieTarget)).toBeLessThanOrEqual(3);
  });

  test('matches the iOS onboarding calculator for representative fixtures', async () => {
    const { calculateOnboardingTargets } = await loadOnboardingService();

    // These exact gram values are the iOS↔backend lockstep contract — the
    // Swift `OnboardingCalculator.macroTargets(for:weightKg:goal:)` must
    // produce identical numbers for the same inputs.
    const fixtures = [
      {
        input: {
          age: 30, sex: 'male' as const, heightCm: 170, weightKg: 70,
          goal: 'lose' as const, activityDetail: 'lightlyActive' as const,
          activityLevel: 'moderate' as const, pace: 'balanced' as const
        },
        expectedTarget: 1724,
        expectedMacros: { protein: 126, carbs: 177, fat: 57 }
      },
      {
        input: {
          age: 25, sex: 'female' as const, heightCm: 160, weightKg: 55,
          goal: 'maintain' as const, activityDetail: 'moderatelyActive' as const,
          activityLevel: 'moderate' as const, pace: 'conservative' as const
        },
        expectedTarget: 1959,
        expectedMacros: { protein: 88, carbs: 256, fat: 65 }
      },
      {
        input: {
          age: 40, sex: 'other' as const, heightCm: 180, weightKg: 82,
          goal: 'gain' as const, activityDetail: 'veryActive' as const,
          activityLevel: 'high' as const, pace: 'aggressive' as const
        },
        expectedTarget: 3482,
        expectedMacros: { protein: 131, carbs: 479, fat: 116 }
      },
      {
        input: {
          age: 30, sex: 'male' as const, heightCm: 183, weightKg: 82,
          goal: 'lose' as const, activityDetail: 'veryActive' as const,
          activityLevel: 'high' as const, pace: 'aggressive' as const
        },
        expectedTarget: 2387,
        expectedMacros: { protein: 148, carbs: 269, fat: 80 }
      }
    ];

    for (const fixture of fixtures) {
      const result = calculateOnboardingTargets({
        userId: 'u1',
        dietPreference: 'none',
        allergies: [],
        units: 'metric',
        timezone: 'UTC',
        ...fixture.input
      });

      expect(result.calculationMode).toBe('biometric');
      expect(result.calorieTarget).toBe(fixture.expectedTarget);
      expect(result.protein).toBe(fixture.expectedMacros.protein);
      expect(result.carbs).toBe(fixture.expectedMacros.carbs);
      expect(result.fat).toBe(fixture.expectedMacros.fat);
      expect(Math.abs(macroKcal(result) - result.calorieTarget)).toBeLessThanOrEqual(3);
    }
  });

  test('protein + fat never push carbs negative on a low target (clamp)', async () => {
    const { resolveMacroTargets } = await loadOnboardingService();

    // Contrived heavy-person / low-target combo no real Mifflin profile reaches
    // (verified by the 2026-05-31 audit), but the calculator must stay total.
    const macros = resolveMacroTargets(1200, 150, 'lose');

    expect(macros.carbs).toBeGreaterThanOrEqual(0);
    expect(macros.protein).toBeGreaterThan(0);
    expect(macros.fat).toBe(90); // essential-fat floor (0.6 g/kg) is preserved
    expect(macros.protein * 4 + macros.fat * 9).toBeLessThanOrEqual(1200 + 3);
    expect(Math.abs(macroKcal(macros) - 1200)).toBeLessThanOrEqual(4);
  });

  test('throws BIOMETRICS_REQUIRED when biometric inputs are absent', async () => {
    const { calculateOnboardingTargets } = await loadOnboardingService();

    let thrown: any;
    try {
      calculateOnboardingTargets({
        userId: 'u1',
        goal: 'maintain',
        dietPreference: 'none',
        allergies: [],
        units: 'imperial',
        activityLevel: 'moderate',
        timezone: 'UTC'
      });
    } catch (err) {
      thrown = err;
    }

    expect(thrown).toBeDefined();
    expect(thrown.statusCode).toBe(400);
    expect(thrown.code).toBe('BIOMETRICS_REQUIRED');
  });

  test('changes normalized input hash when biometric inputs change', async () => {
    const { calculateOnboardingTargets } = await loadOnboardingService();

    const baseInput = {
      userId: 'u1',
      goal: 'maintain' as const,
      dietPreference: 'none',
      allergies: [],
      units: 'metric' as const,
      activityLevel: 'moderate' as const,
      timezone: 'UTC',
      age: 30,
      sex: 'male' as const,
      heightCm: 170,
      weightKg: 70,
      pace: 'balanced' as const,
      activityDetail: 'lightlyActive' as const
    };

    const first = calculateOnboardingTargets(baseInput);
    const second = calculateOnboardingTargets({
      ...baseInput,
      weightKg: 71
    });

    const firstHash = createHash('sha256').update(JSON.stringify(first.normalizedInputs)).digest('hex');
    const secondHash = createHash('sha256').update(JSON.stringify(second.normalizedInputs)).digest('hex');

    expect(firstHash).not.toBe(secondHash);
  });
});
