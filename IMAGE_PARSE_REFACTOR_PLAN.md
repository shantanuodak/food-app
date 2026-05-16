# Image Parse Refactor Plan

## Current Diagnosis

The image parser is failing because the system is being patched one prompt at a time instead of having a clear image parsing architecture.

The main issue is not only Gemini, image compression, or one bad prompt. The current flow has three structural problems:

1. The backend image parser is doing too many jobs in one file.
2. The parser has no explicit inventory/coverage contract for multi-item meals.
3. Phone failures are not fully joined to server-side Gemini stages, so debugging depends on guesses.

## Current End-to-End Flow

### iOS

1. User selects or captures a food image.
2. `MainLoggingImagePayloadFlow.swift` compresses the image to JPEG.
3. Drawer images use `MainLoggingCameraDrawerFlow.swift`.
4. Quick camera widget images use `QuickCameraLoggingService.swift`.
5. Both paths call `APIClient.parseImageLog`.
6. The app records client telemetry separately through `ImageParseAttemptTelemetry`.

### Backend

1. `/v1/logs/parse/image` validates auth, rate limits, MIME type, image size, and `loggedAt`.
2. The route calls `parseImageWithGemini`.
3. `imageParseService.ts` tries:
   - structured image nutrition JSON
   - caption fallback
   - caption-to-text nutrition parse
   - structured rescue
   - low-confidence acceptance
4. The route writes AI cost events.
5. The route creates a parse request.
6. The route returns items, totals, confidence, and image metadata.

## What Is Brittle Today

### 1. `imageParseService.ts` Is Too Large

The file currently owns:

- Gemini multimodal calls
- prompt text
- JSON extraction
- tolerant schema normalization
- fallback strategy ordering
- low-confidence acceptance
- usage/cost event construction
- debug event construction

That makes every fix risky because prompt changes, fallback ordering, and response normalization are coupled.

### 2. The Parser Does Not Know Image Type First

A packaged nutrition label, a single makhana bowl, a thali, a dosa tray, and a restaurant plate are all handled by the same broad prompt.

The parser should first classify the image:

- `nutrition_label`
- `single_food`
- `multi_component_meal`
- `tray_or_thali`
- `menu_or_screenshot`
- `non_food`
- `unclear`

Then it should choose the right strategy.

### 3. Multi-Item Meals Need Coverage Scoring

For a thali/tray, a result like `dal, green chutney` is not a success. It is a partial parse.

The backend needs to know:

- How many visible components were detected.
- How many components received nutrition.
- Whether small sides/condiments were included.
- Whether the result is complete enough to show as confident.

### 4. Phone Route and Internal Test Route Are Not Equivalent

The internal image test route is useful, but it bypasses parts of the authenticated app route.

That means:

- Internal tests can pass while the phone says "try again."
- Phone failures may not include server-side Gemini stage details.
- Dashboard rows can show a failure without explaining which stage failed.

### 5. Fallback Latency Is Too Sequential

The current chain can spend 18-40 seconds trying multiple model calls. That is too close to app UX failure territory.

We need bounded strategy budgets:

- Fast inventory first.
- Nutrition from inventory second.
- Rescue only when it is likely to improve coverage.
- Avoid repeated slow Pro calls when Pro is returning no response.

## Phase 1: Request Joining and Diagnostics

Status: partially implemented.

Goal: make every phone image attempt traceable end to end.

Implemented:

- iOS now sends `clientAttemptId` in `/v1/logs/parse/image`.
- Backend accepts `clientAttemptId` on image parse requests.
- Backend records server-side attempt metadata for success and failure.
- Backend records Gemini debug stages into `image_parse_attempts.metadata_json`.
- Attempt metadata is merged instead of overwritten when client telemetry arrives later.
- Testing dashboard now exposes a `Stages` column for recent image attempts.

Expected result:

- If the phone says "try again," the dashboard should show which server stage failed.
- We should stop guessing whether the failure was upload, route validation, Gemini no-response, invalid JSON, budget/cost accounting, or a client timeout.

## Phase 2: Backend Module Extraction

Goal: split `imageParseService.ts` without changing behavior.

Create:

- `backend/src/services/imageParse/types.ts`
- `backend/src/services/imageParse/jsonRepair.ts`
- `backend/src/services/imageParse/prompts.ts`
- `backend/src/services/imageParse/geminiImageClient.ts`
- `backend/src/services/imageParse/normalizers.ts`
- `backend/src/services/imageParse/diagnostics.ts`
- `backend/src/services/imageParse/orchestratorV1.ts`

Keep:

- Existing response shape.
- Existing tests.
- Existing feature flags.

Success criteria:

- `npm test -- imageParseService.unit.test.ts` passes.
- `npm run build` passes.
- No production behavior change except cleaner internals.

## Phase 3: Inventory-First V2 Orchestrator

Status: started.

Goal: stop asking Gemini for final nutrition before we know what foods are visible.

Implemented:

- Added `AI_IMAGE_ORCHESTRATOR_VERSION=v1|v2`.
- Added `AI_IMAGE_INVENTORY_MODEL` so V2 can use Gemini Flash even if V1 uses another image model.
- Added `AI_IMAGE_FAST_TIMEOUT_MS`.
- Added `AI_IMAGE_COVERAGE_MIN`.
- Added a single-call V2 image inventory + nutrition parser.
- Added global cuisine guidance for US/Western, India/subcontinent, Chinese/East Asian, Italian/Mediterranean, and other common cuisines.
- Added coverage scoring and partial-parse handling.
- V2 returns reviewable partial parses instead of failing when it has positive nutrition but incomplete coverage.
- V2 falls back to the existing V1 chain only when the V2 call produces no usable nutrition.
- Added cost feature tracking for `parse_image_inventory_v2`.
- Added unit tests for complete V2 coverage and partial V2 coverage.

New flow:

1. Run an image inventory pass.
2. Classify the image type.
3. Extract visible components with zones and confidence.
4. Choose nutrition strategy based on image type.
5. Score coverage.
6. Return complete or partial result intentionally.

Inventory contract:

```ts
type ImageInventory = {
  imageType:
    | 'nutrition_label'
    | 'single_food'
    | 'multi_component_meal'
    | 'tray_or_thali'
    | 'menu_or_screenshot'
    | 'non_food'
    | 'unclear';
  orientation: 'upright' | 'rotated_90' | 'rotated_180' | 'rotated_270' | 'unknown';
  visibleComponents: Array<{
    name: string;
    zone: string;
    visualEvidence: string;
    portionHint: string;
    confidence: number;
    isSmallSide: boolean;
  }>;
  coverageConfidence: number;
  warnings: string[];
};
```

Nutrition strategy:

- Nutrition labels: extract label values directly.
- Single foods: estimate one visible serving.
- Multi-component meals: estimate nutrition from inventory components.
- Tray/thali: require separate items for breads/rice, dal/curry, sabzi, chutneys, onions/salad, pickles, powders when visible.
- Non-food: return a clear no-food error.

Success criteria:

- A thali returning only `dal, green chutney` becomes a partial parse, not a successful parse.
- A usable partial parse returns with `needsClarification=true` instead of hard failing.
- The app can show "I found these items. Add anything I missed?" rather than "try again."

## Phase 4: Coverage and Partial Parse UX

Status: backend, diagnostics, and first iOS drawer review state implemented.

Goal: treat imperfect image parsing as reviewable, not broken.

Implemented:

- `detectedComponents`
- `coverageScore` via `imageMeta.coverage.score`
- `coverageWarnings` via `imageMeta.coverage.warnings`
- `partialParse` via `imageMeta.coverage.partial`
- `needsClarification`
- `orchestratorVersion`
- `reasonCodes: ["image_partial_coverage"]` for partial image parses
- Testing dashboard coverage badge for recent image attempts

iOS models now decode:

- `ParseImageMeta.orchestratorVersion`
- `ParseImageMeta.coverage`
- `ParseImageCoverage.visibleComponents`

iOS drawer now shows:

- Detected food rows.
- A short friendly warning if the parser suspects missing items.
- Existing retry/add-context actions.

Remaining UX polish:

- Show a compact list of detected-but-unparsed visible components if V2 returns partial coverage.
- Add a clearer "add missing item" affordance inside the photo drawer.

Example copy:

> I found dal and green chutney, but this looks like a full tray. Add anything I missed?

Success criteria:

- Clear food images should almost never show a dead-end "try again."
- Partial results should be reviewable.
- User can correct the parser without losing the image flow.

## Phase 5: Golden Image Evaluation Harness

Status: initial CLI harness implemented.

Goal: stop relying on one-off manual tests.

Implemented:

- `backend/src/scripts/runImageParseEval.ts`
- `npm run eval:image`
- `backend/image-eval-cases.example.json`

The script supports:

- Single image tests with `--image`.
- Multi-image manifests with `--manifest`.
- Local or Render targets with `--base-url`.
- Required keyword checks.
- Minimum item-count checks.
- Calorie-range checks.
- Partial-parse expectations.
- `needsClarification` expectations.
- Latency target checks, defaulting to 6 seconds.

Golden cases:

- Dal baati thali/tray.
- Rice, rajma, onion, lemon.
- Masala dosa with chutneys/sambar.
- Makhana bowl.
- Packaged protein bar/nutrition label.
- Mixed restaurant plate.
- Low-light food image.
- Rotated food image.
- Non-food image.

Each case should define:

- Required detected keywords.
- Minimum item count.
- Expected calorie range.
- Whether partial parse is acceptable.
- Whether `needsClarification` should be true.

Success criteria:

- The eval can run against local backend or Render.
- Dashboard can show pass/fail by image.
- We can compare V1 and V2 before enabling V2.

## Phase 6: Rollout

Rollout should be behind a backend flag:

- `AI_IMAGE_ORCHESTRATOR_VERSION=v1|v2`

Steps:

1. Deploy diagnostics-only Phase 1.
2. Confirm phone attempts show server stages in dashboard.
3. Deploy module extraction.
4. Enable V2 only for internal/test users.
5. Run golden image eval on Render.
6. Test on phone.
7. Enable V2 for TestFlight.

## What Not To Do

Do not keep adding food-specific prompt lines as the main fix.

That can help individual examples, but it will not solve:

- Missed side dishes.
- Silent partial parses.
- Slow fallback chains.
- Phone-vs-internal route mismatch.
- Debugging failures after the fact.

## Expected Outcome

After Phase 1:

- We can see exactly why phone image parses fail.

After Phase 3:

- Common food photos should return either complete nutrition or a clearly labeled partial parse.

After Phase 5:

- We can test Gemini image quality repeatedly instead of relying on memory and screenshots.

Final product expectation:

- Image parsing will still be probabilistic.
- The user experience should not feel probabilistic.
- The app should either produce a useful estimate or ask for a specific correction.
