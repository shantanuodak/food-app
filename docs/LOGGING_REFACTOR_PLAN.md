# Food App: Logging/Parse/Save Refactor Plan

**Audience:** Codex (or another AI coder) executing the refactor task by task.
**Source context:** `docs/SENIOR_DEV_E2E_HANDOFF_CURRENT_STATE.md` (must read sections 10, 11, 12, 16).
**Author intent:** Reduce complexity in `MainLoggingShellView.swift` and adjacent surfaces. Make logging/parse/save deterministic, testable, and observable. Eliminate the failure classes documented in handoff section 16 without breaking shipped contracts.

---

## 0. Read this first — non-negotiables

These are constraints on every task in every phase. If a proposed change violates one, stop and surface it for human review.

1. **API contracts are frozen.** No changes to `POST /v1/logs`, `PATCH /v1/logs/:id`, `PATCH /v1/logs/:id/image-ref`, `POST /v1/logs/parse*`, or any of their request/response shapes.
2. **Idempotency semantics are frozen.** `log_save_idempotency` table, advisory lock pattern, and the `(user, parse_request_id)` unique partial index from migration `0018` stay exactly as they are.
3. **Image upload stays decoupled from save.** Nutrition data must persist even when storage is broken. The post-save deferred upload path (`DeferredImageUploadStore`, `scheduleDeferredImageUploadRetry`, `AppStore.drainDeferredImageUploads`) is the contract — keep it.
4. **The seven frontend contracts in handoff section 10 are non-negotiable.** Any UX change must explicitly preserve them.
5. **Each phase ships independently and is reversible.** Phases 2 and 3 ship behind feature flags so production traffic can be cut back to legacy behavior in seconds without a redeploy.
6. **No phase is allowed to delete legacy code paths until its replacement has been live, flagged on, for at least 7 days with no regressions.**
7. **Verify before declaring done.** Build green is necessary, not sufficient. Every phase has an "acceptance" subsection — meet it before moving on. The save-path verification rule from `CLAUDE.md` applies: take a real meal end-to-end, confirm the row landed.

---

## 1. The problem in one diagram

```
┌─────────────────────────── MainLoggingShellView (~5000 LOC) ───────────────────────────┐
│                                                                                         │
│  UI rendering    Debounce    Parse dispatch    Row mapping    Idempotency-key mgmt     │
│  Save queue      Patch path  Delete path       Sync pill      Persistence to UserDefs  │
│  Image upload    Auth recovery                 Day swipe      Notification posting     │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

Everything is fused. One file owns concerns that should be three or four files. The result is the bug class in handoff section 16 — fragmented state flags create races, save eligibility is computed from too many sources, and small drifts in row text vs. parse provenance cause silent 422s.

---

## 2. The target architecture

```
┌───────────────────────┐      ┌───────────────────────┐      ┌───────────────────────┐
│  ParseCoordinator     │      │  SaveCoordinator      │      │  MainLoggingShellView │
│  (actor)              │◀────▶│  (actor)              │◀────▶│  (SwiftUI view)       │
│                       │      │                       │      │                       │
│  • debounce           │      │  • queue              │      │  • render rows        │
│  • dispatch parse     │      │  • idempotency        │      │  • dispatch events    │
│  • row → parseReq map │      │  • POST vs. PATCH     │      │  • observe state     │
│  • snapshot rawText   │      │  • retry policy       │      │  • show sync pill     │
│  • backpressure       │      │  • image upload retry │      │                       │
└───────────────────────┘      └───────────────────────┘      └───────────────────────┘
                                          ▲
                                          │
                                  ┌───────┴───────────┐
                                  │ Pure helpers      │
                                  │ • SaveEligibility │
                                  │ • IdempotencyKey  │
                                  │ • ParseSnapshot   │
                                  └───────────────────┘
```

**Why actors:** Both coordinators own mutable state that's accessed from concurrent tasks (debounced parses, retry timers, drain-on-launch). Actors give us serialization without manual locks. Use `@MainActor` for the coordinators if SwiftUI binding is awkward — they don't need to be off the main thread, just serialized.

---

## 3. Phase 0 — Observability (do this first; no functional changes)

**Why first:** We can't refactor what we can't see. The `parse_only` ambiguity (handoff 16.1) and the autosave inconsistency (16.2) are both observability failures dressed up as logic failures. Add the instruments first. Then the refactor has a measurable success bar.

**Estimate:** 1–2 days of mechanical work.

### Task 0.1 — iOS save-attempt telemetry

**File:** `Food App/Food App/SaveAttemptTelemetry.swift` (new)

Build a tiny logger that emits structured events tied to `parseRequestId`:

```swift
enum SaveAttemptOutcome: String { case attempted, succeeded, failed, skippedNoEligibleState, skippedDuplicate }

struct SaveAttemptEvent {
    let parseRequestId: String
    let rowID: UUID
    let outcome: SaveAttemptOutcome
    let errorCode: String?
    let latencyMs: Int?
    let source: String  // "auto" | "manual" | "retry" | "patch"
    let clientBuild: String  // CFBundleVersion
    let backendCommit: String?  // from /health, optional
    let timestamp: Date
}
```

Emit via `NSLog` for now (we'll add a backend ingest endpoint in Phase 5). Call sites:

- `MainLoggingShellView.scheduleAutoSave` — emit `attempted` per saveable row
- `MainLoggingShellView.autoSaveIfNeeded` — emit `skippedNoEligibleState` when filtering excludes a row that had calories visible
- `submitSave` success → `succeeded` with latency
- `submitSave` catch → `failed` with `error.code`
- `scheduleDeferredImageUploadRetry` retry path → emit `source: "retry"`

**Acceptance:** Logging a meal produces at least one `attempted` and one `succeeded` (or `failed`) event in the device console. Each event has `parseRequestId` populated.

**Rollback:** Pure additive — delete the file.

### Task 0.2 — Backend startup schema assertion

**File:** `backend/src/db/schemaAssertions.ts` (new), called from `backend/src/index.ts` before `app.listen`.

```typescript
export async function assertRequiredSchema() {
  const required = [
    { table: 'food_logs', column: 'parse_request_id', migration: '0017' },
    { table: 'food_logs', column: 'image_ref', migration: '0012' },
    { table: 'food_logs', column: 'input_kind', migration: '0012' },
    { table: 'log_save_idempotency', column: 'log_id', migration: '0002' },
  ];
  for (const r of required) {
    const result = await pool.query(
      `SELECT 1 FROM information_schema.columns
        WHERE table_name = $1 AND column_name = $2`,
      [r.table, r.column]
    );
    if (result.rowCount === 0) {
      console.error(`[FATAL] Schema assertion failed: ${r.table}.${r.column} missing (need migration ${r.migration})`);
      process.exit(1);
    }
  }
  // Also check unique partial index from 0018
  const idxCheck = await pool.query(
    `SELECT 1 FROM pg_indexes WHERE indexname = 'food_logs_user_parse_request_unique'`
  );
  if (idxCheck.rowCount === 0) {
    console.error('[FATAL] Schema assertion failed: food_logs_user_parse_request_unique index missing (need migration 0018)');
    process.exit(1);
  }
  console.log('[boot] Schema assertions passed.');
}
```

Directly addresses handoff section 16.4: Render redeployed code that depended on a column the live DB hadn't run the migration for, and the failure was silent.

**Acceptance:** Backend boots successfully on Render. Locally, drop a column and confirm the process exits with a clear log line.

**Rollback:** Comment out the call in `index.ts`.

### Task 0.3 — `/health` returns the commit SHA

**File:** `backend/src/routes/health.ts`

Return `{ status: 'ok', commit: process.env.RENDER_GIT_COMMIT ?? 'unknown', schemaVersion: maxAppliedMigration }`. iOS can stash `commit` for telemetry events (Task 0.1). Solves "engineer was inspecting the wrong env" (handoff 16.10).

**Acceptance:** `curl https://food-app-backend-ifdx.onrender.com/health` returns the commit SHA from Render's env injection.

**Rollback:** Single field; remove from response.

---

## 4. Phase 1 — Extract pure helpers (low risk, high payoff)

**Why:** Unit-testable pure modules. Each one removes ~50–100 lines of inline logic from `MainLoggingShellView.swift`. None of them change behavior.

**Estimate:** 2 days.

### Task 1.1 — `SaveEligibility.swift` (pure)

**File:** `Food App/Food App/Logging/SaveEligibility.swift` (new)

```swift
struct SaveEligibility {
    static func isRowEligible(
        row: HomeLogRow,
        completedParse: CompletedRowParse?,
        autoSavedParseIDs: Set<String>,
        autoSaveMinConfidence: Double
    ) -> Bool {
        // Single source of truth for "should this row save right now?"
        // Rule (per handoff 16.2):
        //   - If row.calories != nil → eligible.
        //   - Else if completedParse exists with confidence ≥ min and items non-empty
        //     and parseRequestId not already in autoSavedParseIDs → eligible.
        //   - Else → not eligible.
    }
}
```

Replace the four duplicated eligibility filters in `MainLoggingShellView.scheduleAutoSave`, `autoSaveIfNeeded`, `flushPendingAutoSaveIfEligible`, and the legacy fallback path with calls to this function.

**Test:** `Food App/Food AppTests/SaveEligibilityTests.swift`. Cover: row with calories no parse → eligible. Low-confidence parse → not eligible. Already auto-saved parseRequestId → not eligible. Empty items → not eligible.

**Acceptance:** Build green. The same set of rows that used to save still save (verify with one text and one image meal end-to-end).

### Task 1.2 — `IdempotencyKeyResolver.swift` (pure)

**File:** `Food App/Food App/Logging/IdempotencyKeyResolver.swift` (new)

Today the idempotency-key derivation is duplicated in `scheduleAutoSave`, `autoSaveIfNeeded`, and `submitSave` (search for `existingRowKey` and `UUID()`). Centralize:

```swift
struct IdempotencyKeyResolver {
    /// Returns the existing key for this row if one's already in the queue
    /// (so retries reuse the server-side dedupe), else mints a new one.
    static func resolve(rowID: UUID, queue: [PendingSaveQueueItem]) -> UUID
}
```

**Test:** Existing key in queue → returns it. No queue entry → returns a new UUID. Mismatched rowID → returns a new UUID.

**Acceptance:** Build green. Save a meal twice in quick succession; verify backend `log_save_idempotency` has two distinct keys for two rows, but a re-fired retry of the same row reuses one key.

### Task 1.3 — `ParseSnapshot.swift` (pure)

**File:** `Food App/Food App/Logging/ParseSnapshot.swift` (new)

```swift
struct ParseSnapshot {
    let rowID: UUID
    let parseRequestId: String
    let parseVersion: String
    let rawText: String  // exact normalization the backend will check against
    let response: ParseLogResponse
    let rowItems: [ParsedFoodItem]
    let capturedAt: Date
}
```

This is the unit `completedRowParses` already uses (it's an unnamed tuple). Promote to a named struct with explicit fields. Adds clarity, lets future tests construct snapshots directly, and gives Phase 3 (`ParseCoordinator`) a clean handoff type. Replaces the tuple in `@State private var completedRowParses: [(rowID: UUID, parseRequestId: String, ...)]`.

**Acceptance:** Build green. No behavior change. `completedRowParses` is now `[ParseSnapshot]`.

---

## 5. Phase 2 — `SaveCoordinator` (the big one)

**Why:** Owns the failure surface from handoff 16.2 (autosave inconsistency), 16.3 (duplicates), 16.5 (422 strictness). Pulls all save orchestration out of the SwiftUI view.

**Estimate:** 3–4 days.

**Rollout note:** This phase originally shipped behind `FeatureFlag.useSaveCoordinator`. After the Phase 4 cutover, the coordinator path is the active path and the iOS feature flag helper has been removed.

### Task 2.1 — Create `SaveCoordinator.swift`

**File:** `Food App/Food App/Logging/SaveCoordinator.swift` (new)

```swift
@MainActor
final class SaveCoordinator: ObservableObject {
    @Published private(set) var pendingItems: [PendingSaveQueueItem] = []
    @Published private(set) var lastError: SaveError?

    private let api: APIClient
    private let imageStore: ImageStorageService
    private let deferredUploadStore: DeferredImageUploadStore?
    private let persistence: HomePendingSaveStore.Type  // for static methods today
    private let telemetry: SaveAttemptTelemetry

    func enqueue(snapshot: ParseSnapshot, row: HomeLogRow) async
    func patch(logId: String, snapshot: ParseSnapshot, row: HomeLogRow) async
    func delete(logId: String) async
    func flushAll(reason: FlushReason) async
    func handleAuthRestored() async  // re-attempts pending items
}
```

Owns:
- The `pendingSaveQueue` array (currently `@State` in the view)
- `submitSave`, `submitRowPatch`, `prepareSaveRequestForNetwork`, `requestWithImageRef`
- `markPendingSaveAttemptStarted`, `markPendingSaveSucceeded`, `markPendingSaveFailed`
- `clearPendingSaveContext`
- `scheduleDeferredImageUploadRetry`
- `lastAutoSavedContentFingerprint`

`MainLoggingShellView` keeps a `@StateObject` reference and calls `coordinator.enqueue(snapshot:row:)` instead of running the queue logic inline.

### Task 2.2 — Coordinator wiring

Historical rollout kept both coordinator and legacy paths callable behind a flag. After Phase 4, the iOS app runs through `SaveCoordinator` directly and the feature flag helper has been removed.

### Task 2.3 — Unit tests for `SaveCoordinator`

**File:** `Food App/Food AppTests/SaveCoordinatorTests.swift`

Mock `APIClient` and `ImageStorageService` (protocols, inject them). Tests:

1. `enqueue` happy path → POST fires, queue cleared, telemetry emits succeeded.
2. `enqueue` with same `parseRequestId` twice → only one POST (idempotency-key reused).
3. POST returns 422 NEEDS_CLARIFICATION → row marked failed, no retry burn loop.
4. POST returns 500 → retry queue, `flushAll` succeeds when network restores.
5. Image-mode `enqueue` with broken upload → `food_logs` saved with `imageRef = nil`, deferred upload queued.
6. Patch path: `patch(logId:)` calls PATCH, not POST; idempotency-key not sent.
7. Delete path: removes any pending entries for that log id, calls DELETE.

### Task 2.4 — Production rollout

1. Historical rollout shipped behind a local flag and baked on staff/internal usage first.
2. Phase 4 removed the iOS feature flag helper and legacy save/parse fallback branches from `MainLoggingShellView`.
3. Current verification should focus on real save success rate, queue reconciliation, and dashboard save-attempt state.

**Acceptance:** Production save success rate (saved / parse_attempts where parse confidence ≥ 0.7) does not drop. Run the diagnostic from `CLAUDE.md` schema cheat sheet to compare before/after.

**Rollback:** Revert the Phase 4 iOS cutover commit. No DB migrations involved.

---

## 6. Phase 3 — `ParseCoordinator`

**Why:** The 422 silent-failure class (handoff 16.5) is fundamentally about parse-time vs. save-time state drift. A coordinator that owns the snapshot makes the drift impossible.

**Estimate:** 3–4 days.

**Rollout note:** This phase originally shipped behind `FeatureFlag.useParseCoordinator`. After the Phase 4 cutover, the coordinator path is the active path and the iOS feature flag helper has been removed.

### Task 3.1 — Create `ParseCoordinator.swift`

**File:** `Food App/Food App/Logging/ParseCoordinator.swift` (new)

```swift
@MainActor
final class ParseCoordinator: ObservableObject {
    @Published private(set) var snapshots: [UUID: ParseSnapshot] = [:]  // rowID → snapshot
    @Published private(set) var inFlight: Set<UUID> = []

    private let api: APIClient
    private let saveCoordinator: SaveCoordinator
    private let debounceInterval: TimeInterval = 0.5

    func textChanged(rowID: UUID, newText: String, loggedAt: Date) async
    func cancelInFlight(rowID: UUID) async
    func snapshotFor(rowID: UUID) -> ParseSnapshot?
}
```

Owns:
- `debounceTask`
- `parseTask`
- `parseRequestSequence`
- `activeParseRowID`
- `queuedRowIDs`
- The mapping `rowID → parseRequestId`
- The `applyRowParseResult` logic (with the row-mapping heuristics)

When parse completes, calls `saveCoordinator.enqueue(snapshot: snapshot, row: row)`.

### Task 3.2 — Image and voice paths plug into the same coordinator

Image: `parseImageLog` flow ends with `parseCoordinator.applyImageParseResult(rowID:response:)` which constructs a `ParseSnapshot` and routes to `SaveCoordinator` the same way text does. Today these are forked in `handlePickedImage` and `handleDrawerLogIt`; unify them.

Voice: same pattern. Voice transcribes to text, then runs through `textChanged`. The "voice" indicator becomes a UI flag, not a separate code path. Removes a class of bugs where voice and text saves diverge (we never verified voice saves work — see handoff 16.10).

### Task 3.3 — Tests

**File:** `Food App/Food AppTests/ParseCoordinatorTests.swift`

1. `textChanged` debounces — 5 keystrokes within 500ms = 1 parse request.
2. `textChanged` followed by another `textChanged` mid-flight cancels the in-flight parse.
3. Successful parse stores a snapshot keyed by rowID.
4. Successful parse calls `SaveCoordinator.enqueue` exactly once.
5. Parse returns `needsClarification` → snapshot stored but `enqueue` not called.

**Acceptance:** Verify with the same end-to-end save test as Phase 2 + a multi-row typing test (type three rows in a row, all should land in `food_logs`).

**Rollback:** Flag off.

---

## 7. Phase 4 — Slim `MainLoggingShellView`

**Why:** Once Phases 2 and 3 have been live and clean for 7+ days, the legacy code is dead weight. Delete it and let the view become render-only.

**Estimate:** 2 days.

### Tasks

1. Delete every `legacy_*` function added in Phases 2 and 3.
2. Delete every `@State` variable that's now owned by a coordinator (`pendingSaveQueue`, `completedRowParses`, `parseTask`, etc.).
3. The view should be < 1500 lines after this phase. Track LOC before and after; if it's still > 2000, something's still leaked.
4. Replace `pendingSaveQueue.first { ... }` patterns with `saveCoordinator.pendingItems.first { ... }`.
5. Eliminate the current batch-save lag path where completed rows visibly show calories but do not flush to saved state until the user changes days. After the coordinator cutover, completed rows should drain through the save queue without requiring navigation-triggered `flushPendingAutoSaveIfEligible()`.
6. Remove per-row full-day refresh behavior on successful batch autosaves when it is not needed for correctness. Batch saves should reconcile promptly, but the app must not refetch the full day after every single row in a large queue if that is what is delaying visible saved state.
7. Remove normal-operation sync pill anxiety: healthy saves should happen quietly, while exception states still surface actionable retry/waiting information.
8. Update CLAUDE.md to reflect the new architecture.

**Acceptance:** Build green. No new failures in production save success rate. In a multi-row batch, completed rows move to saved/reconciled state without requiring a day switch. Switching to Yesterday and back to Today must not be measurably faster than staying on Today for the same batch flush. The bottom sync pill should stay hidden during healthy saves and appear only when a real exception requires user awareness. The original `View LOC <= 1500` target remains a Phase 7/code-shrink target after the coordinator-only path bakes cleanly.

---

## 8. Phase 5 — Backend hardening (independent of iOS phases, can run in parallel)

**Estimate:** 1 day.

### Task 5.1 — Save attempt telemetry endpoint

**File:** `backend/src/routes/internalMetrics.ts`

```typescript
router.post('/save-attempts', async (req, res, next) => {
  // Accepts the SaveAttemptEvent shape from iOS Task 0.1.
  // Inserts into a new save_attempts table.
  // Auth: x-internal-metrics-key (same pattern as other internal endpoints).
});
```

**Migration:** `0019_save_attempts.sql`

```sql
CREATE TABLE IF NOT EXISTS save_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  parse_request_id TEXT,
  row_id UUID,
  outcome TEXT NOT NULL,
  error_code TEXT,
  latency_ms INTEGER,
  source TEXT,
  client_build TEXT,
  backend_commit TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_save_attempts_user_created_at ON save_attempts(user_id, created_at DESC);
CREATE INDEX idx_save_attempts_parse_request_id ON save_attempts(parse_request_id) WHERE parse_request_id IS NOT NULL;
```

Now the dashboard can join `parse_requests`, `food_logs`, AND `save_attempts` to give true ground truth: "did the client try to save? did it succeed? if not, what error?" — eliminates the `parse_only` ambiguity from handoff 16.1.

### Task 5.2 — Update `recent-parses` to use save_attempts

**File:** `backend/src/routes/evalDashboard.ts`

Add `saveAttempted`, `saveErrorCode`, `saveLatencyMs`, `saveSource`, `clientBuild`, `backendCommit` to each row in the `recent-parses` response. Pull from `save_attempts` joined on `parse_request_id`. Per handoff 16.13.

**Acceptance:** Dashboard `/recent-parses` rows now show whether the save was attempted client-side. A row that says `parse_only AND saveAttempted=false` is unambiguously "client never tried." A row that says `parse_only AND saveAttempted=true AND saveErrorCode=22` is "client tried and got 422" — actionable.

### Task 5.3 — Update PR template / CLAUDE.md

Add to the save-path verification rule: "After verifying `food_logs` row, also paste the matching `save_attempts` row showing `outcome = succeeded`."

---

## 9. Phase 6 — Dashboard upgrade (after Phase 5)

**Estimate:** 1 day.

### Task 6.1 — Render new columns in `index.html`

In `backend/src/testing-dashboard/index.html` `loadRecentParses` function, surface the new columns from Task 5.2. Sort/filter by `saveErrorCode` so all 422 failures cluster.

### Task 6.2 — "Stuck users" detail page

Click any user in the existing save-health card → opens a detail view with their last 50 parse requests, save attempts, and food_logs. Designed for "show me what's happening with this one user right now."

---

## 7b. Phase 7 — Code shrinkage (after Phase 4)

**Why:** Phases 0–6 add net code (tests, coordinators, telemetry). Phase 7 reclaims the LOC budget by going through the codebase with a sharp knife once the new architecture is stable. **Do not start until Phase 4 has been live for 14 days clean** — deleting things prematurely loses bug fixes.

**Estimate:** 3 days.

### Task 7.1 — LOC budget enforcement

For every file in `Food App/Food App/`, target:

| File class | Max LOC | Action if over |
|---|---|---|
| Coordinators | 500 | Extract sub-responsibility into a helper |
| SwiftUI views | 800 | Extract subviews into separate files |
| Pure helpers | 300 | Split into multiple helpers |
| Models / API types | 1000 | Acceptable; data shapes can be long |

After Phase 4, `MainLoggingShellView` should be < 1500. After Phase 7, **no file in `Food App/Food App/` exceeds 1000 LOC** except `MainLoggingShellView` itself (target 800), which becomes a thin shell that delegates to coordinators.

### Task 7.2 — Audit unused assets

```bash
# In project root:
find "Food App/Food App/Assets.xcassets" -name "*.imageset" -type d | while read dir; do
  name=$(basename "$dir" .imageset)
  hits=$(grep -rln "\"$name\"\|Image(\"$name\")\|UIImage(named: \"$name\")" "Food App/Food App/" --include="*.swift" | wc -l)
  if [ "$hits" -eq 0 ]; then echo "UNUSED: $name"; fi
done
```

Delete unused image assets. Audit the `IntroFood1`, `IntroFood2` etc. assets — onboarding may have been redesigned past them.

### Task 7.3 — Audit unused SPM packages

```bash
# What's declared:
grep -A2 "XCRemoteSwiftPackageReference" "Food App.xcodeproj/project.pbxproj" | grep "repositoryURL"

# What's imported:
grep -rh "^import " "Food App/Food App/" --include="*.swift" | sort -u
```

Cross-reference. Anything declared and not imported → remove. Common suspects: experimental SDKs added during prototyping.

### Task 7.4 — Delete dead Swift code

Run a build with `-warn-unused-code` (Swift compiler flag). Delete every function flagged as unused. Manual pass: search for `private func` definitions that are never called.

### Task 7.5 — Backend dead-code pass

```bash
cd backend && npx ts-prune --error
```

`ts-prune` finds exported symbols never imported elsewhere. Prune them.

**Acceptance:**
- iOS app binary size **< 90% of pre-refactor baseline** (record current with `du -sh "/path/to/.app"`)
- No file in `Food App/Food App/` exceeds 1000 LOC (excl. `MainLoggingShellView` ≤ 800)
- `ts-prune --error` exits 0 in `backend/`

**Rollback:** Revert the deletion PRs individually. (This is why Phase 7 ships as small PRs, one per category — easy to undo a specific one.)

---

## 7c. Phase 8 — Network + image efficiency

**Why:** Handoff data showed 234 parse_requests for 42 food_logs in 14 days. Even accounting for re-parses-while-typing, that's a lot of Gemini calls. And every image save uploads a full-size JPEG today (no compression). Both are real money and real latency on weak networks.

**Estimate:** 2 days.

### Task 8.1 — Image compression before upload

**File:** `Food App/Food App/ImageStorageService.swift`

Today `uploadJPEG` uploads whatever bytes it's handed. Add a compression step in `prepareImagePayload` (`MainLoggingShellView`) and the equivalent paths:

```swift
// Target: max 1920px long edge, quality 0.85, target ~500KB
extension UIImage {
    func compressedForUpload(maxDimension: CGFloat = 1920, quality: CGFloat = 0.85) -> Data? {
        let scale = min(maxDimension / max(size.width, size.height), 1.0)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(target, true, 1.0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: target))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        return resized?.jpegData(compressionQuality: quality)
    }
}
```

**Acceptance:** Take a meal photo → upload bytes < 600KB. Verify in `food_logs.image_ref` that the photo is intact and viewable in the app's review screen.

### Task 8.2 — Client-side parse cache (in-session)

**File:** `Food App/Food App/Logging/ParseCoordinator.swift`

Add an LRU cache keyed by normalized `rawText`. If the same string is parsed twice in the same session, return the cached `ParseSnapshot` immediately without hitting the server. 50-entry cap, 30-min TTL.

```swift
// Inside ParseCoordinator
private var parseCache: [String: ParseSnapshot] = [:]
private var parseCacheOrder: [String] = []
```

This handles the common case of "user types 'banana', deletes a character, retypes" — three parses today, one parse after.

**Acceptance:** Parse "banana" twice in 30 seconds. Telemetry should show 1 parse_request, not 2. Verify with `SELECT created_at FROM parse_requests WHERE raw_text='banana' ORDER BY created_at DESC LIMIT 5;`.

### Task 8.3 — Cold-start warmup ping

**File:** `Food App/Food App/Food_AppApp.swift`

On app launch, fire-and-forget a HEAD request to `/health`. Render's free tier sleeps after 15 minutes of inactivity; the wakeup takes ~10s. Doing it on launch (in parallel with auth restore + data fetch) means by the time the user types their first meal, the server is warm.

```swift
.task {
    // ... existing tasks ...
    Task.detached(priority: .background) {
        var req = URLRequest(url: appStore.configuration.baseURL.appendingPathComponent("/health"))
        req.httpMethod = "HEAD"
        req.timeoutInterval = 5
        _ = try? await URLSession.shared.data(for: req)
    }
}
```

**Acceptance:** Cold-launch the app (force-quit, wait 30 minutes, relaunch). Time from first character typed to first parse response. Should be < 5s P50 (was 15s+ before).

### Task 8.4 — Audit Gemini call necessity

**File:** `backend/src/routes/parse.ts`

Today the deterministic parser runs first and falls back to Gemini if confidence is too low. Audit the threshold: are we calling Gemini for things the deterministic parser could have handled?

Run:
```sql
SELECT primary_route, COUNT(*) FROM parse_requests
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY primary_route ORDER BY COUNT(*) DESC;
```

If `gemini` is > 70% of calls, the deterministic threshold is too aggressive. Consider raising the threshold or adding more deterministic patterns for common foods. Each Gemini call is real money and latency.

**Acceptance:** Gemini route share drops by **≥ 20%** week-over-week with no regression in `parse_only` rate.

---

## 7d. Phase 9 — iOS render + memory

**Why:** SwiftUI re-renders aggressively. With 12 `@State` variables in `MainLoggingShellView`, every state change triggers a full body recomputation. This isn't a bug — it's just wasteful, especially during typing. After Phases 2 and 3 move state into actors (which don't trigger SwiftUI invalidation), this gets better automatically. But there are explicit wins to grab.

**Estimate:** 2 days.

### Task 9.1 — Drop image preview bytes after save

**File:** `Food App/Food App/HomeFlowComponents.swift` (HomeLogRow)

Today `imagePreviewData: Data?` is held forever on every row, even after the row is `isSaved = true`. For a session with 10 image meals, that's ~50MB of preview data sitting in memory.

Once a row has `serverLogId != nil` AND `imageRef != nil` (photo successfully uploaded), set `imagePreviewData = nil` and lazy-load from the server `imageRef` if the user opens the detail view.

**Acceptance:** Use Xcode's Memory Graph debugger. Log 10 image meals in a session. Total app memory should not exceed pre-refactor baseline + 10MB.

### Task 9.2 — Audit `@Published` invalidations

Use Xcode's "SwiftUI Instruments" template. Record a 30s session of typing meals. Look for views that re-render > 60 times per second. The `MainLoggingShellView` body is the hot suspect.

After Phases 2 and 3, the coordinators publish less frequently than `@State` did (they batch updates within their actor). This phase verifies that and prunes any leftover spurious `@Published` properties.

**Acceptance:** No view in the rendering path re-evaluates more than once per actual user input event during a 30s typing test.

### Task 9.3 — Battery / background work audit

`AppStore.drainDeferredImageUploads` fires on every `.task` and on `isSessionRestored` change. The implementation already bails fast when there's nothing to drain (returns after `store.drain()` finds 0 entries). Verify that early-bail is < 10ms by adding a `signpost`.

If the deferred-upload entries pile up while the user is offline, `drain()` could try a long-running upload at launch on cellular. Add a Reachability check: skip drain on `.cellular` if there are > 3 pending entries; wait for Wi-Fi.

**Acceptance:** Background time spent in `drainDeferredImageUploads` < 50ms when queue is empty (the common case). When queue has entries on cellular, drain is gated on Wi-Fi or explicit user action.

---

## 7e. Phase 10 — Backend performance

**Why:** Every save POST runs in a transaction with two advisory locks. That's correct, but let's verify the query plan and connection pool are tuned. None of this is a current bottleneck — but it's cheap to check now and expensive to discover later.

**Estimate:** 1 day.

### Task 10.1 — Query plan audit

```sql
EXPLAIN ANALYZE
INSERT INTO food_logs (user_id, logged_at, ...) VALUES (...) RETURNING id;

EXPLAIN ANALYZE
SELECT id FROM food_logs WHERE user_id = $1 AND parse_request_id = $2;
```

Run for the 5 hot queries in `logService.ts`. If any uses a sequential scan on a table > 100k rows, add an index migration. The save flow today should be ≤ 4 sequential ops + 0 scans.

### Task 10.2 — Connection pool tuning

**File:** `backend/src/db.ts`

Current `pg.Pool` defaults: 10 connections, 30s idle timeout. On Render's free tier with one instance, that's fine. If we ever upgrade, the pool size should match Supabase's connection limit minus other consumers. Document the current value with a comment explaining the choice.

### Task 10.3 — Prepared statements

Convert hot queries in `logService.ts` to use named prepared statements:

```typescript
const insertFoodLogQuery = {
  name: 'insert-food-log',
  text: `INSERT INTO food_logs (...) VALUES ($1, $2, ...) RETURNING id`,
};
```

Per Postgres docs, named statements get cached query plans across invocations. Saves the planner work on every save.

**Acceptance:** P50 of `POST /v1/logs` request handler latency drops by **≥ 15%**. Measure via the existing metrics endpoint (or add a histogram if not present).

---

## 10. Bug-history mapping (handoff section 16 → phases)

| Bug from handoff section 16 | Fixed/mitigated in |
|---|---|
| 16.1 `parse_only` ambiguity | Phase 0 (telemetry) + Phase 5 (backend ingest) + Phase 6 (dashboard) |
| 16.2 Autosave inconsistency | Phase 1 (`SaveEligibility`) + Phase 2 (`SaveCoordinator`) |
| 16.3 Duplicates | Already handled by migrations 0017/0018; **Phase 0.2 verifies they're applied** |
| 16.4 Migration drift | Phase 0.2 (startup schema assert) |
| 16.5 422 strictness drift | Phase 1 (`ParseSnapshot`) + Phase 3 (`ParseCoordinator`) |
| 16.6 Keyboard/composer focus | UI test added in Phase 4 (no code change otherwise — already implemented) |
| 16.7 Save + image coupling | Already shipped in commits `0443246` and PR #2; **preserve** |
| 16.8 Cold start | Phase 0 (instrument cold-start; explicit "waking server" UI is a separate product task) |
| 16.9 Unresolved policy | **Out of scope — needs PM decision before code change** |
| 16.10 Env confusion | Phase 0.3 (`/health` returns commit SHA) |
| 16.11 Dark mode | **Out of scope — separate UI track** |
| 16.12 Onboarding copy | **Out of scope — product/copy track** |
| 16.13 Dashboard columns | Phase 5 + Phase 6 |

---

## 11. Acceptance criteria for the whole refactor

Adopted from handoff section 12.3 plus explicit performance numbers from Phases 7–10:

### Correctness (Phases 0–6)

1. **Single-row text save:** parse → visible calories → row in `food_logs` in **< 3s median** measured from telemetry, **99th percentile < 8s**.
2. **Multi-row typing:** type 5 rows back-to-back; **all 5 rows land in `food_logs`** in the next 30s. No skipped rows.
3. **No duplicates under retry/race:** run a script that fires the same save POST 10× concurrently; **exactly 1 row** in `food_logs`.
4. **Day swipe during pending autosave:** type a meal, immediately swipe to next day; the typed meal **lands on the original day's date**, not the swiped-to day.
5. **Force-quit + relaunch:** save a meal, force-quit before the deferred upload retry, relaunch; the row appears in `food_logs` and **`image_ref` is non-null** within 60s of relaunch.
6. **Cold start:** first action after 30 minutes of inactivity completes within 15s (Render free-tier wakeup); **dashboard shows `cold_start = true`** for that request.
7. **Schema drift detection:** drop a required column on a staging DB; backend exits cleanly within 30s of restart.

### Efficiency (Phases 7–10)

8. **Codebase shrinkage:** iOS app binary size **< 90% of pre-refactor baseline** measured via `du -sh "*.app"`.
9. **No file overweight:** no Swift file in `Food App/Food App/` exceeds 1000 LOC except `MainLoggingShellView` (≤ 800).
10. **Image upload size:** average uploaded image bytes **< 600KB** (was unbounded; could be 5MB+ on a recent iPhone).
11. **Cache effectiveness:** repeated parse of the same `rawText` within 30 minutes hits the in-session cache and **does not trigger a server `parse_request` row**.
12. **Cold-launch responsiveness:** time from app foreground to first meal saved **< 8s P50** (was 15s+ on free-tier cold start).
13. **Memory steady state:** logging 10 image meals in a row keeps process memory under **pre-refactor baseline + 10MB**.
14. **Backend latency:** P50 of `POST /v1/logs` handler latency **< 200ms**, P99 **< 800ms**.
15. **Gemini cost reduction:** Gemini route share of `parse_requests` drops **≥ 20% week-over-week** with no regression in `parse_only` rate.

Each criterion is independently testable. The refactor is "done" when:
- Criteria 1–7 (correctness) pass for 7 consecutive days on the coordinator-only build.
- Criteria 8–15 (efficiency) pass on the post-Phase-10 build.

If any criterion regresses, the responsible phase is rolled back by reverting the coordinator-only cutover or the specific non-cutover change that introduced the regression.

---

## 12. What the executor (codex) should NOT do

- Do not introduce new external dependencies (no new SPM packages, no new npm packages outside the existing set).
- Do not rename any public API endpoints, request/response fields, or DB columns.
- Do not rewrite tests that already pass — keep the existing `backend/tests/*.unit.test.ts` and `Food App/Food AppTests/*.swift` green throughout.
- Do not commit changes that fail `xcodebuild build` or `npx tsc --noEmit`.
- Do not delete legacy code paths in the same PR that introduces their replacement. Always two-phase: ship behind a safe rollout control → bake → delete.
- Do not modify `Food App/CLAUDE.md` to weaken the save-path verification rule.

---

## 13. PR strategy

One PR per **task** (not per phase). Each PR:

- Title: `[Phase N.X] <task name>`
- Body: link to this plan, acceptance criteria from the task subsection, manual test plan
- Size: aim for < 500 lines diff. If a task is bigger, split it.
- Reviewer: one human read-through, focus on correctness vs. the acceptance criteria
- Merge: squash, into `main`

Phase 0 PRs can land back-to-back (low risk). Phase 2 and 3 PRs need 48h staff bake before flag flip to 100%. Phase 4 PRs are deletion-only after 7 days of production traffic on the new code.

---

## 14. Estimated total time

| Phase | Theme | Effort | Wall-clock cumulative |
|---|---|---|---|
| 0 — Observability | Correctness | 1.5 days | 1.5 days |
| 1 — Pure helpers | Correctness | 2 days | 3.5 days |
| 2 — SaveCoordinator | Correctness | 4 days + 7-day bake | 14.5 days |
| 3 — ParseCoordinator | Correctness | 4 days + 7-day bake | 25.5 days |
| 4 — Slim view | Correctness + cleanup | 2 days | 27.5 days |
| 5 — Backend telemetry | Correctness | 1 day (parallel) | — |
| 6 — Dashboard upgrade | Correctness | 1 day (parallel) | — |
| **— 14-day post-Phase-4 soak —** | | | 41.5 days |
| 7 — Code shrinkage | Efficiency | 3 days | 44.5 days |
| 8 — Network + image | Efficiency | 2 days | 46.5 days |
| 9 — iOS render + memory | Efficiency | 2 days | 48.5 days |
| 10 — Backend perf | Efficiency | 1 day (parallel) | — |

**Total engineering time:** ~22 days. **Total wall time:** ~7 weeks.

Wall time dominated by:
1. The 7-day bake periods after Phases 2 and 3 (mandatory, not negotiable for save-flow changes).
2. The 14-day soak between Phase 4 and Phase 7. This is critical: **do not start cleanup phases until the new architecture has been live and stable for two weeks.** Premature cleanup has a near-100% rate of accidentally deleting a hard-won bug fix.

If you want this faster, the only safe lever is to run Phase 5, 6, and 10 fully in parallel with Phases 0–4 on the iOS side (different files, different repos). Listed estimates assume that already.

**What you cannot safely cut:**
- The bake periods. Skipping them is how the 18-day silent NULL happened.
- The soak between Phases 4 and 7. Skipping it deletes bug fixes.
- The acceptance criteria. Skipping them turns this into a vibes-based refactor.

---

## 15. Final note

The hardest part of this refactor is restraint. The `MainLoggingShellView.swift` file has 18 months of bug fixes layered on top of each other; every flag exists because something broke. **Don't delete a flag because it looks redundant.** Replace it deliberately, behind a feature flag, with telemetry confirming the new path is at least as good as the old one.

The goal is not "elegant code." The goal is "parse + save works on every meal, every time, forever." Elegance is a side effect.
