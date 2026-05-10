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
    expect(result.calculatorVersion).toBe('onboarding-target-calculator-v4');
    expect(result.calorieTarget).toBe(1724);
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

  test('matches iOS onboarding calculator for representative biometric fixtures', async () => {
    const { calculateOnboardingTargets } = await loadOnboardingService();

    const fixtures = [
      {
        input: {
          age: 30,
          sex: 'male' as const,
          heightCm: 170,
          weightKg: 70,
          goal: 'lose' as const,
          activityDetail: 'lightlyActive' as const,
          activityLevel: 'moderate' as const,
          pace: 'balanced' as const
        },
        expectedTarget: 1724
      },
      {
        input: {
          age: 25,
          sex: 'female' as const,
          heightCm: 160,
          weightKg: 55,
          goal: 'maintain' as const,
          activityDetail: 'moderatelyActive' as const,
          activityLevel: 'moderate' as const,
          pace: 'conservative' as const
        },
        expectedTarget: 1959
      },
      {
        input: {
          age: 40,
          sex: 'other' as const,
          heightCm: 180,
          weightKg: 82,
          goal: 'gain' as const,
          activityDetail: 'veryActive' as const,
          activityLevel: 'high' as const,
          pace: 'aggressive' as const
        },
        expectedTarget: 3482
      },
      {
        input: {
          age: 30,
          sex: 'male' as const,
          heightCm: 183,
          weightKg: 82,
          goal: 'lose' as const,
          activityDetail: 'veryActive' as const,
          activityLevel: 'high' as const,
          pace: 'aggressive' as const
        },
        expectedTarget: 2387
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
      expect((4 * result.protein) + (4 * result.carbs) + (9 * result.fat)).toBe(result.calorieTarget);
    }
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
    expect(result.calculatorVersion).toBe('onboarding-target-calculator-v4');
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
