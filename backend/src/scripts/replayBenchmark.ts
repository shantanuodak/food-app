import { appendFileSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';
import { config } from '../config.js';
import { parseFoodText } from '../services/deterministicParser.js';
import { tryCheapAIFallback } from '../services/aiNormalizerService.js';
import { runEscalationParse } from '../services/aiEscalationService.js';

type BenchmarkArgs = {
  count: number;
  seed: number;
  label: string | null;
  escalateOnClarification: boolean;
  outputDir: string;
};

type LogClass = 'high' | 'medium' | 'low';
type ReplayCase = { text: string; class: LogClass };
type ReplayResult = {
  inputText: string;
  class: LogClass;
  primaryLatencyMs: number;
  endToEndLatencyMs: number;
  fallbackUsed: boolean;
  escalationUsed: boolean;
  needsClarification: boolean;
  budgetBlockedFallback: boolean;
  budgetBlockedEscalation: boolean;
  estimatedCostUsd: number;
  inputTokens: number;
  outputTokens: number;
};

const HIGH_CONFIDENCE_LOGS = [
  '2 eggs, 2 slices toast, black coffee',
  '1 cup rice, 4 oz chicken',
  '3 eggs, black coffee',
  '1 cup brown rice, grilled chicken',
  '2 slices toast with butter, coffee',
  '1 egg, 1 slice toast, black coffee'
];

const MEDIUM_CONFIDENCE_LOGS = [
  '2 egs, toast',
  '1 cup rcie, chkn',
  '2 egs + black cofee',
  'chkn 6 oz, rcie 1 cup',
  '2 slices tost, coffe',
  '1 cup rise, grilled chkn'
];

const LOW_CONFIDENCE_LOGS = [
  'mystery bowl from cafe',
  'combo meal from restaurant',
  'house special takeout',
  'chef tasting plate',
  'random snack pack',
  'unknown lunch set'
];

function parseArgs(argv: string[]): BenchmarkArgs {
  const args: BenchmarkArgs = {
    count: 1000,
    seed: 42,
    label: null,
    escalateOnClarification: true,
    outputDir: ''
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    const next = argv[i + 1];
    if (token === '--count' && next) {
      args.count = Math.max(1, Math.floor(Number(next) || 1000));
      i += 1;
    } else if (token === '--seed' && next) {
      args.seed = Math.floor(Number(next) || 42);
      i += 1;
    } else if (token === '--label' && next) {
      args.label = next.trim() || null;
      i += 1;
    } else if (token === '--no-escalate') {
      args.escalateOnClarification = false;
    } else if (token === '--output-dir' && next) {
      args.outputDir = next;
      i += 1;
    }
  }

  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);
  args.outputDir = args.outputDir || path.resolve(__dirname, '../../benchmarks/artifacts');
  return args;
}

function createRng(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (1664525 * state + 1013904223) >>> 0;
    return state / 4294967296;
  };
}

function chooseCase(rand: () => number): ReplayCase {
  const bucket = rand();
  const cls: LogClass = bucket < 0.7 ? 'high' : bucket < 0.9 ? 'medium' : 'low';
  const source = cls === 'high' ? HIGH_CONFIDENCE_LOGS : cls === 'medium' ? MEDIUM_CONFIDENCE_LOGS : LOW_CONFIDENCE_LOGS;
  const index = Math.floor(rand() * source.length);
  return {
    text: source[index] || source[0],
    class: cls
  };
}

function percentile(values: number[], p: number): number {
  if (values.length === 0) {
    return 0;
  }
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[index] || 0;
}

function round(value: number, digits = 6): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

async function runReplayCase(
  replayCase: ReplayCase,
  state: { budgetUsedUsd: number },
  options: { escalateOnClarification: boolean }
): Promise<ReplayResult> {
  const totalStart = performance.now();
  const primaryStart = performance.now();
  let result = parseFoodText(replayCase.text);
  let fallbackUsed = false;
  let escalationUsed = false;
  let budgetBlockedFallback = false;
  let budgetBlockedEscalation = false;
  let estimatedCostUsd = 0;
  let inputTokens = 0;
  let outputTokens = 0;

  const shouldTryFallback =
    result.confidence >= config.aiFallbackConfidenceMin &&
    result.confidence < config.aiFallbackConfidenceMax;

  if (config.aiFallbackEnabled && shouldTryFallback) {
    if (state.budgetUsedUsd + config.aiFallbackCostUsd <= config.aiDailyBudgetUsd) {
      const fallback = await tryCheapAIFallback(replayCase.text, result);
      if (fallback) {
        fallbackUsed = true;
        result = fallback.result;
        state.budgetUsedUsd += fallback.usage.estimatedCostUsd;
        estimatedCostUsd += fallback.usage.estimatedCostUsd;
        inputTokens += fallback.usage.inputTokens;
        outputTokens += fallback.usage.outputTokens;
      }
    } else {
      budgetBlockedFallback = true;
    }
  }

  const primaryLatencyMs = performance.now() - primaryStart;
  const needsClarification = result.confidence < config.aiFallbackConfidenceMin;

  if (needsClarification && options.escalateOnClarification && config.aiEscalationEnabled) {
    if (state.budgetUsedUsd + config.aiEscalationCostUsd <= config.aiDailyBudgetUsd) {
      const escalation = await runEscalationParse(replayCase.text, {
        modelName: config.aiEscalationModelName,
        estimatedCostUsd: config.aiEscalationCostUsd
      });
      if (escalation && state.budgetUsedUsd + escalation.estimatedCostUsd <= config.aiDailyBudgetUsd) {
        escalationUsed = true;
        state.budgetUsedUsd += escalation.estimatedCostUsd;
        estimatedCostUsd += escalation.estimatedCostUsd;
        inputTokens += escalation.inputTokens;
        outputTokens += escalation.outputTokens;
      }
    } else {
      budgetBlockedEscalation = true;
    }
  }

  if (needsClarification && (!config.aiEscalationEnabled || !options.escalateOnClarification)) {
    budgetBlockedEscalation = true;
  }

  const endToEndLatencyMs = performance.now() - totalStart;
  return {
    inputText: replayCase.text,
    class: replayCase.class,
    primaryLatencyMs: round(primaryLatencyMs, 3),
    endToEndLatencyMs: round(endToEndLatencyMs, 3),
    fallbackUsed,
    escalationUsed,
    needsClarification,
    budgetBlockedFallback,
    budgetBlockedEscalation,
    estimatedCostUsd: round(estimatedCostUsd, 6),
    inputTokens,
    outputTokens
  };
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const rng = createRng(args.seed);
  const budgetState = { budgetUsedUsd: 0 };
  const results: ReplayResult[] = [];
  const classMix: Record<LogClass, number> = { high: 0, medium: 0, low: 0 };

  for (let i = 0; i < args.count; i += 1) {
    const replayCase = chooseCase(rng);
    classMix[replayCase.class] += 1;
    // eslint-disable-next-line no-await-in-loop
    const result = await runReplayCase(replayCase, budgetState, {
      escalateOnClarification: args.escalateOnClarification
    });
    results.push(result);
  }

  const fallbackCount = results.filter((r) => r.fallbackUsed).length;
  const escalationCount = results.filter((r) => r.escalationUsed).length;
  const clarificationCount = results.filter((r) => r.needsClarification).length;
  const fallbackBlockedCount = results.filter((r) => r.budgetBlockedFallback).length;
  const escalationBlockedCount = results.filter((r) => r.budgetBlockedEscalation).length;
  const totalCostUsd = results.reduce((sum, r) => sum + r.estimatedCostUsd, 0);
  const totalInputTokens = results.reduce((sum, r) => sum + r.inputTokens, 0);
  const totalOutputTokens = results.reduce((sum, r) => sum + r.outputTokens, 0);
  const primaryLatencies = results.map((r) => r.primaryLatencyMs);
  const endToEndLatencies = results.map((r) => r.endToEndLatencyMs);

  const summary = {
    totalLogs: args.count,
    classMix,
    fallbackRate: round(fallbackCount / args.count, 6),
    escalationRate: round(escalationCount / args.count, 6),
    clarificationRate: round(clarificationCount / args.count, 6),
    budgetBlockedFallbackRate: round(fallbackBlockedCount / args.count, 6),
    budgetBlockedEscalationRate: round(escalationBlockedCount / args.count, 6),
    costPerLogUsd: round(totalCostUsd / args.count, 6),
    totalEstimatedCostUsd: round(totalCostUsd, 6),
    totalInputTokens,
    totalOutputTokens,
    latency: {
      primaryP50Ms: round(percentile(primaryLatencies, 50), 3),
      primaryP95Ms: round(percentile(primaryLatencies, 95), 3),
      endToEndP50Ms: round(percentile(endToEndLatencies, 50), 3),
      endToEndP95Ms: round(percentile(endToEndLatencies, 95), 3)
    }
  };

  const generatedAt = new Date().toISOString();
  const runId =
    generatedAt.replace(/[:.]/g, '-') + (args.label ? `-${args.label.replace(/[^a-zA-Z0-9_-]/g, '')}` : '');

  mkdirSync(args.outputDir, { recursive: true });
  const report = {
    runId,
    generatedAt,
    configSnapshot: {
      aiFallbackEnabled: config.aiFallbackEnabled,
      aiFallbackConfidenceMin: config.aiFallbackConfidenceMin,
      aiFallbackConfidenceMax: config.aiFallbackConfidenceMax,
      aiEscalationEnabled: config.aiEscalationEnabled,
      aiDailyBudgetUsd: config.aiDailyBudgetUsd,
      aiFallbackCostUsd: config.aiFallbackCostUsd,
      aiEscalationCostUsd: config.aiEscalationCostUsd
    },
    benchmarkArgs: {
      count: args.count,
      seed: args.seed,
      escalateOnClarification: args.escalateOnClarification
    },
    summary,
    sampleRows: results.slice(0, 25)
  };

  const runPath = path.join(args.outputDir, `replay-${runId}.json`);
  const latestPath = path.join(args.outputDir, 'replay-latest.json');
  const indexPath = path.join(args.outputDir, 'replay-runs.ndjson');
  writeFileSync(runPath, `${JSON.stringify(report, null, 2)}\n`);
  writeFileSync(latestPath, `${JSON.stringify(report, null, 2)}\n`);
  appendFileSync(
    indexPath,
    `${JSON.stringify({
      runId,
      generatedAt,
      totalLogs: args.count,
      fallbackRate: summary.fallbackRate,
      escalationRate: summary.escalationRate,
      costPerLogUsd: summary.costPerLogUsd,
      endToEndP95Ms: summary.latency.endToEndP95Ms
    })}\n`
  );

  console.log(`Replay benchmark complete (${args.count} logs)`);
  console.log(`Artifact: ${runPath}`);
  console.log(
    JSON.stringify(
      {
        fallbackRate: summary.fallbackRate,
        escalationRate: summary.escalationRate,
        costPerLogUsd: summary.costPerLogUsd,
        endToEndP95Ms: summary.latency.endToEndP95Ms
      },
      null,
      2
    )
  );
}

main().catch((err) => {
  console.error('Replay benchmark failed', err);
  process.exit(1);
});
