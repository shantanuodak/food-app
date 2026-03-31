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

describe('onboarding target calculator', () => {
  test('uses biometric calculation path when full baseline inputs are present', async () => {
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
    expect(result.calculatorVersion).toBe('onboarding-target-calculator-v3');
    expect(result.calorieTarget).toBe(1591);
    expect(result.normalizedInputs).toMatchObject({
      age: 30,
      sex: 'male',
      heightCm: 170,
      weightKg: 70,
      pace: 'balanced',
      activityDetail: 'lightlyActive'
    });
    expect((4 * result.protein) + (4 * result.carbs) + (9 * result.fat)).toBe(result.calorieTarget);
    expect((result.protein * 4) / result.calorieTarget).toBeGreaterThan(0.27);
    expect((result.protein * 4) / result.calorieTarget).toBeLessThan(0.33);
    expect((result.carbs * 4) / result.calorieTarget).toBeGreaterThan(0.37);
    expect((result.carbs * 4) / result.calorieTarget).toBeLessThan(0.43);
    expect((result.fat * 9) / result.calorieTarget).toBeGreaterThan(0.27);
    expect((result.fat * 9) / result.calorieTarget).toBeLessThan(0.33);
  });

  test('keeps legacy calorie buckets when biometrics are absent but still uses aligned macro ratios', async () => {
    const { calculateOnboardingTargets } = await loadOnboardingService();

    const result = calculateOnboardingTargets({
      userId: 'u1',
      goal: 'maintain',
      dietPreference: 'none',
      allergies: [],
      units: 'imperial',
      activityLevel: 'moderate',
      timezone: 'UTC'
    });

    expect(result.calculationMode).toBe('legacy');
    expect(result.calculatorVersion).toBe('onboarding-target-calculator-v3');
    expect(result.calorieTarget).toBe(2200);
    expect(result.normalizedInputs).toMatchObject({
      age: null,
      sex: null,
      heightCm: null,
      weightKg: null,
      pace: null,
      activityDetail: null
    });
    expect((4 * result.protein) + (4 * result.carbs) + (9 * result.fat)).toBe(result.calorieTarget);
    expect((result.protein * 4) / result.calorieTarget).toBeGreaterThan(0.27);
    expect((result.protein * 4) / result.calorieTarget).toBeLessThan(0.33);
    expect((result.carbs * 4) / result.calorieTarget).toBeGreaterThan(0.37);
    expect((result.carbs * 4) / result.calorieTarget).toBeLessThan(0.43);
    expect((result.fat * 9) / result.calorieTarget).toBeGreaterThan(0.27);
    expect((result.fat * 9) / result.calorieTarget).toBeLessThan(0.33);
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
