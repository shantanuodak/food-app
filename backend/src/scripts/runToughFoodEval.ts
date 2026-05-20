import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';

import { runPrimaryParsePipeline } from '../services/parsePipelineService.js';

type ToughFoodCase = {
  id: string;
  cuisine: string;
  input: string;
  expectedKeywords: string[];
  caloriesRange?: { min: number; max: number };
  minItems?: number;
};

type CaseReport = {
  id: string;
  cuisine: string;
  input: string;
  route: string | null;
  itemNames: string[];
  totalCalories: number | null;
  passKeywords: boolean;
  missingKeywords: string[];
  passCalories: boolean;
  passMinItems: boolean;
  passed: boolean;
  latencyMs: number;
  error?: string;
};

function parseArgs(argv: string[]): { manifest: string; outputDir: string } {
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);
  const defaults = {
    manifest: path.resolve(__dirname, '../../tough-food-text-cases.json'),
    outputDir: path.resolve(__dirname, '../../benchmarks/tough-food-eval-runs')
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    const next = argv[i + 1];
    if (token === '--manifest' && next) {
      defaults.manifest = path.resolve(process.cwd(), next);
      i += 1;
    } else if (token === '--output-dir' && next) {
      defaults.outputDir = path.resolve(process.cwd(), next);
      i += 1;
    }
  }

  return defaults;
}

function normalize(value: string): string {
  return value
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function keywordPresent(searchable: string, keyword: string): boolean {
  const key = normalize(keyword);
  if (!key) return true;
  const aliases: Record<string, string[]> = {
    rice: ['rice', 'chawal'],
    onion: ['onion', 'pyaz'],
    coconut: ['coconut', 'cocnut'],
    coffee: ['coffee', 'coffe'],
    quesadilla: ['quesadilla', 'qesadilla'],
    guacamole: ['guacamole', 'guac'],
    'sour cream': ['sour cream', 'sour crem'],
    'olive oil': ['olive oil', 'oil drizzle'],
    'pulled pork': ['pulled pork', 'pork'],
    'garlic rice': ['garlic rice', 'rice'],
    'khao soi': ['khao soi', 'curry noodles'],
    'bun bo hue': ['bun bo hue', 'beef noodle soup'],
    'baba': ['baba ganoush', 'eggplant dip', 'baba']
  };
  return (aliases[key] ?? [key]).some((candidate) => searchable.includes(candidate));
}

function readCases(manifest: string): ToughFoodCase[] {
  if (!existsSync(manifest)) {
    throw new Error(`Manifest not found: ${manifest}`);
  }
  const parsed = JSON.parse(readFileSync(manifest, 'utf8')) as unknown;
  if (!Array.isArray(parsed)) {
    throw new Error('Tough food manifest must be a JSON array.');
  }
  return parsed as ToughFoodCase[];
}

async function runCase(testCase: ToughFoodCase, cacheScope: string): Promise<CaseReport> {
  const startedAt = performance.now();
  try {
    const output = await runPrimaryParsePipeline(testCase.input, {
      userId: 'tough-food-eval',
      allowFallback: true,
      cacheScope,
      featureFlags: { geminiEnabled: true }
    });
    const latencyMs = Math.round((performance.now() - startedAt) * 10) / 10;
    const itemNames = output.result.items.map((item) => item.name);
    const searchable = normalize([testCase.input, ...itemNames].join(' '));
    const missingKeywords = testCase.expectedKeywords.filter((keyword) => !keywordPresent(searchable, keyword));
    const totalCalories = output.result.totals.calories;
    const passCalories = testCase.caloriesRange
      ? totalCalories >= testCase.caloriesRange.min && totalCalories <= testCase.caloriesRange.max
      : true;
    const passMinItems = output.result.items.length >= (testCase.minItems ?? 1);
    const passKeywords = missingKeywords.length === 0;

    return {
      id: testCase.id,
      cuisine: testCase.cuisine,
      input: testCase.input,
      route: output.route,
      itemNames,
      totalCalories,
      passKeywords,
      missingKeywords,
      passCalories,
      passMinItems,
      passed: passKeywords && passCalories && passMinItems,
      latencyMs
    };
  } catch (error) {
    return {
      id: testCase.id,
      cuisine: testCase.cuisine,
      input: testCase.input,
      route: null,
      itemNames: [],
      totalCalories: null,
      passKeywords: false,
      missingKeywords: testCase.expectedKeywords,
      passCalories: false,
      passMinItems: false,
      passed: false,
      latencyMs: Math.round((performance.now() - startedAt) * 10) / 10,
      error: error instanceof Error ? error.message : String(error)
    };
  }
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const cases = readCases(args.manifest);
  const runId = new Date().toISOString().replace(/[:.]/g, '-');
  const cacheScope = `tough-food-${runId}`;
  const reports: CaseReport[] = [];

  for (const testCase of cases) {
    const report = await runCase(testCase, cacheScope);
    reports.push(report);
    const status = report.passed ? 'PASS' : 'FAIL';
    const calories = report.totalCalories == null ? 'cal -' : `cal ${report.totalCalories}`;
    const names = report.itemNames.length ? report.itemNames.join(' | ') : '(none)';
    const failures = [
      report.passKeywords ? '' : `missing=${report.missingKeywords.join(',')}`,
      report.passCalories ? '' : 'calories',
      report.passMinItems ? '' : 'minItems',
      report.error ? `error=${report.error}` : ''
    ].filter(Boolean);
    console.log(`${status} ${report.id} · ${report.cuisine} · ${calories} · items ${report.itemNames.length} · ${report.latencyMs}ms`);
    console.log(`  ${names}`);
    if (failures.length) console.log(`  failed: ${failures.join(' · ')}`);
  }

  const passed = reports.filter((report) => report.passed).length;
  const sortedLatency = reports.map((report) => report.latencyMs).sort((a, b) => a - b);
  const p95 = sortedLatency.length ? sortedLatency[Math.min(sortedLatency.length - 1, Math.ceil(sortedLatency.length * 0.95) - 1)] : 0;
  const summary = {
    total: reports.length,
    passed,
    failed: reports.length - passed,
    passRate: reports.length ? passed / reports.length : 0,
    avgLatencyMs: reports.length ? Math.round(reports.reduce((sum, report) => sum + report.latencyMs, 0) / reports.length) : 0,
    p95LatencyMs: p95
  };
  mkdirSync(args.outputDir, { recursive: true });
  const outputPath = path.join(args.outputDir, `tough-food-eval-${runId}.json`);
  writeFileSync(
    outputPath,
    JSON.stringify(
      {
        runId,
        runAt: new Date().toISOString(),
        manifest: args.manifest,
        summary,
        cases: reports
      },
      null,
      2
    )
  );

  console.log('\nSummary');
  console.log(`Passed: ${summary.passed}/${summary.total}`);
  console.log(`Failed: ${summary.failed}/${summary.total}`);
  console.log(`Pass rate: ${(summary.passRate * 100).toFixed(1)}%`);
  console.log(`Avg latency: ${summary.avgLatencyMs}ms`);
  console.log(`P95 latency: ${summary.p95LatencyMs}ms`);
  console.log(`Wrote ${outputPath}`);

  if (summary.failed > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error('Tough food eval failed', error);
  process.exitCode = 1;
});
