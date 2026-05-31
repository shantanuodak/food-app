# Overnight End-to-End Code Review — Final Report

**Branch:** `end-to-end-code-debug-and-review` (base `e71e52d`) · **Your `main`: never touched.**

## TL;DR
- **22 commits**, 40 source files, **1,672 lines of dead/duplicate code removed** (54 added — a security util + inlined call sites).
- **3 whole dead files deleted**; everything verified (backend `tsc` + 245 `vitest` tests green; iOS `xcodebuild` green after every batch).
- **1 real security fix** (timing-safe admin-key comparison).
- Every risky bug (save-path / auth / camera / data) was **documented, not auto-fixed** → see `REVIEW_NOTES_HUMAN_VERIFY.md`.
- All work lives in a **separate git worktree**; your repo directory stayed on `main` the entire time.

## How `main` was protected
- Work done in a worktree at `…/e2e-review-worktree`; your repo dir at `…/Food App/Food App` never left `main`.
- `main` re-verified `== e71e52d` after **every** commit.
- **Local only** — nothing pushed, no PR opened.
- iOS builds used a separate DerivedData (`…/e2e-derived-data`) so they couldn't collide with your Xcode.

## What was applied & verified

### Backend (`tsc` + `vitest` green, 245 tests)
- **Dead code removed** (~230 LOC): `streamGeminiJson`(+`extractCompleteJsonObjects`,`StreamItemCallback`), `tokenOverlapRatio`, `lookupByName`, `getTodayEstimatedCostUsd`, dead `export`, dead `resolvedStatus` ternary.
- **🔒 Security**: internal admin key was compared with plain `!==` across **7 endpoints** (6 routes + dashboard login) — a timing side-channel. Added `utils/internalKey.ts` (`timingSafeEqual`) and routed all comparisons through it.
- **Hardened**: log previously-swallowed SSE parse errors; `void` the fire-and-forget save-attempt telemetry in the error path.
- **Kept all `*ForTests` test seams** (verified each is imported by the test suite — not dead).

### iOS (`xcodebuild` green after each batch)
- **3 whole files deleted**: `HomeFlowComponents.swift` (467 LOC of `HM0x` prototype views), `UIImage+FixedOrientation.swift`, and the orb half of `OnboardingAnimatedBackground.swift` → trimmed + renamed to `OnboardingStaticBackground.swift`.
- **Onboarding** (~600 LOC): 7 dead component structs, dead animated-orb background, `OB03AgeScreen` `AgeWheelPickerRepresentable`+`agePickerSelection`+drag state, `.planPreview` zombie route (enum case + 5 switch arms), `normalizedForActiveFlow` identity fn, `OB02c` `helpCard`.
- **Profile** (~210 LOC): `profileHubSection`, `summaryHeaderSection`, `mealReminderSection`(+summary), `identityRow`, `heroData`, `trendData`.
- **Misc**: dead Streak helpers, dead `dismissTask` state (×2 files), `CameraView.showPhotoLibrary`, `FoodCameraURL`, `FoodStoryDay.shareText`, dead recipe audio-URL import path, `RecipeImportPendingStore` URL helpers, `isPasteFocused`, `SharedRecipePayload.with(url:)`, unused `ProfileDraftStore.preferenceSymbol`.

> Found one boundary mistake mid-run (a deletion clipped an `@ViewBuilder` attribute) — the **build caught it before any commit**, I reverted and redid it correctly. Nothing broken was ever committed.

## What was NOT touched — needs your eyes + a device test → `REVIEW_NOTES_HUMAN_VERIFY.md`
Real bugs deliberately left alone because they touch the save/parse/image path, auth, or camera behavior (your `CLAUDE.md` save-path rule). Highlights:
- 🔴 Deferred image bytes **not persisted to disk on a save *failure*** → `image_ref = NULL` risk (same shape as your 2026-04 incident).
- 🔴 `upsertPendingItem` matches `rowID` OR `idempotencyKey` → can overwrite a promoted item with edit data.
- 🔴 `autoSavedParseIDs` never cleared on failure; `reconcile` compares `loggedAt` by exact string (stuck sync pill).
- 🔴 `AuthService` single-flight reuses the first caller's metadata; mirroring `Task` leaks.
- 🔴 `CalorieHeroTile` uses a separate `ProfileDraftStore` → silent profile-draft overwrite.
- 🔴 `CameraService` mutates `@MainActor` state from a background queue (race); `switchCamera()` leaves a black viewfinder after capture.

## Remaining optional cleanups (documented, not applied)
- **BentoTokens**: ~24 unused color aliases in `HomeProfileBentoScreen` (~55 LOC, low priority) — grep-verify each, then remove.
- **Perf**: cache the per-render `DateFormatter`s as `static let` (5 sites); add a TTL to `QuickCameraPendingLogStore`.
- **Reduce-Motion typo** `HomeGreetingAnimations` `headTopY = reduceMotion ? 4 : 4` — clearly a bug, but the correct value is your call (likely `: 13`).
- **Backend (low-risk, test-backed)**: rate-limiter bucket-size cap, DNS-resolution timeout, `DELETE /devices/:token` `min(32)`, IANA timezone validation, `evalDashboard` `||`→`??`, re-enable CSP.
- **Xcode hygiene**: remove the duplicate `InstrumentSerif` font entries in Copy Bundle Resources (warns every build).

## Full detail
- `AUDIT_FINDINGS.md` + `AUDIT_FINDINGS_WAVE2.md` — every finding from the 10-agent read-only audit.
- `PROGRESS.md` — the running checkpoint (also the resume point if anything restarts).

## How to review & use this branch
The branch is checked out in the worktree at `…/e2e-review-worktree` (that's why it isn't directly checkout-able in your main repo yet).
1. **See the diff** (from your main repo, no checkout needed):
   `git -C "<repo>" diff e71e52d..end-to-end-code-debug-and-review`
2. **Build it yourself** in Xcode from the worktree dir to confirm green (I verified via `xcodebuild` CLI).
3. **To bring it into your main repo**: `git -C "<repo>" worktree remove "…/e2e-review-worktree"` then `git checkout end-to-end-code-debug-and-review` (or merge: your `main` is still at `e71e52d`, so it fast-forwards). Push when ready with `git push -u origin end-to-end-code-debug-and-review`.
4. Then work through `REVIEW_NOTES_HUMAN_VERIFY.md` with a real save/auth/camera test.

_Generated by the overnight autonomous review loop. Backend re-confirmed `tsc` green at report time._
