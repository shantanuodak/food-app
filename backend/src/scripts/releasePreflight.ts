import { readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../db.js';
import { config } from '../config.js';

type CheckResult = {
  name: string;
  ok: boolean;
  details: string;
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const migrationsDir = path.resolve(__dirname, '../../migrations');

async function checkDbConnectivity(): Promise<CheckResult> {
  try {
    await pool.query('SELECT 1');
    return { name: 'db-connectivity', ok: true, details: 'Database connection established.' };
  } catch (err) {
    return { name: 'db-connectivity', ok: false, details: `Database connection failed: ${(err as Error).message}` };
  }
}

async function checkMigrationState(): Promise<CheckResult> {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        id TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    const result = await pool.query<{ id: string }>('SELECT id FROM schema_migrations');
    const applied = new Set(result.rows.map((row) => row.id));
    const files = readdirSync(migrationsDir).filter((name) => name.endsWith('.sql')).sort();
    const pending = files.filter((file) => !applied.has(file));

    if (pending.length > 0) {
      return {
        name: 'migration-state',
        ok: false,
        details: `Pending migrations: ${pending.join(', ')}`
      };
    }

    return {
      name: 'migration-state',
      ok: true,
      details: `All migrations applied (${files.length} files).`
    };
  } catch (err) {
    return { name: 'migration-state', ok: false, details: `Failed to inspect migrations: ${(err as Error).message}` };
  }
}

function checkConfigShape(): CheckResult {
  const invalids: string[] = [];

  if (!config.parseVersion.trim()) invalids.push('PARSE_VERSION');
  if (!config.parseCacheSchemaVersion.trim()) invalids.push('PARSE_CACHE_SCHEMA_VERSION');
  if (!config.parseProviderRouteVersion.trim()) invalids.push('PARSE_PROVIDER_ROUTE_VERSION');
  if (!config.parsePromptVersion.trim()) invalids.push('PARSE_PROMPT_VERSION');
  if (config.aiDailyBudgetUsd <= 0) invalids.push('AI_DAILY_BUDGET_USD must be > 0');
  if (config.aiUserSoftCapUsd <= 0) invalids.push('AI_USER_SOFT_CAP_USD must be > 0');
  if (config.aiFallbackCostUsd <= 0) invalids.push('AI_FALLBACK_COST_USD must be > 0');

  if (invalids.length > 0) {
    return {
      name: 'config-shape',
      ok: false,
      details: `Invalid config values: ${invalids.join(', ')}`
    };
  }

  return {
    name: 'config-shape',
    ok: true,
    details: `Parse namespace: cache=${config.parseCacheSchemaVersion}, parser=${config.parseVersion}, route=${config.parseProviderRouteVersion}, prompt=${config.parsePromptVersion}`
  };
}

async function run(): Promise<void> {
  const checks: CheckResult[] = [];
  checks.push(checkConfigShape());
  checks.push(await checkDbConnectivity());
  checks.push(await checkMigrationState());

  const failed = checks.filter((check) => !check.ok);
  for (const check of checks) {
    const marker = check.ok ? 'PASS' : 'FAIL';
    console.log(`[${marker}] ${check.name}: ${check.details}`);
  }

  await pool.end();

  if (failed.length > 0) {
    console.error(`Preflight failed: ${failed.length} check(s) failed.`);
    process.exit(1);
  }

  console.log('Preflight passed: backend is release-ready.');
}

run().catch(async (err) => {
  console.error('Preflight execution failed', err);
  await pool.end();
  process.exit(1);
});
