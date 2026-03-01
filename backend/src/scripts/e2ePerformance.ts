import { performance } from 'node:perf_hooks';
import { randomUUID } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import request from 'supertest';
import { Pool } from 'pg';
import { runMigrations } from '../db/migrations.js';

type PerfSample = {
  parseMs: number;
  saveMs: number;
  summaryMs: number;
  totalMs: number;
};

type PerfSummary = {
  iterations: number;
  parse: { p50Ms: number; p95Ms: number; maxMs: number };
  save: { p50Ms: number; p95Ms: number; maxMs: number };
  summary: { p50Ms: number; p95Ms: number; maxMs: number };
  total: { p50Ms: number; p95Ms: number; maxMs: number };
  meetsTargetUnder10s: boolean;
};

function percentile(values: number[], p: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[index] ?? 0;
}

function round(value: number, digits = 2): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function parseIterations(argv: string[]): number {
  const flagIndex = argv.findIndex((token) => token === '--iterations');
  if (flagIndex === -1) return 30;
  const raw = Number(argv[flagIndex + 1]);
  if (!Number.isFinite(raw) || raw <= 0) return 30;
  return Math.floor(raw);
}

function summarize(samples: PerfSample[]): PerfSummary {
  const parseVals = samples.map((s) => s.parseMs);
  const saveVals = samples.map((s) => s.saveMs);
  const summaryVals = samples.map((s) => s.summaryMs);
  const totalVals = samples.map((s) => s.totalMs);

  const stats = (vals: number[]) => ({
    p50Ms: round(percentile(vals, 50)),
    p95Ms: round(percentile(vals, 95)),
    maxMs: round(Math.max(...vals))
  });

  const totalStats = stats(totalVals);
  return {
    iterations: samples.length,
    parse: stats(parseVals),
    save: stats(saveVals),
    summary: stats(summaryVals),
    total: totalStats,
    meetsTargetUnder10s: totalStats.p95Ms < 10_000
  };
}

async function main(): Promise<void> {
  const iterations = parseIterations(process.argv.slice(2));
  const testDbUrl = process.env.DATABASE_URL_TEST || process.env.DATABASE_URL;
  if (!testDbUrl) {
    throw new Error('DATABASE_URL_TEST or DATABASE_URL must be set.');
  }

  process.env.DATABASE_URL = testDbUrl;
  process.env.AI_ESCALATION_ENABLED = process.env.AI_ESCALATION_ENABLED || 'true';
  process.env.AI_DAILY_BUDGET_USD = process.env.AI_DAILY_BUDGET_USD || '0.5';
  process.env.AI_USER_SOFT_CAP_USD = process.env.AI_USER_SOFT_CAP_USD || '0.1';

  const pool = new Pool({ connectionString: testDbUrl });
  try {
    const __filename = fileURLToPath(import.meta.url);
    const __dirname = path.dirname(__filename);
    const migrationsDir = path.resolve(__dirname, '../../migrations');
    await runMigrations(pool, migrationsDir);

    await pool.query(
      'TRUNCATE TABLE food_log_items, food_logs, onboarding_profiles, users, parse_cache, parse_requests, log_save_idempotency, ai_cost_events RESTART IDENTITY CASCADE'
    );

    const appModule = await import('../app.js');
    const app = appModule.createApp();
    const userId = '11111111-1111-1111-1111-111111111111';
    const auth = { Authorization: `Bearer dev-${userId}` };

    const onboarding = await request(app).post('/v1/onboarding').set(auth).send({
      goal: 'maintain',
      dietPreference: 'none',
      allergies: [],
      units: 'imperial',
      activityLevel: 'moderate'
    });
    if (onboarding.status !== 200) {
      throw new Error(`Onboarding failed: status=${onboarding.status}`);
    }

    const samples: PerfSample[] = [];
    const baseTime = Date.parse('2026-02-15T08:00:00.000Z');

    for (let i = 0; i < iterations; i += 1) {
      const loggedAt = new Date(baseTime + i * 60_000).toISOString();
      const parseText = '2 eggs, 2 slices toast, black coffee';

      const parseStart = performance.now();
      const parse = await request(app).post('/v1/logs/parse').set(auth).send({ text: parseText, loggedAt });
      const parseMs = performance.now() - parseStart;
      if (parse.status !== 200) {
        throw new Error(`Parse failed at iteration ${i + 1}: status=${parse.status}`);
      }

      const saveStart = performance.now();
      const save = await request(app)
        .post('/v1/logs')
        .set(auth)
        .set('Idempotency-Key', randomUUID())
        .send({
          parseRequestId: parse.body.parseRequestId,
          parseVersion: parse.body.parseVersion,
          parsedLog: {
            rawText: parseText,
            loggedAt,
            confidence: parse.body.confidence,
            totals: parse.body.totals,
            items: parse.body.items
          }
        });
      const saveMs = performance.now() - saveStart;
      if (save.status !== 200) {
        throw new Error(`Save failed at iteration ${i + 1}: status=${save.status}`);
      }

      const date = loggedAt.slice(0, 10);
      const summaryStart = performance.now();
      const summary = await request(app).get('/v1/logs/day-summary').set(auth).query({ date });
      const summaryMs = performance.now() - summaryStart;
      if (summary.status !== 200) {
        throw new Error(`Summary failed at iteration ${i + 1}: status=${summary.status}`);
      }

      samples.push({
        parseMs: round(parseMs),
        saveMs: round(saveMs),
        summaryMs: round(summaryMs),
        totalMs: round(parseMs + saveMs + summaryMs)
      });
    }

    const result = summarize(samples);
    const generatedAt = new Date().toISOString();
    const artifactsDir = path.resolve(__dirname, '../../benchmarks/artifacts');
    mkdirSync(artifactsDir, { recursive: true });
    const reportPath = path.join(artifactsDir, `e2e-performance-${generatedAt.replace(/[:.]/g, '-')}.json`);
    writeFileSync(
      reportPath,
      JSON.stringify(
        {
          generatedAt,
          environment: 'local',
          db: 'test',
          result,
          samplePreview: samples.slice(0, 5)
        },
        null,
        2
      ),
      'utf8'
    );

    // eslint-disable-next-line no-console
    console.log(JSON.stringify({ generatedAt, result, reportPath }, null, 2));
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error('E2E performance benchmark failed:', err);
  process.exitCode = 1;
});
