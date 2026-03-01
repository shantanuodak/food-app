import { pool } from '../db.js';
import { ensureUserExists } from './userService.js';
import { ApiError } from '../utils/errors.js';

type CostEventInput = {
  userId: string;
  requestId: string;
  feature: 'parse_fallback' | 'escalation' | 'enrichment' | 'parse_image_primary' | 'parse_image_fallback';
  model: string;
  inputTokens: number;
  outputTokens: number;
  estimatedCostUsd: number;
};

function startOfUtcDay(date = new Date()): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

export async function getTodayEstimatedCostUsd(feature?: CostEventInput['feature']): Promise<number> {
  const start = startOfUtcDay();
  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 1);

  const result = await pool.query<{ total_cost: string }>(
    `
    SELECT COALESCE(SUM(estimated_cost_usd), 0) AS total_cost
    FROM ai_cost_events
    WHERE created_at >= $1
      AND created_at < $2
      ${feature ? 'AND feature = $3' : ''}
    `,
    feature ? [start.toISOString(), end.toISOString(), feature] : [start.toISOString(), end.toISOString()]
  );

  return Number(result.rows[0]?.total_cost || 0);
}

export async function writeAiCostEvent(input: CostEventInput): Promise<void> {
  await ensureUserExists(input.userId);

  await pool.query(
    `
    INSERT INTO ai_cost_events (
      user_id, request_id, feature, model,
      input_tokens, output_tokens, estimated_cost_usd, created_at
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,NOW())
    `,
    [
      input.userId,
      input.requestId,
      input.feature,
      input.model,
      input.inputTokens,
      input.outputTokens,
      input.estimatedCostUsd
    ]
  );
}

export type BudgetSnapshot = {
  dailyBudgetUsd: number;
  userSoftCapUsd: number;
  globalUsedTodayUsd: number;
  userUsedTodayUsd: number;
  globalBudgetExceeded: boolean;
  userSoftCapExceeded: boolean;
};

async function getBudgetSums(
  userId: string,
  client?: { query: (sql: string, params?: unknown[]) => Promise<{ rows: Array<Record<string, string>> }> }
): Promise<{ globalUsed: number; userUsed: number }> {
  const db = client || pool;
  const start = startOfUtcDay();
  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 1);

  const totalResult = await db.query(
    `
    SELECT COALESCE(SUM(estimated_cost_usd), 0)::text AS total_cost
    FROM ai_cost_events
    WHERE created_at >= $1
      AND created_at < $2
    `,
    [start.toISOString(), end.toISOString()]
  );

  const userResult = await db.query(
    `
    SELECT COALESCE(SUM(estimated_cost_usd), 0)::text AS user_cost
    FROM ai_cost_events
    WHERE user_id = $1
      AND created_at >= $2
      AND created_at < $3
    `,
    [userId, start.toISOString(), end.toISOString()]
  );

  return {
    globalUsed: Number(totalResult.rows[0]?.total_cost || 0),
    userUsed: Number(userResult.rows[0]?.user_cost || 0)
  };
}

export async function getBudgetSnapshotForUser(input: {
  userId: string;
  dailyBudgetUsd: number;
  userSoftCapUsd: number;
}): Promise<BudgetSnapshot> {
  const sums = await getBudgetSums(input.userId);
  return {
    dailyBudgetUsd: input.dailyBudgetUsd,
    userSoftCapUsd: input.userSoftCapUsd,
    globalUsedTodayUsd: sums.globalUsed,
    userUsedTodayUsd: sums.userUsed,
    globalBudgetExceeded: sums.globalUsed >= input.dailyBudgetUsd,
    userSoftCapExceeded: sums.userUsed >= input.userSoftCapUsd
  };
}

export async function recordAiCostWithBudgetGuard(input: {
  userId: string;
  requestId: string;
  feature: CostEventInput['feature'];
  model: string;
  inputTokens: number;
  outputTokens: number;
  estimatedCostUsd: number;
  dailyBudgetUsd: number;
  userSoftCapUsd: number;
}): Promise<BudgetSnapshot> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Transaction-scoped lock to keep daily budget accounting consistent under concurrency.
    await client.query('SELECT pg_advisory_xact_lock($1)', [7812301]);

    const before = await getBudgetSums(input.userId, client);
    if (before.globalUsed + input.estimatedCostUsd > input.dailyBudgetUsd) {
      throw new ApiError(429, 'BUDGET_EXCEEDED', 'Daily AI budget exceeded');
    }

    await ensureUserExists(input.userId, undefined, client);

    await client.query(
      `
      INSERT INTO ai_cost_events (
        user_id, request_id, feature, model,
        input_tokens, output_tokens, estimated_cost_usd, created_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,NOW())
      `,
      [input.userId, input.requestId, input.feature, input.model, input.inputTokens, input.outputTokens, input.estimatedCostUsd]
    );

    const after = await getBudgetSums(input.userId, client);
    await client.query('COMMIT');
    return {
      dailyBudgetUsd: input.dailyBudgetUsd,
      userSoftCapUsd: input.userSoftCapUsd,
      globalUsedTodayUsd: after.globalUsed,
      userUsedTodayUsd: after.userUsed,
      globalBudgetExceeded: after.globalUsed >= input.dailyBudgetUsd,
      userSoftCapExceeded: after.userUsed >= input.userSoftCapUsd
    };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
