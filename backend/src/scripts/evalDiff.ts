/**
 * Compare two eval runs and print pass-rate / per-macro / per-category deltas
 * plus a per-case IMPROVED / REGRESSED / UNCHANGED breakdown.
 *
 * Usage:
 *   npm run eval:diff                               — most-recent vs second-most-recent run in eval-runs/
 *   npm run eval:diff <file>                        — <file> vs eval-latest.json
 *   npm run eval:diff <baseline> <candidate>        — explicit pair (order: baseline → candidate)
 */

import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

type MacroKey = 'calories' | 'protein' | 'carbs' | 'fat';
const MACRO_KEYS: MacroKey[] = ['calories', 'protein', 'carbs', 'fat'];

type MacroPassed = { calories: boolean; protein: boolean; carbs: boolean; fat: boolean; all: boolean };

type EvalCaseReport = {
  id: string;
  category: string;
  input: string;
  expected: { calories: number; protein: number; carbs: number; fat: number };
  actual: { calories: number; protein: number; carbs: number; fat: number } | null;
  deltas: Record<MacroKey, number> | null;
  passed: MacroPassed | null;
  route: string | null;
  latencyMs: number;
  costUsd: number;
  error?: string;
};

type EvalReport = {
  runId: string;
  runAt: string;
  parseVersion: string;
  model: string | null;
  cacheScope: string;
  reusedCache: boolean;
  label: string | null;
  summary: {
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
  cases: EvalCaseReport[];
};

function defaultRunsDir(): string {
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);
  return path.resolve(__dirname, '../../benchmarks/eval-runs');
}

function loadReport(filePath: string): EvalReport {
  const absolute = path.resolve(filePath);
  const raw = readFileSync(absolute, 'utf8');
  return JSON.parse(raw) as EvalReport;
}

function listRunFilesByMtime(dir: string): string[] {
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return [];
  }
  return entries
    .filter((name) => name.startsWith('eval-') && name.endsWith('.json') && name !== 'eval-latest.json')
    .map((name) => path.join(dir, name))
    .map((filePath) => ({ filePath, mtimeMs: statSync(filePath).mtimeMs }))
    .sort((a, b) => b.mtimeMs - a.mtimeMs)
    .map((entry) => entry.filePath);
}

function resolvePair(argv: string[]): { baselinePath: string; candidatePath: string } {
  const dir = defaultRunsDir();

  if (argv.length >= 2) {
    return { baselinePath: argv[0], candidatePath: argv[1] };
  }

  if (argv.length === 1) {
    return {
      baselinePath: argv[0],
      candidatePath: path.join(dir, 'eval-latest.json')
    };
  }

  const files = listRunFilesByMtime(dir);
  if (files.length < 2) {
    console.error(
      `Need at least 2 eval runs in ${dir} to diff, found ${files.length}.\n` +
        `Usage: npm run eval:diff [<baseline>] [<candidate>]`
    );
    process.exit(1);
  }
  return {
    baselinePath: files[1], // older
    candidatePath: files[0] // newer
  };
}

function formatPct(value: number): string {
  return `${(value * 100).toFixed(1)}%`;
}

function formatDelta(before: number, after: number, asPercent = true): string {
  const delta = after - before;
  const sign = delta > 0 ? '+' : delta < 0 ? '' : ' ';
  if (Math.abs(delta) < 0.00005) {
    return '  —';
  }
  if (asPercent) {
    return `${sign}${(delta * 100).toFixed(1)}%`;
  }
  return `${sign}${delta.toFixed(4)}`;
}

function formatLatencyDelta(before: number, after: number): string {
  const delta = after - before;
  if (Math.abs(delta) < 1) return '  —';
  const sign = delta > 0 ? '+' : '';
  return `${sign}${delta.toFixed(0)}ms`;
}

function formatCostDelta(before: number, after: number): string {
  const delta = after - before;
  if (Math.abs(delta) < 0.00005) return '  —';
  const sign = delta > 0 ? '+' : '';
  return `${sign}$${delta.toFixed(4)}`;
}

function statusForCase(kase: EvalCaseReport): 'PASS' | 'FAIL' | 'PARTIAL' | 'ERROR' {
  if (kase.error) return 'ERROR';
  if (!kase.passed) return 'ERROR';
  if (kase.passed.all) return 'PASS';
  const anyPass = kase.passed.calories || kase.passed.protein || kase.passed.carbs || kase.passed.fat;
  return anyPass ? 'PARTIAL' : 'FAIL';
}

function describeFailingMacros(kase: EvalCaseReport): string {
  if (!kase.passed || !kase.deltas) return '';
  const failures: string[] = [];
  for (const macro of MACRO_KEYS) {
    if (!kase.passed[macro]) {
      const delta = kase.deltas[macro];
      const pct = (delta * 100).toFixed(0);
      failures.push(`${macro} ${delta >= 0 ? '+' : ''}${pct}%`);
    }
  }
  return failures.length > 0 ? ` (${failures.join(', ')})` : '';
}

function main(): void {
  const argv = process.argv.slice(2);
  const { baselinePath, candidatePath } = resolvePair(argv);

  const baseline = loadReport(baselinePath);
  const candidate = loadReport(candidatePath);

  console.log(
    `Eval Diff: ${path.basename(baselinePath)} → ${path.basename(candidatePath)}\n`
  );

  // Top-level stats
  const b = baseline.summary;
  const c = candidate.summary;

  console.log('Pass rate:     ' +
    `${formatPct(b.passRate)}  →  ${formatPct(c.passRate)}  (${formatDelta(b.passRate, c.passRate)})`);
  console.log('Total cost:    ' +
    `$${b.totalCostUsd.toFixed(4)} → $${c.totalCostUsd.toFixed(4)}  (${formatCostDelta(b.totalCostUsd, c.totalCostUsd)})`);
  console.log('p95 latency:   ' +
    `${b.p95LatencyMs}ms → ${c.p95LatencyMs}ms  (${formatLatencyDelta(b.p95LatencyMs, c.p95LatencyMs)})`);
  console.log('Errors:        ' +
    `${b.errorCount} → ${c.errorCount}  (${c.errorCount - b.errorCount >= 0 ? '+' : ''}${c.errorCount - b.errorCount})`);

  // Per-macro
  console.log('\nPer-macro:');
  for (const macro of MACRO_KEYS) {
    const before = b.perMacroPassRate[macro] ?? 0;
    const after = c.perMacroPassRate[macro] ?? 0;
    console.log(
      `  ${macro.padEnd(10)} ${formatPct(before).padStart(6)} → ${formatPct(after).padStart(6)}  (${formatDelta(before, after)})`
    );
  }

  // Per-category
  console.log('\nPer-category:');
  const categories = new Set([
    ...Object.keys(b.perCategoryPassRate),
    ...Object.keys(c.perCategoryPassRate)
  ]);
  let biggestDelta = 0;
  let biggestCategory = '';
  for (const cat of categories) {
    const before = b.perCategoryPassRate[cat] ?? 0;
    const after = c.perCategoryPassRate[cat] ?? 0;
    const delta = after - before;
    if (Math.abs(delta) > Math.abs(biggestDelta)) {
      biggestDelta = delta;
      biggestCategory = cat;
    }
    console.log(
      `  ${cat.padEnd(16)} ${formatPct(before).padStart(6)} → ${formatPct(after).padStart(6)}  (${formatDelta(before, after)})`
    );
  }
  if (Math.abs(biggestDelta) >= 0.05) {
    const direction = biggestDelta > 0 ? 'biggest improvement' : 'biggest regression';
    console.log(`  ← ${biggestCategory}: ${direction}`);
  }

  // Per-case comparison matched by id
  const baselineById = new Map(baseline.cases.map((k) => [k.id, k]));
  const candidateById = new Map(candidate.cases.map((k) => [k.id, k]));

  const improved: Array<{ kase: EvalCaseReport; from: string; to: string }> = [];
  const regressed: Array<{ kase: EvalCaseReport; from: string; to: string }> = [];
  const unchanged: EvalCaseReport[] = [];
  const added: EvalCaseReport[] = [];
  const removed: EvalCaseReport[] = [];

  for (const [id, candidateCase] of candidateById.entries()) {
    const baselineCase = baselineById.get(id);
    if (!baselineCase) {
      added.push(candidateCase);
      continue;
    }
    const fromStatus = statusForCase(baselineCase);
    const toStatus = statusForCase(candidateCase);

    const rank = (s: 'PASS' | 'FAIL' | 'PARTIAL' | 'ERROR'): number => {
      if (s === 'PASS') return 3;
      if (s === 'PARTIAL') return 2;
      if (s === 'FAIL') return 1;
      return 0;
    };

    if (rank(toStatus) > rank(fromStatus)) {
      improved.push({ kase: candidateCase, from: fromStatus, to: toStatus });
    } else if (rank(toStatus) < rank(fromStatus)) {
      regressed.push({ kase: candidateCase, from: fromStatus, to: toStatus });
    } else {
      unchanged.push(candidateCase);
    }
  }

  for (const [id, baselineCase] of baselineById.entries()) {
    if (!candidateById.has(id)) removed.push(baselineCase);
  }

  console.log('\nCases changed:');
  if (improved.length > 0) {
    console.log(`  IMPROVED (${improved.length}):`);
    for (const entry of improved) {
      const inputShort = entry.kase.input.length > 32 ? `${entry.kase.input.slice(0, 29)}...` : entry.kase.input;
      console.log(
        `    ${entry.kase.id.padEnd(10)} ${inputShort.padEnd(34)} ${entry.from} → ${entry.to}`
      );
    }
  }
  if (regressed.length > 0) {
    console.log(`  REGRESSED (${regressed.length}):`);
    for (const entry of regressed) {
      const inputShort = entry.kase.input.length > 32 ? `${entry.kase.input.slice(0, 29)}...` : entry.kase.input;
      console.log(
        `    ${entry.kase.id.padEnd(10)} ${inputShort.padEnd(34)} ${entry.from} → ${entry.to}${describeFailingMacros(entry.kase)}`
      );
    }
  }
  console.log(`  UNCHANGED (${unchanged.length})`);

  if (added.length > 0) {
    console.log(`\nAdded cases: ${added.length}`);
    for (const kase of added) {
      console.log(`  + ${kase.id} ${kase.input}`);
    }
  }
  if (removed.length > 0) {
    console.log(`\nRemoved cases: ${removed.length}`);
    for (const kase of removed) {
      console.log(`  - ${kase.id} ${kase.input}`);
    }
  }
}

main();
