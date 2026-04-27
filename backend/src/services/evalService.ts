import { performance } from 'node:perf_hooks';
import { runPrimaryParsePipeline } from './parsePipelineService.js';
import { pool } from '../db.js';
import {
  type BenchmarkConfidence,
  type BenchmarkSpec,
  resolveNutritionBenchmark
} from './nutritionBenchmarkService.js';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type EvalCaseResult = {
  cuisine: string;
  input: string;
  route: string;
  actualCalories: number;
  expectedCaloriesMin: number;
  expectedCaloriesMax: number;
  benchmarkSource: string;
  benchmarkConfidence: BenchmarkConfidence;
  benchmarkNotes: string;
  benchmarkReference?: string;
  detectedItems: string;
  passKeywords: boolean;
  passCalories: boolean;
  pass: boolean;
  confidence: number;
  latencyMs: number;
};

export type EvalRunResult = {
  runType: string;
  caseSet: EvalCaseSet;
  cacheMode: EvalCacheMode;
  requestedCases: number;
  evaluatedCases: number;
  totalCases: number;
  passed: number;
  failed: number;
  passRate: number;
  byCategory: Record<string, { total: number; passed: number }>;
  byRoute: Record<string, number>;
  cases: EvalCaseResult[];
  durationMs: number;
};

export type EvalRunSummary = {
  id: string;
  runType: string;
  runAt: string;
  totalCases: number;
  passed: number;
  failed: number;
  passRate: number;
  durationMs: number;
};

// ---------------------------------------------------------------------------
// Golden case definitions (57 cases across 12 cuisines)
// Sourced from goldenSetEval.ts
// ---------------------------------------------------------------------------

type GoldenCase = {
  cuisine: string;
  text: string;
  expectedKeywords: string[];
  caloriesRange?: { min: number; max: number };
  benchmark?: BenchmarkSpec;
};

export type EvalCaseSet = 'golden' | 'exploration' | 'combined';
export type EvalCacheMode = 'cached' | 'fresh';

export type EvalRunOptions = {
  caseSet?: EvalCaseSet;
  cacheMode?: EvalCacheMode;
  maxCases?: number;
  onProgress?: (casesDone: number, totalCases: number) => void;
};

const GOLDEN_CASES: GoldenCase[] = [
  {
    cuisine: 'American',
    text: 'Black Coffee 1 Cup',
    expectedKeywords: ['coffee'],
    caloriesRange: { min: 0, max: 15 },
    benchmark: usdaBenchmark(
      { min: 0, max: 15 },
      'coffee, brewed',
      237,
      'USDA-backed benchmark for one 8 fl oz cup of brewed black coffee.',
      0.75,
      10
    )
  },
  {
    cuisine: 'American',
    text: 'Coke 8oz',
    expectedKeywords: ['coke', 'cola', 'soft drink', 'soda'],
    caloriesRange: { min: 60, max: 120 },
    benchmark: usdaBenchmark(
      { min: 60, max: 120 },
      'cola regular',
      240,
      'USDA-backed benchmark for 8 fl oz of regular cola.',
      0.2,
      10
    )
  },
  { cuisine: 'American', text: 'Cheeseburger 1 burger', expectedKeywords: ['cheeseburger', 'burger'], caloriesRange: { min: 250, max: 900 } },
  { cuisine: 'American', text: 'Pepperoni Pizza 2 slices', expectedKeywords: ['pizza', 'pepperoni'], caloriesRange: { min: 300, max: 900 } },
  { cuisine: 'American', text: 'Caesar Salad with Chicken', expectedKeywords: ['caesar', 'salad', 'chicken'], caloriesRange: { min: 180, max: 800 } },
  { cuisine: 'American', text: 'Buffalo Wings 6 pieces', expectedKeywords: ['wing', 'buffalo'], caloriesRange: { min: 250, max: 1000 } },
  { cuisine: 'American', text: 'Chocolate Milkshake 12 oz', expectedKeywords: ['milkshake', 'chocolate'], caloriesRange: { min: 180, max: 800 } },
  { cuisine: 'Indian', text: 'Chicken Tikka Masala 1 cup', expectedKeywords: ['chicken', 'tikka', 'masala'], caloriesRange: { min: 180, max: 750 } },
  { cuisine: 'Indian', text: 'Dal Tadka 1 bowl', expectedKeywords: ['dal', 'lentil', 'tadka'], caloriesRange: { min: 120, max: 550 } },
  { cuisine: 'Indian', text: 'Chole Bhature 1 plate', expectedKeywords: ['chole', 'bhature', 'chickpea'], caloriesRange: { min: 350, max: 1300 } },
  { cuisine: 'Indian', text: 'Pav Bhaji 1 plate', expectedKeywords: ['pav', 'bhaji'], caloriesRange: { min: 180, max: 900 } },
  { cuisine: 'Indian', text: 'Samosa 2 pieces', expectedKeywords: ['samosa'], caloriesRange: { min: 140, max: 700 } },
  { cuisine: 'Indian', text: 'Aloo Paratha with Butter', expectedKeywords: ['aloo', 'paratha'], caloriesRange: { min: 220, max: 900 } },
  { cuisine: 'Indian', text: 'Idli 3 pieces with Sambar', expectedKeywords: ['idli', 'sambar'], caloriesRange: { min: 120, max: 700 } },
  { cuisine: 'Indian', text: 'Masala Dosa 1 dosa', expectedKeywords: ['dosa', 'masala'], caloriesRange: { min: 180, max: 850 } },
  { cuisine: 'Indian', text: 'Rajma Chawal 1 bowl', expectedKeywords: ['rajma', 'rice', 'chawal'], caloriesRange: { min: 220, max: 900 } },
  { cuisine: 'Indian', text: 'Palak Paneer 1 cup', expectedKeywords: ['palak', 'paneer'], caloriesRange: { min: 160, max: 700 } },
  { cuisine: 'Italian', text: 'Spaghetti Bolognese 1 plate', expectedKeywords: ['spaghetti', 'bolognese', 'pasta'], caloriesRange: { min: 220, max: 1100 } },
  { cuisine: 'Italian', text: 'Penne Alfredo 1 bowl', expectedKeywords: ['penne', 'alfredo', 'pasta'], caloriesRange: { min: 250, max: 1200 } },
  { cuisine: 'Italian', text: 'Margherita Pizza 3 slices', expectedKeywords: ['pizza', 'margherita'], caloriesRange: { min: 250, max: 1100 } },
  { cuisine: 'Italian', text: 'Lasagna 1 serving', expectedKeywords: ['lasagna'], caloriesRange: { min: 220, max: 1000 } },
  { cuisine: 'Italian', text: 'Minestrone Soup 1 bowl', expectedKeywords: ['minestrone', 'soup'], caloriesRange: { min: 70, max: 450 } },
  { cuisine: 'Italian', text: 'Risotto Mushroom 1 cup', expectedKeywords: ['risotto', 'mushroom'], caloriesRange: { min: 180, max: 800 } },
  { cuisine: 'Italian', text: 'Tiramisu 1 slice', expectedKeywords: ['tiramisu'], caloriesRange: { min: 180, max: 700 } },
  { cuisine: 'Mexican', text: 'Chicken Burrito 1 burrito', expectedKeywords: ['burrito', 'chicken'], caloriesRange: { min: 250, max: 1200 } },
  { cuisine: 'Mexican', text: 'Beef Tacos 3 tacos', expectedKeywords: ['taco', 'beef'], caloriesRange: { min: 220, max: 1200 } },
  { cuisine: 'Mexican', text: 'Quesadilla Cheese 1 piece', expectedKeywords: ['quesadilla', 'cheese'], caloriesRange: { min: 180, max: 900 } },
  { cuisine: 'Mexican', text: 'Nachos with Salsa', expectedKeywords: ['nachos', 'salsa'], caloriesRange: { min: 140, max: 1000 } },
  { cuisine: 'Mexican', text: 'Chicken Fajitas 1 plate', expectedKeywords: ['fajita', 'chicken'], caloriesRange: { min: 180, max: 1000 } },
  { cuisine: 'Mexican', text: 'Guacamole 1 cup', expectedKeywords: ['guacamole', 'avocado'], caloriesRange: { min: 120, max: 700 } },
  { cuisine: 'Chinese', text: 'Kung Pao Chicken 1 bowl', expectedKeywords: ['kung pao', 'chicken'], caloriesRange: { min: 200, max: 950 } },
  { cuisine: 'Chinese', text: 'Vegetable Fried Rice 1 bowl', expectedKeywords: ['fried rice', 'vegetable', 'rice'], caloriesRange: { min: 180, max: 950 } },
  { cuisine: 'Chinese', text: 'Chow Mein 1 plate', expectedKeywords: ['chow mein', 'noodle'], caloriesRange: { min: 180, max: 950 } },
  { cuisine: 'Chinese', text: 'Sweet and Sour Pork 1 serving', expectedKeywords: ['sweet', 'sour', 'pork'], caloriesRange: { min: 220, max: 950 } },
  { cuisine: 'Chinese', text: 'Dim Sum 6 pieces', expectedKeywords: ['dim sum', 'dumpling'], caloriesRange: { min: 150, max: 900 } },
  { cuisine: 'Chinese', text: 'Hot and Sour Soup 1 bowl', expectedKeywords: ['hot', 'sour', 'soup'], caloriesRange: { min: 70, max: 450 } },
  { cuisine: 'Japanese', text: 'Salmon Sushi 8 pieces', expectedKeywords: ['salmon', 'sushi'], caloriesRange: { min: 180, max: 700 } },
  { cuisine: 'Japanese', text: 'Chicken Teriyaki with Rice', expectedKeywords: ['teriyaki', 'chicken', 'rice'], caloriesRange: { min: 220, max: 1000 } },
  { cuisine: 'Japanese', text: 'Ramen Tonkotsu 1 bowl', expectedKeywords: ['ramen', 'tonkotsu'], caloriesRange: { min: 250, max: 1200 } },
  { cuisine: 'Japanese', text: 'Miso Soup 1 cup', expectedKeywords: ['miso', 'soup'], caloriesRange: { min: 20, max: 250 } },
  { cuisine: 'Japanese', text: 'Tempura Shrimp 5 pieces', expectedKeywords: ['tempura', 'shrimp'], caloriesRange: { min: 160, max: 900 } },
  { cuisine: 'Middle Eastern', text: 'Chicken Shawarma Wrap', expectedKeywords: ['shawarma', 'chicken', 'wrap'], caloriesRange: { min: 220, max: 950 } },
  { cuisine: 'Middle Eastern', text: 'Falafel 6 pieces', expectedKeywords: ['falafel'], caloriesRange: { min: 180, max: 900 } },
  { cuisine: 'Middle Eastern', text: 'Hummus 1 cup with Pita', expectedKeywords: ['hummus', 'pita'], caloriesRange: { min: 180, max: 1000 } },
  { cuisine: 'Middle Eastern', text: 'Lamb Kebab 2 skewers', expectedKeywords: ['lamb', 'kebab'], caloriesRange: { min: 220, max: 1000 } },
  { cuisine: 'Middle Eastern', text: 'Tabbouleh Salad 1 bowl', expectedKeywords: ['tabbouleh', 'salad'], caloriesRange: { min: 80, max: 500 } },
  { cuisine: 'Thai', text: 'Pad Thai Shrimp 1 plate', expectedKeywords: ['pad thai', 'shrimp'], caloriesRange: { min: 220, max: 1100 } },
  { cuisine: 'Thai', text: 'Green Curry Chicken 1 bowl', expectedKeywords: ['green curry', 'chicken'], caloriesRange: { min: 220, max: 1000 } },
  { cuisine: 'Thai', text: 'Tom Yum Soup 1 bowl', expectedKeywords: ['tom yum', 'soup'], caloriesRange: { min: 50, max: 450 } },
  { cuisine: 'Vietnamese', text: 'Pho Beef 1 bowl', expectedKeywords: ['pho', 'beef', 'noodle'], caloriesRange: { min: 180, max: 900 } },
  { cuisine: 'Vietnamese', text: 'Spring Rolls 2 rolls', expectedKeywords: ['spring roll'], caloriesRange: { min: 120, max: 700 } },
  { cuisine: 'Korean', text: 'Bibimbap 1 bowl', expectedKeywords: ['bibimbap', 'rice'], caloriesRange: { min: 220, max: 1000 } },
  { cuisine: 'Korean', text: 'Kimchi Fried Rice 1 bowl', expectedKeywords: ['kimchi', 'fried rice'], caloriesRange: { min: 180, max: 950 } },
  { cuisine: 'Korean', text: 'Bulgogi Beef 1 serving', expectedKeywords: ['bulgogi', 'beef'], caloriesRange: { min: 180, max: 900 } },
  { cuisine: 'Mediterranean', text: 'Greek Salad with Feta', expectedKeywords: ['greek', 'salad', 'feta'], caloriesRange: { min: 120, max: 700 } },
  { cuisine: 'Mediterranean', text: 'Avocado Toast 2 slices', expectedKeywords: ['avocado', 'toast'], caloriesRange: { min: 180, max: 800 } },
  { cuisine: 'Dessert', text: 'Vanilla Ice Cream 1 scoop', expectedKeywords: ['vanilla', 'ice cream'], caloriesRange: { min: 80, max: 450 } },
  { cuisine: 'Dessert', text: 'Brownie 1 piece', expectedKeywords: ['brownie'], caloriesRange: { min: 120, max: 650 } },
  { cuisine: 'Dessert', text: 'Banana Pudding 1 cup', expectedKeywords: ['banana', 'pudding'], caloriesRange: { min: 120, max: 700 } }
];

const EXPLORATION_SEEDS: GoldenCase[] = [
  {
    cuisine: 'Indian',
    text: 'cold coffee 8 oz',
    expectedKeywords: ['cold', 'coffee'],
    caloriesRange: { min: 80, max: 350 },
    benchmark: curatedBenchmark(
      { min: 80, max: 350 },
      'Curated cuisine benchmark',
      'Indian cold coffee commonly implies milk and sugar unless the user says black coffee.',
      'medium'
    )
  },
  { cuisine: 'Indian', text: 'Indian cold coffee 1 glass', expectedKeywords: ['cold', 'coffee'], caloriesRange: { min: 120, max: 450 } },
  {
    cuisine: 'American',
    text: 'black iced coffee 8 oz',
    expectedKeywords: ['coffee'],
    caloriesRange: { min: 0, max: 20 },
    benchmark: usdaBenchmark(
      { min: 0, max: 20 },
      'coffee, brewed',
      237,
      'USDA-backed benchmark for unsweetened black iced coffee.',
      0.75,
      10
    )
  },
  {
    cuisine: 'American',
    text: 'cold brew coffee 8 oz',
    expectedKeywords: ['coffee'],
    caloriesRange: { min: 0, max: 25 },
    benchmark: usdaBenchmark(
      { min: 0, max: 25 },
      'coffee, brewed',
      237,
      'USDA-backed benchmark for unsweetened cold brew coffee.',
      0.75,
      10
    )
  },
  { cuisine: 'Indian', text: 'masala chai 1 cup', expectedKeywords: ['chai', 'tea'], caloriesRange: { min: 40, max: 220 } },
  { cuisine: 'Indian', text: 'sweet lassi 1 glass', expectedKeywords: ['lassi'], caloriesRange: { min: 120, max: 420 } },
  { cuisine: 'Indian', text: 'mango lassi 12 oz', expectedKeywords: ['mango', 'lassi'], caloriesRange: { min: 180, max: 650 } },
  { cuisine: 'Indian', text: 'buttermilk 1 glass', expectedKeywords: ['buttermilk'], caloriesRange: { min: 30, max: 180 } },
  { cuisine: 'Indian', text: 'poha 1 bowl', expectedKeywords: ['poha'], caloriesRange: { min: 150, max: 550 } },
  { cuisine: 'Indian', text: 'upma 1 bowl', expectedKeywords: ['upma'], caloriesRange: { min: 150, max: 550 } },
  { cuisine: 'Indian', text: 'vada pav 1 piece', expectedKeywords: ['vada', 'pav'], caloriesRange: { min: 180, max: 600 } },
  { cuisine: 'Indian', text: 'paneer tikka 6 pieces', expectedKeywords: ['paneer', 'tikka'], caloriesRange: { min: 180, max: 700 } },
  { cuisine: 'Indian', text: 'naan 1 piece', expectedKeywords: ['naan'], caloriesRange: { min: 180, max: 450 } },
  { cuisine: 'Indian', text: 'garlic naan 1 piece', expectedKeywords: ['naan', 'garlic'], caloriesRange: { min: 220, max: 550 } },
  { cuisine: 'Indian', text: 'rava dosa 1 dosa', expectedKeywords: ['dosa'], caloriesRange: { min: 150, max: 650 } },
  { cuisine: 'Indian', text: 'sev puri 1 plate', expectedKeywords: ['sev', 'puri'], caloriesRange: { min: 180, max: 650 } },
  { cuisine: 'Indian', text: 'dahi puri 1 plate', expectedKeywords: ['dahi', 'puri'], caloriesRange: { min: 180, max: 700 } },
  { cuisine: 'Indian', text: 'biryani chicken 1 plate', expectedKeywords: ['biryani', 'chicken'], caloriesRange: { min: 350, max: 1200 } },
  { cuisine: 'American', text: 'iced latte 12 oz', expectedKeywords: ['latte'], caloriesRange: { min: 60, max: 350 } },
  { cuisine: 'American', text: 'frappuccino 16 oz', expectedKeywords: ['frappuccino', 'coffee'], caloriesRange: { min: 180, max: 650 } },
  { cuisine: 'American', text: 'oat milk latte 12 oz', expectedKeywords: ['latte', 'oat'], caloriesRange: { min: 90, max: 350 } },
  { cuisine: 'Mexican', text: 'horchata 12 oz', expectedKeywords: ['horchata'], caloriesRange: { min: 120, max: 450 } },
  { cuisine: 'Thai', text: 'thai iced tea 12 oz', expectedKeywords: ['thai', 'tea'], caloriesRange: { min: 120, max: 500 } },
  { cuisine: 'Vietnamese', text: 'vietnamese iced coffee 8 oz', expectedKeywords: ['coffee'], caloriesRange: { min: 80, max: 350 } },
  { cuisine: 'Middle Eastern', text: 'turkish coffee 1 cup', expectedKeywords: ['coffee'], caloriesRange: { min: 0, max: 80 } },
  { cuisine: 'Korean', text: 'banana milk 1 bottle', expectedKeywords: ['banana', 'milk'], caloriesRange: { min: 120, max: 350 } },
  { cuisine: 'Japanese', text: 'matcha latte 12 oz', expectedKeywords: ['matcha', 'latte'], caloriesRange: { min: 80, max: 420 } },
  { cuisine: 'Mediterranean', text: 'turkish ayran 1 glass', expectedKeywords: ['ayran'], caloriesRange: { min: 40, max: 180 } }
];

const PORTION_VARIANTS = ['1 cup', '1 bowl', '1 plate', '2 pieces', '1 serving'];

function generatedExplorationCases(): GoldenCase[] {
  const generated: GoldenCase[] = [];
  for (const seed of EXPLORATION_SEEDS) {
    generated.push(seed);
    for (const portion of PORTION_VARIANTS) {
      if (generated.length >= 500) break;
      const baseName = seed.text
        .replace(/\b\d+(?:\.\d+)?\s*(?:oz|cup|cups|glass|bowl|plate|pieces?|serving|bottle)\b/gi, '')
        .replace(/\s+/g, ' ')
        .trim();
      generated.push({
        ...seed,
        text: `${baseName} ${portion}`,
        caloriesRange: widenRange(seed.caloriesRange),
        benchmark: seed.caloriesRange
          ? curatedBenchmark(
              widenRange(seed.caloriesRange)!,
              'Generated exploration range',
              'Generated from a seed case with a deliberately widened range because the portion variant has not been individually sourced.',
              'low'
            )
          : undefined
      });
    }
  }
  return dedupeCases(generated).slice(0, 500);
}

function widenRange(range?: { min: number; max: number }): { min: number; max: number } | undefined {
  if (!range) return undefined;
  return {
    min: Math.max(0, Math.floor(range.min * 0.5)),
    max: Math.ceil(range.max * 1.8)
  };
}

function curatedBenchmark(
  range: { min: number; max: number },
  label: string,
  notes: string,
  confidence: BenchmarkConfidence = 'medium'
): BenchmarkSpec {
  return {
    range,
    source: {
      type: 'curated',
      label,
      confidence,
      notes
    }
  };
}

function usdaBenchmark(
  range: { min: number; max: number },
  query: string,
  grams: number,
  notes: string,
  tolerancePct = 0.25,
  minToleranceCalories = 15
): BenchmarkSpec {
  return {
    ...curatedBenchmark(range, 'Curated fallback benchmark', notes, 'medium'),
    usda: {
      query,
      grams,
      tolerancePct,
      minToleranceCalories
    }
  };
}

function benchmarkForCase(testCase: GoldenCase): BenchmarkSpec | undefined {
  if (testCase.benchmark) return testCase.benchmark;
  if (!testCase.caloriesRange) return undefined;
  return curatedBenchmark(
    testCase.caloriesRange,
    'Curated eval range',
    'Hand-authored calorie range used as a broad sanity check until this case is upgraded to a sourced benchmark.',
    'low'
  );
}

function dedupeCases(cases: GoldenCase[]): GoldenCase[] {
  const seen = new Set<string>();
  return cases.filter((testCase) => {
    const key = `${testCase.cuisine}:${normalizeText(testCase.text)}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function normalizeText(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}

function includesAnyKeyword(resultNames: string, keywords: string[]): boolean {
  return keywords.some((kw) => normalizeText(resultNames).includes(normalizeText(kw)));
}

function round(value: number, digits = 3): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

// ---------------------------------------------------------------------------
// Core eval runner
// ---------------------------------------------------------------------------

function casesForSet(caseSet: EvalCaseSet): GoldenCase[] {
  if (caseSet === 'golden') return GOLDEN_CASES;
  if (caseSet === 'exploration') return generatedExplorationCases();
  return dedupeCases([...GOLDEN_CASES, ...generatedExplorationCases()]);
}

function boundedCaseLimit(cacheMode: EvalCacheMode, requested: number, available: number): number {
  const maxAllowed = cacheMode === 'fresh' ? 75 : 500;
  return Math.max(1, Math.min(requested, available, maxAllowed));
}

export async function runGoldenSetEval(options: EvalRunOptions = {}): Promise<EvalRunResult> {
  const runStart = performance.now();
  const cases: EvalCaseResult[] = [];
  const byCategory: Record<string, { total: number; passed: number }> = {};
  const byRoute: Record<string, number> = {};
  const caseSet = options.caseSet ?? 'golden';
  const cacheMode = options.cacheMode ?? 'cached';
  const availableCases = casesForSet(caseSet);
  const requestedCases = options.maxCases ?? (caseSet === 'golden' ? GOLDEN_CASES.length : 50);
  const caseLimit = boundedCaseLimit(cacheMode, requestedCases, availableCases.length);
  const evalCases = availableCases.slice(0, caseLimit);
  const cacheScope = cacheMode === 'fresh'
    ? `eval:${caseSet}:${Date.now()}:${Math.random().toString(36).slice(2)}`
    : 'global';

  for (const testCase of evalCases) {
    const caseStart = performance.now();
    const benchmark = await resolveNutritionBenchmark(benchmarkForCase(testCase));

    let output;
    try {
      output = await runPrimaryParsePipeline(testCase.text, {
        allowFallback: true,
        cacheScope
      });
    } catch {
      // If the pipeline throws (e.g. no DB connection in eval env), record as failed
      cases.push({
        cuisine: testCase.cuisine,
        input: testCase.text,
        route: 'error',
        actualCalories: 0,
        expectedCaloriesMin: benchmark.range.min,
        expectedCaloriesMax: benchmark.range.max,
        benchmarkSource: benchmark.sourceLabel,
        benchmarkConfidence: benchmark.confidence,
        benchmarkNotes: benchmark.notes,
        benchmarkReference: benchmark.reference,
        detectedItems: '',
        passKeywords: false,
        passCalories: false,
        pass: false,
        confidence: 0,
        latencyMs: round(performance.now() - caseStart)
      });
      options.onProgress?.(cases.length, evalCases.length);
      continue;
    }

    const latencyMs = round(performance.now() - caseStart);
    const names = output.result.items.map((item) => item.name).join(' | ');
    const totalCalories = output.result.totals.calories;
    const passKeywords = includesAnyKeyword(names, testCase.expectedKeywords);
    const passCalories = totalCalories >= benchmark.range.min && totalCalories <= benchmark.range.max;
    const pass = passKeywords && passCalories;

    // Track by cuisine
    if (!byCategory[testCase.cuisine]) byCategory[testCase.cuisine] = { total: 0, passed: 0 };
    byCategory[testCase.cuisine].total++;
    if (pass) byCategory[testCase.cuisine].passed++;

    // Track by route
    byRoute[output.route] = (byRoute[output.route] ?? 0) + 1;

    cases.push({
      cuisine: testCase.cuisine,
      input: testCase.text,
      route: output.route,
      actualCalories: round(totalCalories),
      expectedCaloriesMin: benchmark.range.min,
      expectedCaloriesMax: benchmark.range.max,
      benchmarkSource: benchmark.sourceLabel,
      benchmarkConfidence: benchmark.confidence,
      benchmarkNotes: benchmark.notes,
      benchmarkReference: benchmark.reference,
      detectedItems: names,
      passKeywords,
      passCalories,
      pass,
      confidence: round(output.result.confidence),
      latencyMs
    });
    options.onProgress?.(cases.length, evalCases.length);
  }

  const passed = cases.filter((c) => c.pass).length;
  const failed = cases.length - passed;
  const durationMs = round(performance.now() - runStart);

  return {
    runType: `parse_${caseSet}_${cacheMode}`,
    caseSet,
    cacheMode,
    requestedCases,
    evaluatedCases: evalCases.length,
    totalCases: cases.length,
    passed,
    failed,
    passRate: cases.length > 0 ? round(passed / cases.length, 4) : 0,
    byCategory,
    byRoute,
    cases,
    durationMs
  };
}

// ---------------------------------------------------------------------------
// Persistence
// ---------------------------------------------------------------------------

export async function saveEvalRun(result: EvalRunResult, runType = 'golden_set'): Promise<string> {
  const { rows } = await pool.query<{ id: string }>(
    `INSERT INTO eval_runs (run_type, total_cases, passed, failed, pass_rate, duration_ms, results_json)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING id`,
    [
      runType,
      result.totalCases,
      result.passed,
      result.failed,
      result.passRate,
      Math.round(result.durationMs),
      JSON.stringify(result)
    ]
  );
  return rows[0]!.id;
}

export async function getEvalRunHistory(limit = 20): Promise<EvalRunSummary[]> {
  const { rows } = await pool.query<{
    id: string;
    run_type: string;
    run_at: Date;
    total_cases: number;
    passed: number;
    failed: number;
    pass_rate: number;
    duration_ms: number;
  }>(
    `SELECT id, run_type, run_at, total_cases, passed, failed, pass_rate, duration_ms
     FROM eval_runs
     ORDER BY run_at DESC
     LIMIT $1`,
    [limit]
  );

  return rows.map((r) => ({
    id: r.id,
    runType: r.run_type,
    runAt: r.run_at.toISOString(),
    totalCases: r.total_cases,
    passed: r.passed,
    failed: r.failed,
    passRate: r.pass_rate,
    durationMs: r.duration_ms
  }));
}

export async function getEvalRunById(id: string): Promise<EvalRunResult | null> {
  const { rows } = await pool.query<{ results_json: EvalRunResult }>(
    `SELECT results_json FROM eval_runs WHERE id = $1`,
    [id]
  );
  return rows[0]?.results_json ?? null;
}
