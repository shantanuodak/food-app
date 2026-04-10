/**
 * Parse pipeline accuracy evaluation harness.
 *
 * Runs the curated golden set through `runPrimaryParsePipeline` and writes
 * a timestamped JSON report with per-case pass/fail, per-macro deltas,
 * per-category aggregates, cost, and latency.
 *
 * Usage:
 *   npm run eval                          — run all cases, fresh cache scope per run
 *   npm run eval -- --filter generic      — only one category
 *   npm run eval -- --reuse-cache         — use shared 'eval-shared' scope
 *   npm run eval -- --cache-scope X       — explicit scope
 *   npm run eval -- --label my-experiment — adds label to output filename
 *   npm run eval -- --output-dir <path>   — override default output dir
 *
 * TODO(ci): Not safe to wire into PR-CI without budget controls.
 * Cost per run is ~$0.04 at current Gemini prices (~$0.001 × 38 cases).
 */

import { appendFileSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';

import { runPrimaryParsePipeline } from '../services/parsePipelineService.js';
import { config } from '../config.js';
import {
  EVAL_GOLDEN_SET,
  DEFAULT_TOLERANCE,
  type EvalCase,
  type EvalCategory,
  type EvalExpected
} from './evalGoldenSet.js';

type CliArgs = {
  filter: EvalCategory | null;
  reuseCache: boolean;
  cacheScope: string | null;
  label: string | null;
  outputDir: string;
};

type MacroKey = 'calories' | 'protein' | 'carbs' | 'fat';
const MACRO_KEYS: MacroKey[] = ['calories', 'protein', 'carbs', 'fat'];

type MacroPassed = { calories: boolean; protein: boolean; carbs: boolean; fat: boolean; all: boolean };

type CaseReport = {
  id: string;
  category: EvalCategory;
  input: string;
  expected: EvalExpected;
  actual: EvalExpected | null;
  /** Signed fractional delta (actual - expected) / expected. Null if errored. */
  deltas: Record<MacroKey, number | null> | null;
  passed: MacroPassed | null;
  route: string | null;
  cacheHit: boolean | null;
  fallbackUsed: boolean | null;
  fallbackModel: string | null;
  latencyMs: number;
  costUsd: number;
  tokens: { input: number; output: number } | null;
  itemsCount: number;
  itemNames: string[];
  error?: string;
};

type Summary = {
  totalCases: number;
  errorCount: number;
  passedAll4: number;
  passRate: number;
  perMacroPassRate: Record<MacroKey, number>;
  perCategoryPassRate: Record<string, number>;
  perRoute: Record<string, number>;
  totalCostUsd: number;
  avgLatencyMs: number;
  p50LatencyMs: number;
  p95LatencyMs: number;
  durationMs: number;
};

type EvalReport = {
  runId: string;
  runAt: string;
  parseVersion: string;
  model: string | null;
  cacheScope: string;
  reusedCache: boolean;
  label: string | null;
  summary: Summary;
  cases: CaseReport[];
};

function parseArgs(argv: string[]): CliArgs {
  const args: CliArgs = {
    filter: null,
    reuseCache: false,
    cacheScope: null,
    label: null,
    outputDir: ''
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    const next = argv[i + 1];
    if (token === '--filter' && next) {
      args.filter = next as EvalCategory;
      i += 1;
    } else if (token === '--reuse-cache') {
      args.reuseCache = true;
    } else if (token === '--cache-scope' && next) {
      args.cacheScope = next;
      i += 1;
    } else if (token === '--label' && next) {
      args.label = next.trim() || null;
      i += 1;
    } else if (token === '--output-dir' && next) {
      args.outputDir = next;
      i += 1;
    }
  }

  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);
  args.outputDir = args.outputDir || path.resolve(__dirname, '../../benchmarks/eval-runs');
  return args;
}

function resolveTolerance(kase: EvalCase, macro: MacroKey): number {
  const override = kase.tolerance?.[macro];
  return typeof override === 'number' ? override : DEFAULT_TOLERANCE;
}

function scoreMacro(
  kase: EvalCase,
  macro: MacroKey,
  actual: number
): { delta: number; passed: boolean } {
  const expected = kase.expected[macro];
  const tolerance = resolveTolerance(kase, macro);

  // Near-zero expected values (e.g. fat in rice, protein in coke) need
  // absolute handling, not fractional — otherwise 0.1g actual vs 0g expected
  // would register as "infinite delta" and fail.
  if (expected <= 0.5) {
    // Tolerance here is interpreted as an absolute gram/kcal allowance.
    // If the case author set an explicit tolerance (e.g. { protein: 1 }), honor it.
    // Otherwise allow 1g/1kcal of slack.
    const absAllowance = typeof kase.tolerance?.[macro] === 'number' ? kase.tolerance[macro]! : 1;
    return {
      delta: actual, // store raw actual value as the "delta"
      passed: actual <= absAllowance
    };
  }

  const delta = (actual - expected) / expected;
  return { delta, passed: Math.abs(delta) <= tolerance };
}

function percentile(sortedValues: number[], p: number): number {
  if (sortedValues.length === 0) return 0;
  const rank = (p / 100) * (sortedValues.length - 1);
  const low = Math.floor(rank);
  const high = Math.ceil(rank);
  if (low === high) return sortedValues[low];
  return sortedValues[low] + (sortedValues[high] - sortedValues[low]) * (rank - low);
}

function round(value: number, digits = 3): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function fmtPct(fraction: number): string {
  return `${(fraction * 100).toFixed(1)}%`;
}

async function runSingleCase(kase: EvalCase, cacheScope: string): Promise<CaseReport> {
  const startedAt = performance.now();
  try {
    const output = await runPrimaryParsePipeline(kase.input, {
      userId: 'eval-user',
      allowFallback: true,
      cacheScope,
      featureFlags: { geminiEnabled: true }
    });
    const latencyMs = performance.now() - startedAt;

    const actualTotals = output.result.totals;
    const actual: EvalExpected = {
      calories: actualTotals.calories,
      protein: actualTotals.protein,
      carbs: actualTotals.carbs,
      fat: actualTotals.fat
    };

    const deltas: Record<MacroKey, number> = {
      calories: 0,
      protein: 0,
      carbs: 0,
      fat: 0
    };
    const passedFlags: Record<MacroKey, boolean> = {
      calories: false,
      protein: false,
      carbs: false,
      fat: false
    };

    for (const macro of MACRO_KEYS) {
      const { delta, passed } = scoreMacro(kase, macro, actual[macro]);
      deltas[macro] = round(delta, 4);
      passedFlags[macro] = passed;
    }

    const passed: MacroPassed = {
      ...passedFlags,
      all: passedFlags.calories && passedFlags.protein && passedFlags.carbs && passedFlags.fat
    };

    const fallbackUsage = output.fallbackUsage;
    const costUsd = fallbackUsage?.estimatedCostUsd ?? 0;
    const tokens = fallbackUsage
      ? { input: fallbackUsage.inputTokens, output: fallbackUsage.outputTokens }
      : null;

    return {
      id: kase.id,
      category: kase.category,
      input: kase.input,
      expected: kase.expected,
      actual,
      deltas,
      passed,
      route: output.route,
      cacheHit: output.cacheHit,
      fallbackUsed: output.fallbackUsed,
      fallbackModel: output.fallbackModel ?? fallbackUsage?.model ?? null,
      latencyMs: round(latencyMs, 1),
      costUsd: round(costUsd, 5),
      tokens,
      itemsCount: output.result.items.length,
      itemNames: output.result.items.map((item) => item.name)
    };
  } catch (err) {
    const latencyMs = performance.now() - startedAt;
    return {
      id: kase.id,
      category: kase.category,
      input: kase.input,
      expected: kase.expected,
      actual: null,
      deltas: null,
      passed: null,
      route: null,
      cacheHit: null,
      fallbackUsed: null,
      fallbackModel: null,
      latencyMs: round(latencyMs, 1),
      costUsd: 0,
      tokens: null,
      itemsCount: 0,
      itemNames: [],
      error: err instanceof Error ? err.message : String(err)
    };
  }
}

function computeSummary(cases: CaseReport[], durationMs: number): Summary {
  const errorCount = cases.filter((c) => c.error).length;
  const scored = cases.filter((c): c is CaseReport & { passed: MacroPassed } => c.passed !== null);

  const passedAll4 = scored.filter((c) => c.passed.all).length;

  const perMacroPassRate: Record<MacroKey, number> = {
    calories: 0,
    protein: 0,
    carbs: 0,
    fat: 0
  };
  for (const macro of MACRO_KEYS) {
    const passCount = scored.filter((c) => c.passed[macro]).length;
    perMacroPassRate[macro] = scored.length > 0 ? round(passCount / scored.length, 4) : 0;
  }

  const perCategoryPassRate: Record<string, number> = {};
  const byCategory = new Map<string, CaseReport[]>();
  for (const c of cases) {
    const list = byCategory.get(c.category) ?? [];
    list.push(c);
    byCategory.set(c.category, list);
  }
  for (const [category, list] of byCategory.entries()) {
    const scoredInCategory = list.filter((c) => c.passed !== null);
    const passedInCategory = scoredInCategory.filter((c) => c.passed!.all).length;
    perCategoryPassRate[category] =
      scoredInCategory.length > 0 ? round(passedInCategory / scoredInCategory.length, 4) : 0;
  }

  const perRoute: Record<string, number> = {};
  for (const c of cases) {
    const key = c.route ?? 'error';
    perRoute[key] = (perRoute[key] ?? 0) + 1;
  }

  const totalCostUsd = cases.reduce((sum, c) => sum + c.costUsd, 0);
  const latencies = cases.map((c) => c.latencyMs).sort((a, b) => a - b);
  const avgLatencyMs =
    latencies.length > 0 ? latencies.reduce((s, n) => s + n, 0) / latencies.length : 0;

  return {
    totalCases: cases.length,
    errorCount,
    passedAll4,
    passRate: scored.length > 0 ? round(passedAll4 / scored.length, 4) : 0,
    perMacroPassRate,
    perCategoryPassRate,
    perRoute,
    totalCostUsd: round(totalCostUsd, 5),
    avgLatencyMs: round(avgLatencyMs, 1),
    p50LatencyMs: round(percentile(latencies, 50), 1),
    p95LatencyMs: round(percentile(latencies, 95), 1),
    durationMs: round(durationMs, 1)
  };
}

function formatConsoleSummary(report: EvalReport): string {
  const s = report.summary;
  const byCategory: Record<string, string> = {};
  for (const [k, v] of Object.entries(s.perCategoryPassRate)) {
    byCategory[k] = fmtPct(v);
  }
  return JSON.stringify(
    {
      passRate: `${fmtPct(s.passRate)} (${s.passedAll4}/${s.totalCases - s.errorCount})`,
      perMacro: {
        cal: fmtPct(s.perMacroPassRate.calories),
        pro: fmtPct(s.perMacroPassRate.protein),
        carb: fmtPct(s.perMacroPassRate.carbs),
        fat: fmtPct(s.perMacroPassRate.fat)
      },
      byCategory,
      errors: s.errorCount,
      cost: `$${s.totalCostUsd.toFixed(4)}`,
      p95Latency: `${s.p95LatencyMs}ms`,
      duration: `${(s.durationMs / 1000).toFixed(1)}s`,
      routes: s.perRoute
    },
    null,
    2
  );
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  const casesToRun = args.filter
    ? EVAL_GOLDEN_SET.filter((c) => c.category === args.filter)
    : EVAL_GOLDEN_SET;

  if (casesToRun.length === 0) {
    console.error(`No cases match filter=${args.filter}`);
    process.exit(1);
  }

  const runAt = new Date().toISOString();
  const cacheScope =
    args.cacheScope ?? (args.reuseCache ? 'eval-shared' : `eval-run-${runAt}`);

  console.log(
    `Running ${casesToRun.length} eval cases (scope=${cacheScope}, reuseCache=${args.reuseCache})...`
  );

  const overallStart = performance.now();
  const reports: CaseReport[] = [];

  for (const kase of casesToRun) {
    const caseReport = await runSingleCase(kase, cacheScope);
    reports.push(caseReport);
    const statusIcon = caseReport.error
      ? '!'
      : caseReport.passed?.all
        ? '✓'
        : '×';
    const deltaHint = caseReport.deltas
      ? ` cal=${caseReport.deltas.calories === null ? 'n/a' : caseReport.deltas.calories.toFixed(2)}`
      : '';
    console.log(
      `  ${statusIcon} ${caseReport.id.padEnd(10)} ${caseReport.category.padEnd(16)} ${caseReport.latencyMs.toFixed(0).padStart(5)}ms${deltaHint}  ${caseReport.input}`
    );
    if (caseReport.error) {
      console.log(`      error: ${caseReport.error}`);
    }
  }

  const overallDurationMs = performance.now() - overallStart;
  const summary = computeSummary(reports, overallDurationMs);

  const resolvedModel =
    reports.find((r) => r.fallbackModel)?.fallbackModel ?? null;

  const runIdSafe = runAt.replace(/[:.]/g, '-');
  const labelSuffix = args.label
    ? `-${args.label.replace(/[^a-zA-Z0-9_-]/g, '')}`
    : '';

  const report: EvalReport = {
    runId: `eval-${runIdSafe}${labelSuffix}`,
    runAt,
    parseVersion: config.parseVersion,
    model: resolvedModel,
    cacheScope,
    reusedCache: args.reuseCache,
    label: args.label,
    summary,
    cases: reports
  };

  mkdirSync(args.outputDir, { recursive: true });
  const runPath = path.join(args.outputDir, `eval-${runIdSafe}${labelSuffix}.json`);
  const latestPath = path.join(args.outputDir, 'eval-latest.json');
  const indexPath = path.join(args.outputDir, 'eval-runs.ndjson');

  writeFileSync(runPath, `${JSON.stringify(report, null, 2)}\n`);
  writeFileSync(latestPath, `${JSON.stringify(report, null, 2)}\n`);
  appendFileSync(
    indexPath,
    `${JSON.stringify({
      runId: report.runId,
      runAt,
      passRate: summary.passRate,
      passedAll4: summary.passedAll4,
      totalCases: summary.totalCases,
      totalCostUsd: summary.totalCostUsd,
      file: path.basename(runPath)
    })}\n`
  );

  console.log(`\nEval run complete → ${runPath}\n`);
  console.log(formatConsoleSummary(report));
}

main().catch((err) => {
  console.error('Eval run failed', err);
  process.exitCode = 1;
});
