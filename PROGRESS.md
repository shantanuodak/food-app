# End-to-End Code Review & Cleanup — PROGRESS / CHECKPOINT

**Branch:** `end-to-end-code-debug-and-review` · **Base:** `e71e52d`
**Worktree (do ALL work here):** `/Users/shantanuodak/Desktop/Codex Folders/Food App/e2e-review-worktree`
**Main repo (NEVER touch):** `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App` · **DerivedData:** `…/e2e-derived-data`

## STRICT RULES
- NEVER modify `main`. main stays `e71e52d`; verify after each commit. Local only (no push/PR).
- ALL work in this worktree on the branch. If stuck, stay stuck + document; never fall back to main.
- Verify before commit: backend `tsc --noEmit` + `vitest`; iOS `xcodebuild` GREEN (separate DerivedData). NEVER commit a red build.
- Do NOT touch save-path/auth beyond clearly-dead code. Document HV items, never auto-fix.
- Use `grep` not `rg`.

## GOTCHAS / LESSONS (learned this run)
- **Xcode-16 filesystem-synchronized groups**: files are NOT listed in `project.pbxproj` → a whole dead `.swift` file can be deleted with `git rm` (no pbxproj edit). Build reflects disk.
- **`@ViewBuilder` (and other attribute lines) sit ABOVE the member they decorate.** When deleting a member by line range, STOP before the next member's attribute/doc-comment line — do NOT include it in the previous deletion, or you strip the next member's `@ViewBuilder` and break its `some View` body. (Caught by build; cost one rebuild.)
- Always `grep -nB1` the member after a deletion to confirm its attribute survived; restore via `git checkout HEAD -- <file>` if a build fails.

## VERIFICATION LOOP
- Backend: `"<wt>/backend/node_modules/.bin/tsc" --noEmit -p "<wt>/backend/tsconfig.json"` ; `npm --prefix "<wt>/backend" test`
- iOS: `xcodebuild build -project "<wt>/Food App.xcodeproj" -scheme "Food App" -destination "generic/platform=iOS Simulator" -derivedDataPath "<dd>"` (-quiet; EXIT=0 = green)

## PHASES
- [x] 0 setup  · [x] 1 baselines GREEN  · [x] 2 audit (10 agents → AUDIT_FINDINGS*.md)
- [~] 3/4 applying verified cleanups (IN PROGRESS)
- [ ] 5 final report (REVIEW_NOTES_HUMAN_VERIFY.md + summary)

## APPLIED (committed, verified GREEN) — running total ~1,237 LOC dead code removed
1. backend dead code: streamGeminiJson/tokenOverlapRatio/lookupByName; unexport helper. ~230. (f756d84)
2. backend: rm getTodayEstimatedCostUsd; SSE error log; void telemetry; inline dead ternary. (e814601)
3. backend SECURITY: constant-time internal-admin-key compare ×7 (+utils/internalKey.ts). (4031935)
4. iOS: StreakBadgeProgress+helpers; helpCard/helpShimmer; heroSubtitle. ~115. (e8626d4)
5. iOS: 7 dead OnboardingComponents structs. ~195. (e5c76d4)
6. iOS: DELETE dead whole file HomeFlowComponents.swift (5 HM0x prototype views). 467. (b4afc92)
7. iOS: dead Profile sections (profileHubSection/summaryHeaderSection/mealReminderSection/mealReminderSummaryText; identityRow/heroData/trendData). ~210. (e4d9424)
8. iOS misc dead: whole-file UIImage+FixedOrientation.swift; CameraView.showPhotoLibrary; FoodCameraURL; FoodStoryDay.shareText; RecipeAudioURLImportRequest+importRecipeFromAudioURL; RecipeImportPendingStore url helpers; StreakAchievementPopup dismissTask. ~60. (latest)
NOTE: `greetingPrefix` NOT removed (used by live GreetingAnimationPlaygroundView via HomeProfileScreen:90). BadgesTrophyCaseView has its OWN dead dismissTask (separate, pending).

## NEXT (priority order; build-verify each)
- iOS in-file dead: AppFlowCoordinator `.planPreview` route + `normalizedForActiveFlow`; OnboardingAnimatedBackground orb-variant (keep OnboardingStaticBackground; strip its #Preview); OB03AgeScreen agePickerSelection/AgeWheelPickerRepresentable + dragOffset/dragStartAge; HomeProfileBentoScreen BentoTokens unused aliases (~55); ProfileDraftStore preferenceSymbol; StreakAchievementPopup dismissTask; HomeGreetingAnimations greetingPrefix+CaseIterable; HomeFoodStoryDrawerView shareText; recipes (RecipeAudioURLImportRequest+importRecipeFromAudioURL, RecipeImportPendingStore savePendingURL/consumePendingURL, ShareViewController with(url:)); camera (CameraView showPhotoLibrary, FoodCameraWidget FoodCameraURL).
- iOS whole-file-dead candidates (verify zero-ref then `git rm`): UIImage+FixedOrientation.swift (check), GreetingAnimationPlaygroundView.swift (#if DEBUG/QA only?).
- iOS safe bug fixes: DateFormatter→`static let` (HomeStreakDrawerView dateKey, HomeFoodStoryDrawerView 2×, ExistingAccountDetectedView, MindfulPauseSheet, LoggingResultDrawerBody); reduce-motion `4:4`→`4:13` (HomeGreetingAnimations:276); dead @FocusState isPasteFocused (HomeRecipesDrawer); releaseVersion! force-unwrap.
- Backend remainder (optional): DELETE token min(32)+timezone validation; evalDashboard `||`→`??`; rate-limiter size cap; DNS timeout. (CSP = DEFER/document.)
- DOCUMENT ONLY → REVIEW_NOTES_HUMAN_VERIFY.md: all save-path/auth/camera-behavioral/data-overwrite HV items + duplicate InstrumentSerif font in Copy Bundle Resources.

## HOW TO RESUME
1. Read this file + CLAUDE.md. Confirm worktree exists, `main` still `e71e52d`.
2. Continue from NEXT. Apply one area, verify, commit, update this file. Heed GOTCHAS.
3. NEVER operate in the main repo dir.
