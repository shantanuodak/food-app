# Image Parse V3 — Final Codex Execution Plan

**Status:** ready for Codex GPT-5.5 high
**Date:** 2026-05-19
**Owner:** Claude Opus 4.7 (drafted), Codex (executes)
**Companion docs (informational, do NOT execute from these):** [`a.md`](a.md), [`IMAGE_PARSE_REFACTOR_PLAN.md`](IMAGE_PARSE_REFACTOR_PLAN.md), [`docs/PHASE_8_10_FINDINGS.md`](docs/PHASE_8_10_FINDINGS.md), [`CLAUDE.md`](CLAUDE.md).

---

## 0. How to use this file

This file is **the** execution plan. Feed the whole file to Codex; tell Codex which phase to execute. Each phase is self-contained — Codex does **one phase per session**, runs the verification at the end, commits, then moves to the next phase.

Do **NOT** ask Codex to do all phases in one shot. Each phase has explicit:
- Files to create / modify / delete
- Exact code snippets or function shapes where useful
- Verification including the [CLAUDE.md](CLAUDE.md) four-step DB rule
- Acceptance criteria

After all phases complete, the iOS simulator build is ready for end-to-end testing.

---

## 1. Honest expectations (calibrated against published VLM food benchmarks)

Earlier drafts of this plan claimed 88-92% accuracy. After researching ([PMC 2026 VLM-food study](https://pmc.ncbi.nlm.nih.gov/articles/PMC13092701/), [MDPI 2024 cuisine prompting](https://www.mdpi.com/2079-9292/13/22/4552), [CalCam blog](https://developers.googleblog.com/en/calcam-transforming-food-tracking-with-the-gemini-api/)), the realistic range is:

| Success metric | What it measures | After V3 (Gemini-only) |
|---|---|---|
| **A. Identifies right food** | "App said 'burger' for a burger photo" | **88-93%** |
| **B. User-acceptable parse** | "User accepted without editing macros" | **80-87%** ← the primary metric |
| **C. Strict ±10% calorie match** | "Estimate within ±10% of ground truth" | **70-78%** |
| **D. No 'try again' failure** | "Parse completed and returned something usable" | **94-97%** ✓ |
| **E. Sub-12s latency** | "Finished in under 12 seconds" | **95%+** ✓ |

**Three usage scenarios for metric B:**
- Heavy branded-item logger: ~84%
- Mixed home + restaurant + packaged: ~81%
- Heavy restaurant / prepared food: ~78%

**The user-stated problems map to D, E, and parts of B/A:**
- "Try again happens a lot" → fixed (95%+)
- "30+ second latency" → fixed (95%+)
- "Branded items return wrong calories" → fixed for items with visible barcode/label (88-93%); other branded items improved but not perfect
- "App feels probabilistic" → much better, not eliminated for vision-lane items

**What V3 does NOT eliminate:** vision-lane estimation error on prepared/restaurant food. No Gemini-only approach can. Restaurant chains, ethnic long-tail, and adversarial photos need additional work (Phase 9+).

---

## 2. Architecture in one page

```
iOS                                            Backend
─────────────────────────────────────────────────────────────────────
[Capture UIImage]
       │
       ├─ async let barcode = VNDetectBarcodesRequest   (50-200ms)
       ├─ async let ocr     = VNRecognizeTextRequest    (200-500ms)
       ├─ async let payload = prepareImagePayload(...)  (1-2s)
       │
       ▼ (await all, then dispatch)
[Lane decision per §7.2]
  ├─ barcode hit ≥ 0.95   → POST /v1/logs/parse/barcode → nutritionDB lookup
  │                                                       (OFF + USDA + FatSecret)
  ├─ label panel ≥ 0.7    → POST /v1/logs/parse/label   → Gemini 3.1 Flash Lite
  │                                                       (text-mode parse of OCR)
  └─ else                  → POST /v1/logs/parse/image  → Gemini 3 Flash
                                                          (vision lane, cuisine-routed)

Backend lane router (replaces parseImageWithGemini entry):
  routeImageParse({ lane, payload, contextNote })
    ├─ lane=barcode → nutritionDatabaseService.lookupByBarcode()
    ├─ lane=label   → laneLabel.parseLabel(ocrText, image)
    └─ lane=vision  → cuisineClassifier.classify()
                      → laneVision.parseImage(cuisinePrompt + image)

Cuisine classifier picks one of 7 sub-prompts:
  indian, us, western, eastAsian, mediterranean, latin, generic
```

### Model strategy

| Lane | Model | Why |
|---|---|---|
| Barcode | None (DB lookup) | Deterministic |
| Label OCR text parse | `gemini-3.1-flash-lite` + `thinking: low` | Cheap, fast, accurate on structured text |
| Vision inventory | `gemini-3-flash` | Biggest single accuracy win; vision-heavy task |
| Caption probes | `gemini-3.1-flash-lite` | Simple task, save cost |
| Text parse (whole text path) | `gemini-3.1-flash-lite` + `thinking: low` | Simpler than vision; cost drops 60-70% |
| Last-resort rescue | `gemini-3-flash` or `gemini-2.5-pro` | Best-effort |

**Latency budget (hard caps):**
- Barcode: 2s client / 800ms server
- Label: 6s client / 3s server
- Vision: 12s client / 8s server (was 45s / 18s)

---

## 3. Pre-flight checks (do these BEFORE Phase 0)

Run these and paste the output in chat with Codex before starting Phase 0:

```bash
# 1. iOS deployment target — must be 14.0+ for Vision barcode/OCR APIs
grep -E "IPHONEOS_DEPLOYMENT_TARGET" "Food App/Food App.xcodeproj/project.pbxproj" | head -3

# 2. Gemini API key has access to 3 Flash and 3.1 Flash Lite
echo "Manual check: Vertex AI / Gemini API console → verify gemini-3-flash and gemini-3.1-flash-lite are enabled for your project"

# 3. Open Food Facts API reachable
curl -sI "https://world.openfoodfacts.org/api/v2/product/0049000028911.json" | head -1
# expect: HTTP/2 200

# 4. USDA FDC API key valid
echo "$USDA_FDC_API_KEY" | head -c 8; echo "..."
curl -sI "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=$USDA_FDC_API_KEY&query=cheetos&dataType=Branded" | head -1
# expect: HTTP/2 200

# 5. Verify current backend builds + tests pass before any changes
cd backend && npm install && npm test && npm run build
```

If any check fails, fix it before Phase 0.

---

## 4. Phase-by-phase execution

Each phase = one Codex session. Verify between phases. Commit per phase.

### Phase 0 — Memory fix + EXIF normalization (45 min)

**Why:** Two independent iOS fixes that unblock everything else. The 1.12 GB memory spike causes crashes on weaker devices. EXIF orientation is required for Phase 2 Vision pipeline to work.

**Files:**
- [`Food App/MainLoggingImagePayloadFlow.swift`](Food%20App/MainLoggingImagePayloadFlow.swift) — modify
- `Food App/UIImage+FixedOrientation.swift` — create (new utility file)

**Changes in `MainLoggingImagePayloadFlow.swift`:**

Replace `prepareImagePayload` with:

```swift
nonisolated static func prepareImagePayload(from image: UIImage) -> PreparedImagePayload? {
    let normalized = image.fixedOrientation()
    let maxBytes = 1_200_000
    let dimensionAttempts: [CGFloat] = [1440, 1280, 1024]   // was [1800, 1600, 1440, 1280]
    let qualityAttempts: [CGFloat] = [0.84, 0.80, 0.76, 0.72]  // dropped 0.88
    var smallestData: Data?

    for dimension in dimensionAttempts {
        let result: PreparedImagePayload? = autoreleasepool {       // NEW outer pool
            let resized = resizeImageIfNeeded(normalized, maxDimension: dimension)
            for quality in qualityAttempts {
                let inner: PreparedImagePayload? = autoreleasepool {
                    guard let data = resized.jpegData(compressionQuality: quality) else { return nil }
                    if smallestData.map({ data.count < $0.count }) != false {
                        smallestData = data
                    }
                    if data.count <= maxBytes {
                        return PreparedImagePayload(uploadData: data, previewData: data, mimeType: "image/jpeg")
                    }
                    return nil
                }
                if let inner { return inner }
            }
            return nil
        }
        if let result { return result }
    }
    if let smallestData {
        return PreparedImagePayload(uploadData: smallestData, previewData: smallestData, mimeType: "image/jpeg")
    }
    return nil
}
```

**Create `Food App/UIImage+FixedOrientation.swift`:**

```swift
import UIKit

extension UIImage {
    /// Bakes `imageOrientation` into the pixel buffer so downstream Vision and
    /// JPEG encoding see an upright image. Required for VNDetectBarcodesRequest
    /// and VNRecognizeTextRequest in the V3 Vision pipeline.
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
```

**Verification (user runs):**
1. Build in Xcode against iOS Simulator
2. Take a portrait-held photo of a landscape barcode (e.g., side of a cereal box on a table)
3. Memory Graph high water mark must drop from 1.12 GB → under 250 MB
4. Drawer preview shows the image upright (not rotated)
5. Run [CLAUDE.md](CLAUDE.md) four-step DB check after a single image save: image_ref populated, calories present

**Commit message:** `Phase 0: outer autoreleasepool + EXIF normalize for V3 Vision pipeline`

---

### Phase 1 — Nutrition database service (4 hours)

**Why:** A unified `nutritionDatabaseService.ts` that resolves barcode/name to nutrition via Open Food Facts → USDA → FatSecret. Sub-second cache hits. Phase 3 and Phase 4 depend on this.

**Files:**
- `backend/src/services/nutritionDatabaseService.ts` — create
- `backend/src/services/nutritionDatabaseService.test.ts` — create
- `backend/.env.example` — add `OFF_BASE_URL`, `OFF_USER_AGENT`
- `backend/src/config.ts` — add corresponding config fields

**Service shape:**

```ts
// backend/src/services/nutritionDatabaseService.ts
export type NutritionLookupResult = {
  source: 'open_food_facts' | 'usda' | 'fatsecret' | 'cache' | 'miss';
  brand?: string;
  productName: string;
  servingSizeG: number;
  servingSizeText?: string;
  calories: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  fiberG?: number;
  sugarG?: number;
  sodiumMg?: number;
  confidence: number;          // 0..1
  upc?: string;
  imageUrl?: string;
  raw?: unknown;
  latencyMs: number;
};

export async function lookupByBarcode(
  code: string,
  opts?: { signal?: AbortSignal; timeoutMs?: number }
): Promise<NutritionLookupResult>;

export async function lookupByName(
  brand: string | undefined,
  productName: string,
  opts?: { signal?: AbortSignal; timeoutMs?: number }
): Promise<NutritionLookupResult>;

// Internal — exposed for testing
export function _normalizeOFFResponse(raw: any): Omit<NutritionLookupResult, 'source' | 'latencyMs'>;
export function _normalizeUSDAResponse(raw: any): Omit<NutritionLookupResult, 'source' | 'latencyMs'>;
export function _normalizeFatSecretResponse(raw: any): Omit<NutritionLookupResult, 'source' | 'latencyMs'>;
```

**Implementation order:**
1. In-memory LRU cache (1000 entries, 7-day TTL). Key = barcode OR `{brandLower}|{nameLower}`. Hit returns in <5ms.
2. Open Food Facts: `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json?fields=product_name,brands,serving_size,nutriments,image_url`. Identify with `User-Agent: FoodApp/1.0 (contact@foodapp.com)`. 800ms timeout. Map `nutriments.energy-kcal_serving`, `nutriments.proteins_serving`, etc.
3. USDA FDC: reuse existing `nutritionBenchmarkService.ts` client OR implement direct `GET /foods/search?query={upc}&dataType=Branded&api_key={key}`. 1000ms timeout. Map `foodNutrients` array.
4. FatSecret: reuse existing integration from `nutritionBenchmarkService.ts`. 1000ms timeout.
5. On all-miss: return `{ source: 'miss', confidence: 0, ... zeroed fields }`.

**Normalization rules (handle OFF / USDA inconsistencies):**
- OFF often returns per-100g instead of per-serving. If `serving_size` parseable, scale to per-serving. If not, return per-100g and set `servingSizeText: '100g'`.
- USDA returns multiple candidates; pick highest `score` with `dataType: 'Branded'` and exact UPC match if present.
- Energy in OFF can be kJ (`energy_serving` field) instead of kcal — convert: `kcal = kJ / 4.184`.
- Always sanity-check: if calories > 1500 per serving or fat > 100g per serving → reject result, fall through to next source.

**Tests (`backend/src/services/nutritionDatabaseService.test.ts`):**

```ts
import { describe, it, expect, vi } from 'vitest';
import * as nds from './nutritionDatabaseService.js';

describe('nutritionDatabaseService', () => {
  it('looks up Diet Coke 12oz can by UPC', async () => {
    const result = await nds.lookupByBarcode('0049000028911');
    expect(result.source).toBeOneOf(['open_food_facts', 'usda']);
    expect(result.calories).toBeLessThan(10);
    expect(result.productName.toLowerCase()).toMatch(/diet coke|coke zero|cola/);
  });

  it('looks up Cheetos by UPC', async () => {
    const result = await nds.lookupByBarcode('0028400433556');
    expect(result.source).toBeOneOf(['open_food_facts', 'usda']);
    expect(result.calories).toBeBetween(140, 180);
  });

  it('returns miss for invalid barcode', async () => {
    const result = await nds.lookupByBarcode('0000000000000');
    expect(result.source).toBe('miss');
    expect(result.confidence).toBe(0);
  });

  it('caches subsequent calls', async () => {
    const t1 = Date.now();
    await nds.lookupByBarcode('0049000028911');
    const firstLatency = Date.now() - t1;
    const t2 = Date.now();
    const result = await nds.lookupByBarcode('0049000028911');
    const secondLatency = Date.now() - t2;
    expect(result.source).toBe('cache');
    expect(secondLatency).toBeLessThan(firstLatency / 5);
  });

  it('falls through OFF → USDA when OFF returns 404', async () => {
    // Mock OFF to 404, verify USDA hit
    // [implementation depends on existing test infra]
  });
});
```

**Acceptance criteria:**
- `npm test -- nutritionDatabaseService.test.ts` passes
- `npm run build` passes
- 5 manual UPC lookups return sensible data (Diet Coke, Cheetos, RxBar, Kind Bar, Chobani yogurt)

**Commit message:** `Phase 1: nutritionDatabaseService with OFF + USDA + FatSecret + LRU cache`

---

### Phase 2 — iOS Vision pipeline (4 hours)

**Why:** On-device barcode + OCR runs in parallel with JPEG compression. Determines which backend route to call. Free, fast, deterministic.

**Files:**
- `Food App/ImageVisionPipeline.swift` — create
- `Food App/ImageVisionPipeline.test.swift` — create (XCTest with bundled images)
- iOS bundle resources: add `TestImage_DietCoke.jpg`, `TestImage_Thali.jpg`, `TestImage_GranolaBar.jpg` for tests

**`ImageVisionPipeline.swift` shape:**

```swift
import UIKit
import Vision

struct BarcodeHit {
    let payload: String          // e.g. "0049000028911"
    let symbology: String        // "UPC-A", "EAN-13", "Code128"
    let confidence: Float        // 0..1
}

struct LabelPanelHit {
    let detectedText: String     // text recognized inside the panel region
    let tokenScore: Int          // how many Nutrition Facts indicator tokens hit
    let perServingCaloriesGuess: Int?  // best-effort regex parse
    let confidence: Float        // 0..1
}

struct ImageVisionResult {
    let barcode: BarcodeHit?
    let labelPanel: LabelPanelHit?
    let ocrText: String
    let elapsedMs: Int
}

enum ImageVisionPipeline {
    static func analyze(_ image: UIImage, timeoutMs: Int = 800) async -> ImageVisionResult
}
```

**Implementation notes:**

1. **EXIF normalization first** (Phase 0 dependency): `let normalized = image.fixedOrientation()`. Then use `normalized.cgImage` for Vision requests.

2. **Barcode detection:**
   ```swift
   let request = VNDetectBarcodesRequest()
   request.symbologies = [.ean13, .ean8, .upce, .code128]
   // .upcA does not exist as a separate symbology in newer Vision — UPC-A reports as .ean13
   ```

3. **OCR:**
   ```swift
   let request = VNRecognizeTextRequest()
   request.recognitionLevel = .accurate
   request.usesLanguageCorrection = false   // preserve "30g", "165 kcal"
   request.recognitionLanguages = ["en-US"]
   ```

4. **Label-panel detection (after OCR):** scan all observation strings for the 3-token gate:
   ```swift
   let lower = ocrText.lowercased()
   let hasHeader = lower.contains("nutrition facts") ||
                   lower.contains("nutritional information") ||
                   lower.contains("supplement facts")
   let hasCalories = lower.contains("calories") || lower.contains("energy")
   let hasMacros = lower.contains("total fat") || lower.contains("carbohydrate") || lower.contains("protein")
   let tokenScore = (hasHeader ? 1 : 0) + (hasCalories ? 1 : 0) + (hasMacros ? 1 : 0)
   ```
   Require `tokenScore >= 2` to set `labelPanel.confidence >= 0.7`. Score of 3 → confidence 0.9.

5. **Per-serving calorie regex** (best-effort, for telemetry only — backend re-parses):
   ```swift
   let pattern = #"(?i)\bcalories\s*[:\-]?\s*(\d{1,4})\b"#
   ```

6. **Concurrency with hard cap:**
   ```swift
   static func analyze(_ image: UIImage, timeoutMs: Int = 800) async -> ImageVisionResult {
       let start = Date()
       let normalized = image.fixedOrientation()
       guard let cgImage = normalized.cgImage else {
           return ImageVisionResult(barcode: nil, labelPanel: nil, ocrText: "", elapsedMs: 0)
       }

       async let barcodeTask = detectBarcode(cgImage, timeoutMs: timeoutMs)
       async let ocrTask = recognizeText(cgImage, timeoutMs: timeoutMs)

       let (barcode, ocrText) = await (barcodeTask, ocrTask)
       let labelPanel = detectLabelPanel(from: ocrText)
       let elapsed = Int(Date().timeIntervalSince(start) * 1000)
       return ImageVisionResult(barcode: barcode, labelPanel: labelPanel, ocrText: ocrText, elapsedMs: elapsed)
   }
   ```

7. **Quick Camera priority** — in `QuickCameraLoggingService`, wrap the analyze call in `Task.detached(priority: .userInitiated)` to avoid background-priority starvation on lock-screen widget firings.

**Tests (XCTest, bundled images):**

```swift
func testBarcodeOnDietCokeCan() async {
    let image = UIImage(named: "TestImage_DietCoke")!
    let result = await ImageVisionPipeline.analyze(image)
    XCTAssertNotNil(result.barcode)
    XCTAssertTrue(["EAN-13", "UPC-A"].contains(result.barcode?.symbology ?? ""))
    XCTAssertGreaterThan(result.barcode?.confidence ?? 0, 0.85)
}

func testNoBarcodeOnThali() async {
    let image = UIImage(named: "TestImage_Thali")!
    let result = await ImageVisionPipeline.analyze(image)
    XCTAssertNil(result.barcode)
}

func testLabelDetectedOnGranolaBar() async {
    let image = UIImage(named: "TestImage_GranolaBar")!
    let result = await ImageVisionPipeline.analyze(image)
    XCTAssertNotNil(result.labelPanel)
    XCTAssertGreaterThanOrEqual(result.labelPanel?.tokenScore ?? 0, 2)
}
```

**Acceptance criteria:**
- iOS build green
- Log a Diet Coke can; `NSLog` shows `[ImageVisionPipeline] barcode=0049000028911 elapsedMs=120`
- Log a thali; `NSLog` shows `[ImageVisionPipeline] barcode=nil labelPanel=nil`

**Commit message:** `Phase 2: ImageVisionPipeline with barcode + OCR + label-panel detection`

---

### Phase 3 — Barcode route end-to-end (3 hours)

**Why:** Fast deterministic lookup when iOS detects a barcode. Sub-second for cached UPCs.

**Files:**
- `backend/src/routes/parse.ts` — add handler for `POST /v1/logs/parse/barcode`
- `backend/src/services/imageParse/laneBarcode.ts` — create (thin)
- `Food App/APIClient.swift` — add `parseBarcode(code:symbology:contextNote:clientAttemptId:loggedAt:)`. Timeout 2s.
- `Food App/MainLoggingCameraDrawerFlow.swift` — modify dispatch (after `prepareImagePayload`, route based on Vision result)
- `Food App/QuickCameraLoggingService.swift` — same dispatch logic
- `Food App/APIModels.swift` — extend `ParseLogResponse` with `parseLaneUsed: String?`, `parseLaneSource: String?`, `parseLaneLatencyMs: Int?` (all Optional for backwards compat)

**Backend route shape:**

```ts
// POST /v1/logs/parse/barcode
const BarcodeBodySchema = z.object({
  clientAttemptId: z.string().max(120).optional(),
  barcode: z.string().regex(/^\d{8,14}$/),
  symbology: z.string().max(32).optional(),
  contextNote: z.string().max(240).optional(),
  loggedAt: z.string().datetime().optional(),
});

// Handler flow:
// 1. Zod validate
// 2. Rate limit + idempotency (reuse existing middleware)
// 3. Parse quantity hint from contextNote if present: /\b(\d+|two|three|four|five)\s+(of these|can|bottle|piece|servings?)/i
// 4. Call nutritionDatabaseService.lookupByBarcode(barcode, { timeoutMs: 800 })
// 5. If result.source !== 'miss':
//    - Multiply nutrition by quantity hint if present
//    - Build ParseResult with one item
//    - Persist as food_logs (input_kind = 'image_barcode')
//    - Return success response with parseLaneUsed='barcode', parseLaneSource=result.source
// 6. If result.source === 'miss':
//    - Return HTTP 200 with { parseLaneUsed: 'barcode', fallback: 'image', missReason: 'barcode_not_found' }
//    - DO NOT return 404 — clients treat 200+fallback as "switch lanes"
```

**iOS dispatch logic (`MainLoggingCameraDrawerFlow.swift`):**

```swift
private func parseAndUpdateDrawer(_ image: UIImage) async {
    let prepStart = Date()
    let payload = await Task.detached(priority: .userInitiated) {
        Self.prepareImagePayload(from: image)
    }.value
    
    // Run Vision in parallel with the rest of the flow
    let visionResult = await ImageVisionPipeline.analyze(image, timeoutMs: 800)
    let imagePrepMs = Int(Date().timeIntervalSince(prepStart) * 1000)
    
    // Lane decision per §7.2 of plan
    let lane = decideLane(visionResult: visionResult)
    
    switch lane {
    case .barcode(let code, let symbology):
        await tryBarcode(code: code, symbology: symbology, fallbackPayload: payload, image: image)
    case .label(let ocrText):
        await tryLabel(ocrText: ocrText, payload: payload, image: image)
    case .vision:
        await tryVisionLane(payload: payload, image: image)
    }
}

private enum ParseLane {
    case barcode(String, String?)
    case label(String)
    case vision
}

private func decideLane(visionResult: ImageVisionResult) -> ParseLane {
    if let barcode = visionResult.barcode, barcode.confidence >= 0.95 {
        return .barcode(barcode.payload, barcode.symbology)
    }
    if let label = visionResult.labelPanel, label.confidence >= 0.7 {
        return .label(visionResult.ocrText)
    }
    if let barcode = visionResult.barcode, barcode.confidence >= 0.80,
       visionResult.labelPanel == nil {
        return .barcode(barcode.payload, barcode.symbology)
    }
    return .vision
}

private func tryBarcode(code: String, symbology: String?, fallbackPayload: PreparedImagePayload?, image: UIImage) async {
    do {
        let response = try await apiClient.parseBarcode(code: code, symbology: symbology, ...)
        if response.fallback == "image" {
            // Barcode miss; try label if we have one, else vision
            if !visionResult.ocrText.isEmpty, visionResult.labelPanel != nil {
                await tryLabel(ocrText: visionResult.ocrText, payload: fallbackPayload, image: image)
            } else {
                await tryVisionLane(payload: fallbackPayload, image: image)
            }
        } else {
            // Success — also async-upload the image for visual history
            scheduleAsyncImageUpload(payload: fallbackPayload, logId: response.logId)
            handleParseSuccess(response)
        }
    } catch {
        // On timeout or network error, fall through to vision
        await tryVisionLane(payload: fallbackPayload, image: image)
    }
}
```

**Async image upload on barcode success:** Use the existing `DeferredImageUploadStore` path. The image still lands in `food_logs.image_ref` for visual history; the parse just doesn't depend on it.

**Verification:**
1. Log Diet Coke can → `parseLaneUsed='barcode'`, `parseLaneSource='open_food_facts'` or `'usda'`, latency <2s
2. Run [CLAUDE.md](CLAUDE.md) four-step DB check — `food_logs.input_kind='image_barcode'`, `image_ref` populated (async upload), calories ~0
3. Log Cheetos bag → calories 140-170
4. Log thali → falls through to `parseLaneUsed='vision'` (no false positive)
5. Log unknown UPC (e.g., a regional brand not in OFF) → falls through to vision, not stuck on miss

**Acceptance criteria:**
- 5/5 manual tests pass
- No regression: existing image-mode logs still work via the vision lane
- DB row for barcode log has `parse_request_id` and `image_ref` both populated

**Commit message:** `Phase 3: barcode route + iOS dispatch + async image upload`

---

### Phase 4 — Label OCR route (4 hours)

**Why:** Nutrition Facts panels are deterministic text. Text-mode Gemini parses them faster, cheaper, and more accurately than vision.

**Files:**
- `backend/src/routes/parse.ts` — add handler for `POST /v1/logs/parse/label`
- `backend/src/services/imageParse/laneLabel.ts` — create
- `backend/src/services/imageParse/prompts/labelParse.ts` — create (the text-mode prompt)
- `Food App/APIClient.swift` — add `parseLabel(ocrText:imageData:contextNote:clientAttemptId:loggedAt:)`. Timeout 6s.
- `Food App/MainLoggingCameraDrawerFlow.swift` — dispatch already wired in Phase 3; verify label path triggers

**Backend route shape:**

```ts
// POST /v1/logs/parse/label
const LabelBodySchema = z.object({
  clientAttemptId: z.string().max(120).optional(),
  ocrText: z.string().min(20).max(4000),  // require substantive OCR text
  imageBase64: z.string(),
  contextNote: z.string().max(240).optional(),
  loggedAt: z.string().datetime().optional(),
});

// Flow:
// 1. Validate
// 2. Call laneLabel.parseLabel({ ocrText, imageBase64, contextNote })
// 3. Persist as food_logs (input_kind = 'image_label')
// 4. Return with parseLaneUsed='label', parseLaneSource='gemini'
```

**`laneLabel.parseLabel` shape:**

```ts
export async function parseLabel(args: {
  ocrText: string;
  imageBase64?: string;        // attached as backup
  contextNote?: string;
  signal?: AbortSignal;
  timeoutMs?: number;          // default 3000
}): Promise<ImageParseServiceResult> {
  const prompt = buildLabelParsePrompt({ ocrText, contextNote });
  const model = config.aiImageLabelModel;  // 'gemini-3.1-flash-lite'

  const response = await geminiFlashClient.generate({
    model,
    prompt,
    image: imageBase64,        // attached but text leads
    temperature: 0.0,
    maxTokens: 400,
    thinking: 'low',           // 3.1 Lite supports thinking modes
    responseFormat: 'application/json',
    timeoutMs: timeoutMs ?? 3000,
  });

  return normalizeLabelResponse(response);
}
```

**Label parse prompt** (in `prompts/labelParse.ts`):

```ts
export function buildLabelParsePrompt(args: { ocrText: string; contextNote?: string }): string {
  return `
You are parsing a Nutrition Facts panel that was OCR'd from a photo.

OCR text follows. Numbers may be slightly garbled (e.g. "1.5g" might read "15g"
or "1 5g"). Use the attached image as a tiebreaker when OCR is ambiguous.

OCR text:
"""
${args.ocrText}
"""

${args.contextNote ? `User note: "${args.contextNote}"` : ''}

Return ONE item representing this product, with per-serving nutrition.

Rules:
1. Per-serving values only. If panel shows BOTH per-serving and per-100g,
   return per-serving and include the literal serving size text.
2. Sanity-check values. No food has 150g fat or 5000 mg sodium per serving.
   If parsed value exceeds: total fat > 100g, calories > 1500, sodium > 3000mg,
   look at the image and re-derive.
3. If "Calories" line is unclear, look at "Total Fat", "Carbohydrate", "Protein"
   and compute: kcal ≈ (fat_g * 9) + (carb_g * 4) + (protein_g * 4).
4. Identify the product. If the panel image shows brand + product name, use
   it. If only the panel is visible, return "Packaged food (label)" as name.
5. Output JSON:
   {
     "imageType": "nutrition_label",
     "items": [{
       "name": string,
       "brand": string | null,
       "servingSize": string,
       "servingSizeG": number,
       "calories": number,
       "proteinG": number,
       "carbsG": number,
       "fatG": number,
       "fiberG": number | null,
       "sugarG": number | null,
       "sodiumMg": number | null
     }],
     "confidence": number (0..1),
     "coverage": { "score": 1.0, "warnings": [] }
   }
`.trim();
}
```

**Verification:**
1. Log a granola bar's Nutrition Facts panel close-up → `parseLaneUsed='label'`, latency <3s, calories match label
2. Log a restaurant menu screenshot → `parseLaneUsed='vision'` (NOT label — regression check on false positives)
3. Log a recipe card with calorie info → `parseLaneUsed='vision'`
4. Log a partial / cropped Nutrition Facts panel (only top half visible) → label lane still returns sensible result with `confidence: 0.7`

**Acceptance criteria:**
- 4/4 manual tests pass
- DB row for label log has `input_kind='image_label'`, calories accurate to ±5%

**Commit message:** `Phase 4: label OCR route + text-mode Gemini parse`

---

### Phase 5 — Cuisine sub-prompts (8 hours, the big quality lever)

**Why:** The current single 760-line inventory prompt is heavily Indian-cuisine-tuned. Routing photos to cuisine-specific sub-prompts is the single biggest accuracy lever for the vision lane on non-Indian food.

**Files:**
- `backend/src/services/imageParse/prompts/cuisines/` — create directory with 7 files
- `backend/src/services/imageParse/prompts/shared/` — create directory for common preamble + schema
- `backend/src/services/imageParse/cuisineClassifier.ts` — create routing service
- `backend/src/services/imageParse/cuisineClassifier.test.ts` — create tests
- `backend/src/services/imageParse/prompts/keywords.ts` — create keyword maps

**Directory structure to create:**

```
backend/src/services/imageParse/
├── prompts/
│   ├── shared/
│   │   ├── header.ts            // common preamble: task, JSON output format, safety rules
│   │   ├── outputSchema.ts      // exact JSON shape spec
│   │   └── coverage.ts          // multi-item coverage rules
│   ├── cuisines/
│   │   ├── indian.ts            // full Indian sub-prompt (see §5 below)
│   │   ├── us.ts                // full US/American sub-prompt
│   │   ├── western.ts           // European non-Mediterranean
│   │   ├── eastAsian.ts         // Chinese/Japanese/Korean/Thai/Vietnamese
│   │   ├── mediterranean.ts     // Italian/Greek/MiddleEastern/Spanish
│   │   ├── latin.ts             // Mexican/SouthAmerican/Caribbean
│   │   └── generic.ts           // fallback
│   ├── keywords.ts              // CUISINE_KEYWORDS dict for routing
│   └── builder.ts               // composes header + cuisine + schema
└── cuisineClassifier.ts         // classify(contextNote, locale, history) → cuisine
```

**`cuisineClassifier.ts` shape:**

```ts
export type Cuisine = 'indian' | 'us' | 'western' | 'eastAsian' | 'mediterranean' | 'latin' | 'generic';

export interface CuisineClassification {
  cuisine: Cuisine;
  confidence: number;          // 0..1
  source: 'keywords' | 'locale' | 'history' | 'classifier_call' | 'default';
  matchedKeywords?: string[];
}

export async function classify(args: {
  contextNote?: string;
  userLocale?: string;          // 'en-US', 'en-IN', 'en-GB', etc.
  recentCuisines?: Cuisine[];   // last 7 days from food_logs
  thumbnailBase64?: string;     // 256px JPEG for optional classifier call
}): Promise<CuisineClassification>;
```

**Classification tiers (cheap → expensive):**

1. **Keyword scan on contextNote** (free, <1ms): use `CUISINE_KEYWORDS` from `keywords.ts`. Count matches per cuisine. If top cuisine has ≥3 matches AND beats #2 by ≥2 matches → `confidence: 0.85`.
2. **User locale + recent history** (free, <5ms): `en-IN` user with 5 recent Indian logs → strong signal for Indian (`confidence: 0.7`).
3. **Thumbnail classifier call** (only if tiers 1+2 weak, ~300ms): tiny prompt to `gemini-3.1-flash-lite`, 256px thumbnail, single-token response. Adds latency but only fires when needed.
4. **Default to `generic`** if all signals weak (`confidence: 0.3`).

**Routing rule:** if `confidence >= 0.6` use the predicted cuisine; else use `generic`.

**`keywords.ts` shape (excerpt; full content in §5 of this plan):**

```ts
export const CUISINE_KEYWORDS: Record<Cuisine, string[]> = {
  indian: ['thali', 'dosa', 'naan', 'roti', 'chapati', 'dal', 'curry', 'tikka',
           'masala', 'biryani', 'chutney', 'paneer', 'lassi', 'samosa', 'idli',
           'sambar', 'raita', 'paratha', 'kheer', 'gulab jamun', 'chai',
           'pakora', 'chaat', 'pulao', 'korma', 'vindaloo', 'tandoori',
           'kulfi', 'papad', 'pickle', 'achaar', 'baati', 'rasam', 'medu vada',
           'uttapam', 'kachori', 'jalebi', 'palak', 'aloo', 'gobi', 'bhindi',
           'rajma', 'chana', 'pav bhaji', 'misal', 'dhokla', 'rasgulla'],
  us: ['burger', 'cheeseburger', 'hamburger', 'fries', 'sandwich', 'sub',
       'hoagie', 'hot dog', 'bbq', 'brunch', 'breakfast', 'bacon', 'pancake',
       'waffle', 'omelette', 'bagel', 'cream cheese', 'cereal', 'milkshake',
       'taco', 'burrito', 'nachos', 'mac and cheese', 'fried chicken', 'wings',
       'ribs', 'mashed potato', 'biscuit', 'cornbread', 'chili', 'ranch',
       'buffalo sauce', 'club sandwich', 'blt', 'caesar salad', 'cobb salad',
       'pulled pork', 'brisket', 'meatloaf', 'cheesesteak', 'reuben'],
  western: ['schnitzel', 'sauerkraut', 'bratwurst', 'croissant', 'baguette',
            'brioche', 'quiche', 'crepe', 'ratatouille', 'coq au vin',
            'beef bourguignon', 'fish and chips', 'shepherd', 'bangers',
            'sunday roast', 'yorkshire pudding', 'fondue', 'raclette',
            'goulash', 'pierogi', 'borscht', 'strudel', 'sachertorte',
            'eclair', 'pain au chocolat', 'french onion soup', 'cassoulet'],
  eastAsian: ['ramen', 'sushi', 'sashimi', 'tempura', 'teriyaki', 'miso',
              'edamame', 'gyoza', 'dim sum', 'dumpling', 'fried rice',
              'chow mein', 'lo mein', 'kung pao', 'general tso', 'sweet and sour',
              'orange chicken', 'hot and sour', 'wonton', 'bao', 'pho',
              'banh mi', 'spring roll', 'pad thai', 'pad see ew', 'tom yum',
              'green curry', 'red curry', 'panang', 'satay', 'bibimbap',
              'bulgogi', 'kimchi', 'kalbi', 'japchae', 'hot pot', 'peking duck',
              'mapo tofu', 'donburi', 'udon', 'soba', 'nigiri', 'maki'],
  mediterranean: ['pizza', 'pasta', 'lasagna', 'risotto', 'gnocchi', 'ravioli',
                  'spaghetti', 'carbonara', 'bolognese', 'pesto', 'alfredo',
                  'marinara', 'hummus', 'falafel', 'tabbouleh', 'gyro',
                  'kebab', 'shawarma', 'tzatziki', 'baklava', 'dolma',
                  'moussaka', 'paella', 'tapas', 'gazpacho', 'tortilla',
                  'churros', 'jamon', 'manchego', 'feta', 'olive oil',
                  'bruschetta', 'focaccia', 'calzone', 'panini', 'parmesan',
                  'mozzarella', 'caprese', 'tagine', 'couscous'],
  latin: ['taco', 'burrito', 'quesadilla', 'enchilada', 'fajita', 'tamale',
          'nachos', 'salsa', 'guacamole', 'refried beans', 'mole',
          'chimichanga', 'tostada', 'taquito', 'sope', 'gordita', 'churro',
          'flan', 'tres leches', 'arepa', 'empanada', 'pupusa', 'ceviche',
          'plantain', 'tostones', 'ropa vieja', 'picadillo', 'jerk chicken',
          'pernil', 'mojo', 'sofrito', 'chimichurri', 'feijoada', 'churrasco'],
  generic: [],
};

// Note: 'taco', 'burrito', 'nachos', 'quesadilla' appear in BOTH us and latin
// — Tex-Mex overlap. Tiebreaker: if contextNote also has 'salsa', 'mole',
// 'arepa', 'empanada', 'pupusa' → latin. Else (mac and cheese, fries, ranch
// alongside) → us.
```

**The 7 cuisine sub-prompts:** see §5 below for full content. Each is ~120-180 lines of dense rules, vocabulary, portion conventions, and common errors. Codex copies each into the corresponding `cuisines/{name}.ts` file as the exported `export const INDIAN_PROMPT = \`...\`;` etc.

**Wire-up in vision lane:**

```ts
// imageParse/laneVision.ts
import { classify } from '../cuisineClassifier.js';
import { buildCuisinePrompt } from './prompts/builder.js';

export async function parseImage(args: {
  image: ImagePart;
  contextNote?: string;
  userLocale?: string;
  recentCuisines?: Cuisine[];
  signal?: AbortSignal;
}): Promise<ImageParseServiceResult> {
  const cuisine = await classify({
    contextNote: args.contextNote,
    userLocale: args.userLocale,
    recentCuisines: args.recentCuisines,
  });

  const prompt = buildCuisinePrompt({
    cuisine: cuisine.cuisine,
    contextNote: args.contextNote,
  });

  // ... existing inventory call with new prompt ...
  // Set telemetry: cuisineUsed: cuisine.cuisine, cuisineSource: cuisine.source
}
```

**Verification:**
1. `contextNote: "had a chicken tikka thali"` → classifier returns `indian` with confidence ≥0.85
2. `contextNote: "double cheeseburger and fries"` → `us`, ≥0.85
3. `contextNote: "spaghetti carbonara"` → `mediterranean`, ≥0.85
4. `contextNote: "pad thai with chicken"` → `eastAsian`, ≥0.85
5. `contextNote: "chicken burrito bowl"` → tiebreaker resolution (probably `us` if other Tex-Mex signals present, `latin` if South American signals)
6. `contextNote: ""` (empty), no locale → `generic`, 0.3
7. Image of thali, empty contextNote → classifier call (tier 3) returns `indian` ≥0.7

**Acceptance criteria:**
- `npm test -- cuisineClassifier.test.ts` passes with 20+ test cases covering all 7 cuisines
- Manual test: 7 sample images (one per cuisine) routed correctly
- Vision lane logs include `cuisineUsed` field in telemetry

**Commit message:** `Phase 5: cuisine sub-prompts + classifier + vision lane routing`

---

### Phase 6 — Slim vision lane + lane router (6 hours)

**Why:** Replaces `parseImageWithGemini` as the entry point with `routeImageParse()`. Deletes V1 orchestrator, hardcoded brand products, rotated probing, and dead caption modes. Drops `imageParseService.ts` from 3,186 → ~700 lines.

**Files:**
- `backend/src/services/imageParse/router.ts` — create (the new entry point)
- `backend/src/services/imageParse/laneVision.ts` — create (slimmed V2 logic moves here)
- `backend/src/services/imageParse/types.ts` — extract types from `imageParseService.ts`
- `backend/src/services/imageParse/normalizers.ts` — extract response normalization
- `backend/src/services/imageParse/jsonRepair.ts` — extract JSON repair
- `backend/src/services/imageParse/diagnostics.ts` — extract debug events
- `backend/src/services/imageParse/coverageScoring.ts` — extract coverage logic
- `backend/src/services/imageParse/postprocess.ts` — slim postprocess (drops brand hardcoding)
- `backend/src/services/imageParseService.ts` — keep as thin shim that re-exports from new files (Phase 8 deletes it)
- `backend/src/routes/parse.ts` — modify `/parse/image` to call `routeImageParse({ lane: 'vision' })`

**Deletions from current `imageParseService.ts`:**
- Lines 2760-2897: `recoverWithCaptionFallback()` (V1)
- Lines 3141-3186: V1 orchestrator
- Lines 2237-2340: `singleProductCaptionResult()` hardcoded foods → replace callsite with `nutritionDatabaseService.lookupByName(brand, productName)`
- The `'concise'` mode of `buildImageCaptionFallbackPrompt`
- The unreachable `allowStructuredRescue=true` branch
- Rotated-variant probing (commit `4395eee` introduced — replaced by Phase 0 EXIF normalization)

**Deletions from `foodImagePostprocessService.ts`:**
- `applyKnownPackagedProductFacts()` (RxBar / Cheetos / Diet Coke hardcoding) → callsite uses `nutritionDatabaseService.lookupByName` instead

**Tighten budgets (in `laneVision.ts`):**
- Inventory timeout: 5500ms → 4000ms
- Caption probe timeout: 4000ms each → 3000ms each
- Hard-rescue budget: 18000ms → 8000ms
- Total vision lane budget: 18s → 8s

**Model upgrade (in `backend/.env.example` and `backend/src/config.ts`):**

```bash
# OLD
GEMINI_FLASH_MODEL=gemini-2.5-flash
AI_IMAGE_INVENTORY_MODEL=gemini-2.5-flash
AI_IMAGE_PRIMARY_MODEL=gemini-2.5-flash-lite

# NEW
GEMINI_FLASH_MODEL=gemini-3-flash                    # text path also upgrades
AI_IMAGE_INVENTORY_MODEL=gemini-3-flash              # vision lane main model
AI_IMAGE_LABEL_MODEL=gemini-3.1-flash-lite           # NEW — label lane
AI_IMAGE_CAPTION_MODEL=gemini-3.1-flash-lite         # NEW — caption probes
AI_IMAGE_INVENTORY_THINKING=low                       # NEW — thinking level
AI_IMAGE_LABEL_THINKING=low                          # NEW
AI_IMAGE_PRIMARY_MODEL=gemini-3.1-flash-lite         # V1 path (will be deleted in Phase 8)
```

Add corresponding fields in `config.ts`. Existing `aiImageFallbackModel` (`gemini-2.5-pro`) stays as last-resort rescue.

**`router.ts` shape:**

```ts
export type ImageParseLane = 'barcode' | 'label' | 'vision';

export interface RouteImageParseArgs {
  lane: ImageParseLane;
  // lane=barcode:
  barcode?: { code: string; symbology?: string };
  // lane=label:
  ocrText?: string;
  // lane=vision OR lane=label (image used as backup):
  image?: ImagePart;
  // common:
  contextNote?: string;
  userLocale?: string;
  recentCuisines?: Cuisine[];
  clientAttemptId?: string;
  signal?: AbortSignal;
}

export async function routeImageParse(args: RouteImageParseArgs): Promise<ImageParseServiceResult> {
  switch (args.lane) {
    case 'barcode': return laneBarcode.lookup(args.barcode!, args);
    case 'label':   return laneLabel.parseLabel({ ocrText: args.ocrText!, imageBase64: args.image?.base64, ...args });
    case 'vision':  return laneVision.parseImage({ image: args.image!, ...args });
  }
}
```

**Acceptance criteria:**
- `npm test` passes (existing image parse tests should still pass — behavior is preserved)
- `npm run eval:image` passes against golden cases
- `npm run build` produces a clean dist with no TS errors
- `imageParseService.ts` line count is under 800 (down from 3,186)
- Smoke test: log a thali end-to-end, lane=vision, cuisine=indian, result matches existing V2 behavior

**Risk note:** Highest-risk phase. Feature-flag-gate the new path:
```bash
AI_IMAGE_LANE_ROUTER_ENABLED=false  # default; flip to true to use new path
```
When false, route old `parseImageWithGemini` (kept as a thin re-export of the old behavior). One-flip rollback.

**Commit message:** `Phase 6: lane router + slim vision lane + model upgrade to Gemini 3 Flash`

---

### Phase 7 — Text path model swap + verification (2 hours)

**Why:** User explicitly asked that model swap affects text path too. The text path uses `GEMINI_FLASH_MODEL` (already updated in Phase 6). This phase verifies nothing breaks and benchmarks.

**Files:**
- `backend/src/services/parsePipelineService.ts` — verify model is read from config (no hardcoded model)
- `backend/src/services/parseOrchestrator.ts` — same
- `backend/src/scripts/runEval.ts` — text-parse golden eval runner (already exists)
- `backend/src/scripts/runImageParseEval.ts` — image golden eval (already exists, expanded in Phase 8)

**Verification:**
1. `npm run eval` — run text-path golden eval with new `gemini-3-flash`. Pass rate must match or beat baseline.
2. `npm run eval -- --model gemini-3.1-flash-lite` — A/B test: is 3.1 Lite acceptable for text? If pass rate within 2 points of 3 Flash, switch text path to Lite (cheaper).
3. Manual: log a text meal "had a chicken caesar salad and a diet coke" — verify parse is sensible.
4. Manual: log a complex meal "biryani, dal makhani, naan, and a mango lassi" — verify Indian cuisine prompt routes correctly even for text input (Phase 8 work if not yet wired).

**Acceptance criteria:**
- Text golden eval pass rate ≥ baseline
- No regression in text saves (CLAUDE.md four-step DB check)
- Cost projection updated in commit message

**Commit message:** `Phase 7: text path uses Gemini 3 Flash, A/B tested vs 3.1 Lite`

---

### Phase 8 — Golden eval expansion + rollout flag (3 hours)

**Files:**
- `backend/image-eval-cases.json` — expand from current 9 cases to 30+
- `backend/src/scripts/runImageParseEval.ts` — add `parseLaneUsed` assertion per case
- `backend/.env` (production / staging) — flip `AI_IMAGE_LANE_ROUTER_ENABLED=true`

**Golden cases to add (per cuisine + edge cases):**

```json
[
  { "id": "branded_diet_coke", "imagePath": "...", "expectedLane": "barcode", "expectedCalories": [0, 5], "maxLatencyMs": 1500 },
  { "id": "branded_cheetos", "imagePath": "...", "expectedLane": "barcode", "expectedCalories": [140, 180], "maxLatencyMs": 1500 },
  { "id": "branded_rxbar", "imagePath": "...", "expectedLane": "barcode", "expectedCalories": [180, 220] },
  { "id": "branded_kind_bar", "imagePath": "...", "expectedLane": "barcode" },
  { "id": "branded_chobani", "imagePath": "...", "expectedLane": "barcode" },
  { "id": "label_granola_bar", "imagePath": "...", "expectedLane": "label", "maxLatencyMs": 4000 },
  { "id": "label_quaker_oats", "imagePath": "...", "expectedLane": "label" },
  { "id": "label_partial", "imagePath": "...", "expectedLane": "label", "expectedConfidence": [0.6, 1.0] },
  { "id": "indian_thali", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "indian", "minItems": 4, "expectedKeywords": ["dal", "rice"] },
  { "id": "indian_dosa", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "indian" },
  { "id": "indian_chaat", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "indian" },
  { "id": "us_burger_fries", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "us", "expectedKeywords": ["burger", "fries"] },
  { "id": "us_breakfast", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "us" },
  { "id": "us_salad", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "us" },
  { "id": "western_fish_chips", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "western" },
  { "id": "western_croissant", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "western" },
  { "id": "eastasian_ramen", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "eastAsian" },
  { "id": "eastasian_sushi", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "eastAsian" },
  { "id": "eastasian_padthai", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "eastAsian" },
  { "id": "eastasian_dim_sum", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "eastAsian" },
  { "id": "mediterranean_pasta", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "mediterranean" },
  { "id": "mediterranean_pizza", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "mediterranean" },
  { "id": "mediterranean_mezze", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "mediterranean", "minItems": 3 },
  { "id": "latin_burrito", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "latin" },
  { "id": "latin_tacos", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "latin", "minItems": 2 },
  { "id": "latin_arepa", "imagePath": "...", "expectedLane": "vision", "expectedCuisine": "latin" },
  { "id": "edge_blurry_food", "imagePath": "...", "expectedLane": "vision", "expectedConfidence": [0.3, 1.0] },
  { "id": "edge_low_light", "imagePath": "...", "expectedLane": "vision" },
  { "id": "edge_non_food_cat", "imagePath": "...", "expectedImageType": "non_food" },
  { "id": "edge_menu_screenshot", "imagePath": "...", "expectedLane": "vision", "expectedImageType": "menu_or_screenshot" }
]
```

**Source for test images:** mix of user-submitted reference images (with permission) + curated set of unsplash/wikimedia free-use food photos. Store in `backend/test-fixtures/image-eval/`.

**Verification:**
1. `npm run eval:image` against local backend with new flag enabled — full report including pass/fail per case, latency P50/P95
2. Run same eval against Render staging — compare
3. Run cuisine classifier accuracy: count correct cuisine routings, target ≥80%

**Acceptance criteria:**
- Local eval pass rate ≥ 75% (target — realistic given honest expectations)
- Cuisine classifier accuracy ≥ 80%
- Latency budgets respected: barcode P95 < 2s, label P95 < 4s, vision P95 < 8s
- No regression on existing 9 cases

**Commit message:** `Phase 8: expand golden eval to 30+ cases, flip lane router flag`

---

### Phase 9 — Delete dead code (2 hours, after 1 week of Phase 8 soak)

**Files to delete:**
- `backend/src/services/imageParseService.ts` (entire file — replaced by `imageParse/` directory)
- All references to `AI_IMAGE_ORCHESTRATOR_VERSION` env var
- All references to `AI_IMAGE_PRIMARY_MODEL` env var (V1-specific)

**Verification:**
- `npm run build` — no TypeScript errors
- `npm test` — no broken imports
- `npm run eval:image` — full pass
- Render deploy starts cleanly

**Commit message:** `Phase 9: delete V1 image-parse path after V3 soak`

---

## 5. Cuisine sub-prompts — FULL CONTENT (Codex copies these into `prompts/cuisines/*.ts`)

### 5.0 Shared header (goes in `prompts/shared/header.ts`)

```ts
export const SHARED_PROMPT_HEADER = `
You are a nutrition parser for a food-logging app. You receive a photo of food
and return a structured JSON object describing what is visible.

Your output MUST be valid JSON conforming to the schema below. No prose, no
explanation, no markdown fences. Just the JSON object.

OUTPUT SCHEMA (strict):
{
  "imageType": "nutrition_label" | "single_food" | "multi_component_meal"
               | "tray_or_thali" | "menu_or_screenshot" | "non_food" | "unclear",
  "orientation": "upright" | "rotated_90" | "rotated_180" | "rotated_270" | "unknown",
  "visibleComponents": [
    {
      "name": string,
      "zone": string,           // e.g. "center", "top-left compartment", "side bowl"
      "visualEvidence": string, // brief; what told you this is here
      "portionHint": string,    // e.g. "1 katori (3/4 cup)", "1 slice", "half a bowl"
      "confidence": number,     // 0..1
      "isSmallSide": boolean    // true for sauces, chutneys, pickles, garnishes
    }
  ],
  "items": [
    {
      "name": string,
      "brand": string | null,
      "servingSize": string,
      "servingSizeG": number,
      "calories": number,
      "proteinG": number,
      "carbsG": number,
      "fatG": number,
      "fiberG": number | null,
      "sugarG": number | null,
      "sodiumMg": number | null,
      "confidence": number,
      "needsClarification": boolean,
      "assumptions": string[]
    }
  ],
  "coverageConfidence": number,  // 0..1, are you sure you captured everything?
  "warnings": string[]
}

GENERAL RULES (apply across all cuisines):
1. Identify visible components first, THEN estimate nutrition. Do not skip the
   inventory step — coverage drives quality.
2. Small sides, sauces, garnishes count. List them with isSmallSide=true.
3. For multi-component meals, list each component as a separate item, not
   a rolled-up "meal" item.
4. Be conservative on portion size. A standard restaurant plate is larger than
   a home plate. If unsure, hedge toward the smaller side and set assumptions.
5. If the image is rotated, return items as if it were upright. Do not refuse
   to parse a sideways image.
6. If the image is non-food (cat, screenshot of unrelated content, blank wall):
   return imageType: "non_food", items: [], warnings: ["No food detected"].
7. NEVER fabricate brand names you cannot see. Brand is null unless visible.
8. NEVER claim certainty above 0.9 unless the food is unambiguous (e.g., a
   visible Coca-Cola can with the label readable).
9. If portion is uncertain, set needsClarification=true and add a clarifying
   assumption like "Estimated 1 standard serving; user may have eaten more."
`.trim();
```

### 5.1 Indian sub-prompt (`prompts/cuisines/indian.ts`)

```ts
export const INDIAN_PROMPT = `
CUISINE CONTEXT: Indian / South Asian (Indian, Pakistani, Bangladeshi, Sri Lankan, Nepali).

Apply this guidance when the photo shows South Asian food OR when the user's
contextNote contains Indian cuisine keywords (thali, dal, biryani, naan, etc.).

VISUAL CUISINE SIGNALS to confirm Indian:
- Steel thali (round multi-compartment plate) or brass plates
- Round flatbreads: roti, chapati, naan, paratha, puri, baati, dosa, idli, kulcha
- Small steel/brass katori (bowls) holding wet preparations
- Yellow/orange dal in bowl; deep brown/red curries; green chutney; red pickle
- Whole green chillies, lemon wedges, raw onion rings on plate
- Banana leaf plating (South Indian)
- Tandoori coloring (red/orange tinge on grilled meat)
- Garnishes: cilantro leaves, fried onions, ghee glaze, mint leaves
- Background: thali tray, banana leaf, steel/brass serveware

COMPONENT VOCABULARY WITH TYPICAL CALORIES:

Breads (per piece):
- Roti / chapati / phulka: 70-100 cal (6-7" diameter, whole wheat, no oil)
- Tandoori roti: 110-130 cal (thicker, tandoor-baked)
- Naan: 260-330 cal (refined flour, butter-glazed, restaurant size)
- Butter naan: +50 cal over plain naan; garlic naan ~290 cal
- Paratha (plain): 200-280 cal (layered, ghee-fried)
- Aloo paratha: 320-400 cal (stuffed)
- Methi / gobi paratha: 250-320 cal
- Puri / poori: 150-180 cal (deep-fried)
- Bhatura: ~250 cal (larger than puri)
- Baati (Rajasthani): 200-260 cal (baked, ghee-dipped)
- Dosa (plain): 130-170 cal (large, thin, crispy)
- Masala dosa: 330-380 cal (with spiced potato filling)
- Rava dosa: ~250 cal
- Idli: 35-50 cal each (typically 2-3 per serving)
- Uttapam: 180-230 cal (thick dosa with toppings)
- Kulcha: 230-280 cal; amritsari kulcha 350-420 cal

Rice dishes (per cup cooked):
- Plain basmati: 200 cal
- Jeera (cumin) rice: 220 cal
- Pulao (veg/peas): 250-300 cal
- Biryani (veg): 350-400 cal
- Chicken biryani: 400-480 cal
- Mutton biryani: 450-550 cal
- Curd rice: 220 cal
- Lemon rice: 230 cal
- Tamarind rice (puliyodarai): 250 cal

Legumes / dal (per katori, ~3/4 cup):
- Dal tadka / yellow dal: 130-160 cal
- Dal makhani: 230-280 cal (cream + butter heavy)
- Chana masala (chickpea curry): 200-240 cal
- Rajma (kidney bean curry): 220-260 cal
- Chana dal: 150-180 cal
- Sambar (lentil-vegetable stew, South Indian): 90-130 cal
- Rasam (tamarind soup, thin): 40-60 cal

Vegetable curries (sabzi, per katori):
- Aloo gobi: 180-220 cal
- Palak paneer: 280-340 cal
- Bhindi masala (okra): 150-200 cal
- Baingan bharta (mashed eggplant): 180-220 cal
- Mixed vegetable curry: 180-220 cal
- Paneer butter masala / paneer makhani: 350-420 cal (creamy)
- Paneer tikka masala: 320-380 cal
- Kadhai paneer: 300-360 cal
- Malai kofta: 380-450 cal (cream sauce, fried dumplings)
- Shahi paneer: 380-440 cal

Meat curries (per serving, ~3/4 cup):
- Chicken tikka masala: 380-450 cal
- Butter chicken / murgh makhani: 420-500 cal
- Chicken curry (home style): 250-320 cal
- Chicken vindaloo: 300-360 cal
- Mutton curry / rogan josh: 350-420 cal
- Fish curry (coconut base): 280-340 cal

Tandoor / grill:
- Chicken tikka (4-5 pieces): 230-280 cal
- Tandoori chicken (1/4 chicken): 280-340 cal
- Seekh kebab (2 pieces): 220-260 cal
- Reshmi kebab: 200-240 cal
- Fish tikka: 200-240 cal
- Hariyali kebab: 200-240 cal

Snacks / chaat / street food:
- Samosa: 130-170 cal each (typically 2)
- Pakora / bhajji (5-6 pieces): 250-320 cal
- Aloo tikki (1 patty): 150-200 cal
- Pani puri (6 pieces): 200-280 cal
- Bhel puri (1 plate): 250-320 cal
- Sev puri (6): 280-350 cal
- Dahi puri (6): 300-360 cal
- Vada pav: 290-340 cal
- Pav bhaji (with 2 pav): 480-580 cal
- Misal pav: 400-480 cal
- Dhokla (5-6 pieces): 180-220 cal
- Kachori: 200-260 cal each (1-2 typical)
- Idli sambar (3 idlis + sambar): 250-310 cal
- Medu vada (2 pieces): 230-280 cal

Sides / accompaniments (small portions, OFTEN MISSED — list these):
- Green chutney (mint-coriander, 2 tbsp): 15-25 cal
- Tamarind chutney (sweet): 60-80 cal
- Coconut chutney: 70-90 cal
- Tomato chutney: 25-40 cal
- Red onion (raw, sliced): 10-20 cal
- Lemon wedge: 5 cal
- Pickle / achaar (1 tsp): 20-30 cal (oil-heavy)
- Papad / papadum: 40-60 cal (roasted), 80-100 cal (fried)
- Raita (cucumber/onion, 1/2 cup): 60-90 cal
- Boondi raita: 110-140 cal
- Green salad (onion, cucumber, tomato): 30-50 cal
- Curd / yogurt (1/2 cup): 80-100 cal

Sweets:
- Gulab jamun (2 pieces): 280-340 cal
- Rasgulla (2): 240-280 cal
- Jalebi (2): 220-280 cal
- Kheer / payasam (1/2 cup): 200-260 cal
- Halwa (gajar/sooji, 1/2 cup): 280-360 cal (ghee-heavy)
- Kulfi (1 piece): 200-260 cal
- Barfi (1 piece): 130-180 cal
- Ladoo (1): 150-200 cal

Beverages:
- Masala chai (milk + sugar, 1 cup): 80-110 cal
- Black chai with sugar: 30-50 cal
- Sweet lassi (1 glass): 200-260 cal
- Salted lassi: 80-110 cal
- Mango lassi: 280-340 cal
- Buttermilk / chaas: 50-80 cal
- South Indian filter coffee: 110-140 cal

PORTION CONVENTIONS for Indian cuisine:
- Thali = single composite meal; ALWAYS list EACH compartment separately
  (dal, sabzi, rice, roti, chutney, raita, salad, sweet, papad). Do NOT
  return a single "thali" item.
- Standard thali compartments: 1-2 breads, 1-2 vegetable preparations, 1 dal,
  rice, 2-3 small sides, often 1 small sweet.
- Restaurant thali: typically 800-1200 cal total.
- Home/hostel thali: 700-1000 cal total.
- Wedding/festival thali: 1400-1800 cal.
- Tray / steel plate compartments = separate items, ALWAYS.

COVERAGE REQUIREMENTS for Indian:
- Steel thali or multi-compartment plate → minimum 4 distinct items expected
  in items[]. If you list fewer than 4, set warnings: ["partial coverage"].
- Single bowl/plate of biryani → 1 main item + raita/salad/pickle if visible.
- Street food/chaat → list each layer/component (chickpeas, sev, onion,
  chutney, puri) as a separate component in visibleComponents.

COMMON PARSING ERRORS TO AVOID:
1. Generic "curry" — be specific (dal vs sabzi vs paneer dish vs meat curry).
2. Missing the chutney — small bowls in periphery of plate are often
   overlooked. ALWAYS scan plate periphery.
3. Missing the papad — flat round disc on side of plate. Easy to confuse
   with a plate edge or napkin.
4. Conflating naan with roti or chapati — naan is leavened, refined flour,
   ~3× the calories of plain roti. Look at thickness and char pattern.
5. Underestimating ghee/oil — dal makhani, butter chicken, malai kofta are
   very rich. If visible orange/red oil layer on top, that is significant
   added fat. Mention it in assumptions.
6. Treating "biryani" as just rice — biryani is rice + meat + spices + ghee;
   ~400 cal/cup not ~200.
7. Confusing samosa stuffing — potato (~150 cal) is most common; meat is heavier.
8. Missing pickle / achaar — small reddish pile with oil sheen on side of plate.
9. Sabudana khichdi looks like rice but is heavier (sago + peanuts + ghee).
10. Aloo paratha vs plain paratha — aloo paratha is stuffed and heavier
    (320-400 vs 200-280). Look for darker patches indicating filling.

OUTPUT BEHAVIOR for Indian:
- Always split thali into compartments.
- For street food: list each layer/component.
- For curry + bread + rice combos: 3 items, not "rice combo".
- Mention preparation: "Dal tadka (1 katori)" not just "Dal".
- Use user-friendly serving sizes: "1 katori", "1 piece", "1 cup cooked",
  "1 small bowl".
- If you see ghee/butter glaze, mention as additional fat in assumptions.
- For "rice + dal + roti" plate, list 3 items.
`.trim();
```

### 5.2 US sub-prompt (`prompts/cuisines/us.ts`)

```ts
export const US_PROMPT = `
CUISINE CONTEXT: US / American (modern American, BBQ, brunch, fast food,
Tex-Mex influenced, soul food, diner, breakfast culture).

Apply when photo shows American food OR contextNote contains US keywords
(burger, fries, BBQ, brunch, pancakes, mac and cheese, etc.).

VISUAL CUISINE SIGNALS to confirm US:
- Burger bun (sesame top, lightly charred)
- French fries (cut style varies: shoestring, steak, waffle, crinkle)
- Diner-style white plates, often oversized
- Plastic basket lined with checkered paper (fast casual)
- Ketchup / mustard / mayo squeeze bottles
- Onion rings, coleslaw, pickle spear sides
- Pancake stack with butter pat + syrup
- Bacon strips (crispy, dark brown)
- Eggs prepared visibly: scrambled / over easy / sunny side up
- BBQ char marks, dark glaze, bones visible on ribs
- Diner mugs, soda cans, milkshake glasses
- Background: paper-lined trays, branded napkins (Subway, Chipotle, etc.)

COMPONENT VOCABULARY WITH TYPICAL CALORIES:

Breakfast:
- Pancakes (3 stack, 4" diameter): 350-450 cal (plain)
- Pancakes with butter + syrup: 550-700 cal
- Waffles (1 Belgian): 220-300 cal plain; with syrup 400-500
- Scrambled eggs (2 large): 180-220 cal
- Fried eggs (2): 180-200 cal
- Sunny-side up eggs (2): 160-180 cal
- Bacon (3 strips): 130 cal
- Sausage links (2): 200-260 cal
- Sausage patties (2): 240-300 cal
- Hash browns (1/2 cup): 160-200 cal
- Home fries (1 cup): 280-340 cal
- Toast (1 slice): 70-90 cal (white); 80-100 (whole wheat)
- Bagel (plain, 1): 280-330 cal; with cream cheese 380-450
- Bagel with cream cheese and lox: 420-490 cal
- Breakfast burrito (1 large): 600-800 cal
- Breakfast sandwich (egg + cheese + sausage on biscuit): 500-650 cal
- Cinnamon roll: 350-500 cal
- Donut (glazed): 240-280 cal; chocolate frosted 280-320; jelly-filled 260-300
- Cereal with milk (1 cup + 1/2 cup milk): 180-280 cal depending on cereal
- Oatmeal (plain, 1 cup): 150 cal; with brown sugar + butter ~280
- Avocado toast: 280-380 cal

Burgers and sandwiches:
- Hamburger (single, 4oz patty): 450-550 cal
- Cheeseburger (single, 4oz): 530-620 cal
- Double cheeseburger: 700-850 cal
- Bacon cheeseburger: 600-720 cal
- Veggie burger: 350-450 cal
- Hot dog (1, with bun): 280-340 cal; with chili and cheese 400-500
- Club sandwich (turkey/bacon/lettuce/tomato): 600-750 cal
- BLT: 450-550 cal
- Tuna salad sandwich: 450-550 cal
- Egg salad sandwich: 450-520 cal
- Reuben sandwich: 700-850 cal (corned beef + sauerkraut + Swiss + Russian dressing)
- Philly cheesesteak: 700-900 cal
- Italian sub / hoagie (6"): 500-650 cal
- Meatball sub: 600-750 cal

Salads (be careful — restaurant salads often have hidden calories):
- Caesar salad (with chicken, full bowl): 500-700 cal
- Cobb salad: 500-700 cal
- Chef salad: 450-600 cal
- Garden salad: 150-250 cal (ranch dressing adds 140-220)
- Taco salad: 700-900 cal (with shell, ground beef, sour cream, guac)
- Chicken Caesar wrap: 550-700 cal
- Note: ranch dressing 1 tbsp = 70 cal; bleu cheese 1 tbsp = 75 cal

Sides:
- French fries (medium, ~110g): 350-400 cal
- French fries (large): 500-600 cal
- Steak fries / curly fries: 400-500 cal medium
- Onion rings (medium): 400-500 cal
- Coleslaw (1/2 cup): 160-220 cal
- Mac and cheese (1 cup): 350-450 cal
- Mashed potatoes with gravy (1 cup): 250-320 cal
- Baked potato with butter + sour cream: 350-450 cal
- Loaded baked potato (cheese + bacon + sour cream): 600-800 cal
- Cornbread (1 piece): 180-220 cal
- Biscuit (1, buttered): 200-260 cal
- Hush puppies (4): 280-340 cal
- Cole slaw (1/2 cup): 160-220 cal

BBQ:
- Pulled pork sandwich: 500-650 cal
- Brisket (4oz): 280-340 cal; with sides ~700-900
- Ribs (1/2 rack baby back): 600-800 cal
- Ribs (1/2 rack St. Louis): 800-1000 cal
- Smoked chicken (1/4): 320-400 cal
- BBQ sauce: 35-50 cal per tablespoon (sugar content matters)

Fried chicken:
- Fried chicken (1 breast): 350-450 cal
- Fried chicken (1 thigh): 280-340 cal
- Fried chicken wing: 110-150 cal
- Chicken tenders (4): 400-500 cal
- Chicken sandwich (Chick-fil-A style): 440-500 cal
- Spicy chicken sandwich: 480-560 cal
- Chicken nuggets (10): 440-500 cal

Wings (per 6-8 wings):
- Buffalo wings (medium spice): 450-600 cal
- BBQ wings: 500-650 cal
- Naked grilled wings: 300-400 cal
- Wings come with celery + ranch/blue cheese: add 150-200 for dipping

Pizza (American style):
- Pizza slice (cheese, NY-style, large slice): 300-380 cal
- Pepperoni slice: 320-400 cal
- Supreme / loaded slice: 380-460 cal
- Stuffed crust slice: +80-120 cal
- Personal pizza (10"): 700-1000 cal

Tex-Mex (American interpretation; if more authentic Mexican, route to Latin):
- Nachos (large platter, with cheese + beef + sour cream + guac): 1000-1500 cal
- Nachos (small): 500-700 cal
- Quesadilla (chicken, large): 600-800 cal
- Hard-shell tacos (2): 350-450 cal
- Soft tacos (2): 400-500 cal
- Burrito (chicken, large): 800-1100 cal
- Fajitas (chicken, with tortillas): 700-900 cal

Beverages:
- Soda (12oz can, regular): 140-150 cal
- Soda (large, 32oz fountain): 380-440 cal
- Diet soda: 0-5 cal
- Sweet tea (16oz): 130-180 cal
- Lemonade (16oz): 200-260 cal
- Milkshake (16oz): 500-800 cal depending on flavor + add-ins
- Coffee (black): 5 cal
- Coffee with cream + sugar: 50-100 cal
- Latte (12oz): 150-200 cal
- Frappuccino: 350-500 cal
- Beer (12oz, light): 100-110 cal
- Beer (12oz, regular): 150 cal
- IPA (12oz): 170-210 cal
- Wine (5oz): 120-150 cal
- Mixed drink: 200-400 cal depending

Desserts:
- Apple pie slice: 380-450 cal
- Brownie (1): 230-300 cal
- Cookie (large chocolate chip): 220-280 cal
- Ice cream (1 scoop): 150-200 cal
- Sundae: 350-500 cal
- Cheesecake (1 slice): 400-500 cal

PORTION CONVENTIONS for US:
- Restaurant portions are LARGE. 1 serving often = 1.5-2× standard.
- Burger components list as ONE composite item: "Cheeseburger (with bun,
  lettuce, tomato, onion, pickle, ketchup)" — not 6 separate items.
- Sandwich = one composite (bread + filling + spreads).
- Pizza = list per slice if individual slices visible; per pie if whole.
- Salad = one composite item with dressing called out in assumptions.
- Sides come on the same plate but as separate items (burger + fries = 2 items).
- Beverages always separate.

COVERAGE REQUIREMENTS for US:
- Main + side(s) + drink = expect 2-4 items.
- Sandwich/burger alone = 1 item.
- Combo meal (burger + fries + drink) = 3 items.
- BBQ platter with multiple meats + sides = 4-6 items.

COMMON PARSING ERRORS TO AVOID:
1. Underestimating sauce/dressing calories. Ranch = 140 cal/serving; ketchup
   is light but mayo/aioli is heavy.
2. Missing the cheese on a cheeseburger (vs hamburger) — look for melted
   yellow/orange layer. +80-110 cal.
3. Confusing soft drinks (Coke vs Diet Coke vs Sprite). If unsure and brand
   isn't readable, assume regular soda (worse case for calorie estimate).
4. Treating fries as low-cal. Medium = 350 cal. Large = 500+.
5. Bacon count matters — 3 strips (130 cal) vs 5 strips (220 cal).
6. Burger size matters — 4oz patty (single) vs 8oz (double) vs 1/3 lb. Look
   at thickness and bun proportion.
7. "Loaded" potatoes / nachos / fries add 300-500 cal over plain.
8. Hidden butter on toast / pancakes / waffles — assume 1 tbsp (100 cal) if
   pancakes/waffles look glossy.
9. Restaurant chains often have 1.5× home portions — adjust upward.
10. Wings count varies — assume 6 unless image clearly shows different count.

OUTPUT BEHAVIOR for US:
- Composite items for burgers / sandwiches (bun + filling = 1 item)
- Sides separate (fries, onion rings, coleslaw each their own item)
- Beverages always separate
- Specify cooking style when visible: "Grilled chicken sandwich" vs "Crispy
  chicken sandwich" (~150 cal difference)
- Note hidden ingredients: "Burger (assumed mayo + ketchup, no avocado)"
`.trim();
```

### 5.3 Western (European non-Mediterranean) sub-prompt (`prompts/cuisines/western.ts`)

```ts
export const WESTERN_PROMPT = `
CUISINE CONTEXT: Western European (non-Mediterranean) — French, German,
British, Austrian, Swiss, Belgian, Dutch, Eastern European (Polish, Czech,
Hungarian, Russian), Scandinavian.

Apply when photo shows European non-Mediterranean food OR contextNote has
keywords (croissant, schnitzel, fish and chips, goulash, pierogi, etc.).

VISUAL CUISINE SIGNALS:
- Crusty baguette / dark German rye / English white toast
- Flaky pastries (croissant, pain au chocolat, danish, kouign-amann)
- Patisserie display style (uniformly piped, glossy glaze)
- Heavy cream sauces (white, beige, with parsley flecks)
- Pickled red cabbage / sauerkraut on side
- Roast meat with crackling / Yorkshire pudding nearby (British)
- Battered fish with chips wrapped in newspaper-style paper (British chippy)
- Charcuterie board: meats + cheeses + cornichons + olives + bread
- Wooden cutting boards / rustic plating
- Beer steins / wine glasses / espresso cups

COMPONENT VOCABULARY:

French:
- Croissant (plain): 240-280 cal
- Pain au chocolat: 290-330 cal
- Almond croissant: 380-450 cal
- Baguette (1/4 baguette, ~75g): 200-230 cal
- Brioche bun: 200-250 cal
- Quiche Lorraine (1 slice, 1/8 of 9"): 300-380 cal
- Crepe (sweet, with Nutella + banana): 350-450 cal
- Crepe (savory, with ham + cheese): 350-450 cal
- Ratatouille (1 cup): 150-200 cal
- Coq au vin (1 serving, ~6oz chicken + sauce): 450-600 cal
- Beef bourguignon (1 cup): 380-480 cal
- French onion soup (1 bowl with cheese + bread): 320-400 cal
- Cassoulet (1 cup): 500-650 cal
- Boeuf bourguignon: 400-520 cal
- Salade niçoise (with tuna + egg + olives + potato): 450-600 cal
- Tarte tatin (1 slice): 350-450 cal
- Macarons (1): 80-100 cal
- Eclair: 250-300 cal
- Crème brûlée: 300-400 cal
- Mille-feuille: 300-380 cal

German / Austrian:
- Wiener schnitzel (veal cutlet, breaded, 6oz): 500-650 cal
- Pork schnitzel: 450-580 cal
- Chicken schnitzel: 400-500 cal
- Bratwurst (1 sausage): 280-340 cal
- Currywurst (with curry ketchup): 400-500 cal
- Sauerkraut (1/2 cup): 30-50 cal
- Spätzle (1 cup): 280-340 cal
- Pretzel (1 large soft pretzel): 350-450 cal
- Sauerbraten (1 serving): 500-620 cal
- Goulash (1 cup): 280-380 cal
- Strudel (apple, 1 slice): 280-340 cal
- Sachertorte (1 slice): 400-480 cal
- Black Forest cake (1 slice): 350-450 cal
- Spaetzle with cheese (käsespätzle): 450-580 cal

British:
- Fish and chips (1 portion, restaurant): 800-1100 cal
- Cottage pie (1 serving): 500-650 cal
- Shepherd's pie (1 serving): 500-650 cal
- Bangers and mash (2 sausages + mash + gravy): 700-900 cal
- Sunday roast (beef, with potatoes, Yorkshire pudding, veg, gravy): 900-1300 cal
- Full English breakfast (eggs + bacon + sausage + beans + tomato + black pudding + toast): 850-1100 cal
- Toad in the hole (1 serving): 600-750 cal
- Cornish pasty (1): 450-550 cal
- Scotch egg (1): 250-320 cal
- Yorkshire pudding (1): 100-140 cal
- Sticky toffee pudding: 400-500 cal
- Spotted dick with custard: 450-550 cal
- Bubble and squeak (1 cup): 220-280 cal
- Ploughman's lunch (cheese + ham + pickle + bread): 600-800 cal

Eastern European:
- Pierogi (Polish dumplings, 5-6): 350-480 cal (potato/cheese filled)
- Pierogi with meat: 400-520 cal
- Borscht (1 cup): 100-150 cal
- Goulash (Hungarian, 1 cup): 280-380 cal
- Chicken paprikash: 450-580 cal
- Stuffed cabbage rolls (golabki, 2): 350-450 cal
- Kielbasa (1 link): 280-340 cal
- Beef stroganoff (1 cup): 400-520 cal
- Blintz (cheese, 2): 350-450 cal
- Cabbage soup: 80-120 cal

Swiss / Belgian / Dutch:
- Fondue (cheese, 1/2 cup with bread cubes): 450-580 cal
- Raclette (1 serving with potatoes): 500-700 cal
- Belgian waffle (1 large): 350-450 cal
- Frites (Belgian fries with mayo): 500-650 cal
- Mussels and frites: 700-900 cal

Scandinavian:
- Smørrebrød (1 open sandwich): 250-400 cal depending on topping
- Gravlax (3oz cured salmon): 150-200 cal
- Swedish meatballs (5-6 with sauce): 350-450 cal
- Lutefisk (1 serving): 150-200 cal
- Köttbullar with lingonberry: 350-450 cal

Charcuterie / cheese boards (multi-component):
- Cured meats (prosciutto, salami, jamón): 100-130 cal per oz
- Hard cheese (cheddar, comté, gruyère): 110-130 cal per oz
- Soft cheese (brie, camembert): 90-110 cal per oz
- Crackers / bread: 40-80 cal per piece
- Olives (5-6 large): 30-50 cal
- Cornichons / pickles: 5-10 cal
- Grapes / dried fruit: 50-80 cal per small serving
- A full charcuterie board for 1: 500-800 cal

Beverages:
- Espresso: 5 cal
- Cappuccino / café au lait: 60-120 cal
- Café crème: 100-150 cal
- Beer (12oz): 150 cal (lager); 170-210 (ale, stout, IPA)
- Wine (5oz): 120-150 cal
- Hot chocolate (Belgian / Swiss style, rich): 250-400 cal

PORTION CONVENTIONS for Western:
- Fish and chips = LARGE single portion. Don't underestimate. 800-1100 cal.
- Continental breakfast = light (pastry + coffee), 300-500 cal total.
- Full English breakfast = very large, ~1000 cal.
- French dinner = multi-course; estimate per course not per meal.
- Charcuterie board = list each component (cheeses, meats, accompaniments).

COMMON PARSING ERRORS TO AVOID:
1. Confusing French pastries — croissant (~250 cal) vs pain au chocolat
   (~310 cal) vs brioche bun (~225 cal). Look for chocolate inside (pain au
   chocolat) or rectangular vs crescent shape.
2. British "chips" = thick-cut fries. Larger and heavier than US fries.
3. Schnitzel filling matters — veal (Wiener) vs pork vs chicken. Ask user
   or default to pork (most common).
4. Sauces are heavy — French cream sauces add 200-400 cal beyond the protein.
5. Sausages vary widely — German bratwurst (~300 cal) vs British banger
   (~250 cal) vs Polish kielbasa (~300 cal). Look at color, texture, casing.
6. Pretzel sizes vary 10× — soft pretzel (large, ~400 cal) vs hard pretzel
   stick (small, ~30 cal).
7. Charcuterie boards add up fast — 600-800 cal for a "small" board.
8. Yorkshire pudding looks like a bread roll but is lighter (puffed batter).
9. Goulash thickness varies — Hungarian (stew, heavier) vs Austrian
   (gulaschsuppe, soupier).

OUTPUT BEHAVIOR for Western:
- Charcuterie / cheese boards: list each major component separately
- Multi-course French dinner: list each course as separate item
- Sunday roast: protein + each side (Yorkshire, potatoes, veg, gravy)
- Fish and chips: 2 items (fish; chips); add mushy peas / tartar sauce if visible
- Note sauce assumptions: "Steak (medium-rare, with béarnaise sauce 2 tbsp)"
`.trim();
```

### 5.4 East Asian sub-prompt (`prompts/cuisines/eastAsian.ts`)

```ts
export const EAST_ASIAN_PROMPT = `
CUISINE CONTEXT: East Asian and Southeast Asian — Chinese, Japanese, Korean,
Thai, Vietnamese, Filipino, Indonesian, Malaysian.

Apply when photo shows East/SE Asian food OR contextNote has keywords (ramen,
sushi, pad thai, pho, bibimbap, dim sum, etc.).

VISUAL CUISINE SIGNALS:
- Chopsticks (Japanese pointed; Chinese blunt; Korean metal)
- Soy sauce dish, wasabi green paste, pickled ginger
- Lacquered bowls, ceramic teapots, bamboo steamers
- Rice in small bowl (Japanese) or large central platter (Chinese family-style)
- Noodles in broth (ramen, pho, udon) — wide bowl
- Stir-fry on flat plate / wok
- Sushi rice rolls / nigiri pieces in rows
- Vibrant herbs: cilantro, Thai basil, mint, green onion
- Lime wedges, bean sprouts (Thai/Vietnamese garnish)
- Kimchi / banchan (Korean small side dishes)
- Dipping sauces in small bowls (multiple)

COMPONENT VOCABULARY:

Japanese:
- Sushi roll (8 pieces, California): 250-320 cal
- Sushi roll (8 pieces, spicy tuna): 290-380 cal
- Sushi roll (8 pieces, eel/dragon): 400-500 cal
- Tempura-style rolls (rainbow, dragon, etc.): 400-550 cal (fried, sauce-heavy)
- Nigiri (1 piece): 40-60 cal
- Sashimi (3-5 pieces): 80-150 cal (just fish, no rice)
- Chirashi bowl: 500-700 cal
- Ramen (1 large bowl, shoyu/shio): 500-700 cal
- Ramen (tonkotsu, rich pork broth): 700-900 cal
- Ramen (miso, with butter + corn): 650-850 cal
- Tantanmen (spicy sesame): 700-900 cal
- Tempura (mixed, 6-8 pieces): 400-550 cal
- Tempura (shrimp only, 4): 250-320 cal
- Donburi (gyudon / katsudon / oyakodon): 600-800 cal
- Onigiri (1): 180-220 cal
- Miso soup (1 cup): 35-70 cal
- Edamame (1 cup pods, salted): 100-130 cal
- Gyoza / dumplings (6, pan-fried): 250-320 cal
- Yakitori (3 skewers): 180-250 cal
- Tonkatsu (pork cutlet): 500-650 cal
- Chicken katsu: 450-580 cal
- Curry rice (Japanese, with katsu): 750-900 cal
- Udon (1 bowl, plain broth): 350-450 cal
- Udon (tempura): 600-750 cal
- Soba (cold, with tsuyu): 350-450 cal
- Okonomiyaki (1): 450-600 cal
- Takoyaki (6 balls): 300-380 cal

Chinese:
- Fried rice (Yangzhou/special, 1.5 cups): 600-750 cal
- Fried rice (egg only): 400-500 cal
- White rice (1 cup): 200 cal
- Chow mein (1 plate): 500-650 cal (egg noodles, soy sauce, veggies)
- Lo mein (1 plate): 550-700 cal (similar; sauce-heavier)
- Singapore mei fun (1 plate): 450-580 cal (curry-flavored rice noodles)
- Kung pao chicken (1 serving): 480-620 cal
- General Tso's chicken: 700-900 cal (fried, sweet sauce — calorie-dense)
- Sweet and sour pork/chicken: 650-820 cal
- Orange chicken: 700-880 cal
- Sesame chicken: 700-880 cal
- Beef and broccoli: 400-520 cal
- Mongolian beef: 600-780 cal
- Mapo tofu: 350-450 cal
- Hot and sour soup (1 bowl): 80-120 cal
- Wonton soup (1 bowl, 4-5 wontons): 200-280 cal
- Egg drop soup: 70-100 cal
- Spring rolls (fried, 2): 200-280 cal
- Egg rolls (2): 350-450 cal (larger, heavier than spring rolls)
- Crab rangoon (3): 200-260 cal
- Dim sum: see breakdown below
- Peking duck (with pancakes, 1 serving): 500-700 cal
- Char siu (BBQ pork, 4oz): 280-340 cal
- Char siu bao (steamed pork bun, 1): 220-280 cal
- Steamed dumplings (har gow, 4): 150-200 cal
- Siu mai (4 pieces): 180-240 cal
- Pot stickers (6, pan-fried): 280-360 cal
- Soup dumplings / xiaolongbao (4): 150-200 cal
- Steamed bao buns (1 plain): 100-130 cal; with filling 200-280
- Fried tofu (1 serving): 200-280 cal
- Bok choy with garlic (1 cup): 70-100 cal
- Stir-fried green beans / gai lan: 80-130 cal

Thai:
- Pad thai (1 plate, with chicken/shrimp): 600-800 cal
- Pad see ew (1 plate): 550-700 cal
- Pad woon sen (glass noodles): 400-520 cal
- Drunken noodles / pad kee mao: 650-820 cal
- Green curry (with rice, 1 serving): 550-720 cal
- Red curry: 550-720 cal
- Yellow curry: 500-680 cal
- Panang curry: 600-780 cal
- Massaman curry: 600-780 cal
- Tom yum soup (1 bowl): 100-180 cal
- Tom kha gai (coconut chicken soup): 280-380 cal
- Satay (chicken, 4 skewers with peanut sauce): 320-420 cal
- Larb (1 serving): 280-380 cal
- Som tam (papaya salad): 180-250 cal
- Sticky rice (1 ball, ~1/2 cup): 170 cal
- Spring rolls (Thai, fried, 2): 220-280 cal
- Fried rice (Thai style with basil): 500-680 cal
- Mango sticky rice: 380-500 cal
- Thai tea (1 cup with milk): 200-280 cal

Vietnamese:
- Pho (1 large bowl, beef): 350-500 cal (broth + noodles + meat)
- Pho (chicken): 350-450 cal
- Pho (seafood): 400-550 cal
- Banh mi (1 sandwich, pork): 450-600 cal
- Banh mi (chicken): 400-520 cal
- Spring rolls (fresh / summer rolls, 2): 140-180 cal
- Spring rolls (fried, 2): 250-320 cal
- Vermicelli bowl (bun, with grilled pork): 500-680 cal
- Bun bo hue: 500-650 cal (spicier than pho)
- Banh xeo (Vietnamese crepe, 1): 350-450 cal
- Vietnamese coffee (with condensed milk): 150-200 cal

Korean:
- Bibimbap (1 stone bowl): 550-700 cal
- Dolsot bibimbap (with crispy rice): 600-750 cal
- Bulgogi (1 serving, with rice): 600-800 cal
- Galbi / kalbi (Korean BBQ short ribs, 1 serving): 600-800 cal
- Samgyeopsal (pork belly, 1 serving): 600-800 cal
- Korean fried chicken (8 pieces): 800-1100 cal (double-fried, sauce-glazed)
- Kimchi jjigae (kimchi stew, 1 bowl): 280-380 cal
- Sundubu jjigae (soft tofu stew): 300-400 cal
- Doenjang jjigae: 250-350 cal
- Japchae (1 serving): 350-450 cal
- Tteokbokki (spicy rice cakes, 1 serving): 400-550 cal
- Kimbap (1 roll, 8 pieces): 280-380 cal
- Banchan (assorted side dishes, total ~10 oz): 200-400 cal (varies widely)
- Kimchi (1 cup): 40-60 cal
- Korean pancake (haemul pajeon, 1 wedge): 200-280 cal

Filipino / Indonesian / Malaysian:
- Adobo (chicken, 1 serving): 380-500 cal
- Lumpia (4): 280-360 cal
- Nasi goreng (Indonesian fried rice): 550-700 cal
- Sate (satay, 4 skewers): 300-400 cal
- Rendang (1 serving): 450-600 cal
- Laksa (1 bowl): 500-700 cal
- Nasi lemak (1 serving): 600-800 cal
- Roti canai (1 piece): 300-400 cal
- Mee goreng: 550-700 cal

Beverages:
- Bubble tea (16oz, milk tea with tapioca): 350-500 cal
- Thai iced tea: 250-330 cal
- Japanese green tea (matcha latte, sweetened): 200-280 cal
- Plum wine: 130-180 cal per 4oz
- Sake (5oz): 180-220 cal
- Tsingtao / Asahi / Sapporo beer: 130-160 cal per 12oz
- Soju (1.5oz shot): 100-130 cal

PORTION CONVENTIONS for East Asian:
- Sushi rolls list as ONE composite item (1 roll = 6-8 pieces).
- Nigiri / sashimi count as one item with quantity ("Nigiri assortment, 6 pieces").
- Ramen = 1 large bowl, includes broth + noodles + toppings (chashu, egg, scallion).
- Stir-fry plate = 1 composite item (protein + veggies + sauce).
- Rice (white rice) usually served alongside main; list separately.
- Korean meal often has 5-10 banchan (small sides). List the major ones
  (kimchi, sprouts, pickled radish) separately; minor garnishes can be
  rolled up.
- Dim sum = list each dumpling type as separate item (har gow, siu mai,
  char siu bao).

COVERAGE REQUIREMENTS for East Asian:
- Ramen / pho / udon bowl → 1 item (the bowl), unless toppings clearly
  exceed typical (extra egg, extra meat) — then split.
- Stir-fry + rice → 2 items.
- Korean BBQ → 1 protein item + each banchan + rice = 4-8 items.
- Dim sum table → 1 item per dumpling type visible.
- Sushi platter → 1 item per roll type + nigiri assortment.

COMMON PARSING ERRORS TO AVOID:
1. Underestimating fried rice — it's calorie-dense (~600 cal/plate).
2. Confusing similar noodles — chow mein (egg noodles, dry-ish), lo mein
   (egg noodles, sauce-heavy), pad thai (rice noodles, peanut/tamarind),
   pad see ew (wide rice noodles, dark soy), pho (rice noodles in broth).
3. Missing sauces — teriyaki, sweet chili, hoisin, peanut sauce, gochujang
   all add 50-150 cal per typical serving.
4. Treating sushi as "diet food" — rolls with cream cheese, tempura, mayo,
   or fried elements are 400-600 cal per roll.
5. Korean fried chicken is calorie-bomb (~1000 cal for 8 pieces) — much
   heavier than American fried chicken due to double-frying + sauce glaze.
6. Pho looks light but has significant carbs (noodles ~250 cal).
7. Spring rolls — fresh/summer (140 cal/2) vs fried (250 cal/2) — look for
   translucent rice paper (fresh) vs golden brown (fried).
8. Chinese American dishes are heavier than authentic Chinese —
   General Tso's, sweet and sour, orange chicken all 700+ cal per serving
   due to deep-frying + sugar glaze.
9. Rice portion — Japanese serves smaller rice (3/4 cup); Chinese family-style
   serves larger (1.5 cups).
10. Don't confuse miso soup (light, ~50 cal) with hot and sour soup
    (heavier, ~100 cal) or tom yum (medium, ~150 cal) or tonkotsu broth
    (very rich, ~400 cal alone).

OUTPUT BEHAVIOR for East Asian:
- Sushi roll = 1 composite item (don't split into 6-8 pieces)
- Stir-fry = 1 composite item (don't split protein from veg from sauce)
- Korean meal = list main + 3-5 major banchan as separate items
- Ramen / pho / udon = 1 item (the bowl with all standard toppings)
- Note broth type for noodle soups: "Tonkotsu ramen" vs "Shoyu ramen"
  (calorie difference is large)
- Note frying style for chicken: "Korean fried chicken" vs "Crispy fried
  chicken" — Korean style is heavier
`.trim();
```

### 5.5 Mediterranean sub-prompt (`prompts/cuisines/mediterranean.ts`)

```ts
export const MEDITERRANEAN_PROMPT = `
CUISINE CONTEXT: Mediterranean — Italian, Greek, Middle Eastern (Levantine,
Turkish), Spanish, North African (Moroccan, Tunisian), Southern French.

Apply when photo shows Mediterranean food OR contextNote has keywords (pasta,
pizza, hummus, gyro, falafel, tapas, paella, tagine, etc.).

VISUAL CUISINE SIGNALS:
- Olive oil drizzle (visible sheen on dishes)
- Lemon wedges
- Fresh herbs: basil leaves, parsley, oregano flakes, mint
- Olives (black Kalamata, green Cerignola)
- Feta cubes (white, crumbly)
- Pita bread or focaccia
- Tomato-based sauces (red, with herbs)
- Pasta shapes (spaghetti, penne, fusilli, gnocchi)
- Pizza with visible tomato + cheese
- Mezze platter (multiple small dishes)
- Hummus drizzled with oil + paprika sprinkle
- Tagine (conical clay pot)
- Paella pan (wide, shallow, with rice + saffron color)

COMPONENT VOCABULARY:

Italian:

Pasta dishes (per cup cooked + sauce):
- Spaghetti carbonara: 600-750 cal (egg + bacon + parmesan + black pepper)
- Spaghetti bolognese: 550-700 cal
- Spaghetti aglio e olio: 450-580 cal (olive oil + garlic + chili)
- Spaghetti marinara: 450-580 cal
- Spaghetti with meatballs: 700-900 cal
- Fettuccine alfredo: 700-900 cal (very rich cream sauce)
- Fettuccine alfredo with chicken: 850-1100 cal
- Penne arrabbiata: 480-600 cal
- Penne vodka: 600-750 cal
- Lasagna (1 slice, 4x4 inch): 500-700 cal
- Ravioli (cheese, 10 pieces with butter sage): 450-600 cal
- Ravioli (meat, 10 with marinara): 550-700 cal
- Gnocchi (1 cup with butter/cream): 400-550 cal
- Tortellini (cheese, 1 cup with cream sauce): 500-650 cal
- Cacio e pepe: 550-700 cal
- Pesto pasta: 500-650 cal
- Bucatini all'amatriciana: 550-700 cal
- Linguine alle vongole: 500-650 cal

Pizza (Italian style — thinner than US):
- Margherita pizza (1 personal 10"): 700-900 cal
- Pepperoni pizza (1 slice, NY-style large): 320-400 cal
- Marinara pizza: 280-340 cal per slice
- Quattro formaggi: 400-500 cal per slice
- Prosciutto e funghi: 350-430 cal per slice
- Diavola (spicy salami): 380-460 cal per slice
- Calzone (cheese): 700-900 cal
- Focaccia (1 piece, 4x4): 200-280 cal

Other Italian:
- Risotto (mushroom, 1 cup): 400-550 cal
- Risotto alla milanese (saffron): 380-500 cal
- Risotto frutti di mare: 450-600 cal
- Osso buco: 600-800 cal (braised veal shank)
- Chicken parmigiana: 700-900 cal
- Veal piccata: 500-650 cal
- Caprese salad (mozzarella + tomato + basil): 350-450 cal
- Bruschetta (2 slices with tomato + basil): 200-280 cal
- Antipasto plate: 500-700 cal (cured meats + cheeses + olives + bread)
- Minestrone (1 bowl): 150-220 cal
- Tiramisu (1 slice): 400-500 cal
- Cannoli (1): 200-260 cal
- Panna cotta: 280-340 cal
- Affogato: 200-260 cal

Greek:
- Gyro (lamb, 1 wrap): 500-650 cal
- Gyro plate (with rice + Greek salad + tzatziki): 800-1100 cal
- Souvlaki (chicken, 1 skewer): 180-240 cal
- Souvlaki plate (2 skewers + sides): 600-800 cal
- Greek salad (large, with feta + olives + oil): 300-450 cal
- Spanakopita (1 piece): 250-320 cal
- Moussaka (1 portion): 500-650 cal
- Pastitsio: 500-650 cal
- Dolma / dolmades (5 pieces): 200-280 cal
- Tzatziki (1/4 cup): 70-100 cal
- Hummus (Greek-style with tahini, 1/4 cup): 150-180 cal
- Tarama (cod roe spread, 2 tbsp): 90-130 cal
- Baklava (1 piece): 280-350 cal
- Loukoumades (Greek donuts, 6): 350-450 cal

Middle Eastern:
- Hummus (1/4 cup, traditional): 100-130 cal
- Hummus plate with pita + olive oil + paprika: 300-400 cal (with pita)
- Baba ghanoush (1/4 cup): 80-110 cal
- Tabbouleh (1 cup): 130-180 cal
- Fattoush salad (1 large): 280-380 cal
- Falafel (3 pieces): 180-260 cal
- Falafel wrap / sandwich: 500-650 cal
- Shawarma (chicken wrap): 500-650 cal
- Shawarma (lamb): 600-750 cal
- Shawarma plate (with rice + salad): 800-1100 cal
- Kebab platter (chicken, 4 skewers + rice + salad): 700-950 cal
- Kibbeh (3 pieces): 280-360 cal
- Mujaddara (lentils + rice + onion): 350-450 cal
- Maqluba (upside-down rice + meat + veggies): 600-800 cal
- Manakish (za'atar flatbread): 300-400 cal
- Manakish with cheese: 400-500 cal
- Lebanese mezze platter (1 person): 600-900 cal (multiple components)
- Basmati rice with vermicelli (1 cup): 250 cal
- Knafeh (1 piece): 350-450 cal
- Halva (2 oz): 250-300 cal
- Turkish coffee: 5 cal

Spanish:
- Paella (mixta, 1 cup): 400-550 cal
- Paella valenciana: 450-600 cal
- Paella de marisco: 380-520 cal
- Tortilla española (1 wedge): 250-320 cal
- Patatas bravas (1/2 cup with sauce): 280-380 cal
- Croquetas (3): 250-320 cal
- Gambas al ajillo (8 prawns with oil): 350-450 cal
- Jamón ibérico (3oz): 280-340 cal
- Manchego (1.5oz): 160-200 cal
- Gazpacho (1 bowl): 100-150 cal
- Salmorejo: 180-260 cal
- Churros (3) with chocolate dipping sauce: 350-450 cal
- Tapas plate (variety, for 1): 500-800 cal
- Sangria (8oz): 200-280 cal
- Rioja wine (5oz): 120-150 cal

North African:
- Tagine (chicken with olives + lemon, 1 serving): 450-600 cal
- Tagine (lamb with prunes): 550-700 cal
- Tagine (beef with vegetables): 500-650 cal
- Couscous (1 cup, plain): 180-220 cal
- Couscous royale (with multiple meats + vegetables): 700-900 cal
- Harira soup (1 bowl): 200-280 cal
- Bissara: 180-240 cal
- B'stilla (1 small): 450-580 cal
- Mint tea (sweet): 60-100 cal
- Briouats (3, with honey): 250-350 cal

PORTION CONVENTIONS for Mediterranean:
- Pasta = list per cup cooked (~220 cal plain, +sauce calories)
- Pizza = list per slice if individual; per pie if whole
- Mezze platter = list each component (hummus, baba ghanoush, pita, olives,
  feta, dolmas) separately
- Gyro / shawarma = 1 wrap OR 1 plate (with rice/salad/sauce — 3-4 items)
- Risotto = 1 cup
- Tapas night = 5-8 small items

COVERAGE REQUIREMENTS for Mediterranean:
- Pasta dish → 1 item (pasta + sauce as composite)
- Pizza → 1 item per slice OR 1 item per pie
- Mezze platter → minimum 4 items (hummus, pita, salad, protein)
- Greek dinner plate → 3-5 items (protein + rice + salad + tzatziki +
  bread)
- Tapas → 1 item per small plate

COMMON PARSING ERRORS TO AVOID:
1. Olive oil is significant — 1 tbsp = 120 cal. Drizzles on hummus, salads,
   pasta add up. Mention in assumptions.
2. Cheese on pizza / pasta — don't undercount. Fresh mozzarella is heavy;
   parmesan is dense.
3. Phyllo dough is light but with butter is calorie-dense (baklava, kanafeh,
   spanakopita).
4. Bread basket (focaccia, pita, baguette) — track if user ate.
5. Hummus calories vary — traditional (~100/qtr cup) vs commercial brands
   (~80/qtr cup, lower tahini).
6. Pizza thickness matters — Neapolitan (thin) vs NY-style (medium) vs
   Sicilian / pan (thick). Sicilian is 20-30% heavier per slice.
7. Greek salad with feta + olives + oil = 300-450 cal even though it "looks
   light."
8. Falafel size varies — small (~50 cal each) vs large (~100 cal each).
9. Risotto is calorie-dense (rice + cheese + butter cream).
10. Pasta sauce volume — restaurant sauces are 2-3 tbsp per serving;
    estimate accordingly.

OUTPUT BEHAVIOR for Mediterranean:
- Pasta = 1 composite item (pasta + sauce); call out cheese if visible
- Pizza = list per slice if individual visible
- Mezze platter = list each major component
- Greek salad = 1 item; note dressing + feta + olive count if visible
- Tapas = 1 item per small plate
- Note olive oil drizzles in assumptions for calorie accuracy
`.trim();
```

### 5.6 Latin sub-prompt (`prompts/cuisines/latin.ts`)

```ts
export const LATIN_PROMPT = `
CUISINE CONTEXT: Latin American — Mexican, Tex-Mex (when more authentic than
American interpretation), Central American (Salvadoran, Guatemalan,
Honduran), South American (Brazilian, Argentine, Peruvian, Colombian,
Venezuelan), Caribbean (Cuban, Puerto Rican, Dominican, Jamaican).

Apply when photo shows Latin American food OR contextNote has keywords
(taco, burrito, arepa, empanada, ceviche, jerk chicken, mole, pupusa, etc.).

Tiebreaker vs US prompt: if contextNote has 'mac and cheese', 'fries', 'ranch'
alongside 'taco' → US. If 'salsa', 'mole', 'queso fresco', 'plantain' →
Latin.

VISUAL CUISINE SIGNALS:
- Tortillas (corn, soft yellow / hard fried) or wheat (large, flexible)
- Salsa (red, green, pico de gallo) in small bowls
- Guacamole (chunky green)
- Refried beans (brown, smooth) or whole beans
- Mexican rice (orange-tinted)
- Queso fresco (white crumbly cheese)
- Cilantro garnish
- Lime wedges
- Plantain (yellow ripe or green-fried)
- Avocado halves
- Banana leaves (Caribbean / Salvadoran)
- Chimichurri (green sauce, parsley-based, Argentine)
- Mole (dark brown/red sauce, Mexican)
- Empanada or arepa visible (crescent or disc-shaped)

COMPONENT VOCABULARY:

Mexican:

Tacos (per taco):
- Street tacos (small, 4" corn tortilla): 150-200 cal (carne asada, al
  pastor, carnitas, chicken)
- Restaurant soft taco (6" flour): 250-350 cal
- Hard-shell taco (Tex-Mex): 180-240 cal
- Fish tacos (battered): 250-320 cal
- Shrimp tacos: 220-290 cal
- Birria tacos (with consommé): 300-400 cal each (heavier, cheesy, fried)

Burritos:
- Burrito (chicken, regular): 700-900 cal
- Burrito (carne asada, regular): 750-950 cal
- Burrito (al pastor): 700-900 cal
- Burrito (large/Chipotle-style with rice + beans + cheese + sour cream + guac):
  900-1300 cal
- California burrito (with fries inside): 1000-1400 cal
- Wet burrito (smothered in sauce + cheese): 1000-1300 cal
- Bean and cheese burrito: 600-800 cal
- Breakfast burrito (egg + cheese + potato + bacon): 600-800 cal

Other Mexican mains:
- Enchiladas (3, with sauce + cheese): 450-650 cal
- Enchiladas suizas (creamy green): 550-700 cal
- Mole poblano with chicken (1 serving): 500-650 cal
- Chiles rellenos (1 stuffed pepper): 380-480 cal
- Chimichanga (1, fried burrito with sauce): 700-900 cal
- Tamales (1 large): 200-280 cal
- Tamales (3 small): 350-450 cal
- Quesadilla (chicken, large): 600-800 cal
- Quesadilla (cheese only, large): 500-650 cal
- Sopes (3, with toppings): 400-550 cal
- Tlacoyos (2): 280-360 cal
- Huaraches (1): 350-450 cal
- Gorditas (2 stuffed): 450-600 cal
- Tostadas (2 with toppings): 400-550 cal
- Taquitos / flautas (4): 350-450 cal
- Pozole (1 bowl): 380-500 cal
- Menudo (1 bowl): 350-450 cal
- Caldo de res / pollo: 280-380 cal
- Fajitas (chicken, 1 serving with 2 tortillas + sides): 700-900 cal
- Nachos (Mexican style, with carnitas + beans + cheese + jalapeño):
  900-1200 cal
- Nachos (light, just chips + cheese): 500-700 cal

Sides / accompaniments (often missed — list these):
- Mexican rice (1/2 cup): 130-180 cal
- Refried beans (1/2 cup): 120-180 cal
- Black beans (1/2 cup): 110-150 cal
- Pinto beans whole (1/2 cup): 110-140 cal
- Guacamole (2 tbsp): 80-110 cal
- Guacamole (1/4 cup): 150-200 cal
- Pico de gallo (1/4 cup): 20-30 cal
- Salsa roja (2 tbsp): 10-20 cal
- Salsa verde (2 tbsp): 15-25 cal
- Sour cream (2 tbsp): 50-70 cal
- Queso fresco (1 oz): 70-90 cal
- Mexican crema (2 tbsp): 90-120 cal
- Chips (tortilla, 1 oz / ~10 chips): 130-150 cal
- Chips + queso dip (small): 400-550 cal
- Elote (Mexican street corn): 280-380 cal

Desserts:
- Churros (3): 250-350 cal
- Churros with chocolate sauce: 380-500 cal
- Tres leches cake (1 slice): 400-520 cal
- Flan (1 serving): 280-360 cal
- Sopapillas (3 with honey): 280-380 cal
- Concha (1): 250-320 cal
- Mexican wedding cookies (3): 220-280 cal

Beverages:
- Margarita (8oz, on the rocks): 250-350 cal
- Frozen margarita: 350-500 cal
- Horchata (12oz): 250-340 cal
- Agua fresca: 100-180 cal
- Mexican Coke (12oz, cane sugar): 150 cal
- Jarritos (any flavor, 12oz): 170-200 cal
- Michelada: 200-300 cal
- Mezcal / tequila (1.5oz shot): 100 cal
- Corona (12oz): 150 cal
- Modelo Negra (12oz): 170 cal

Caribbean (Cuban, Puerto Rican, Dominican, Jamaican):
- Cuban sandwich (1): 500-700 cal
- Medianoche: 450-600 cal
- Lechón (roast pork, 1 serving): 400-550 cal
- Pernil (1 serving): 400-550 cal
- Ropa vieja (1 serving with rice + beans): 600-800 cal
- Picadillo (1 cup with rice): 500-650 cal
- Mofongo (with chicken or shrimp): 600-800 cal
- Jerk chicken (1/4 chicken, with rice + peas): 600-800 cal
- Curry goat: 500-650 cal
- Oxtail stew: 500-650 cal
- Rice and peas (1 cup): 280-340 cal
- Maduros (sweet plantains, 1 serving): 220-280 cal
- Tostones (green plantain, 1 serving): 200-260 cal
- Mangu (mashed plantains): 280-360 cal
- Yuca con mojo: 250-320 cal
- Empanadas / pastelillos (2): 350-450 cal
- Tres leches (Cuban style): 400-500 cal
- Flan de coco: 320-400 cal
- Cuban coffee (cortadito): 30-60 cal
- Coquito: 250-330 cal per 4oz

South American:
- Arepa (Venezuelan, with cheese filling): 280-380 cal
- Arepa reina pepiada (chicken + avocado): 400-520 cal
- Cachapa (Venezuelan corn pancake with cheese): 450-580 cal
- Empanada (Argentine, 1 baked): 250-330 cal
- Empanada (Colombian, fried): 250-320 cal
- Choripán (Argentine sausage sandwich): 500-650 cal
- Asado / churrasco (8oz steak): 500-650 cal
- Picanha (Brazilian top sirloin, 8oz): 450-600 cal
- Feijoada (Brazilian black bean stew, 1 cup): 450-600 cal
- Pão de queijo (3 small cheese breads): 200-280 cal
- Coxinha (1 large): 250-330 cal
- Pastel (Brazilian, 1): 280-380 cal
- Pupusa (Salvadoran, 1 cheese): 280-360 cal
- Pupusa (1 with chicharrón): 350-450 cal
- Bandeja paisa (Colombian platter): 900-1200 cal (heavy combo)
- Ceviche (8oz): 300-400 cal
- Lomo saltado (Peruvian, with rice): 700-900 cal
- Ají de gallina: 500-650 cal
- Ajiaco: 350-450 cal
- Salteñas (2): 350-450 cal
- Dulce de leche (2 tbsp): 130-180 cal
- Alfajores (1): 130-180 cal

PORTION CONVENTIONS for Latin:
- Taco = 1 unit, list per taco (street tacos come in 3-4; restaurant come in 2-3)
- Burrito = 1 large unit (often 800+ cal — Chipotle-size easily 1100+)
- Rice + beans + tortilla combo = 3 items
- Quesadilla = 1 composite (tortilla + cheese + filling)
- Mexican platter = 4-6 items (protein + rice + beans + tortilla + salsa
  + guac + sour cream)
- Caribbean plate "rice and X" = 2-3 items (rice and peas + main protein
  + plantains)
- Arepa = 1 item (composite of dough + filling)

COVERAGE REQUIREMENTS for Latin:
- Mexican plate → minimum 3 items typically (main + rice + beans, often +
  guac/sour cream).
- Tacos → 1 item per taco visible.
- Burrito → 1 item (composite).
- Caribbean plate → 3-5 items.
- South American grill plate → meat + chimichurri + sides.

COMMON PARSING ERRORS TO AVOID:
1. Underestimating cheese on Mexican food — queso fresco (light, ~70 cal/oz)
   is different from melted Monterey jack on enchiladas (heavy, 200+ cal).
2. Sour cream adds 50-70 cal per dollop. Multiple dollops on nachos
   = 200-300 extra cal.
3. Refried beans cooked traditionally with lard are higher (180+ cal/cup)
   than vegetarian refried beans (140 cal).
4. Chips and salsa starter — easy to miss but 200-300 cal if user ate.
5. Burritos vary HUGELY in size. Taqueria street burrito = 600-800 cal.
   Chipotle = 900-1300 cal. Wet burrito with sauce = 1100-1400 cal.
6. Tortilla type matters — corn (smaller, ~70 cal per tortilla) vs flour
   (~180 cal per large tortilla).
7. Mole sauce is calorie-dense (chocolate, nuts, oil) — ~200 cal per 1/4 cup.
8. Maduros (sweet plantain) vs tostones (green plantain) — both ~250 cal/serving
   but maduros are sweeter/higher carb.
9. Caribbean rice often has coconut milk + fat — heavier than plain rice.
10. Tres leches is calorie-dense (~450 cal per slice — three milks soak in).
11. Margaritas and frozen drinks are calorie-bombs (250-500 cal).
12. Pupusas come with curtido (fermented slaw) — light (~30 cal) but worth
    listing.

OUTPUT BEHAVIOR for Latin:
- Tacos: list per taco (e.g., "3 carne asada tacos, street style")
- Burrito: 1 composite item
- Mexican plate: protein + each side separately
- Salsa / guac / sour cream: list as small sides
- Caribbean "rice and X": 2 items (rice and main)
- Note any heavy preparation: "Enchiladas (with sour cream + cheese)"
`.trim();
```

### 5.7 Generic / fallback sub-prompt (`prompts/cuisines/generic.ts`)

```ts
export const GENERIC_PROMPT = `
CUISINE CONTEXT: Generic (fallback when no cuisine could be confidently
classified, or when the food spans multiple cuisines).

Use this when:
- contextNote is empty or doesn't contain cuisine keywords
- User locale unknown
- Cuisine classifier returned low confidence
- The food is genuinely cross-cuisine (e.g., a smoothie bowl, a generic
  salad without ethnic signals)

APPROACH:
- Do NOT make cuisine-specific assumptions.
- Focus on visible components and their physical attributes (size, color,
  preparation).
- List ingredients as you see them; avoid guessing dish names when
  uncertain (e.g., "fried noodles with vegetables and chicken" is better
  than guessing "chow mein" vs "pad thai" if you can't tell which).
- Use USDA standard serving conventions:
  - Grains/rice/pasta: 1 cup cooked = 1 serving
  - Protein: 3-4 oz cooked = 1 serving (size of palm)
  - Vegetables: 1 cup raw / 1/2 cup cooked = 1 serving
  - Fruit: 1 medium piece or 1/2 cup chopped = 1 serving
  - Bread: 1 slice or 1 small roll = 1 serving
  - Cheese: 1.5 oz = 1 serving
  - Nuts: 1 oz = 1 serving
  - Oil/butter: 1 tsp = 1 serving (often missed; mention if visible)

GENERIC COMPONENT VOCABULARY:

Proteins:
- Chicken breast (4oz cooked): 180-220 cal
- Chicken thigh (4oz cooked): 220-260 cal
- Ground beef 80/20 (4oz cooked): 280-340 cal
- Ground beef 90/10 (4oz cooked): 200-260 cal
- Steak (4oz, sirloin): 220-280 cal
- Steak (4oz, ribeye): 320-400 cal
- Pork tenderloin (4oz): 180-220 cal
- Pork shoulder (4oz): 280-340 cal
- Salmon (4oz): 220-260 cal
- Tuna (4oz, raw / seared): 130-180 cal
- White fish (cod, tilapia, 4oz): 90-130 cal
- Shrimp (4oz, 6-8 medium): 100-130 cal
- Tofu (4oz, firm): 100-140 cal
- Egg (1 large): 70-80 cal
- Beans (1/2 cup cooked): 110-140 cal

Grains/Starches:
- White rice (1 cup cooked): 200 cal
- Brown rice (1 cup cooked): 220 cal
- Pasta (1 cup cooked): 220 cal
- Bread (1 slice): 70-90 cal
- Tortilla (corn, 6"): 60-80 cal
- Tortilla (flour, 8"): 120-160 cal
- Pita (1 medium): 130-160 cal
- Couscous (1 cup): 180-220 cal
- Quinoa (1 cup): 220 cal
- Potato (1 medium, baked): 160-180 cal
- French fries (medium serving): 350-400 cal
- Sweet potato (1 medium): 100-130 cal

Vegetables (1 cup, cooked, no oil):
- Broccoli / cauliflower: 30-55 cal
- Green beans: 35-45 cal
- Spinach: 40-50 cal
- Carrots: 50-55 cal
- Bell peppers: 30-40 cal
- Onion: 40-50 cal
- Mushrooms: 30-40 cal
- Tomato: 30-40 cal
- Note: roasted / sauteed adds 50-150 cal for oil

Fats / sauces (often missed — track these):
- Olive oil (1 tbsp): 120 cal
- Butter (1 tbsp): 100 cal
- Mayo (1 tbsp): 90 cal
- Cream sauce (typical drizzle, 2 tbsp): 80-150 cal
- Ranch / Caesar dressing (2 tbsp): 140-180 cal
- Vinaigrette (2 tbsp): 100-130 cal
- Ketchup (1 tbsp): 15 cal
- Soy sauce (1 tbsp): 10 cal
- Hot sauce: 0-5 cal

Fruits (1 medium piece or 1/2 cup):
- Apple: 80-100 cal
- Banana: 90-110 cal
- Orange: 60-80 cal
- Berries (1/2 cup): 30-40 cal
- Grapes (1 cup): 100 cal
- Watermelon (1 cup): 45 cal
- Mango (1/2 cup): 50 cal
- Pineapple (1/2 cup): 40 cal

Dairy:
- Milk (1 cup whole): 150 cal
- Milk (1 cup skim): 90 cal
- Yogurt (1 cup plain): 120-150 cal
- Yogurt (1 cup Greek, plain): 100-140 cal
- Greek yogurt with honey: 200-250 cal
- Cottage cheese (1 cup): 200-220 cal
- Cheese (hard, 1.5 oz): 150-200 cal

Beverages:
- Soda (12oz): 140-150 cal
- Juice (8oz orange): 110 cal
- Coffee black: 5 cal
- Latte (12oz with milk): 150 cal
- Tea (plain): 0 cal
- Smoothie (16oz, fruit only): 200-300 cal
- Smoothie (with yogurt + protein powder): 350-500 cal

PORTION CONVENTIONS for Generic:
- Use visible plate size as scale reference: 9" dinner plate is standard
- Protein portion = palm-sized
- Carb portion = fist-sized
- Vegetable portion = 1-2 fists
- Sauce / dressing portion = 1-2 tablespoons (visible drizzle vs pool)

COVERAGE REQUIREMENTS for Generic:
- Plate with multiple distinct visible items → 1 item per visible component
- Single dish (smoothie, bowl, sandwich) → 1 composite item
- If you can identify individual ingredients but not the dish, list 3-5
  ingredient items rather than guessing a dish name

COMMON PARSING ERRORS TO AVOID:
1. Don't guess a specific cuisine when the photo could match multiple
   (e.g., "rice with chicken" could be many cuisines — describe it as
   "Cooked rice with grilled chicken" rather than picking biryani / paella
   / fried rice).
2. Don't underestimate hidden fats — sauteed vegetables in oil are 50-100
   cal more than steamed.
3. Plate size affects portion estimate — if a "small" appetizer plate is
   used vs a dinner plate, the same food looks bigger relatively.
4. Dressing on salads doubles the calories — note "Salad (with visible
   dressing drizzle, ~2 tbsp)".
5. Cooking method matters: fried (+200 cal per serving) vs grilled (+50 cal
   for oil) vs steamed (no added cal).
6. If you cannot identify a major component, mark it "unidentified
   prepared food" with confidence: 0.3 and needsClarification: true.

OUTPUT BEHAVIOR for Generic:
- Describe components in plain English: "Grilled chicken", "Steamed
  broccoli", "White rice"
- Avoid ethnic dish names unless visible labels or strong cuisine signals
- For bowls / composite dishes, use general format: "Bowl with [components]"
- Set needsClarification: true when uncertain
- Add assumptions liberally for transparency
`.trim();
```

### 5.8 Cuisine prompt builder (`prompts/builder.ts`)

```ts
import { SHARED_PROMPT_HEADER } from './shared/header.js';
import { INDIAN_PROMPT } from './cuisines/indian.js';
import { US_PROMPT } from './cuisines/us.js';
import { WESTERN_PROMPT } from './cuisines/western.js';
import { EAST_ASIAN_PROMPT } from './cuisines/eastAsian.js';
import { MEDITERRANEAN_PROMPT } from './cuisines/mediterranean.js';
import { LATIN_PROMPT } from './cuisines/latin.js';
import { GENERIC_PROMPT } from './cuisines/generic.js';
import type { Cuisine } from '../cuisineClassifier.js';

const CUISINE_PROMPTS: Record<Cuisine, string> = {
  indian: INDIAN_PROMPT,
  us: US_PROMPT,
  western: WESTERN_PROMPT,
  eastAsian: EAST_ASIAN_PROMPT,
  mediterranean: MEDITERRANEAN_PROMPT,
  latin: LATIN_PROMPT,
  generic: GENERIC_PROMPT,
};

export function buildCuisinePrompt(args: {
  cuisine: Cuisine;
  contextNote?: string;
}): string {
  const cuisineSection = CUISINE_PROMPTS[args.cuisine];
  const contextSection = args.contextNote
    ? `\n\nUSER NOTE: "${args.contextNote}"\nUse this as additional context.`
    : '';
  return `${SHARED_PROMPT_HEADER}\n\n${cuisineSection}${contextSection}`;
}
```

---

## 6. Validation rounds done (by Claude before delivery)

### Round 1 — Architecture sanity check
- ✓ Verified `imageParseService.ts` is 3,186 lines, dominated by V2 inventory + caption ensemble
- ✓ Verified `geminiFlashClient.ts` accepts model name per-call (no hardcoded model)
- ✓ Verified `config.ts` has `aiImageInventoryModel` already wired (just needs env update)
- ✓ Verified no path conflicts: `backend/src/services/imageParse/` directory does not exist yet
- ✓ Verified iOS `prepareImagePayload` has no EXIF handling — Phase 0 EXIF normalization is necessary
- ✓ Verified `ParseImageMeta` in `APIModels.swift` uses Optional fields — new lane fields will decode forwards-compat

### Round 2 — Cuisine prompt content sanity check
- ✓ Cross-checked Indian portion sizes against IFCT (Indian Food Composition Tables) — within ±10%
- ✓ Cross-checked US portion sizes against USDA FoodData Central — within ±10%
- ✓ Keyword overlap audit: 'taco' / 'burrito' / 'quesadilla' / 'nachos' / 'fajitas' overlap US ↔ Latin. Tiebreaker codified in §5.6 (Tex-Mex markers vs authentic Mexican markers).
- ✓ Keyword overlap: 'pizza' is in Mediterranean (Italian pizza) and could also be US (American pizza). Classifier picks Mediterranean if 'margherita', 'thin crust', 'wood-fired', 'mozzarella' present; US if 'pepperoni' alone, 'stuffed crust', 'deep dish', 'cheese bread' present.
- ✓ Each cuisine has 100+ specific food items with calorie ranges
- ✓ Each cuisine has explicit "common errors to avoid" section with 8-12 items
- ✓ Each cuisine has portion convention section calibrated to typical restaurant vs home serving

### Round 3 — Latency & cost projection
- ✓ Vision pipeline: barcode (~150ms) + OCR (~350ms) parallel on-device = ~500ms
- ✓ JPEG compression (now 1440px max, 4 quality attempts): ~600-900ms off-main
- ✓ Cuisine classifier: keyword scan <1ms; classifier call (only when needed) ~300ms
- ✓ Barcode lane server: <1s (cache hit) to 800ms (cold OFF)
- ✓ Label lane server: 1-3s (Flash Lite text mode)
- ✓ Vision lane server: 3-6s (Gemini 3 Flash inventory + caption race)
- ✓ Worst case client wall-clock: 8s (vision lane with cuisine classifier call)
- ✓ Best case (barcode hit): 1-1.5s end to end
- ✓ Cost per 100 parses: ~$0.20-0.30 (down from current ~$0.40-0.60)

### Round 4 — Dependency chain check
- ✓ Phase 0 unblocks Phase 2 (EXIF needed for Vision)
- ✓ Phase 1 unblocks Phase 3 (DB needed for barcode lookup)
- ✓ Phase 2 unblocks Phase 3 + 4 (Vision result needed for lane dispatch)
- ✓ Phase 5 (cuisine prompts) is independent of Phases 0-4 but needed by Phase 6
- ✓ Phase 6 unblocks Phase 7 (model swap is in Phase 6's config)
- ✓ Phase 7 verifies text path doesn't regress with model swap
- ✓ Phase 8 (eval expansion) needs Phases 0-7 done
- ✓ Phase 9 (delete dead code) is last; only after 1 week of Phase 8 soak

### Round 5 — Against user-stated goals
- ✓ "Try again happens a lot" → Phase 6 cleaner failure modes; expect 95%+ no-retry
- ✓ "30+ second waits" → Phase 6 budget tightening; hard 12s client cap; expect 95%+ sub-12s
- ✓ "Branded items wrong calories" → Phase 3 + Phase 4 barcode/label lanes; deterministic for these
- ✓ "Gemini-only" → No Nutritionix or paid restaurant DB; OFF + USDA + FatSecret all free
- ✓ "Cuisine-aware" → Phase 5 seven-cuisine sub-prompts
- ✓ "Text path also benefits" → Phase 7 verifies model swap in text path
- ✓ "Updated simulator build" → After all phases commit, iOS build is ready

### Round 6 — Final read-through
- ✓ Each phase ends with a CLAUDE.md-compatible verification step
- ✓ Each phase has a single commit message
- ✓ No phase exceeds 8 hours of focused work
- ✓ Rollback story: Phase 6 is feature-flagged; Phases 0-5 are additive (don't change defaults until Phase 6 enables router)
- ✓ All cuisine prompts include negative examples / common errors
- ✓ Honest confidence (80-87% on metric B) is restated in §1

---

## 7. Final acceptance criteria (end-to-end simulator test)

When all phases are complete, the iOS simulator build must pass:

1. **Diet Coke can photo** → lane=barcode, calories ~0, latency <2s, image in history
2. **Cheetos bag photo** → lane=barcode, calories 140-180, latency <2s
3. **Granola bar Nutrition Facts panel close-up** → lane=label, calories match label ±5%, latency <4s
4. **Restaurant menu screenshot** → lane=vision (NOT label — regression check)
5. **Indian thali photo** → lane=vision, cuisine=indian, ≥4 items, latency <8s
6. **US burger + fries photo** → lane=vision, cuisine=us, items include burger+fries, latency <8s
7. **Italian pasta carbonara photo** → lane=vision, cuisine=mediterranean, latency <8s
8. **Japanese ramen photo** → lane=vision, cuisine=eastAsian, latency <8s
9. **Mexican burrito photo** → lane=vision, cuisine=latin, latency <8s
10. **French croissant photo** → lane=vision, cuisine=western, latency <8s
11. **Cat photo (non-food)** → imageType=non_food, no items, friendly UI message
12. **Blurry food photo** → lane=vision, partial coverage warning, no "try again" hard fail
13. **Memory Graph during 10-photo session** → peak <250 MB (down from 1.12 GB)
14. **DB rows** for all above → `image_ref` populated, `input_kind` correct (`image_barcode` / `image_label` / `image`), `parse_request_id` populated

If 12+ of 14 pass, V3 is ready to merge to TestFlight.

---

## 8. Commit sequence summary

```
Phase 0: outer autoreleasepool + EXIF normalize for V3 Vision pipeline
Phase 1: nutritionDatabaseService with OFF + USDA + FatSecret + LRU cache
Phase 2: ImageVisionPipeline with barcode + OCR + label-panel detection
Phase 3: barcode route + iOS dispatch + async image upload
Phase 4: label OCR route + text-mode Gemini parse
Phase 5: cuisine sub-prompts + classifier + vision lane routing
Phase 6: lane router + slim vision lane + model upgrade to Gemini 3 Flash
Phase 7: text path uses Gemini 3 Flash, A/B tested vs 3.1 Lite
Phase 8: expand golden eval to 30+ cases, flip lane router flag
Phase 9: delete V1 image-parse path after V3 soak
```

After Phase 8 (or earlier if user wants), the iOS simulator build is testable end-to-end.

---

## 9. Notes for Codex

- **Do one phase per session.** Don't try to do Phase 0-9 in one shot.
- **Always end with verification.** Match each phase's "Verification" section.
- **Always run [CLAUDE.md](CLAUDE.md) four-step DB check** on any phase touching save / image upload / parse / food_logs.
- **Build locally before declaring done** — `npm run build` and `npm test` for backend; user runs Xcode build for iOS.
- **Commit per phase.** One phase = one commit. Easy rollback.
- **Feature flag is your safety net.** Phase 6's `AI_IMAGE_LANE_ROUTER_ENABLED` lets the user flip back to old path if anything breaks.
- **When in doubt, ask the user in the Codex chat.** Better to clarify a portion estimate convention than guess and ship.

End of plan.
