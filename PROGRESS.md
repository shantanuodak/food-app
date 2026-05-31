# End-to-End Code Review & Cleanup — PROGRESS / CHECKPOINT

**Branch:** `end-to-end-code-debug-and-review` · **Base:** `e71e52d`
**Worktree (do ALL work here):** `/Users/shantanuodak/Desktop/Codex Folders/Food App/e2e-review-worktree`
**Main repo (NEVER touch):** `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App` · **DerivedData:** `…/e2e-derived-data`

## STRICT RULES
- NEVER modify `main` (ref or dir). main stays `e71e52d`; verify after each commit. Local only.
- ALL work in this worktree on the branch. If stuck, stay stuck + document; never fall back to main.
- Verify before commit: backend `tsc --noEmit` + `vitest`; iOS `xcodebuild` green (separate DerivedData).
- Do NOT touch save-path/auth beyond clearly-dead code. Document HV items, never auto-fix.
- Use `grep` not `rg`. iOS = in-file removals only (no project.pbxproj / whole-file deletes — queue those).

## VERIFICATION LOOP
- Backend: `"<wt>/backend/node_modules/.bin/tsc" --noEmit -p "<wt>/backend/tsconfig.json"` ; `npm --prefix "<wt>/backend" test`
- iOS: `xcodebuild build -project "<wt>/Food App.xcodeproj" -scheme "Food App" -destination "generic/platform=iOS Simulator" -derivedDataPath "<dd>"`

## PHASES
- [x] 0 setup + main isolation  · [x] 1 baselines GREEN (iOS build; backend tsc+vitest 245)  · [x] 2 audit (10 agents → AUDIT_FINDINGS*.md)
- [~] 3/4 applying verified cleanups (IN PROGRESS — backend nearly done; iOS dead-code next)
- [ ] 5 final report

## APPLIED (committed, verified GREEN)
1. backend dead code: streamGeminiJson(+helper,+StreamItemCallback), tokenOverlapRatio, lookupByName; unexport isUnresolvedPlaceholderItem. ~230 LOC. (f756d84)
2. backend: remove getTodayEstimatedCostUsd; log SSE parse errors; void fire-and-forget telemetry; inline dead resolvedStatus ternary. (e814601)
3. backend SECURITY: constant-time internal-admin-key compare across 7 endpoints (+ `utils/internalKey.ts`). (4031935)
4. iOS dead code: StreakBadgeProgress + earnedBadges/lockedBadges/progressToNext; helpCard/helpShimmer; heroSubtitle. ~115 LOC. xcodebuild GREEN. (e8626d4)
5. iOS dead code: 7 dead OnboardingComponents structs (Primary/SecondaryButton, SelectableTiles, PermissionBlock, InputField, 2 ButtonStyles). ~195 LOC. xcodebuild GREEN. (latest)

## NEXT (priority order)
- **iOS dead-code (PRIORITY — the big LOC wins; build-verify each area, commit per area):**
  - Onboarding: OnboardingComponents 5 unused structs(+2 ButtonStyles) ~180; OnboardingAnimatedBackground orb+helpers ~185; OB03AgeScreen agePickerSelection/AgeWheelPickerRepresentable ~100 + dragOffset/dragStartAge; OB02cChallengeInsightScreen helpCard ~60; AppFlowCoordinator .planPreview ~20 + normalizedForActiveFlow ~15.
  - Home: HomeFlowComponents HM00/HM02/HM03/HM04/HM06 ~340; StreakRewardModels StreakBadgeProgress+3 ~45; HomeStreakDrawerView heroSubtitle ~10; HomeGreetingAnimations greetingPrefix ~10; HomeFoodStoryDrawerView shareText; StreakAchievementPopup dismissTask.
  - Profile: HomeProfileScreen profileHubSection ~59/summaryHeaderSection ~27/mealReminderSection ~38; HomeProfileBentoScreen identityRow ~22/heroData ~20/trendData ~31/BentoTokens ~55; ProfileDraftStore preferenceSymbol ~16.
  - Recipes (CONSERVATIVE): RecipeAudioURLImportRequest+importRecipeFromAudioURL; RecipeImportPendingStore savePendingURL/consumePendingURL; ShareViewController with(url:).
  - Camera: CameraView showPhotoLibrary; FoodCameraWidget FoodCameraURL.
- **iOS safe bug fixes (build-verified):** DateFormatter→`static let` (HomeStreakDrawerView/HomeFoodStoryDrawerView/ExistingAccountDetectedView/MindfulPauseSheet/LoggingResultDrawerBody); reduce-motion `4:4`→`4:13` (HomeGreetingAnimations); dead @FocusState isPasteFocused; releaseVersion! force-unwrap.
- **Backend remainder (optional, lower value):** DELETE token min(32)+timezone validation; evalDashboard `||`→`??`; rate-limiter size cap; DNS resolve timeout. (CSP re-enable = DEFER/document — risk of breaking dashboard.)
- **DOCUMENT ONLY → write REVIEW_NOTES_HUMAN_VERIFY.md:** CalorieHeroTile draftStore overwrite; CameraService MainActor race + switchCamera black-screen; deferred-image disk-persist; upsertPendingItem rowID-OR-key; autoSavedParseIDs cleanup; clearPendingSaveContext; reconcile loggedAt string compare; AuthService single-flight metadata + mirroring-task leak; double-tap save sheet race. Plus project hygiene: duplicate InstrumentSerif font in Copy Bundle Resources.

## HOW TO RESUME
1. Read this file + CLAUDE.md. Confirm worktree exists, `main` still `e71e52d`.
2. Continue from NEXT. Apply one area, verify (xcodebuild / tsc+vitest), commit, update this file.
3. NEVER operate in the main repo dir.
