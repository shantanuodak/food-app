import { pool } from '../db.js';

export type RewardsTotals = {
  logs: number;
  foodItems: number;
  uniqueFoods: number;
  textLogs: number;
  voiceLogs: number;
  imageLogs: number;
  manualLogs: number;
  manualOverrideItems: number;
  highConfidenceLogs: number;
  highConfidenceItems: number;
  healthActiveDays: number;
  healthStepDays10k: number;
};

export type RewardsSummary = {
  timezone: string;
  generatedAt: string;
  totals: RewardsTotals;
};

type RewardsStatsRow = {
  logs: string;
  text_logs: string;
  voice_logs: string;
  image_logs: string;
  manual_logs: string;
  high_confidence_logs: string;
  food_items: string;
  unique_foods: string;
  manual_override_items: string;
  high_confidence_items: string;
  health_active_days: string;
  health_step_days_10k: string;
};

function toInt(value: string | number | null | undefined): number {
  if (value === null || value === undefined) return 0;
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : 0;
}

export function normalizeRewardsTimezone(timezone: string | undefined): string {
  const trimmed = timezone?.trim();
  if (!trimmed) return 'UTC';

  try {
    Intl.DateTimeFormat(undefined, { timeZone: trimmed });
    return trimmed;
  } catch {
    return 'UTC';
  }
}

export async function getRewardsSummary(userId: string, timezone?: string): Promise<RewardsSummary> {
  const normalizedTimezone = normalizeRewardsTimezone(timezone);
  const result = await pool.query<RewardsStatsRow>(
    `
    WITH log_stats AS (
      SELECT
        COUNT(*)::bigint AS logs,
        COUNT(*) FILTER (WHERE COALESCE(NULLIF(input_kind, ''), 'text') = 'text')::bigint AS text_logs,
        COUNT(*) FILTER (WHERE COALESCE(NULLIF(input_kind, ''), 'text') = 'voice')::bigint AS voice_logs,
        COUNT(*) FILTER (WHERE COALESCE(NULLIF(input_kind, ''), 'text') = 'image')::bigint AS image_logs,
        COUNT(*) FILTER (WHERE COALESCE(NULLIF(input_kind, ''), 'text') = 'manual')::bigint AS manual_logs,
        COUNT(*) FILTER (WHERE parse_confidence >= 0.85)::bigint AS high_confidence_logs
      FROM food_logs
      WHERE user_id = $1
    ),
    item_stats AS (
      SELECT
        COUNT(fli.id)::bigint AS food_items,
        COUNT(DISTINCT NULLIF(lower(trim(fli.food_name)), ''))::bigint AS unique_foods,
        COUNT(*) FILTER (WHERE fli.manual_override_json IS NOT NULL)::bigint AS manual_override_items,
        COUNT(*) FILTER (WHERE fli.match_confidence >= 0.85)::bigint AS high_confidence_items
      FROM food_log_items fli
      JOIN food_logs fl ON fl.id = fli.food_log_id
      WHERE fl.user_id = $1
    ),
    health_stats AS (
      SELECT
        COUNT(*) FILTER (WHERE steps > 0 OR active_energy_kcal > 0)::bigint AS health_active_days,
        COUNT(*) FILTER (WHERE steps >= 10000)::bigint AS health_step_days_10k
      FROM health_activity_snapshots
      WHERE user_id = $1
    )
    SELECT
      log_stats.logs,
      log_stats.text_logs,
      log_stats.voice_logs,
      log_stats.image_logs,
      log_stats.manual_logs,
      log_stats.high_confidence_logs,
      item_stats.food_items,
      item_stats.unique_foods,
      item_stats.manual_override_items,
      item_stats.high_confidence_items,
      health_stats.health_active_days,
      health_stats.health_step_days_10k
    FROM log_stats, item_stats, health_stats
    `,
    [userId]
  );

  const row = result.rows[0];
  return {
    timezone: normalizedTimezone,
    generatedAt: new Date().toISOString(),
    totals: {
      logs: toInt(row?.logs),
      foodItems: toInt(row?.food_items),
      uniqueFoods: toInt(row?.unique_foods),
      textLogs: toInt(row?.text_logs),
      voiceLogs: toInt(row?.voice_logs),
      imageLogs: toInt(row?.image_logs),
      manualLogs: toInt(row?.manual_logs),
      manualOverrideItems: toInt(row?.manual_override_items),
      highConfidenceLogs: toInt(row?.high_confidence_logs),
      highConfidenceItems: toInt(row?.high_confidence_items),
      healthActiveDays: toInt(row?.health_active_days),
      healthStepDays10k: toInt(row?.health_step_days_10k)
    }
  };
}
