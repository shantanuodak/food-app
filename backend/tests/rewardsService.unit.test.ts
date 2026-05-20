import { afterEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };

afterEach(() => {
  vi.resetModules();
  vi.restoreAllMocks();
  process.env = { ...baseEnv };
});

async function loadRewardsServiceWithRow(row: Record<string, string>) {
  process.env.NODE_ENV = 'test';
  process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
  const query = vi.fn().mockResolvedValue({ rows: [row], rowCount: 1 });
  vi.doMock('../src/db.js', () => ({ pool: { query } }));
  const service = await import('../src/services/rewardsService.js');
  return { service, query };
}

describe('rewardsService.getRewardsSummary', () => {
  test('maps aggregate reward stats into camelCase API totals', async () => {
    const { service, query } = await loadRewardsServiceWithRow({
      logs: '12',
      text_logs: '7',
      voice_logs: '2',
      image_logs: '3',
      manual_logs: '0',
      high_confidence_logs: '9',
      food_items: '31',
      unique_foods: '22',
      manual_override_items: '4',
      high_confidence_items: '25',
      health_active_days: '6',
      health_step_days_10k: '2'
    });

    const summary = await service.getRewardsSummary('u1', 'America/New_York');

    expect(query).toHaveBeenCalledWith(expect.stringContaining('WITH log_stats AS'), ['u1']);
    expect(query.mock.calls[0]?.[0]).toContain('fl.id = fli.food_log_id');
    expect(query.mock.calls[0]?.[0]).toContain("LIKE 'image%'");
    expect(summary.timezone).toBe('America/New_York');
    expect(summary.generatedAt).toEqual(expect.any(String));
    expect(summary.totals).toEqual({
      logs: 12,
      foodItems: 31,
      uniqueFoods: 22,
      textLogs: 7,
      voiceLogs: 2,
      imageLogs: 3,
      manualLogs: 0,
      manualOverrideItems: 4,
      highConfidenceLogs: 9,
      highConfidenceItems: 25,
      healthActiveDays: 6,
      healthStepDays10k: 2
    });
  });

  test('falls back to UTC for invalid timezone input', async () => {
    const { service } = await loadRewardsServiceWithRow({
      logs: '0',
      text_logs: '0',
      voice_logs: '0',
      image_logs: '0',
      manual_logs: '0',
      high_confidence_logs: '0',
      food_items: '0',
      unique_foods: '0',
      manual_override_items: '0',
      high_confidence_items: '0',
      health_active_days: '0',
      health_step_days_10k: '0'
    });

    const summary = await service.getRewardsSummary('u1', 'not-a-timezone');
    expect(summary.timezone).toBe('UTC');
  });
});
