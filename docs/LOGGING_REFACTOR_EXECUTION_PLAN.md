# Logging Refactor: Execution Plan

## Current status (2026-05-03)
- Phase 0: Complete
- Phase 1: Complete
- Phase 2: Complete (SaveCoordinator is now the active iOS save path)
- Phase 3: Complete (ParseCoordinator is now the active iOS parse snapshot path; image/text/voice converge through shared snapshot persistence)
- Phase 4: Stable after manual gate verification
- Phase 5: Complete (save_attempts telemetry table, ingest endpoint, server-side save-route recording)
- Phase 6: Complete (recent-parses endpoint/dashboard now show save-attempt state)
- Phase 7: In progress (Phase 7A extraction pass active; large home component split is complete)
- Phase 8: Partially complete (image compression, same-row parse cache, cold-start warmup)
- Phase 9: Partially complete (saved image rows release preview bytes; deferred upload drain avoids expensive constrained batches)
- Phase 10: Partially complete (configurable DB pool max and prepared statements for hot save queries)

### Phase 4 implementation notes
1. Removed live save/parse feature-flag branching from `MainLoggingShellView`; active behavior now runs through `SaveCoordinator` and `ParseCoordinator`.
2. Removed the obsolete iOS `LoggingFeatureFlags` helper after the coordinator-only cutover.
3. Fixed batch autosave throughput by preserving an existing autosave timer instead of restarting it for every completed row.
4. Batch queue drains now defer full-day refresh until the batch completes, avoiding `loadDaySummary` + `loadDayLogs` after every saved row.
5. The normal bottom sync pill is hidden during healthy saves. The app only surfaces the bottom sync pill for exception states where a save error exists and pending work remains.
6. Extracted display-only helpers out of `MainLoggingShellView`:
   - `MainLoggingDockViews.swift`
   - `MainLoggingNutritionViews.swift`
   - `AuthSessionDisplayName.swift`
   - `HomeLoggingTextMatch.swift`
7. Validation run:
   - iOS build: `xcodebuild ... build` succeeded.
   - Manual 12-item batch test saved cleanly while staying on the same day.
8. Constraint: `MainLoggingShellView` is still above the long-term LOC target, but was reduced from 6,948 to 6,216 lines in the local cleanup pass. Deeper extraction remains Phase 7/code-shrink work.

### Phase 3 completion notes
1. Added `ParseCoordinator`; the original feature flag wiring was removed during the Phase 4 coordinator-only cutover.
2. Parse snapshot ownership now flows through a single helper path, and autosave consumers read coordinator snapshots directly.
3. Image and voice flows now use the same snapshot/autosave pipeline used by text parsing.
4. Canonical parse raw-text capture is enforced for save payload provenance (fixes parse-reference drift that causes `parse_only` persistence gaps).
5. Validation run:
   - iOS build: `xcodebuild ... build` succeeded.
   - Backend integration suite: `npm run test:integration` passed (30/30).
6. Constraint: the iOS project currently has no XCTest target, so Phase 3 unit tests were validated via build + integration + manual runtime verification instead of automated iOS unit tests.

### Phase 5/6 completion notes
1. Added `save_attempts` telemetry persistence with diagnostic-only constraints so telemetry cannot block user saves.
2. Added `/v1/internal/save-attempts` for structured save-attempt ingest behind the internal metrics key.
3. Added server-side save-route recording for `attempted`, `succeeded`, `failed`, and idempotency replay/duplicate-guard outcomes.
4. Enriched `/v1/internal/dashboard/recent-parses` with save-attempt fields:
   - `saveAttempted`
   - `saveAttemptCount`
   - `latestSaveOutcome`
   - `latestSaveErrorCode`
   - `latestSaveLatencyMs`
   - `latestSaveAttemptAt`
5. Updated the testing dashboard Recent Parses table with an `Attempt` column so parse-only rows can be distinguished from failed/attempted/succeeded saves.
6. Validation run:
   - Backend build: `npm run build` succeeded.
   - Backend unit suite: `npm test` passed.
   - Backend integration suite: `npm run test:integration` passed (31/31).

### Phase 7-10 pass notes
1. Phase 7 audit:
   - Starting Swift LOC audit showed `MainLoggingShellView.swift` at 5,580 lines, `HomeFlowComponents.swift` at 2,325 lines, `OnboardingView.swift` at 1,263 lines, and `ContentView.swift` at 1,030 lines.
   - Asset audit found all imagesets currently referenced.
   - Phase 7A implementation has started. Completed slices extracted logging presentation views, extracted the home status strip, removed unused logging detail panels, split row models, split the home composer, split the streak drawer, moved `RollingNumberText` into a shared file, and extracted shell-only enums.
   - Current LOC after these slices:
     - `MainLoggingShellView.swift`: 5,003
     - `MainLoggingShellModels.swift`: 24
     - `HomeFlowComponents.swift`: 467
     - `HomeComposerView.swift`: 1,061
     - `HomeStreakDrawerView.swift`: 460
     - `HomeLogRowModels.swift`: 317
   - Full Phase 7 is not complete; the next major target remains extracting parse/save/date/image flow wrappers from `MainLoggingShellView.swift`.
2. Phase 8:
   - Image parse payload prep now targets <= 600KB with progressive dimension/quality attempts.
   - `ParseCoordinator` now keeps a 50-entry, 30-minute same-row parse response cache. Cache keys include row ID and logged timestamp so repeat meals in new rows do not reuse parse IDs and collide with duplicate-save protection.
   - App launch now fires a background HEAD `/health` warmup to reduce Render cold-start impact before first parse.
3. Phase 9:
   - Saved image rows drop `imagePreviewData` after an `imageRef` exists, reducing retained JPEG bytes in long sessions.
   - Deferred photo upload drain now skips batches larger than three entries on constrained/expensive networks and logs drain timing.
4. Phase 10:
   - Backend DB pool max is now explicit/configurable via `DATABASE_POOL_MAX` with default 10.
   - Hot save-path queries use named prepared statements for food-log insert, item insert, existing parse lookup, and ownership lock checks.
5. Validation run:
   - Backend build: `npm run build` succeeded.
   - Backend unit suite: `npm test` passed.
   - Backend integration suite: `npm run test:integration` passed (31/31).
   - iOS build: `xcodebuild ... build` succeeded.

## Scope
Implementation plan for `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/LOGGING_REFACTOR_PLAN.md`.

This document converts the architecture plan into an execution sequence with shipping gates, rollback points, and test/ops requirements.

## Plan efficacy (assessment)

### Overall efficacy
- **High (8.5/10)** for correctness and operational safety.
- **Medium-high (7.5/10)** for speed (bake windows intentionally slow delivery).

### Why this is strong
1. Frozen API/DB contracts reduce migration risk.
2. Feature-flag rollout for the two riskiest phases (SaveCoordinator, ParseCoordinator).
3. Early observability closes the current diagnosis gap (`parse_only` ambiguity).
4. Explicit acceptance criteria avoids “refactor by feel.”

### Gaps to watch
1. `ParseCoordinator` mapping logic is still the hardest part; regressions likely if row mapping is moved too aggressively in one PR.
2. Out-of-scope product decisions (unresolved-item policy, dark mode/copy) can still create perceived failures even if code is correct.
3. Team discipline is required for bake/soak windows; schedule pressure is the main risk.

## Execution model

### Branching and release strategy
1. Use short-lived branches per task PR: `phase-0-1-save-telemetry`, etc.
2. Squash merge to `main` only after task acceptance is met.
3. Historical note: Phases 2 and 3 shipped behind runtime feature flags.
4. Current state: after Phase 4, the iOS app runs the coordinator paths directly and the legacy feature flag helper has been removed.

### Non-negotiable quality gates
1. iOS build: `xcodebuild` green.
2. Backend type/build: `npm run build` green.
3. Backend tests: `npm test` and `npm run test:integration` green.
4. Real end-to-end save verification (not just unit tests):
   - parse a real meal
   - save row
   - verify `food_logs` persisted
   - verify dashboard row behavior

## Phase-by-phase implementation sequence

## Phase 0 (Observability first)
### PR 0.1 — iOS save-attempt telemetry
- Add `SaveAttemptTelemetry.swift`.
- Add event emission in auto/manual/retry/patch paths.
- Add `parseRequestId` and row linkage everywhere possible.
- Acceptance:
  - Console shows attempted + succeeded/failed events for one meal.

### PR 0.2 — Backend schema assertions at boot
- Add `schemaAssertions.ts`.
- Call before `app.listen` in `index.ts`.
- Assert required columns and the unique index from migration `0018`.
- Acceptance:
  - Boot passes on healthy schema.
  - Boot exits on intentionally broken local schema.

### PR 0.3 — `/health` adds commit + schema metadata
- Include `commit` and `schemaVersion` fields.
- Acceptance:
  - Render `/health` returns expected metadata.

## Phase 1 (pure extraction, no behavior change)
### PR 1.1 — `SaveEligibility.swift`
- Centralize eligibility logic.
- Replace duplicated filters.
- Add focused unit tests.

### PR 1.2 — `IdempotencyKeyResolver.swift`
- Centralize row-key reuse logic.
- Add tests.

### PR 1.3 — `ParseSnapshot.swift`
- Replace tuple-based `completedRowParses` with typed model.
- No functional change.

## Phase 2 (SaveCoordinator)
### PR 2.1 — Create coordinator + protocols
- Build `SaveCoordinator` with injected API/storage/telemetry deps.
- Move queue state ownership into coordinator.

### PR 2.2 — Wire coordinator
- Historical rollout used a feature flag.
- Current behavior is coordinator-only after Phase 4.

### PR 2.3 — Unit tests
- Happy path, retries, duplicates, image failure fallback, patch, delete.

### Release gate for Phase 2
1. Historical rollout used a flag-off, staff-only, bake, then all-user sequence.
2. Current behavior is coordinator-only after Phase 4.
3. Rollback is now commit-level rollback of the Phase 4 cutover, not runtime flag toggling.

## Phase 3 (ParseCoordinator)
### PR 3.1 — Coordinator + row snapshot ownership
- Move debounce/in-flight/queue/snapshot logic from view.

### PR 3.2 — Unify image/voice into same coordinator pipeline
- Standardize parse->snapshot->save enqueue path.

### PR 3.3 — Unit tests
- Debounce, cancellation, snapshot creation, enqueue trigger behavior.

### Release gate for Phase 3
1. Historical rollout used a flag-off, staff-only, bake, then gradual all-user sequence.
2. Current behavior is coordinator-only after Phase 4.
3. Rollback is now commit-level rollback of the Phase 4 cutover, not runtime flag toggling.

## Phase 4 (view slimming and legacy removal)
### PR 4.1 — Remove legacy save/parse branches
- Remove `legacy_*` only after Phase 2+3 stability windows.
- Reduce `MainLoggingShellView` state surface.
- Fix batch autosave throughput so completed rows do not rely on day-switch navigation to flush quickly.
- Remove unnecessary per-row day refreshes during large autosave batches when the refresh pattern is the cause of delayed saved-state reconciliation.

### PR 4.2 — Update docs and runbook
- Update `CLAUDE.md` and verification checklist.

### Acceptance
- `MainLoggingShellView` materially reduced; final target LOC remains Phase 7/code-shrink work.
- No save success-rate regression.
- Multi-row batch save behaves the same while staying on Today as it does after switching away and back; navigation should not be required to accelerate save reconciliation.

## Phase 5/6 (backend telemetry and dashboard, parallel track)
### PR 5.1 — `save_attempts` migration + ingest endpoint
- Add `0019_save_attempts.sql`.
- Add `/v1/internal/save-attempts` ingest.

### PR 5.2 — enrich `recent-parses` response
- Add `saveAttempted`, `saveErrorCode`, `saveLatencyMs`, etc.

### PR 6.1 — dashboard UI columns/filters
- Render these fields in testing dashboard.

## Phase 7–10 (post-stability efficiency track)
- Phase 7: code shrinkage and dead code/assets pruning.
- Phase 8: image compression, session parse cache, warmup ping.
- Phase 9: render/memory optimization.
- Phase 10: backend perf tuning (query plans/pool/prepared statements).

Detailed Phase 7 execution plan: `docs/PHASE_7_EXTRACTION_PLAN.md`.

Start only after 14-day stable soak post-Phase 4.

## Test matrix (minimum per phase)

### Must-pass manual scenarios
1. Single text entry save.
2. Multi-row typing then autosave.
3. Rapid edits (quantity fast path).
4. Swipe day immediately after typing.
5. Image parse + save + delayed image attach.
6. Force-quit between save and deferred image upload.
7. Retry path after network loss.

### Must-pass DB checks
1. Exactly one `food_logs` row per `(user_id, parse_request_id)`.
2. `log_save_idempotency` row present for saves.
3. Dashboard row has coherent parse/save state.

## Rollback playbook

1. For Phase 2/3 regressions after Phase 4: revert or roll back the coordinator-only cutover build.
2. For backend telemetry regressions: disable internal ingest route use (non-user-facing).
3. For migration issues: halt deploy and restore last healthy release.
4. Never rollback by destructive DB reset; use forward fixes or controlled deploy rollback.

## What to expect (outcomes)

### After Phases 0–4
1. Save behavior becomes deterministic and diagnosable.
2. Duplicate-save class is guarded at both app and DB levels.
3. `MainLoggingShellView` becomes materially smaller and easier to maintain.
4. On-call debugging time drops because parse/save attempts are traceable.

### After Phases 5–10
1. Dashboard becomes true source for parse/save intent vs. persistence outcome.
2. Reduced payload and parse churn lowers latency and infra cost.
3. Memory/render profile is more stable on long sessions.

## What you need to do to see a build

### For local/dev validation
1. Pull latest `main`.
2. Run backend:
   - `cd backend`
   - `npm install`
   - `npm run migrate`
   - `npm run build`
   - `npm run start`
3. Run iOS build:
   - `xcodebuild -project "Food App.xcodeproj" -scheme "Food App" -configuration Debug -destination 'generic/platform=iOS Simulator' build`
4. Launch app and run the manual test matrix above.

### For deployed/staging validation
1. Push merged PR to `main`.
2. Confirm Render deploy is on expected commit SHA (`/health`).
3. Confirm migrations applied (`schema_migrations` includes required migration IDs).
4. Enable flags only per rollout gate.

### Final expectation on your side
1. You should expect a safer but slower rollout due to mandatory bake windows.
2. You should expect no API-level behavior breaks if constraints are respected.
3. You will need to actively run acceptance checks at each phase; this plan is not “merge and hope.”
