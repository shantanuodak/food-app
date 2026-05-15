import { afterEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };

afterEach(() => {
  vi.resetModules();
  process.env = { ...baseEnv };
});

describe('app security defaults', () => {
  test('validates testing dashboard access with a server-side signed cookie value', async () => {
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
    process.env.INTERNAL_METRICS_KEY = 'test-dashboard-key';

    const appModule = await import('../src/app.js');
    const token = appModule.dashboardSessionValueForTests();

    expect(appModule.isDashboardCookieHeaderValidForTests(undefined)).toBe(false);
    expect(appModule.isDashboardCookieHeaderValidForTests('food_app_dashboard=wrong')).toBe(false);
    expect(appModule.isDashboardCookieHeaderValidForTests(`food_app_dashboard=${token}`)).toBe(true);
  });
});
