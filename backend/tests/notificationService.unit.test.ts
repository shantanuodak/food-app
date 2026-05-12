import { afterEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };

afterEach(() => {
  vi.resetModules();
  vi.restoreAllMocks();
  process.env = { ...baseEnv };
});

async function loadNotificationService() {
  process.env.NODE_ENV = 'test';
  process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
  vi.doMock('../src/db.js', () => ({
    pool: {
      query: vi.fn()
    }
  }));
  return import('../src/services/notificationService.js');
}

describe('notificationService.discoveryDeliveryKey', () => {
  test('uses the full local date so discovery nudges dedupe per day, not per month', async () => {
    const { discoveryDeliveryKey } = await loadNotificationService();

    expect(discoveryDeliveryKey('2026-05-11')).toBe('discovery.logging_modes:2026-05-11');
    expect(discoveryDeliveryKey('2026-05-31')).toBe('discovery.logging_modes:2026-05-31');
  });
});

describe('notificationService.classifyCalorieNudge', () => {
  test('returns halfway once the user reaches half the target but not the full target', async () => {
    const { classifyCalorieNudge } = await loadNotificationService();

    expect(classifyCalorieNudge(900, 2000)).toBe(null);
    expect(classifyCalorieNudge(1000, 2000)).toBe('halfway');
    expect(classifyCalorieNudge(1500, 2000)).toBe('halfway');
  });

  test('returns over once the user reaches or exceeds the target', async () => {
    const { classifyCalorieNudge } = await loadNotificationService();

    expect(classifyCalorieNudge(2000, 2000)).toBe('over');
    expect(classifyCalorieNudge(2350, 2000)).toBe('over');
    expect(classifyCalorieNudge(1200, 0)).toBe(null);
  });
});

describe('notificationService.sendApns', () => {
  test('returns an error instead of throwing when APNS credentials are malformed', async () => {
    process.env.APNS_ENABLED = 'true';
    process.env.APNS_TEAM_ID = 'TEAMID1234';
    process.env.APNS_KEY_ID = 'KEYID12345';
    process.env.APNS_BUNDLE_ID = 'com.shantanu.foodapp';
    process.env.APNS_PRIVATE_KEY = 'not-a-real-private-key';

    const { sendApns } = await loadNotificationService();
    const result = await sendApns(
      {
        id: 'device-1',
        token: 'a'.repeat(64),
        environment: 'production'
      },
      {
        template_key: 'engagement.calorie_halfway',
        kind: 'engagement',
        title: 'Halfway',
        body: 'Body',
        destination: 'home',
        is_enabled: true,
        updated_at: new Date()
      } as never,
      'engagement.calorie_halfway:2026-05-11'
    );

    expect(result.error).toBeTruthy();
  });
});
