import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };

afterEach(() => {
  vi.resetModules();
  vi.restoreAllMocks();
  process.env = { ...baseEnv };
});

beforeEach(() => {
  process.env.NODE_ENV = 'test';
  process.env.DATABASE_URL =
    process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
});

interface MockRow {
  user_id: string;
  email: string;
  parses: string;
  saves: string;
  last_parse: Date;
  last_save: Date | null;
}

async function loadServiceWithRows(rows: MockRow[]) {
  vi.doMock('../src/db.js', () => ({
    pool: {
      query: vi.fn().mockResolvedValue({ rows, rowCount: rows.length })
    }
  }));
  return import('../src/services/saveHealthService.js');
}

describe('saveHealthService.getSaveHealthReport', () => {
  test('classifies a 5-parse zero-save user as critical', async () => {
    // The exact pattern that hid the 18-day silent image-save outage
    // (commit 0443246): meaningful parse activity, zero saves landing.
    const { getSaveHealthReport } = await loadServiceWithRows([
      {
        user_id: 'u-critical',
        email: 'stuck@example.com',
        parses: '7',
        saves: '0',
        last_parse: new Date('2026-04-30T02:00:00Z'),
        last_save: null
      }
    ]);

    const report = await getSaveHealthReport();
    expect(report.users).toHaveLength(1);
    expect(report.users[0]).toMatchObject({
      email: 'stuck@example.com',
      parseCount: 7,
      saveCount: 0,
      saveRate: 0,
      severity: 'critical',
      lastSaveAt: null
    });
    expect(report.summary.criticalCount).toBe(1);
    expect(report.summary.warningCount).toBe(0);
  });

  test('classifies low save rate (<10%) over 10+ parses as warning', async () => {
    const { getSaveHealthReport } = await loadServiceWithRows([
      {
        user_id: 'u-warn',
        email: 'sluggish@example.com',
        parses: '20',
        saves: '1',
        last_parse: new Date('2026-04-30T02:00:00Z'),
        last_save: new Date('2026-04-29T10:00:00Z')
      }
    ]);

    const report = await getSaveHealthReport();
    expect(report.users[0].severity).toBe('warning');
    expect(report.users[0].saveRate).toBeCloseTo(0.05, 2);
    expect(report.summary.warningCount).toBe(1);
  });

  test('omits healthy users from default response, includes them when requested', async () => {
    const rows: MockRow[] = [
      {
        user_id: 'u-healthy',
        email: 'normal@example.com',
        parses: '15',
        saves: '5',
        last_parse: new Date('2026-04-30T02:00:00Z'),
        last_save: new Date('2026-04-30T01:00:00Z')
      }
    ];

    const svc = await loadServiceWithRows(rows);

    // Default: omit healthy from the users array but still count them.
    const defaultReport = await svc.getSaveHealthReport();
    expect(defaultReport.users).toHaveLength(0);
    expect(defaultReport.summary.healthyCount).toBe(1);

    // Opt-in: include healthy.
    const fullReport = await svc.getSaveHealthReport({ includeHealthy: true });
    expect(fullReport.users).toHaveLength(1);
    expect(fullReport.users[0].severity).toBe('healthy');
  });

  test('clamps windowDays to [1, 30]', async () => {
    const { getSaveHealthReport } = await loadServiceWithRows([]);
    expect((await getSaveHealthReport({ windowDays: 0 })).windowDays).toBe(1);
    expect((await getSaveHealthReport({ windowDays: 100 })).windowDays).toBe(30);
    expect((await getSaveHealthReport({ windowDays: 14 })).windowDays).toBe(14);
  });

  test('returns expected thresholds in the report', async () => {
    const { getSaveHealthReport } = await loadServiceWithRows([]);
    const report = await getSaveHealthReport();
    expect(report.thresholds).toEqual({
      criticalMinParses: 5,
      warningMinParses: 10,
      warningMaxSaveRate: 0.10
    });
  });
});
