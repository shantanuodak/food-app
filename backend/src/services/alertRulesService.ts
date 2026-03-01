import { config } from '../config.js';
import { pool } from '../db.js';

type AlertSeverity = 'warning';
type AlertState = 'ok' | 'alert' | 'insufficient_data';

export type AlertRuleStatus = {
  key: 'ESCALATION_RATE_HIGH' | 'CACHE_HIT_RATIO_LOW' | 'COST_PER_LOG_DRIFT_HIGH';
  title: string;
  severity: AlertSeverity;
  state: AlertState;
  triggered: boolean;
  window: string;
  value: number;
  threshold: number;
  comparator: 'gt' | 'lt';
  runbook: string;
  sampleSize: number;
};

export type AlertSnapshot = {
  generatedAt: string;
  hasActiveAlerts: boolean;
  alerts: AlertRuleStatus[];
};

type SignalRow = {
  parse_requests_escalation_window: string;
  escalations_window: string;
  parse_requests_cache_window: string;
  cache_hits_window: string;
  ai_cost_window: string;
  logs_window: string;
};

const RUNBOOK_BASE = '/docs/ALERT_RUNBOOK_MVP.md';

function round(value: number, digits = 6): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function toNumber(value: string | undefined): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

export async function getAlertSnapshot(): Promise<AlertSnapshot> {
  const now = new Date();
  const escalationWindowStart = new Date(now.getTime() - config.alertEscalationWindowMinutes * 60 * 1000);
  const cacheWindowStart = new Date(now.getTime() - config.alertCacheWindowHours * 60 * 60 * 1000);
  const costWindowStart = new Date(now.getTime() - config.alertCostWindowHours * 60 * 60 * 1000);

  const result = await pool.query<SignalRow>(
    `
    SELECT
      (SELECT COUNT(*)::text FROM parse_requests WHERE created_at >= $1) AS parse_requests_escalation_window,
      (SELECT COUNT(*)::text FROM ai_cost_events WHERE feature = 'escalation' AND created_at >= $1) AS escalations_window,
      (SELECT COUNT(*)::text FROM parse_requests WHERE created_at >= $2) AS parse_requests_cache_window,
      (SELECT COUNT(*)::text FROM parse_requests WHERE cache_hit = true AND created_at >= $2) AS cache_hits_window,
      (SELECT COALESCE(SUM(estimated_cost_usd), 0)::text FROM ai_cost_events WHERE created_at >= $3) AS ai_cost_window,
      (SELECT COUNT(*)::text FROM food_logs WHERE created_at >= $3) AS logs_window
    `,
    [escalationWindowStart.toISOString(), cacheWindowStart.toISOString(), costWindowStart.toISOString()]
  );

  const row = result.rows[0];
  const parseRequestsEscalationWindow = toNumber(row?.parse_requests_escalation_window);
  const escalationsWindow = toNumber(row?.escalations_window);
  const parseRequestsCacheWindow = toNumber(row?.parse_requests_cache_window);
  const cacheHitsWindow = toNumber(row?.cache_hits_window);
  const aiCostWindow = toNumber(row?.ai_cost_window);
  const logsWindow = toNumber(row?.logs_window);

  const escalationRate =
    parseRequestsEscalationWindow > 0 ? escalationsWindow / parseRequestsEscalationWindow : 0;
  const cacheHitRatio = parseRequestsCacheWindow > 0 ? cacheHitsWindow / parseRequestsCacheWindow : 0;
  const costPerLog = logsWindow > 0 ? aiCostWindow / logsWindow : 0;
  const costPerLogDrift =
    config.alertCostPerLogTargetUsd > 0
      ? (costPerLog - config.alertCostPerLogTargetUsd) / config.alertCostPerLogTargetUsd
      : 0;

  const escalationRule: AlertRuleStatus =
    parseRequestsEscalationWindow < config.alertMinParseRequests
      ? {
          key: 'ESCALATION_RATE_HIGH',
          title: 'Escalation rate high',
          severity: 'warning',
          state: 'insufficient_data',
          triggered: false,
          window: `${config.alertEscalationWindowMinutes}m`,
          value: round(escalationRate),
          threshold: config.alertEscalationRateThreshold,
          comparator: 'gt',
          runbook: `${RUNBOOK_BASE}#escalation-rate-high`,
          sampleSize: parseRequestsEscalationWindow
        }
      : {
          key: 'ESCALATION_RATE_HIGH',
          title: 'Escalation rate high',
          severity: 'warning',
          state: escalationRate > config.alertEscalationRateThreshold ? 'alert' : 'ok',
          triggered: escalationRate > config.alertEscalationRateThreshold,
          window: `${config.alertEscalationWindowMinutes}m`,
          value: round(escalationRate),
          threshold: config.alertEscalationRateThreshold,
          comparator: 'gt',
          runbook: `${RUNBOOK_BASE}#escalation-rate-high`,
          sampleSize: parseRequestsEscalationWindow
        };

  const cacheRule: AlertRuleStatus =
    parseRequestsCacheWindow < config.alertMinParseRequests
      ? {
          key: 'CACHE_HIT_RATIO_LOW',
          title: 'Cache hit ratio low',
          severity: 'warning',
          state: 'insufficient_data',
          triggered: false,
          window: `${config.alertCacheWindowHours}h`,
          value: round(cacheHitRatio),
          threshold: config.alertCacheHitRatioThreshold,
          comparator: 'lt',
          runbook: `${RUNBOOK_BASE}#cache-hit-ratio-low`,
          sampleSize: parseRequestsCacheWindow
        }
      : {
          key: 'CACHE_HIT_RATIO_LOW',
          title: 'Cache hit ratio low',
          severity: 'warning',
          state: cacheHitRatio < config.alertCacheHitRatioThreshold ? 'alert' : 'ok',
          triggered: cacheHitRatio < config.alertCacheHitRatioThreshold,
          window: `${config.alertCacheWindowHours}h`,
          value: round(cacheHitRatio),
          threshold: config.alertCacheHitRatioThreshold,
          comparator: 'lt',
          runbook: `${RUNBOOK_BASE}#cache-hit-ratio-low`,
          sampleSize: parseRequestsCacheWindow
        };

  const costRule: AlertRuleStatus =
    logsWindow < config.alertMinLogs
      ? {
          key: 'COST_PER_LOG_DRIFT_HIGH',
          title: 'Cost per log drift high',
          severity: 'warning',
          state: 'insufficient_data',
          triggered: false,
          window: `${config.alertCostWindowHours}h`,
          value: round(costPerLogDrift),
          threshold: config.alertCostPerLogDriftThreshold,
          comparator: 'gt',
          runbook: `${RUNBOOK_BASE}#cost-per-log-drift-high`,
          sampleSize: logsWindow
        }
      : {
          key: 'COST_PER_LOG_DRIFT_HIGH',
          title: 'Cost per log drift high',
          severity: 'warning',
          state: costPerLogDrift > config.alertCostPerLogDriftThreshold ? 'alert' : 'ok',
          triggered: costPerLogDrift > config.alertCostPerLogDriftThreshold,
          window: `${config.alertCostWindowHours}h`,
          value: round(costPerLogDrift),
          threshold: config.alertCostPerLogDriftThreshold,
          comparator: 'gt',
          runbook: `${RUNBOOK_BASE}#cost-per-log-drift-high`,
          sampleSize: logsWindow
        };

  const alerts = [escalationRule, cacheRule, costRule];
  return {
    generatedAt: now.toISOString(),
    hasActiveAlerts: alerts.some((alert) => alert.triggered),
    alerts
  };
}
