# Logging Refactor: Execution Plan

## Current status (2026-05-01)
- Phase 0: Complete
- Phase 1: Complete
- Phase 2: Complete (flagged path shipped; legacy fallback still present by design)
- Phase 3: Complete (flagged ParseCoordinator path wired; image/text/voice now converge through shared snapshot persistence)
- Phase 4: Blocked by rollout rule (do not remove legacy branches until Phase 2/3 flagged paths have baked cleanly)
- Phase 5: Complete (save_attempts telemetry table, ingest endpoint, server-side save-route recording)
- Phase 6: Complete (recent-parses endpoint/dashboard now show save-attempt state)

### Phase 3 completion notes
1. Added `ParseCoordinator` and parse feature flag wiring (`use_parse_coordinator` / `feature.useParseCoordinator`).
2. Parse snapshot ownership now flows through a single helper path, and autosave consumers read coordinator snapshots when the flag is enabled.
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
3. Use runtime feature flags:
   - `use_save_coordinator`
   - `use_parse_coordinator`
4. Keep legacy path in code until flag-on stability windows are complete.

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

## Phase 2 (SaveCoordinator, behind flag)
### PR 2.1 — Create coordinator + protocols
- Build `SaveCoordinator` with injected API/storage/telemetry deps.
- Move queue state ownership into coordinator.

### PR 2.2 — Wire coordinator under flag
- Keep legacy path as `legacy_*`.
- New path only when `use_save_coordinator` enabled.

### PR 2.3 — Unit tests
- Happy path, retries, duplicates, image failure fallback, patch, delete.

### Release gate for Phase 2
1. Ship with flag OFF.
2. Enable for staff/internal account.
3. 48h bake.
4. If stable, enable for all users.
5. Keep legacy code until 7 days clean.

## Phase 3 (ParseCoordinator, behind flag)
### PR 3.1 — Coordinator + row snapshot ownership
- Move debounce/in-flight/queue/snapshot logic from view.

### PR 3.2 — Unify image/voice into same coordinator pipeline
- Standardize parse->snapshot->save enqueue path.

### PR 3.3 — Unit tests
- Debounce, cancellation, snapshot creation, enqueue trigger behavior.

### Release gate for Phase 3
1. Ship with flag OFF.
2. Enable staff-only.
3. 48h bake.
4. Gradual 100% rollout.
5. Keep legacy parse path 7 days clean.

## Phase 4 (view slimming and legacy removal)
### PR 4.1 — Remove legacy save/parse branches
- Remove `legacy_*` only after Phase 2+3 stability windows.
- Reduce `MainLoggingShellView` state surface.

### PR 4.2 — Update docs and runbook
- Update `CLAUDE.md` and verification checklist.

### Acceptance
- `MainLoggingShellView` at/below target LOC.
- No save success-rate regression.

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

1. For Phase 2/3 regressions: flip feature flag OFF immediately.
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
