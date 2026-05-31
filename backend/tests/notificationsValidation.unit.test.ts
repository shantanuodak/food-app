import { beforeAll, describe, expect, test } from 'vitest';

// Reproduces two input-validation gaps in the notifications routes:
//  - preferences accepted any string as a timezone (bad zone -> stored -> the
//    notification sweep later throws and the user silently stops getting reminders)
//  - DELETE /devices/:token accepted a 1-char junk token (vs min(32) on register)

let preferenceSchema: typeof import('../src/routes/notifications.js')['preferenceSchema'];
let deviceTokenParamSchema: typeof import('../src/routes/notifications.js')['deviceTokenParamSchema'];

const validPreferences = {
  timezone: 'America/New_York',
  remindersEnabled: true,
  breakfastEnabled: true,
  lunchEnabled: true,
  dinnerEnabled: true,
  breakfastStart: '08:00',
  breakfastEnd: '09:00',
  lunchStart: '12:00',
  lunchEnd: '13:00',
  dinnerStart: '18:00',
  dinnerEnd: '19:00',
  eatingWindowEnabled: false,
  eatingWindowStart: '08:00',
  eatingWindowEnd: '20:00'
};

beforeAll(async () => {
  process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
  const mod = await import('../src/routes/notifications.js');
  preferenceSchema = mod.preferenceSchema;
  deviceTokenParamSchema = mod.deviceTokenParamSchema;
});

describe('notification preferences timezone validation', () => {
  test('rejects an invalid IANA timezone', () => {
    expect(() => preferenceSchema.parse({ ...validPreferences, timezone: 'Not/AZone' })).toThrow();
    expect(() => preferenceSchema.parse({ ...validPreferences, timezone: 'garbage' })).toThrow();
  });

  test('accepts a real timezone', () => {
    expect(preferenceSchema.parse({ ...validPreferences, timezone: 'Europe/London' }).timezone).toBe('Europe/London');
  });
});

describe('device unregister token validation', () => {
  test('rejects junk short tokens', () => {
    expect(() => deviceTokenParamSchema.parse('x')).toThrow();
    expect(() => deviceTokenParamSchema.parse('short')).toThrow();
  });

  test('accepts a real-length token', () => {
    const token = 'a'.repeat(64);
    expect(deviceTokenParamSchema.parse(token)).toBe(token);
  });
});
