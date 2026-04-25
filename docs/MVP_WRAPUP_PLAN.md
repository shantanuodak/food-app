# MVP Wrap-Up Plan — Food App (7-day close-out)

Last updated: 2026-04-20
Owner: Shantanu + Engineering

## Context

We are closing out the Food App MVP in the next 7 days. No new features. Fix what's half-wired, lock down a robust testing plan, and drive the app to a production-ready state.

After deep exploration across iOS, backend, and docs, the project is **further along than the FR gap list suggests**. The five "GAP" items in `FUNCTIONAL_REQUIREMENTS.md` §19 are mostly resolved in code:

- GAP-001 future-date lock → **already enforced** in `MainLoggingShellView.swift` (`clampedSummaryDate` ~line 682).
- GAP-002 camera ingestion → **fully wired** (`parseImageLog` → `/v1/logs/parse/image`).
- GAP-003 voice flow → **end-to-end** (Speech → transcript → parse).
- GAP-004 Progress tab → **functional charts** (not placeholder) — `HomeProgressScreen.swift`.
- GAP-005 reduced onboarding payload → **by design** (rich draft captured locally, slim request sent).

The **real outstanding items** are (a) test coverage gaps, (b) the P0/P1 contract items flagged in `JIRA_BACKLOG_MVP.md` EPIC-10, and (c) five pending iOS manual E2E rows in `E2E_QA_MATRIX_MVP.md`. Also: `FUNCTIONAL_REQUIREMENTS.md` §19 is out of date and should be updated to reflect current reality.

## Goal

Land three things by Day 7:

1. **Fix** the remaining known-gap items (no new surface area).
2. **Comprehensive testing plan** (document) + closed test-coverage gaps (code).
3. **Launch-ready** state: release preflight green, TestFlight build uploaded, backend deployable.

---

## Outstanding work punch-list

### A. Backend — P0/P1 contract items still open (per JIRA_BACKLOG_MVP.md EPIC-10)

Approach: **verify-then-test**. Audit current code against each contract; if it already matches, just add a pinning test and close the ticket. Only change code if a real gap is found.

| ID | Prio | Plain-English meaning |
|----|------|----------------------|
| **BE-025** | P0 | *Onboarding provenance.* When we save a user's onboarding profile, do we store the **raw inputs** (age, weight, activity, pace) and compute targets on the fly — or store the **computed targets** and drop inputs? Pick one mode, stamp a version, and persist audit metadata so we can answer "how did we arrive at 2100 kcal for this user?" Migration `0008_onboarding_provenance.sql` + `onboardingService.ts` already exist; we need to confirm the mode is explicitly selected and the integrity test passes. |
| **BE-026** | P0 | *Parse response source attribution + v2 additive item fields.* Response must include `sourcesUsed` (array of source families) and each item must carry `amount`, `unitNormalized`, `gramsPerUnit`, `needsClarification`, `manualOverride`. Totals-from-items invariant enforced server-side. Migration `0011_food_logs_sources_used.sql` exists; need to verify item shape matches on parse response. |
| **BE-027** | P0 | *Item-level clarification gating.* If any item has `needsClarification=true`, save is blocked until clarified or explicitly overridden. Depends on BE-026. Needs a test pinning the 422 code + envelope. |
| **BE-028** | P0 | *Manual override provenance on save.* If user edits "chicken 100g → 150g" before saving, we store that it was manually overridden, keep original provider attribution, and reject incompatible `parseRequestId/parseVersion` with 422. Migration `0009_food_log_item_provenance` exists; need to confirm the save path exercises it. |
| **BE-029** | P0 | *Future-date backend enforcement by timezone.* Reject `loggedAt` in the future relative to the user's timezone (iOS already blocks this, but backend should be the source of truth). Integration tests already cover basic future-date rejection — extend for midnight and DST edges. |
| **BE-030** | P1 | *HealthKit write dedupe contract.* On save retry or log edit, Apple Health write must replace/upsert with a stable per-log dedupe key — not produce duplicate entries. Daily-aggregate mode is explicitly off for MVP. `healthSyncContractService.ts` exists; contract needs to be pinned with a test. |
| **BE-031** | P1 | *Parse cache key v2 composite namespace.* Cache key must include locale + units + parser version + provider route version + prompt version, so a prompt change invalidates stale cache. Migration `0010_parse_cache_scope.sql` did part of this; audit all five dimensions and document the operational purge path. |

Treat each as a **fix-to-contract** (not a new feature). If any expands scope, flag and defer.

### B. Backend — missing unit tests

Add Vitest unit tests under `backend/tests/`:

- `escalationService.unit.test.ts`
- `idempotencyService.unit.test.ts`
- `aiCostService.unit.test.ts` (budget soft-cap + daily hard-cap)
- `daySummaryService.unit.test.ts` (timezone edge cases)
- `parseOrchestrator.unit.test.ts` (cache → fallback → escalation routing)
- `logService.unit.test.ts` (save + PATCH + provenance)
- `imageParseService.unit.test.ts`

### C. Backend — missing integration coverage

Extend `tests/integration.api.test.ts`:

- Daily budget overflow returns `402 BUDGET_EXCEEDED` with clean UX envelope.
- Multi-user RLS isolation (user A cannot read user B's logs / day-summary).
- Image parse cost event recorded correctly.
- Manual override provenance round-trips through save + day-summary.

### D. iOS — test target (currently zero tests)

Add a **new XCTest target** (`Food AppTests`) to `Food App.xcodeproj`. Target the pure / testable units first (no UI snapshots):

- `OnboardingRequest` encoding from `OnboardingDraft` (catches payload regressions).
- Day-navigation clamping helper (`clampedSummaryDate()`).
- Save-payload fingerprint / idempotency key derivation.
- Parse debounce scheduler (extract a small reducer to make it testable — minimum viable refactor, scoped).
- `NetworkStatusMonitor` offline detection.
- `AppConfiguration` env resolution.

**Out of scope for this pass:** breaking up `MainLoggingShellView.swift` (~2100 LOC). Note as post-MVP debt.

### E. iOS — close the 5 pending manual E2E rows

Per `E2E_QA_MATRIX_MVP.md`:

1. API auth failure UX (401 → re-auth).
2. Invalid input error UX (empty / too long / non-food).
3. Offline retry (documented in `IOS_E2E002_OFFLINE_RETRY.md`).
4. Accessibility / localization (`IOS_E2E004_ACCESSIBILITY_LOCALIZATION.md`).
5. Beta readiness (`IOS_E2E005_BETA_READINESS.md`).

For each: run the checklist, fix regressions found, mark row PASS in the matrix.

### F. Docs — single source of truth

- Update `FUNCTIONAL_REQUIREMENTS.md` §19 to reflect current reality (close GAP-001..005).
- Update `FR_TRACEABILITY_MVP_2026-02-28.md` with today's status.
- Create a new **`docs/TESTING_PLAN_MVP.md`** consolidating:
  - iOS XCTest suite + what it covers.
  - Backend unit + integration matrix.
  - E2E manual matrix (link existing).
  - Performance gates (`E2E_PERFORMANCE_MVP.md`).
  - Release preflight order.
  - What each CI job runs.

### G. Launch readiness

- Walk `STRICT_LAUNCH_RUNBOOK_MVP.md` + `BACKEND_RELEASE_CHECKLIST.md` + `IOS_TESTFLIGHT_RELEASE_CHECKLIST.md`.
- Run `npm run release:backend` (in `backend/`) — must be green.
- Run `scripts/ios/testflight_preupload_gate.sh` — must be green.
- Commit work into the existing git repo at `Food App/Food App/.git` with remote `github.com/shantanuodak/food-app`.

---

## Locked decisions

- **Backend items (BE-025–031):** verify-then-test. Audit current code; if contract holds, add pinning test and close. Only change code on a confirmed gap.
- **iOS tests:** unit tests on pure logic only (new `Food AppTests` XCTest target). No snapshot / XCUITest this pass.
- **Git:** one short-lived feature branch per chunk (e.g. `wrapup/backend-unit-tests`, `wrapup/ios-test-target`, `wrapup/be-025-provenance`), PR to `main` on `github.com/shantanuodak/food-app`.

## Day-by-day roadmap (indicative; compressible)

| Day | Focus |
|-----|-------|
| **1** | Write `docs/TESTING_PLAN_MVP.md`. Update FR doc §19 (close GAP-001..005). Audit BE-025–031 against current code; produce a per-item verdict table. Branch: `wrapup/docs-and-audit`. |
| **2** | Backend unit tests B.1–B.4 (escalation, idempotency, aiCost, daySummary). Branch: `wrapup/backend-unit-tests-1`. |
| **3** | Backend unit tests B.5–B.7 (orchestrator, logService, imageParseService). Branch: `wrapup/backend-unit-tests-2`. |
| **4** | BE-025–031 pinning tests (and narrow code fixes only where audit flagged a real gap). Integration tests C.1–C.4 (budget overflow, RLS isolation, image parse cost, override round-trip). Branch per item. |
| **5** | Add iOS `Food AppTests` XCTest target + scheme. Land unit tests D.1–D.6. Branch: `wrapup/ios-test-target`. |
| **6** | iOS manual E2E rows E.1–E.5: run, fix regressions found, mark PASS in matrix. Branch: `wrapup/ios-e2e-closeout`. |
| **7** | Full release preflight: `release:backend`, `testflight_preupload_gate.sh`, runbook dry-run, all branches merged, TestFlight build uploaded. |

Buffer: Days 6–7 double as spill from earlier slippage.

---

## Critical files

**iOS**
- `Food App/Food App/MainLoggingShellView.swift` — parse/save orchestration; target of extracted-reducer pattern for tests.
- `Food App/Food App/OnboardingView.swift` + `OnboardingFlowModels.swift` — encoding tests.
- `Food App/Food App/APIClient.swift`, `APIModels.swift` — contract surface.
- `Food App/Food App.xcodeproj/project.pbxproj` — add test target.

**Backend**
- `backend/src/services/parseOrchestrator.ts`, `parsePipelineService.ts`, `escalationService.ts`, `logService.ts`, `idempotencyService.ts`, `aiCostService.ts`, `daySummaryService.ts`, `imageParseService.ts`, `healthSyncContractService.ts`, `onboardingService.ts`, `parseCacheService.ts`.
- `backend/tests/integration.api.test.ts` — extend with C.1–C.4.
- `backend/migrations/` — only touch if contract gap confirmed.

**Docs**
- New: `docs/TESTING_PLAN_MVP.md`.
- Update: `FUNCTIONAL_REQUIREMENTS.md`, `docs/FR_TRACEABILITY_MVP_2026-02-28.md`, `docs/JIRA_BACKLOG_MVP.md`, `docs/E2E_QA_MATRIX_MVP.md`.

---

## Existing utilities / tests to reuse

- `integration.api.test.ts` already covers onboarding→parse→save→summary, idempotency replay (line 1063, 1106), cache invalidation, timezone, future-date rejection, escalation. **Extend, don't duplicate.**
- `scripts/ios/testflight_preupload_gate.sh` — one-command pre-upload gate.
- `npm run release:backend` — one-command build + test + integration + preflight.
- `npm run benchmark:replay` — 1000-log perf harness (for E2E_PERFORMANCE gates).
- `parseCacheService.ts` namespace helpers — reuse for BE-031 audit.
- `utils/errors.ts` `ApiError` — reuse for BE-025/028 error envelopes.

---

## Verification (how we know we're done)

**End-to-end checks run at close of Day 7:**

1. `cd backend && npm run release:backend` → exits 0.
2. New iOS XCTest target: `xcodebuild test -project "Food App.xcodeproj" -scheme "Food App" -destination "platform=iOS Simulator,name=iPhone 16"` → passes.
3. `backend/tests/integration.api.test.ts` new scenarios (C.1–C.4) all green.
4. `E2E_QA_MATRIX_MVP.md`: all rows PASS (no PENDING left).
5. `docs/TESTING_PLAN_MVP.md` exists and reconciles with actual tests in repo.
6. `JIRA_BACKLOG_MVP.md`: BE-025–031 closed or explicitly deferred with rationale.
7. `scripts/ios/testflight_preupload_gate.sh` → exits 0; build uploaded to TestFlight internal testers.
8. `git log` in `Food App/Food App/` shows the wrap-up work committed and pushed to `origin/main`.

---

## Explicitly out of scope (post-MVP)

- Refactoring `MainLoggingShellView.swift` / `OnboardingView.swift` into smaller views.
- Snapshot / UI tests for iOS (deferred; unit only this pass).
- Landing page polish (current `index.html` + `styles.css` deemed sufficient placeholder).
- FatSecret re-introduction (deprecated per `POLICY-002`).
- Progress feature expansion beyond current charts.
