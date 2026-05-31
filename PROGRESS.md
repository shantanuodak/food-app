# End-to-End Code Review & Cleanup — PROGRESS / CHECKPOINT

**Branch:** `end-to-end-code-debug-and-review`
**Base (current main at start):** `e71e52d`
**Worktree (do ALL work here):** `/Users/shantanuodak/Desktop/Codex Folders/Food App/e2e-review-worktree`
**Main repo (NEVER touch — user's, Xcode open here):** `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App`
**Separate DerivedData:** `/Users/shantanuodak/Desktop/Codex Folders/Food App/e2e-derived-data`

## STRICT RULES (non-negotiable)
- NEVER modify `main` (ref or working dir). main stays at `e71e52d`. Verify after each commit.
- ALL edits/commits in THIS worktree on branch `end-to-end-code-debug-and-review`. Local only (no push/PR until approved).
- If stuck, STAY stuck + document. Do NOT fall back to main.
- Verify before commit: backend `tsc --noEmit` + `vitest` green; iOS `xcodebuild` green (separate DerivedData).
- Do NOT touch parse/save/image save-path beyond clearly-dead code. Document HV items, never auto-fix.
- Use `grep` not `rg` in Bash. iOS dead-code = in-file removals only (avoid project.pbxproj/whole-file deletes — queue those).

## VERIFICATION LOOP
- Backend: `"<wt>/backend/node_modules/.bin/tsc" --noEmit -p "<wt>/backend/tsconfig.json"` ; `npm --prefix "<wt>/backend" test`
- iOS: `xcodebuild build -project "<wt>/Food App.xcodeproj" -scheme "Food App" -destination "generic/platform=iOS Simulator" -derivedDataPath "<dd>"`

## PHASES
- [x] 0. Worktree setup + main isolation verified
- [x] 1. Baselines — iOS build GREEN; backend tsc GREEN; vitest GREEN (245 pass/34 skip)
- [x] 2. Exhaustive audit (10 agents) — AUDIT_FINDINGS.md + AUDIT_FINDINGS_WAVE2.md
- [~] 3/4. Applying verified cleanups (IN PROGRESS)
- [ ] 5. Final report + morning summary

## APPLIED (committed on branch, verified)
1. `refactor(backend): remove dead code` — streamGeminiJson(+extractCompleteJsonObjects,StreamItemCallback), tokenOverlapRatio, lookupByName; unexport isUnresolvedPlaceholderItem. **~230 LOC**. tsc+vitest GREEN.

## NEXT (in order)
- **Backend dead/fixes:** getTodayEstimatedCostUsd (check `startOfUtcDay` orphan after removal), resolvedStatus dead ternary (`routes/logs.ts:79`), recipeQualityScore `__testing`.
- **Backend security (high value):** timing-safe internal-key compare → `utils/internalKey.ts` + 6 routes + `app.ts:175`; floating-promise `void` (`logs.ts:209`); SSE error log (`parse.ts:800`); DELETE token + timezone validation.
- **Backend simplify:** extract `requireInternalKey`/`authContext`; rate-limiter factory.
- **iOS (build-verified, per area):** in-file dead-code removals — onboarding (~600+: OnboardingComponents 5 structs, OnboardingAnimatedBackground orb, AgeWheelPicker, .planPreview, normalizedForActiveFlow, helpCard), home (HM0x ~340, StreakBadgeProgress, heroSubtitle), profile (profileHubSection/summaryHeaderSection/mealReminderSection/identityRow/heroData/trendData/BentoTokens), recipes (conservative), camera. Then: DateFormatter→static, reduce-motion `4:13` fix, dead @State/@FocusState removal, dedup helpers.
- **DOCUMENT ONLY (HV, never auto-fix):** all save-path/auth/camera-behavioral/data-overwrite items (CalorieHeroTile draftStore overwrite, CameraService MainActor race, switchCamera black-screen, deferred-image disk-persist, upsertPendingItem, autoSavedParseIDs, etc.) — collect into REVIEW_NOTES_HUMAN_VERIFY.md.
- Project hygiene (queue for user/Xcode): duplicate InstrumentSerif font entries in Copy Bundle Resources.

## HOW TO RESUME (after a usage-limit reset / fresh session)
1. Read this file + CLAUDE.md. Confirm worktree exists and `main` still at `e71e52d`.
2. Continue from NEXT. Apply one batch, verify (tsc/vitest or xcodebuild), commit, update this file.
3. NEVER operate in the main repo dir. Stay in the worktree.
