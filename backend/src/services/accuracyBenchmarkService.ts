import { config } from '../config.js';
import { pool } from '../db.js';
import { runPrimaryParsePipeline } from './parsePipelineService.js';
import { scoreNutrition, type BenchmarkScores, type NutritionValues } from './benchmarkScoringService.js';

export type BenchmarkCaseStatus = 'draft' | 'reviewed' | 'archived';
export type BenchmarkCacheMode = 'cached' | 'fresh';

export type BenchmarkCaseInput = {
  inputText: string;
  displayName: string | null;
  category: string;
  status: BenchmarkCaseStatus;
  isActive: boolean;
  referenceSourceType: string;
  referenceSourceLabel: string;
  referenceSourceUrl: string | null;
  referenceNotes: string | null;
  servingNotes: string | null;
  referenceCalories: number;
  referenceProtein: number;
  referenceCarbs: number;
  referenceFat: number;
  referenceTolerancePct: number;
  referenceMinToleranceCalories: number;
  mfpItemName: string | null;
  mfpCalories: number | null;
  mfpProtein: number | null;
  mfpCarbs: number | null;
  mfpFat: number | null;
  mfpNotes: string | null;
  mfpCollectedAt: string | null;
};

export type BenchmarkCase = BenchmarkCaseInput & {
  id: string;
  createdAt: string;
  updatedAt: string;
};

export type BenchmarkRunOptions = {
  caseIds?: string[];
  category?: string | null;
  cacheMode: BenchmarkCacheMode;
  maxCases?: number;
  runLabel?: string | null;
};

export type BenchmarkRunSummary = {
  id: string;
  runAt: string;
  runLabel: string | null;
  parserVersion: string | null;
  promptVersion: string | null;
  cacheMode: BenchmarkCacheMode;
  caseCount: number;
  foodAppScore: number;
  mfpScore: number | null;
  categoryScores: unknown;
  summary: unknown;
  createdAt: string;
};

export type BenchmarkRunResult = {
  id: string;
  runId: string;
  caseId: string;
  case?: BenchmarkCase;
  foodAppRoute: string | null;
  foodAppCalories: number | null;
  foodAppProtein: number | null;
  foodAppCarbs: number | null;
  foodAppFat: number | null;
  foodAppItems: unknown[];
  foodAppExplanation: string | null;
  foodAppConfidence: number | null;
  calorieScore: number;
  proteinScore: number;
  carbsScore: number;
  fatScore: number;
  foodAppOverallScore: number;
  mfpOverallScore: number | null;
  resultLabel: BenchmarkScores['label'];
  error: string | null;
  createdAt: string;
};

export type BenchmarkPublicSnapshotInput = {
  runId: string;
  title: string;
  summary: string;
  visibleCategories: string[];
  isActive: boolean;
};

export type BenchmarkPublicSnapshot = BenchmarkPublicSnapshotInput & {
  id: string;
  publishedAt: string | null;
  createdAt: string;
};

type DbBenchmarkCase = {
  id: string;
  input_text: string;
  display_name: string | null;
  category: string;
  status: BenchmarkCaseStatus;
  is_active: boolean;
  reference_source_type: string;
  reference_source_label: string;
  reference_source_url: string | null;
  reference_notes: string | null;
  serving_notes: string | null;
  reference_calories: string | number;
  reference_protein: string | number;
  reference_carbs: string | number;
  reference_fat: string | number;
  reference_tolerance_pct: string | number;
  reference_min_tolerance_calories: string | number;
  mfp_item_name: string | null;
  mfp_calories: string | number | null;
  mfp_protein: string | number | null;
  mfp_carbs: string | number | null;
  mfp_fat: string | number | null;
  mfp_notes: string | null;
  mfp_collected_at: Date | null;
  created_at: Date;
  updated_at: Date;
};

type DbBenchmarkRun = {
  id: string;
  run_at: Date;
  run_label: string | null;
  parser_version: string | null;
  prompt_version: string | null;
  cache_mode: BenchmarkCacheMode;
  case_count: number;
  food_app_score: string | number;
  mfp_score: string | number | null;
  category_scores_json: unknown;
  summary_json: unknown;
  created_at: Date;
};

type DbBenchmarkRunResult = {
  id: string;
  run_id: string;
  case_id: string;
  food_app_route: string | null;
  food_app_calories: string | number | null;
  food_app_protein: string | number | null;
  food_app_carbs: string | number | null;
  food_app_fat: string | number | null;
  food_app_items_json: unknown;
  food_app_explanation: string | null;
  food_app_confidence: string | number | null;
  calorie_score: string | number;
  protein_score: string | number;
  carbs_score: string | number;
  fat_score: string | number;
  food_app_overall_score: string | number;
  mfp_overall_score: string | number | null;
  result_label: BenchmarkScores['label'];
  error: string | null;
  created_at: Date;
};

type DbBenchmarkRunResultWithCase = DbBenchmarkRunResult & {
  case_input_text: string;
  case_display_name: string | null;
  case_category: string;
  case_status: BenchmarkCaseStatus;
  case_is_active: boolean;
  case_reference_source_type: string;
  case_reference_source_label: string;
  case_reference_source_url: string | null;
  case_reference_notes: string | null;
  case_serving_notes: string | null;
  case_reference_calories: string | number;
  case_reference_protein: string | number;
  case_reference_carbs: string | number;
  case_reference_fat: string | number;
  case_reference_tolerance_pct: string | number;
  case_reference_min_tolerance_calories: string | number;
  case_mfp_item_name: string | null;
  case_mfp_calories: string | number | null;
  case_mfp_protein: string | number | null;
  case_mfp_carbs: string | number | null;
  case_mfp_fat: string | number | null;
  case_mfp_notes: string | null;
  case_mfp_collected_at: Date | null;
  case_created_at: Date;
  case_updated_at: Date;
};

type DbBenchmarkPublicSnapshot = {
  id: string;
  run_id: string;
  title: string;
  summary: string;
  visible_categories: string[];
  is_active: boolean;
  published_at: Date | null;
  created_at: Date;
};

const caseSelect = `
  SELECT id, input_text, display_name, category, status, is_active,
         reference_source_type, reference_source_label, reference_source_url,
         reference_notes, serving_notes, reference_calories, reference_protein,
         reference_carbs, reference_fat, reference_tolerance_pct,
         reference_min_tolerance_calories, mfp_item_name, mfp_calories,
         mfp_protein, mfp_carbs, mfp_fat, mfp_notes, mfp_collected_at,
         created_at, updated_at
  FROM benchmark_cases
`;

function num(value: string | number | null | undefined): number | null {
  if (value === null || value === undefined) return null;
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : null;
}

function round(value: number, digits = 1): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function mapCase(row: DbBenchmarkCase): BenchmarkCase {
  return {
    id: row.id,
    inputText: row.input_text,
    displayName: row.display_name,
    category: row.category,
    status: row.status,
    isActive: row.is_active,
    referenceSourceType: row.reference_source_type,
    referenceSourceLabel: row.reference_source_label,
    referenceSourceUrl: row.reference_source_url,
    referenceNotes: row.reference_notes,
    servingNotes: row.serving_notes,
    referenceCalories: num(row.reference_calories) ?? 0,
    referenceProtein: num(row.reference_protein) ?? 0,
    referenceCarbs: num(row.reference_carbs) ?? 0,
    referenceFat: num(row.reference_fat) ?? 0,
    referenceTolerancePct: num(row.reference_tolerance_pct) ?? 0.2,
    referenceMinToleranceCalories: num(row.reference_min_tolerance_calories) ?? 15,
    mfpItemName: row.mfp_item_name,
    mfpCalories: num(row.mfp_calories),
    mfpProtein: num(row.mfp_protein),
    mfpCarbs: num(row.mfp_carbs),
    mfpFat: num(row.mfp_fat),
    mfpNotes: row.mfp_notes,
    mfpCollectedAt: row.mfp_collected_at ? row.mfp_collected_at.toISOString() : null,
    createdAt: row.created_at.toISOString(),
    updatedAt: row.updated_at.toISOString()
  };
}

function mapRun(row: DbBenchmarkRun): BenchmarkRunSummary {
  return {
    id: row.id,
    runAt: row.run_at.toISOString(),
    runLabel: row.run_label,
    parserVersion: row.parser_version,
    promptVersion: row.prompt_version,
    cacheMode: row.cache_mode,
    caseCount: row.case_count,
    foodAppScore: num(row.food_app_score) ?? 0,
    mfpScore: num(row.mfp_score),
    categoryScores: row.category_scores_json,
    summary: row.summary_json,
    createdAt: row.created_at.toISOString()
  };
}

function mapResult(row: DbBenchmarkRunResult, benchmarkCase?: BenchmarkCase): BenchmarkRunResult {
  return {
    id: row.id,
    runId: row.run_id,
    caseId: row.case_id,
    case: benchmarkCase,
    foodAppRoute: row.food_app_route,
    foodAppCalories: num(row.food_app_calories),
    foodAppProtein: num(row.food_app_protein),
    foodAppCarbs: num(row.food_app_carbs),
    foodAppFat: num(row.food_app_fat),
    foodAppItems: Array.isArray(row.food_app_items_json) ? row.food_app_items_json : [],
    foodAppExplanation: row.food_app_explanation,
    foodAppConfidence: num(row.food_app_confidence),
    calorieScore: num(row.calorie_score) ?? 0,
    proteinScore: num(row.protein_score) ?? 0,
    carbsScore: num(row.carbs_score) ?? 0,
    fatScore: num(row.fat_score) ?? 0,
    foodAppOverallScore: num(row.food_app_overall_score) ?? 0,
    mfpOverallScore: num(row.mfp_overall_score),
    resultLabel: row.result_label,
    error: row.error,
    createdAt: row.created_at.toISOString()
  };
}

function mapSnapshot(row: DbBenchmarkPublicSnapshot): BenchmarkPublicSnapshot {
  return {
    id: row.id,
    runId: row.run_id,
    title: row.title,
    summary: row.summary,
    visibleCategories: row.visible_categories ?? [],
    isActive: row.is_active,
    publishedAt: row.published_at ? row.published_at.toISOString() : null,
    createdAt: row.created_at.toISOString()
  };
}

function referenceValues(benchmarkCase: BenchmarkCase): NutritionValues {
  return {
    calories: benchmarkCase.referenceCalories,
    protein: benchmarkCase.referenceProtein,
    carbs: benchmarkCase.referenceCarbs,
    fat: benchmarkCase.referenceFat
  };
}

function mfpValues(benchmarkCase: BenchmarkCase): NutritionValues | null {
  if (benchmarkCase.mfpCalories === null) return null;
  return {
    calories: benchmarkCase.mfpCalories,
    protein: benchmarkCase.mfpProtein ?? 0,
    carbs: benchmarkCase.mfpCarbs ?? 0,
    fat: benchmarkCase.mfpFat ?? 0
  };
}

function average(values: number[]): number | null {
  if (!values.length) return null;
  return round(values.reduce((sum, value) => sum + value, 0) / values.length);
}

function summarizeResults(cases: BenchmarkCase[], results: BenchmarkRunResult[]) {
  const byCategory: Record<string, { count: number; foodAppScore: number; mfpScore: number | null }> = {};
  for (const result of results) {
    const benchmarkCase = cases.find((item) => item.id === result.caseId);
    const category = benchmarkCase?.category ?? 'unknown';
    const existing = byCategory[category] ?? { count: 0, foodAppTotal: 0, mfpScores: [] as number[] };
    existing.count += 1;
    (existing as typeof existing & { foodAppTotal: number; mfpScores: number[] }).foodAppTotal += result.foodAppOverallScore;
    if (result.mfpOverallScore !== null) {
      (existing as typeof existing & { foodAppTotal: number; mfpScores: number[] }).mfpScores.push(result.mfpOverallScore);
    }
    byCategory[category] = existing;
  }

  const categoryScores = Object.fromEntries(
    Object.entries(byCategory).map(([category, value]) => {
      const internal = value as typeof value & { foodAppTotal: number; mfpScores: number[] };
      return [
        category,
        {
          count: value.count,
          foodAppScore: round(internal.foodAppTotal / value.count),
          mfpScore: average(internal.mfpScores)
        }
      ];
    })
  );

  const labels = results.reduce<Record<string, number>>((acc, result) => {
    acc[result.resultLabel] = (acc[result.resultLabel] ?? 0) + 1;
    return acc;
  }, {});

  return {
    categoryScores,
    summary: {
      labels,
      missingMfp: cases.filter((benchmarkCase) => benchmarkCase.mfpCalories === null).length,
      parserErrors: results.filter((result) => result.error).length
    }
  };
}

export async function listBenchmarkCases(filters: {
  status?: BenchmarkCaseStatus;
  category?: string;
  activeOnly?: boolean;
} = {}): Promise<BenchmarkCase[]> {
  const where: string[] = [];
  const params: unknown[] = [];
  if (filters.status) {
    params.push(filters.status);
    where.push(`status = $${params.length}`);
  }
  if (filters.category) {
    params.push(filters.category);
    where.push(`category = $${params.length}`);
  }
  if (filters.activeOnly) where.push('is_active = TRUE');

  const result = await pool.query<DbBenchmarkCase>(
    `
    ${caseSelect}
    ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
    ORDER BY is_active DESC, status = 'reviewed' DESC, category ASC, updated_at DESC
    `,
    params
  );
  return result.rows.map(mapCase);
}

export async function getBenchmarkCase(id: string): Promise<BenchmarkCase | null> {
  const result = await pool.query<DbBenchmarkCase>(`${caseSelect} WHERE id = $1`, [id]);
  return result.rows[0] ? mapCase(result.rows[0]) : null;
}

export async function createBenchmarkCase(input: BenchmarkCaseInput): Promise<BenchmarkCase> {
  const result = await pool.query<{ id: string }>(
    `
    INSERT INTO benchmark_cases (
      input_text, display_name, category, status, is_active,
      reference_source_type, reference_source_label, reference_source_url,
      reference_notes, serving_notes, reference_calories, reference_protein,
      reference_carbs, reference_fat, reference_tolerance_pct,
      reference_min_tolerance_calories, mfp_item_name, mfp_calories,
      mfp_protein, mfp_carbs, mfp_fat, mfp_notes, mfp_collected_at
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23)
    RETURNING id
    `,
    [
      input.inputText,
      input.displayName,
      input.category,
      input.status,
      input.isActive,
      input.referenceSourceType,
      input.referenceSourceLabel,
      input.referenceSourceUrl,
      input.referenceNotes,
      input.servingNotes,
      input.referenceCalories,
      input.referenceProtein,
      input.referenceCarbs,
      input.referenceFat,
      input.referenceTolerancePct,
      input.referenceMinToleranceCalories,
      input.mfpItemName,
      input.mfpCalories,
      input.mfpProtein,
      input.mfpCarbs,
      input.mfpFat,
      input.mfpNotes,
      input.mfpCollectedAt
    ]
  );
  return (await getBenchmarkCase(result.rows[0]!.id))!;
}

export async function updateBenchmarkCase(id: string, input: BenchmarkCaseInput): Promise<BenchmarkCase | null> {
  const result = await pool.query<{ id: string }>(
    `
    UPDATE benchmark_cases
    SET input_text = $2,
        display_name = $3,
        category = $4,
        status = $5,
        is_active = $6,
        reference_source_type = $7,
        reference_source_label = $8,
        reference_source_url = $9,
        reference_notes = $10,
        serving_notes = $11,
        reference_calories = $12,
        reference_protein = $13,
        reference_carbs = $14,
        reference_fat = $15,
        reference_tolerance_pct = $16,
        reference_min_tolerance_calories = $17,
        mfp_item_name = $18,
        mfp_calories = $19,
        mfp_protein = $20,
        mfp_carbs = $21,
        mfp_fat = $22,
        mfp_notes = $23,
        mfp_collected_at = $24,
        updated_at = NOW()
    WHERE id = $1
    RETURNING id
    `,
    [
      id,
      input.inputText,
      input.displayName,
      input.category,
      input.status,
      input.isActive,
      input.referenceSourceType,
      input.referenceSourceLabel,
      input.referenceSourceUrl,
      input.referenceNotes,
      input.servingNotes,
      input.referenceCalories,
      input.referenceProtein,
      input.referenceCarbs,
      input.referenceFat,
      input.referenceTolerancePct,
      input.referenceMinToleranceCalories,
      input.mfpItemName,
      input.mfpCalories,
      input.mfpProtein,
      input.mfpCarbs,
      input.mfpFat,
      input.mfpNotes,
      input.mfpCollectedAt
    ]
  );
  if ((result.rowCount ?? 0) === 0) return null;
  return getBenchmarkCase(id);
}

export async function archiveBenchmarkCase(id: string): Promise<boolean> {
  const result = await pool.query(
    `UPDATE benchmark_cases SET status = 'archived', is_active = FALSE, updated_at = NOW() WHERE id = $1`,
    [id]
  );
  return (result.rowCount ?? 0) > 0;
}

async function selectCasesForRun(options: BenchmarkRunOptions): Promise<BenchmarkCase[]> {
  const params: unknown[] = [];
  const where = ['is_active = TRUE', "status = 'reviewed'"];
  if (options.caseIds?.length) {
    params.push(options.caseIds);
    where.push(`id = ANY($${params.length}::uuid[])`);
  }
  if (options.category) {
    params.push(options.category);
    where.push(`category = $${params.length}`);
  }
  params.push(Math.max(1, Math.min(options.maxCases ?? 25, 100)));
  const result = await pool.query<DbBenchmarkCase>(
    `
    ${caseSelect}
    WHERE ${where.join(' AND ')}
    ORDER BY category ASC, updated_at DESC
    LIMIT $${params.length}
    `,
    params
  );
  return result.rows.map(mapCase);
}

function explanationFromItems(items: Array<{ explanation?: string; foodDescription?: string; name?: string }>): string | null {
  const explanation = items
    .map((item) => item.explanation || item.foodDescription || item.name)
    .filter(Boolean)
    .slice(0, 3)
    .join(' ');
  return explanation || null;
}

async function insertRunResult(
  runId: string,
  benchmarkCase: BenchmarkCase,
  values: NutritionValues,
  route: string | null,
  items: unknown[],
  explanation: string | null,
  confidence: number | null,
  scores: BenchmarkScores,
  mfpScore: number | null,
  error: string | null
): Promise<BenchmarkRunResult> {
  const result = await pool.query<DbBenchmarkRunResult>(
    `
    INSERT INTO benchmark_run_results (
      run_id, case_id, food_app_route, food_app_calories, food_app_protein,
      food_app_carbs, food_app_fat, food_app_items_json, food_app_explanation,
      food_app_confidence, calorie_score, protein_score, carbs_score, fat_score,
      food_app_overall_score, mfp_overall_score, result_label, error
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18)
    RETURNING id, run_id, case_id, food_app_route, food_app_calories,
              food_app_protein, food_app_carbs, food_app_fat, food_app_items_json,
              food_app_explanation, food_app_confidence, calorie_score,
              protein_score, carbs_score, fat_score, food_app_overall_score,
              mfp_overall_score, result_label, error, created_at
    `,
    [
      runId,
      benchmarkCase.id,
      route,
      values.calories,
      values.protein,
      values.carbs,
      values.fat,
      JSON.stringify(items),
      explanation,
      confidence,
      scores.calories,
      scores.protein,
      scores.carbs,
      scores.fat,
      scores.overall,
      mfpScore,
      scores.label,
      error
    ]
  );
  return mapResult(result.rows[0]!, benchmarkCase);
}

export async function runAccuracyBenchmark(options: BenchmarkRunOptions): Promise<{
  run: BenchmarkRunSummary;
  results: BenchmarkRunResult[];
}> {
  const cases = await selectCasesForRun(options);
  const runResult = await pool.query<{ id: string }>(
    `
    INSERT INTO benchmark_runs (run_label, parser_version, prompt_version, cache_mode)
    VALUES ($1,$2,$3,$4)
    RETURNING id
    `,
    [
      options.runLabel || null,
      config.aiFallbackModelName || config.geminiFlashModel || null,
      config.parsePromptVersion || null,
      options.cacheMode
    ]
  );
  const runId = runResult.rows[0]!.id;
  const results: BenchmarkRunResult[] = [];
  const cacheScope = options.cacheMode === 'fresh'
    ? `benchmark:${runId}`
    : 'global';

  for (const benchmarkCase of cases) {
    const reference = referenceValues(benchmarkCase);
    const mfp = mfpValues(benchmarkCase);
    const mfpScore = mfp ? scoreNutrition(reference, mfp).overall : null;
    try {
      const output = await runPrimaryParsePipeline(benchmarkCase.inputText, {
        allowFallback: true,
        cacheScope,
        userId: 'benchmark-runner'
      });
      const totals = output.result.totals;
      const values = {
        calories: totals.calories,
        protein: totals.protein,
        carbs: totals.carbs,
        fat: totals.fat
      };
      const scores = scoreNutrition(reference, values);
      const items = output.result.items;
      results.push(
        await insertRunResult(
          runId,
          benchmarkCase,
          values,
          output.route,
          items,
          explanationFromItems(items),
          output.result.confidence,
          scores,
          mfpScore,
          null
        )
      );
    } catch (err) {
      const scores = scoreNutrition(reference, { calories: null, protein: null, carbs: null, fat: null }, { hasError: true });
      results.push(
        await insertRunResult(
          runId,
          benchmarkCase,
          { calories: null, protein: null, carbs: null, fat: null },
          'error',
          [],
          null,
          null,
          scores,
          mfpScore,
          err instanceof Error ? err.message : String(err)
        )
      );
    }
  }

  const foodAppScore = average(results.map((result) => result.foodAppOverallScore)) ?? 0;
  const mfpScore = average(results.map((result) => result.mfpOverallScore).filter((value): value is number => value !== null));
  const { categoryScores, summary } = summarizeResults(cases, results);

  await pool.query(
    `
    UPDATE benchmark_runs
    SET case_count = $2,
        food_app_score = $3,
        mfp_score = $4,
        category_scores_json = $5,
        summary_json = $6
    WHERE id = $1
    `,
    [runId, cases.length, foodAppScore, mfpScore, JSON.stringify(categoryScores), JSON.stringify(summary)]
  );

  return { run: (await getBenchmarkRun(runId))!.run, results };
}

export async function listBenchmarkRuns(limit = 20): Promise<BenchmarkRunSummary[]> {
  const result = await pool.query<DbBenchmarkRun>(
    `
    SELECT id, run_at, run_label, parser_version, prompt_version, cache_mode,
           case_count, food_app_score, mfp_score, category_scores_json,
           summary_json, created_at
    FROM benchmark_runs
    ORDER BY run_at DESC
    LIMIT $1
    `,
    [limit]
  );
  return result.rows.map(mapRun);
}

export async function getBenchmarkRun(id: string): Promise<{ run: BenchmarkRunSummary; results: BenchmarkRunResult[] } | null> {
  const runResult = await pool.query<DbBenchmarkRun>(
    `
    SELECT id, run_at, run_label, parser_version, prompt_version, cache_mode,
           case_count, food_app_score, mfp_score, category_scores_json,
           summary_json, created_at
    FROM benchmark_runs
    WHERE id = $1
    `,
    [id]
  );
  if (!runResult.rows[0]) return null;

  const resultRows = await pool.query<DbBenchmarkRunResultWithCase>(
    `
    SELECT r.id, r.run_id, r.case_id, r.food_app_route, r.food_app_calories,
           r.food_app_protein, r.food_app_carbs, r.food_app_fat,
           r.food_app_items_json, r.food_app_explanation, r.food_app_confidence,
           r.calorie_score, r.protein_score, r.carbs_score, r.fat_score,
           r.food_app_overall_score, r.mfp_overall_score, r.result_label,
           r.error, r.created_at,
           c.input_text AS case_input_text,
           c.display_name AS case_display_name,
           c.category AS case_category,
           c.status AS case_status,
           c.is_active AS case_is_active,
           c.reference_source_type AS case_reference_source_type,
           c.reference_source_label AS case_reference_source_label,
           c.reference_source_url AS case_reference_source_url,
           c.reference_notes AS case_reference_notes,
           c.serving_notes AS case_serving_notes,
           c.reference_calories AS case_reference_calories,
           c.reference_protein AS case_reference_protein,
           c.reference_carbs AS case_reference_carbs,
           c.reference_fat AS case_reference_fat,
           c.reference_tolerance_pct AS case_reference_tolerance_pct,
           c.reference_min_tolerance_calories AS case_reference_min_tolerance_calories,
           c.mfp_item_name AS case_mfp_item_name,
           c.mfp_calories AS case_mfp_calories,
           c.mfp_protein AS case_mfp_protein,
           c.mfp_carbs AS case_mfp_carbs,
           c.mfp_fat AS case_mfp_fat,
           c.mfp_notes AS case_mfp_notes,
           c.mfp_collected_at AS case_mfp_collected_at,
           c.created_at AS case_created_at,
           c.updated_at AS case_updated_at
    FROM benchmark_run_results r
    JOIN benchmark_cases c ON c.id = r.case_id
    WHERE r.run_id = $1
    ORDER BY c.category ASC, c.input_text ASC
    `,
    [id]
  );

  const results = resultRows.rows.map((row) => {
    const caseRow: DbBenchmarkCase = {
      id: row.case_id,
      input_text: row.case_input_text,
      display_name: row.case_display_name,
      category: row.case_category,
      status: row.case_status,
      is_active: row.case_is_active,
      reference_source_type: row.case_reference_source_type,
      reference_source_label: row.case_reference_source_label,
      reference_source_url: row.case_reference_source_url,
      reference_notes: row.case_reference_notes,
      serving_notes: row.case_serving_notes,
      reference_calories: row.case_reference_calories,
      reference_protein: row.case_reference_protein,
      reference_carbs: row.case_reference_carbs,
      reference_fat: row.case_reference_fat,
      reference_tolerance_pct: row.case_reference_tolerance_pct,
      reference_min_tolerance_calories: row.case_reference_min_tolerance_calories,
      mfp_item_name: row.case_mfp_item_name,
      mfp_calories: row.case_mfp_calories,
      mfp_protein: row.case_mfp_protein,
      mfp_carbs: row.case_mfp_carbs,
      mfp_fat: row.case_mfp_fat,
      mfp_notes: row.case_mfp_notes,
      mfp_collected_at: row.case_mfp_collected_at,
      created_at: row.case_created_at,
      updated_at: row.case_updated_at
    };
    return mapResult(row, mapCase(caseRow));
  });
  return { run: mapRun(runResult.rows[0]), results };
}

export async function getBenchmarkDashboardSummary(): Promise<{
  activeCases: number;
  reviewedCases: number;
  latestRun: BenchmarkRunSummary | null;
}> {
  const [caseCounts, runs] = await Promise.all([
    pool.query<{ active_cases: string; reviewed_cases: string }>(
      `
      SELECT
        COUNT(*) FILTER (WHERE is_active = TRUE)::text AS active_cases,
        COUNT(*) FILTER (WHERE is_active = TRUE AND status = 'reviewed')::text AS reviewed_cases
      FROM benchmark_cases
      `
    ),
    listBenchmarkRuns(1)
  ]);
  return {
    activeCases: Number(caseCounts.rows[0]?.active_cases ?? 0),
    reviewedCases: Number(caseCounts.rows[0]?.reviewed_cases ?? 0),
    latestRun: runs[0] ?? null
  };
}

export async function getBenchmarkPublicSnapshot(): Promise<BenchmarkPublicSnapshot | null> {
  const result = await pool.query<DbBenchmarkPublicSnapshot>(
    `
    SELECT id, run_id, title, summary, visible_categories, is_active, published_at, created_at
    FROM benchmark_public_snapshots
    WHERE is_active = TRUE
    ORDER BY published_at DESC NULLS LAST, created_at DESC
    LIMIT 1
    `
  );
  return result.rows[0] ? mapSnapshot(result.rows[0]) : null;
}

export async function createBenchmarkPublicSnapshot(
  input: BenchmarkPublicSnapshotInput
): Promise<BenchmarkPublicSnapshot> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (input.isActive) {
      await client.query(`UPDATE benchmark_public_snapshots SET is_active = FALSE WHERE is_active = TRUE`);
    }
    const result = await client.query<DbBenchmarkPublicSnapshot>(
      `
      INSERT INTO benchmark_public_snapshots (
        run_id, title, summary, visible_categories, is_active, published_at
      )
      VALUES ($1,$2,$3,$4,$5,$6)
      RETURNING id, run_id, title, summary, visible_categories, is_active, published_at, created_at
      `,
      [
        input.runId,
        input.title,
        input.summary,
        input.visibleCategories,
        input.isActive,
        input.isActive ? new Date() : null
      ]
    );
    await client.query('COMMIT');
    return mapSnapshot(result.rows[0]!);
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
