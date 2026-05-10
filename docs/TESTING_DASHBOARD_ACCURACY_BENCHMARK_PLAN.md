# Testing Dashboard Accuracy Benchmark Plan

Created: 2026-05-10

## Goal

Upgrade the existing testing dashboard `Benchmarks` tab into an end-to-end accuracy benchmark CMS.

The dashboard should let us create benchmark cases, store verified reference nutrition values, record MyFitnessPal comparison values, run Food App against the same cases, score both systems fairly, and publish a reviewed benchmark snapshot later for the marketing website.

The key principle:

> Reference nutrition values are the truth. Food App and MyFitnessPal are both compared against the same truth source.

## Current State

The dashboard already has:

- `Food Quality` eval runner
- `Benchmarks` tab with truth-source guidance
- `History` tab for saved eval runs
- `eval_runs` table storing full JSON results
- `nutritionBenchmarkService.ts` that can resolve calorie ranges from USDA, FatSecret, or curated fallback
- hardcoded golden/exploration eval cases in `evalService.ts`

Current gaps:

- benchmark cases are not editable in the dashboard
- macro reference values are not first-class
- MyFitnessPal values are not stored
- benchmark scoring is mostly pass/fail calorie-range based
- no published/public snapshot selection
- no workflow for reviewed cases versus draft cases

## Product Shape

The `Benchmarks` tab should become a working internal tool with four sections:

1. **Summary**
   - total active cases
   - reviewed cases
   - latest Food App score
   - latest MyFitnessPal score
   - category breakdown

2. **Benchmark Cases**
   - CRUD table for test cases
   - search/filter by category, status, source type, reviewed state
   - create/edit modal

3. **Run Benchmark**
   - run Food App parser against selected cases
   - use fresh or cached parsing
   - show progress
   - persist run results

4. **Published Snapshot**
   - select one reviewed run as the public website source
   - add public summary copy
   - choose visible categories
   - keep draft/internal runs hidden

## Data Model

### Migration: `benchmark_cases`

Stores the reviewed truth cases.

Recommended columns:

```sql
CREATE TABLE benchmark_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  input_text TEXT NOT NULL,
  display_name TEXT,
  category TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,

  reference_source_type TEXT NOT NULL,
  reference_source_label TEXT NOT NULL,
  reference_source_url TEXT,
  reference_notes TEXT,
  serving_notes TEXT,

  reference_calories NUMERIC NOT NULL,
  reference_protein NUMERIC NOT NULL DEFAULT 0,
  reference_carbs NUMERIC NOT NULL DEFAULT 0,
  reference_fat NUMERIC NOT NULL DEFAULT 0,
  reference_tolerance_pct NUMERIC NOT NULL DEFAULT 0.20,
  reference_min_tolerance_calories NUMERIC NOT NULL DEFAULT 15,

  mfp_item_name TEXT,
  mfp_calories NUMERIC,
  mfp_protein NUMERIC,
  mfp_carbs NUMERIC,
  mfp_fat NUMERIC,
  mfp_notes TEXT,
  mfp_collected_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Status values:

- `draft`
- `reviewed`
- `archived`

Reference source types:

- `usda`
- `official_restaurant`
- `official_brand`
- `curated_recipe`
- `curated_manual`

Categories:

- `simple`
- `restaurant`
- `branded`
- `homemade`
- `indian`
- `international`
- `typo`
- `portion`
- `ambiguous`

### Migration: `benchmark_runs`

Stores one run across many cases.

```sql
CREATE TABLE benchmark_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  run_label TEXT,
  parser_version TEXT,
  prompt_version TEXT,
  cache_mode TEXT NOT NULL DEFAULT 'cached',
  case_count INT NOT NULL DEFAULT 0,
  food_app_score NUMERIC NOT NULL DEFAULT 0,
  mfp_score NUMERIC,
  category_scores_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  summary_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Migration: `benchmark_run_results`

Stores one result per case.

```sql
CREATE TABLE benchmark_run_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL REFERENCES benchmark_runs(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES benchmark_cases(id) ON DELETE CASCADE,

  food_app_route TEXT,
  food_app_calories NUMERIC,
  food_app_protein NUMERIC,
  food_app_carbs NUMERIC,
  food_app_fat NUMERIC,
  food_app_items_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  food_app_explanation TEXT,
  food_app_confidence NUMERIC,

  calorie_score NUMERIC NOT NULL DEFAULT 0,
  protein_score NUMERIC NOT NULL DEFAULT 0,
  carbs_score NUMERIC NOT NULL DEFAULT 0,
  fat_score NUMERIC NOT NULL DEFAULT 0,
  food_app_overall_score NUMERIC NOT NULL DEFAULT 0,
  mfp_overall_score NUMERIC,

  result_label TEXT NOT NULL DEFAULT 'needs_review',
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Result labels:

- `strong`
- `reasonable`
- `needs_review`
- `failed`

### Migration: `benchmark_public_snapshots`

Stores the public-facing reviewed benchmark.

```sql
CREATE TABLE benchmark_public_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL REFERENCES benchmark_runs(id),
  title TEXT NOT NULL,
  summary TEXT NOT NULL,
  visible_categories TEXT[] NOT NULL DEFAULT '{}',
  is_active BOOLEAN NOT NULL DEFAULT FALSE,
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Only one snapshot should be active at a time.

## Scoring

Use the same scoring formula for Food App and MyFitnessPal.

```text
Overall score =
40% calories accuracy
25% protein accuracy
20% carbs accuracy
15% fat accuracy
```

Per-macro score:

```text
score = max(0, 100 * (1 - absolute_error_pct))
```

Example:

- reference calories: 400
- Food App calories: 350
- absolute error: 50
- absolute error pct: 12.5%
- calorie score: 87.5

Guardrails:

- If reference macro is 0, skip that macro or use a small floor to avoid divide-by-zero.
- Calories should always be scored.
- For homemade and ambiguous meals, keep tolerance notes visible because the reference itself is an estimate.

Result label:

- `strong`: overall score >= 90
- `reasonable`: overall score >= 75 and < 90
- `needs_review`: overall score >= 50 and < 75
- `failed`: overall score < 50 or parser error

## MyFitnessPal Collection Workflow

MyFitnessPal should be included as a comparison column, but it should not be treated as the truth.

Collection rules:

1. Search the exact benchmark input in MyFitnessPal.
2. Pick the top reasonable result a normal user would likely choose.
3. Store selected item name.
4. Store calories, protein, carbs, fat.
5. Add notes when the result is confusing, duplicated, branded incorrectly, or obviously wrong.

Important:

- Do not scrape or automate MyFitnessPal unless legal/terms review says it is okay.
- Start with manual collection for credibility and safety.
- Keep `mfp_collected_at` so we know when the comparison was last reviewed.

## Backend Work

### Services

Create `backend/src/services/benchmarkCaseService.ts`.

Responsibilities:

- list cases
- get case
- create case
- update case
- archive case
- validate reference/macro values
- compute per-system scores

Create `backend/src/services/accuracyBenchmarkRunService.ts`.

Responsibilities:

- load active/reviewed cases
- run Food App parser for selected cases
- compute Food App scores
- compute MyFitnessPal scores from stored MFP values
- persist run and result rows
- compute category summaries
- return run detail

Create `backend/src/services/benchmarkScoringService.ts`.

Responsibilities:

- pure scoring functions
- macro score handling
- result label logic
- unit tests

### Routes

Add to `backend/src/routes/evalDashboard.ts` or split into `backend/src/routes/benchmarks.ts`.

Recommended endpoints:

```text
GET    /v1/internal/dashboard/benchmark-cases
POST   /v1/internal/dashboard/benchmark-cases
GET    /v1/internal/dashboard/benchmark-cases/:id
PATCH  /v1/internal/dashboard/benchmark-cases/:id
DELETE /v1/internal/dashboard/benchmark-cases/:id

POST   /v1/internal/dashboard/benchmark-runs
GET    /v1/internal/dashboard/benchmark-runs
GET    /v1/internal/dashboard/benchmark-runs/:id

GET    /v1/internal/dashboard/benchmark-public-snapshot
POST   /v1/internal/dashboard/benchmark-public-snapshot
```

All internal routes require `x-internal-metrics-key`.

Later public website endpoint:

```text
GET /v1/public/accuracy-benchmark
```

This should only return the active public snapshot, not raw internal runs.

## Dashboard UI Work

### Benchmarks Tab Header

Rename from:

> Benchmark Truth Sources

To:

> Accuracy Benchmarks

Add summary cards:

- Active Cases
- Reviewed Cases
- Latest Food App Score
- Latest MyFitnessPal Score
- Last Run

### Case Table

Columns:

- Input
- Category
- Reference Source
- Reference Calories
- Reference Macros
- MyFitnessPal Calories
- Status
- Updated
- Actions

Actions:

- Edit
- Duplicate
- Archive
- Run this case

Filters:

- category
- status
- source type
- missing MFP
- missing macros

### Case Editor

Fields:

- Input text
- Display name
- Category
- Status
- Active toggle
- Serving notes
- Reference source type
- Reference source label
- Reference source URL
- Reference calories/protein/carbs/fat
- Reference notes
- MFP item name
- MFP calories/protein/carbs/fat
- MFP notes

Validation:

- calories required and > 0
- macros non-negative
- source type required
- source label required
- MFP fields optional, but dashboard should badge missing MFP comparison

### Run Panel

Controls:

- Run reviewed active cases
- Run selected category
- Run selected cases
- Cache mode: cached/fresh
- Max cases

Show:

- progress
- current case
- estimated cost warning when fresh mode may hit Gemini

### Run Result View

Summary:

- Food App score
- MyFitnessPal score
- Food App vs MFP delta
- cases run
- strong/reasonable/needs review/failed counts

Table:

- input
- category
- reference calories/macros
- Food App calories/macros
- MFP calories/macros
- Food App score
- MFP score
- label
- route
- explanation

### Public Snapshot Panel

Controls:

- select run
- enter public title
- enter public summary
- select visible categories
- publish snapshot

Safety:

- require confirmation before replacing active snapshot
- show last active snapshot

## Seed Cases

Start with 20-25 cases, then expand to 50-70 after the workflow feels good.

Initial categories:

### Simple

- 1 medium banana
- 2 large eggs
- 1 cup cooked white rice
- 6 oz grilled chicken breast
- 1 cup whole milk

### Restaurant / Branded

- McDonald's Big Mac
- Chick-fil-A original chicken sandwich
- Starbucks grande vanilla latte
- Chipotle chicken burrito bowl
- Subway 6 inch turkey breast sub

### Indian / International

- one bowl dal rice
- chicken tikka masala with naan
- paneer bhurji with two rotis
- dosa with sambar
- biryani one plate

### Homemade

- grilled cheese sandwich
- oatmeal with banana and honey
- scrambled eggs with toast
- peanut butter and jelly sandwich
- chicken stir fry with rice

### Typos / Messy Inputs

- chiken tenders
- cocnut water
- avacado toast with egg
- greek yogert with hunny
- one pl chaat papdi

### Portion

- 200g chicken breast grilled
- 50g rolled oats dry
- 2 tbsp honey
- 30g almonds
- 150g cooked brown rice

## Implementation Phases

### Phase 1: Database and Scoring Foundation

- Add migrations for cases, runs, run results, public snapshots.
- Add pure scoring service.
- Add unit tests for scoring.
- Add case CRUD service.

Acceptance:

- migrations run locally and in production
- scoring unit tests pass
- cases can be created/listed/updated through service tests or route smoke tests

### Phase 2: Internal Routes

- Add benchmark case CRUD routes.
- Add benchmark run routes.
- Add public snapshot internal routes.
- Add request validation with zod.

Acceptance:

- internal routes require dashboard key
- invalid nutrition values return clear errors
- run endpoint persists a run and per-case results

### Phase 3: Dashboard UI

- Replace current static Benchmarks tab with CMS UI.
- Add case table, filters, editor modal, and run panel.
- Add result detail view.
- Keep design consistent with existing dashboard tables/cards.

Acceptance:

- admin can add/edit benchmark cases without code changes
- admin can enter MyFitnessPal values manually
- admin can run Food App against reviewed cases
- scores render by case and by category

### Phase 4: Seed Dataset

- Add 20-25 initial reviewed benchmark cases.
- Enter reference values and source notes.
- Manually collect MyFitnessPal values.
- Run first benchmark.

Acceptance:

- first run shows Food App and MyFitnessPal scores
- weak cases are obvious
- results can guide prompt/parser fixes

### Phase 5: Publish Snapshot

- Add active public snapshot selection.
- Add internal preview.
- Add public API route later when website work begins.

Acceptance:

- one reviewed run can be marked public
- public snapshot is stable even when new internal runs happen

## Testing Plan

Backend:

- scoring service unit tests
- route auth tests
- CRUD validation tests
- benchmark run persistence test
- snapshot activation test

Dashboard:

- manual browser test for creating/editing cases
- run 1-3 cases in cached mode
- run reviewed seed set
- confirm table does not wrap or overflow badly
- confirm missing MFP values are visible

Release:

- `npm run build`
- `npm test`
- `npm run preflight:release`
- run migration before relying on production routes

## Risks and Decisions

### Risk: MyFitnessPal Data Collection

Manual entry is safest for now. Avoid scraping unless we review terms and decide it is acceptable.

### Risk: Reference Values for Homemade Foods

Homemade food references are estimates. Mark these as curated and show notes/tolerance.

### Risk: Public Score Can Fluctuate

Do not auto-publish latest run. Use reviewed public snapshots.

### Risk: Cost From Fresh Runs

Fresh benchmark runs may hit Gemini. Dashboard should make this visible before running.

## Recommended Next Build Order

1. Build database tables and scoring service.
2. Build benchmark case CRUD routes.
3. Build dashboard case table/editor.
4. Seed 20-25 benchmark cases.
5. Add run endpoint and result UI.
6. Add MyFitnessPal score comparison.
7. Add public snapshot controls.

This order lets us start managing truth data before spending time on public website design.
