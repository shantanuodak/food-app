/**
 * Image parse eval harness.
 *
 * Runs one or more image files through the same internal Render/local route used
 * for manual Gemini image smoke tests, then scores detection coverage, calories,
 * latency, and partial-parse behavior.
 *
 * Usage:
 *   npm run eval:image -- --image /path/meal.jpg --label "dal baati tray" --context "Indian thali"
 *   npm run eval:image -- --manifest ./image-eval-cases.json --base-url https://food-app-backend-ifdx.onrender.com
 *
 * Required:
 *   INTERNAL_METRICS_KEY must be set for the target backend.
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';

type CliArgs = {
  manifestPath: string | null;
  imagePath: string | null;
  label: string | null;
  contextNote: string | null;
  requiredKeywords: string[];
  minItems: number | null;
  calorieMin: number | null;
  calorieMax: number | null;
  allowPartial: boolean | null;
  expectNeedsClarification: boolean | null;
  baseUrl: string;
  outputDir: string;
  maxMs: number;
  expectedLane: string | null;
  expectedCuisine: string | null;
  expectedImageType: string | null;
  lane: 'barcode' | 'label' | 'vision';
  barcode: string | null;
  symbology: string | null;
  ocrText: string | null;
  userLocale: string | null;
};

type ImageEvalCase = {
  label: string;
  file: string;
  contextNote?: string;
  lane?: 'barcode' | 'label' | 'vision';
  barcode?: string;
  symbology?: string;
  ocrText?: string;
  userLocale?: string;
  recentCuisines?: string[];
  expectedLane?: string;
  expectedCuisine?: string;
  expectedImageType?: string;
  requiredKeywords?: string[];
  minItems?: number;
  calorieMin?: number;
  calorieMax?: number;
  allowPartial?: boolean;
  expectNeedsClarification?: boolean;
  maxMs?: number;
};

type ImageParseItem = {
  name?: string;
  quantity?: number;
  unit?: string;
  grams?: number;
  calories?: number;
  protein?: number;
  carbs?: number;
  fat?: number;
  confidence?: number;
  matchConfidence?: number;
  needsClarification?: boolean;
};

type ImageCoverage = {
  imageType?: string;
  cuisineHints?: string[];
  visibleComponentCount?: number;
  parsedItemCount?: number;
  score?: number;
  partial?: boolean;
  warnings?: string[];
};

type ImageParseResponse = {
  requestId?: string;
  ok?: boolean;
  error?: { code?: string; message?: string; requestId?: string };
  model?: string;
  visionModel?: string;
  orchestratorVersion?: string;
  fallbackUsed?: boolean;
  visionFallbackUsed?: boolean;
  lowConfidenceAccepted?: boolean;
  visionLowConfidenceAccepted?: boolean;
  confidence?: number;
  extractedText?: string;
  totals?: {
    calories?: number;
    protein?: number;
    carbs?: number;
    fat?: number;
  };
  items?: ImageParseItem[];
  needsClarification?: boolean;
  clarificationQuestions?: string[];
  reasonCodes?: string[];
  coverage?: ImageCoverage | null;
  imageMeta?: {
    orchestratorVersion?: string;
    coverage?: ImageCoverage | null;
  };
  parseLaneUsed?: string;
  parseLaneSource?: string | null;
  parseLaneLatencyMs?: number | null;
  cuisineUsed?: string | null;
  cuisineSource?: string | null;
  cuisineConfidence?: number | null;
  diagnostics?: unknown;
  debugEvents?: unknown;
};

type CaseChecks = {
  httpOk: boolean;
  expectedLane: boolean;
  expectedCuisine: boolean;
  expectedImageType: boolean;
  minItems: boolean;
  requiredKeywords: boolean;
  caloriesInRange: boolean;
  partialAllowed: boolean;
  needsClarification: boolean;
  latency: boolean;
};

type CaseReport = {
  label: string;
  file: string;
  status: number;
  ok: boolean;
  ms: number;
  model: string | null;
  parseLaneUsed: string | null;
  parseLaneSource: string | null;
  parseLaneLatencyMs: number | null;
  cuisineUsed: string | null;
  cuisineSource: string | null;
  cuisineConfidence: number | null;
  orchestratorVersion: string | null;
  fallbackUsed: boolean | null;
  confidence: number | null;
  extractedText: string | null;
  totals: ImageParseResponse['totals'] | null;
  coverage: ImageCoverage | null;
  items: Array<{
    name: string;
    calories: number | null;
    grams: number | null;
    confidence: number | null;
    needsClarification: boolean | null;
  }>;
  checks: CaseChecks;
  missingKeywords: string[];
  expected: {
    minItems: number;
    calorieMin: number | null;
    calorieMax: number | null;
    allowPartial: boolean;
    expectNeedsClarification: boolean | null;
    maxMs: number;
    expectedLane: string | null;
    expectedCuisine: string | null;
    expectedImageType: string | null;
  };
  error: ImageParseResponse['error'] | null;
  diagnostics?: unknown;
  debugEvents?: unknown;
};

function parseArgs(argv: string[]): CliArgs {
  const args: CliArgs = {
    manifestPath: null,
    imagePath: null,
    label: null,
    contextNote: null,
    requiredKeywords: [],
    minItems: null,
    calorieMin: null,
    calorieMax: null,
    allowPartial: null,
    expectNeedsClarification: null,
    baseUrl: process.env.IMAGE_EVAL_BASE_URL || 'http://localhost:8080',
    outputDir: '',
    maxMs: Number(process.env.IMAGE_EVAL_MAX_MS || 6_000),
    expectedLane: null,
    expectedCuisine: null,
    expectedImageType: null,
    lane: 'vision',
    barcode: null,
    symbology: null,
    ocrText: null,
    userLocale: null
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    const next = argv[i + 1];
    if (token === '--manifest' && next) {
      args.manifestPath = next;
      i += 1;
    } else if (token === '--image' && next) {
      args.imagePath = next;
      i += 1;
    } else if (token === '--label' && next) {
      args.label = next;
      i += 1;
    } else if (token === '--context' && next) {
      args.contextNote = next;
      i += 1;
    } else if (token === '--required' && next) {
      args.requiredKeywords = next.split(',').map((entry) => entry.trim()).filter(Boolean);
      i += 1;
    } else if (token === '--min-items' && next) {
      args.minItems = numberOrNull(next);
      i += 1;
    } else if (token === '--calories' && next) {
      const [minRaw, maxRaw] = next.split(':');
      args.calorieMin = numberOrNull(minRaw);
      args.calorieMax = numberOrNull(maxRaw);
      i += 1;
    } else if (token === '--allow-partial') {
      args.allowPartial = true;
    } else if (token === '--disallow-partial') {
      args.allowPartial = false;
    } else if (token === '--expect-clarification') {
      args.expectNeedsClarification = true;
    } else if (token === '--expect-no-clarification') {
      args.expectNeedsClarification = false;
    } else if (token === '--base-url' && next) {
      args.baseUrl = next;
      i += 1;
    } else if (token === '--output-dir' && next) {
      args.outputDir = next;
      i += 1;
    } else if (token === '--max-ms' && next) {
      args.maxMs = numberOrNull(next) ?? args.maxMs;
      i += 1;
    } else if (token === '--expected-lane' && next) {
      args.expectedLane = next;
      i += 1;
    } else if (token === '--expected-cuisine' && next) {
      args.expectedCuisine = next;
      i += 1;
    } else if (token === '--expected-image-type' && next) {
      args.expectedImageType = next;
      i += 1;
    } else if (token === '--lane' && next && isLane(next)) {
      args.lane = next;
      i += 1;
    } else if (token === '--barcode' && next) {
      args.barcode = next;
      i += 1;
    } else if (token === '--symbology' && next) {
      args.symbology = next;
      i += 1;
    } else if (token === '--ocr-text' && next) {
      args.ocrText = next;
      i += 1;
    } else if (token === '--user-locale' && next) {
      args.userLocale = next;
      i += 1;
    }
  }

  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);
  args.outputDir = args.outputDir || path.resolve(__dirname, '../../benchmarks/image-eval-runs');
  return args;
}

function numberOrNull(value: string | undefined): number | null {
  if (!value) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function isLane(value: string): value is 'barcode' | 'label' | 'vision' {
  return value === 'barcode' || value === 'label' || value === 'vision';
}

function readCases(args: CliArgs): ImageEvalCase[] {
  if (args.manifestPath) {
    const manifestPath = path.resolve(process.cwd(), args.manifestPath);
    const raw = readFileSync(manifestPath, 'utf8');
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) {
      throw new Error('Image eval manifest must be a JSON array.');
    }
    return parsed.map((entry, index) => normalizeManifestCase(entry, index, path.dirname(manifestPath)));
  }

  if (!args.imagePath) {
    throw new Error(
      [
        'Missing image input.',
        'Use --image /absolute/path.jpg or --manifest ./image-eval-cases.json.',
        'Example: npm run eval:image -- --image ~/Downloads/IMG_5910.JPG --label "dal baati" --required dal,baati --min-items 4'
      ].join('\n')
    );
  }

  return [
    {
      label: args.label || path.basename(args.imagePath),
      file: path.resolve(process.cwd(), args.imagePath),
      contextNote: args.contextNote || undefined,
      lane: args.lane,
      barcode: args.barcode ?? undefined,
      symbology: args.symbology ?? undefined,
      ocrText: args.ocrText ?? undefined,
      userLocale: args.userLocale ?? undefined,
      expectedLane: args.expectedLane ?? undefined,
      expectedCuisine: args.expectedCuisine ?? undefined,
      expectedImageType: args.expectedImageType ?? undefined,
      requiredKeywords: args.requiredKeywords,
      minItems: args.minItems ?? undefined,
      calorieMin: args.calorieMin ?? undefined,
      calorieMax: args.calorieMax ?? undefined,
      allowPartial: args.allowPartial ?? undefined,
      expectNeedsClarification: args.expectNeedsClarification ?? undefined,
      maxMs: args.maxMs
    }
  ];
}

function normalizeManifestCase(entry: unknown, index: number, manifestDir: string): ImageEvalCase {
  if (!entry || typeof entry !== 'object') {
    throw new Error(`Invalid manifest case at index ${index}.`);
  }
  const record = entry as Record<string, unknown>;
  const file = stringValue(record.file);
  if (!file) {
    throw new Error(`Manifest case ${index} is missing file.`);
  }
  const resolvedFile = path.isAbsolute(file) ? file : path.resolve(manifestDir, file);
  return {
    label: stringValue(record.label) || path.basename(resolvedFile),
    file: resolvedFile,
    contextNote: stringValue(record.contextNote),
    lane: laneValue(record.lane),
    barcode: stringValue(record.barcode),
    symbology: stringValue(record.symbology),
    ocrText: stringValue(record.ocrText),
    userLocale: stringValue(record.userLocale),
    recentCuisines: stringArray(record.recentCuisines),
    expectedLane: stringValue(record.expectedLane),
    expectedCuisine: stringValue(record.expectedCuisine),
    expectedImageType: stringValue(record.expectedImageType),
    requiredKeywords: stringArray(record.requiredKeywords),
    minItems: numberValue(record.minItems),
    calorieMin: numberValue(record.calorieMin),
    calorieMax: numberValue(record.calorieMax),
    allowPartial: booleanValue(record.allowPartial),
    expectNeedsClarification: booleanValue(record.expectNeedsClarification),
    maxMs: numberValue(record.maxMs)
  };
}

function laneValue(value: unknown): 'barcode' | 'label' | 'vision' | undefined {
  return typeof value === 'string' && isLane(value) ? value : undefined;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((entry): entry is string => typeof entry === 'string').map((entry) => entry.trim()).filter(Boolean)
    : [];
}

function numberValue(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

function booleanValue(value: unknown): boolean | undefined {
  return typeof value === 'boolean' ? value : undefined;
}

function mimeTypeForFile(file: string): string {
  const ext = path.extname(file).toLowerCase();
  if (ext === '.png') return 'image/png';
  if (ext === '.heic' || ext === '.heif') return 'image/heic';
  return 'image/jpeg';
}

async function runCase(kase: ImageEvalCase, args: CliArgs, key: string): Promise<CaseReport> {
  if (!existsSync(kase.file)) {
    throw new Error(`Image file not found: ${kase.file}`);
  }

  const imageBase64 = readFileSync(kase.file).toString('base64');
  const startedAt = performance.now();
  const response = await fetch(`${args.baseUrl.replace(/\/$/, '')}/v1/internal/test/image-parse`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-internal-metrics-key': key
    },
    body: JSON.stringify({
      imageBase64,
      mimeType: mimeTypeForFile(kase.file),
      contextNote: kase.contextNote,
      lane: kase.lane ?? 'vision',
      barcode: kase.barcode,
      symbology: kase.symbology,
      ocrText: kase.ocrText,
      userLocale: kase.userLocale,
      recentCuisines: kase.recentCuisines
    })
  });
  const ms = Math.round(performance.now() - startedAt);
  const json = (await response.json().catch(() => ({}))) as ImageParseResponse;

  return scoreCase(kase, response.status, response.ok, ms, json, args.maxMs);
}

function scoreCase(
  kase: ImageEvalCase,
  status: number,
  httpOk: boolean,
  ms: number,
  json: ImageParseResponse,
  defaultMaxMs: number
): CaseReport {
  const items = Array.isArray(json.items) ? json.items : [];
  const minItems = kase.minItems ?? 1;
  const calorieMin = kase.calorieMin ?? null;
  const calorieMax = kase.calorieMax ?? null;
  const allowPartial = kase.allowPartial ?? true;
  const expectedClarification = kase.expectNeedsClarification ?? null;
  const maxMs = kase.maxMs ?? defaultMaxMs;
  const coverage = json.coverage ?? json.imageMeta?.coverage ?? null;
  const orchestratorVersion = json.orchestratorVersion ?? json.imageMeta?.orchestratorVersion ?? null;
  const parseLaneUsed = json.parseLaneUsed ?? null;
  const cuisineUsed = json.cuisineUsed ?? coverage?.cuisineHints?.[0] ?? null;
  const imageType = coverage?.imageType ?? null;
  const totalCalories = numberValue(json.totals?.calories);
  const searchable = [
    json.extractedText,
    ...items.map((item) => item.name)
  ]
    .filter((value): value is string => typeof value === 'string')
    .join(' ')
    .toLowerCase();
  const requiredKeywords = kase.requiredKeywords ?? [];
  const missingKeywords = requiredKeywords.filter((keyword) => !keywordPresent(searchable, keyword));
  const partial = coverage?.partial === true;

  const checks: CaseChecks = {
    httpOk,
    expectedLane: !kase.expectedLane || parseLaneUsed === kase.expectedLane,
    expectedCuisine: !kase.expectedCuisine || cuisineUsed === kase.expectedCuisine,
    expectedImageType: !kase.expectedImageType || imageType === kase.expectedImageType,
    minItems: items.length >= minItems,
    requiredKeywords: missingKeywords.length === 0,
    caloriesInRange:
      calorieMin === null && calorieMax === null
        ? true
        : totalCalories !== undefined &&
          (calorieMin === null || totalCalories >= calorieMin) &&
          (calorieMax === null || totalCalories <= calorieMax),
    partialAllowed: allowPartial || !partial,
    needsClarification:
      expectedClarification === null ? true : json.needsClarification === expectedClarification,
    latency: ms <= maxMs
  };

  const ok = Object.values(checks).every(Boolean);
  return {
    label: kase.label,
    file: kase.file,
    status,
    ok,
    ms,
    model: json.model ?? json.visionModel ?? null,
    parseLaneUsed,
    parseLaneSource: json.parseLaneSource ?? null,
    parseLaneLatencyMs: numberValue(json.parseLaneLatencyMs) ?? null,
    cuisineUsed,
    cuisineSource: json.cuisineSource ?? null,
    cuisineConfidence: numberValue(json.cuisineConfidence) ?? null,
    orchestratorVersion,
    fallbackUsed: json.fallbackUsed ?? json.visionFallbackUsed ?? null,
    confidence: numberValue(json.confidence) ?? null,
    extractedText: json.extractedText ?? null,
    totals: json.totals ?? null,
    coverage,
    items: items.map((item) => ({
      name: item.name ?? 'Unknown item',
      calories: numberValue(item.calories) ?? null,
      grams: numberValue(item.grams) ?? null,
      confidence: numberValue(item.matchConfidence) ?? numberValue(item.confidence) ?? null,
      needsClarification: typeof item.needsClarification === 'boolean' ? item.needsClarification : null
    })),
    checks,
    missingKeywords,
    expected: {
      minItems,
      calorieMin,
      calorieMax,
      allowPartial,
      expectNeedsClarification: expectedClarification,
      maxMs,
      expectedLane: kase.expectedLane ?? null,
      expectedCuisine: kase.expectedCuisine ?? null,
      expectedImageType: kase.expectedImageType ?? null
    },
    error: json.error ?? null,
    diagnostics: json.diagnostics,
    debugEvents: json.debugEvents
  };
}

function keywordPresent(searchable: string, keyword: string): boolean {
  const normalized = keyword.toLowerCase().trim();
  if (!normalized) return true;
  const aliases: Record<string, string[]> = {
    bean: ['bean', 'beans', 'rajma', 'kidney bean'],
    burger: ['burger', 'fried chicken sandwich', 'chicken sandwich'],
    roti: ['roti', 'chapati', 'paratha', 'naan', 'flatbread'],
    salad: ['salad', 'mixed greens', 'side salad']
  };
  return (aliases[normalized] ?? [normalized]).some((alias) => searchable.includes(alias));
}

function printReport(reports: CaseReport[]): void {
  for (const report of reports) {
    const state = report.ok ? 'PASS' : 'FAIL';
    const calories = report.totals?.calories ?? '—';
    const coverage = report.coverage?.score !== undefined ? `${Math.round(report.coverage.score * 100)}%` : '—';
    const lane = report.parseLaneUsed ?? '—';
    const cuisine = report.cuisineUsed ?? report.coverage?.cuisineHints?.[0] ?? '—';
    console.log(
      `${state} ${report.label} · ${report.status} · ${report.ms}ms · lane ${lane} · cuisine ${cuisine} · cal ${calories} · items ${report.items.length} · coverage ${coverage}`
    );
    if (!report.ok) {
      const failedChecks = Object.entries(report.checks)
        .filter(([, passed]) => !passed)
        .map(([name]) => name);
      console.log(`  failed: ${failedChecks.join(', ')}`);
      if (report.missingKeywords.length) {
        console.log(`  missing keywords: ${report.missingKeywords.join(', ')}`);
      }
      if (report.error) {
        console.log(`  error: ${report.error.code || 'UNKNOWN'} ${report.error.message || ''}`);
      }
    }
    if (report.items.length) {
      console.log(`  items: ${report.items.map((item) => item.name).join(' · ')}`);
    }
  }
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const key = process.env.INTERNAL_METRICS_KEY;
  if (!key) {
    throw new Error("Missing INTERNAL_METRICS_KEY. Run: export INTERNAL_METRICS_KEY='your-key'");
  }

  const cases = readCases(args);
  const reports: CaseReport[] = [];
  for (const kase of cases) {
    reports.push(await runCase(kase, args, key));
  }

  printReport(reports);
  mkdirSync(args.outputDir, { recursive: true });
  const reportPath = path.join(args.outputDir, `image-eval-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  writeFileSync(
    reportPath,
    JSON.stringify(
      {
        runAt: new Date().toISOString(),
        baseUrl: args.baseUrl,
        summary: {
          total: reports.length,
          passed: reports.filter((report) => report.ok).length,
          failed: reports.filter((report) => !report.ok).length,
          avgMs: Math.round(reports.reduce((sum, report) => sum + report.ms, 0) / Math.max(1, reports.length))
        },
        reports
      },
      null,
      2
    )
  );
  console.log(`\nWrote ${reportPath}`);

  if (reports.some((report) => !report.ok)) {
    process.exitCode = 1;
  }
}

main().catch((err: unknown) => {
  console.error(err instanceof Error ? err.message : err);
  process.exitCode = 1;
});
