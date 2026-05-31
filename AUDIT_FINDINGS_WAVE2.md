# AUDIT FINDINGS — Wave 2 (recipes / home / profile-bento / onboarding / camera)

Base `e71e52d`. Candidates — not yet adversarially verified or applied. **HV** = human-verify (save-path/auth/behavioral — do not auto-fix). All iOS edits require a green `xcodebuild` before commit.

## iOS DEAD CODE (in-file removals unless noted)

### Recipes (CONSERVATIVE — RecipesViews just rewritten on main)
- `RecipeModels.swift:155` `RecipeAudioURLImportRequest` + `APIClient.importRecipeFromAudioURL` — [DEAD Med] ~10
- `RecipeImportPendingStore.swift:115/198` `savePendingURL`/`consumePendingURL`/`pendingURL` — [DEAD Med] ~20
- `Food Recipe Share Extension/ShareViewController.swift:255` `SharedRecipePayload.with(url:)` — [DEAD Low] ~8
- `RecipesViews.swift:2071` `RecipeLibraryView` only used under `#if DEBUG`/VisualQA — [DEAD Low] wrap in `#if DEBUG` (DON'T delete; active area)

### Home
- `HomeFlowComponents.swift:77-467` dead structs `HM00BottomActionDock`,`HM02ParseAndSaveActionsSection`,`HM03ParseSummarySection`,`HM04ClarificationEscalationSection`,`HM06DaySummarySection` — [DEAD High] **~340** (keep file/other types)
- `StreakRewardModels.swift:65` `StreakBadgeProgress`+`progressToNext`/`earnedBadges`/`lockedBadges` — [DEAD High] ~45
- `HomeStreakDrawerView.swift:351` `heroSubtitle` — [DEAD Med] ~10
- `HomeGreetingAnimations.swift:57` `GreetingSlot.greetingPrefix`+`CaseIterable` (playground-only) — [DEAD Med] ~10
- `HomeFoodStoryDrawerView.swift:2014` `FoodStoryDay.shareText` — [DEAD Med] ~3
- `StreakAchievementPopup.swift:22` `dismissTask` declared/cancelled, never assigned — [DEAD Low] ~4

### Profile / Bento
- `HomeProfileScreen.swift:105` `profileHubSection` — [DEAD High] ~59
- `HomeProfileScreen.swift:224` `summaryHeaderSection` — [DEAD High] ~27
- `HomeProfileScreen.swift:647`+`:838` `mealReminderSection`/`mealReminderSummaryText` — [DEAD High] ~38
- `Profile/HomeProfileBentoScreen.swift:250` `identityRow` — [DEAD High] ~22
- `Profile/HomeProfileBentoScreen.swift:412` `heroData` — [DEAD High] ~20
- `Profile/HomeProfileBentoScreen.swift:514` `trendData` (KEEP `SevenDayTrendTile`) — [DEAD High] ~31
- `Profile/HomeProfileBentoScreen.swift:1761` ~24 unused `BentoTokens` aliases — [DEAD Low] ~55
- `Profile/Editors/ProfileDraftStore.swift:225` `preferenceSymbol` (private, unused) — [DEAD Med] ~16
- `BadgeModels.swift:243` `bootstrappedKey` written-never-read — [DEAD Low] ~3 (verify)
- `Profile/Editors/BodyEditorScreen.swift` only VisualQA-referenced — [DEAD Low DEFER] (Bento paused workstream)

### Onboarding (biggest area)
- `OnboardingComponents.swift:287` 5 unused structs (`OnboardingPrimaryButton`/`SecondaryButton`/`SelectableTiles`/`PermissionBlock`/`InputField`) + 2 ButtonStyles — [DEAD High] **~180**
- `OnboardingAnimatedBackground.swift` orb variant + private support types (only `#Preview`) — [DEAD Med] **~185**
- `OB03AgeScreen.swift:83/129` `agePickerSelection` + `AgeWheelPickerRepresentable` — [DEAD Low] ~100
- `OB02cChallengeInsightScreen.swift:203` `helpCard`+`helpShimmer` — [DEAD Med] ~60
- `AppFlowCoordinator.swift:18` `.planPreview` zombie route (+copy/route arms) — [DEAD High] ~20
- `AppFlowCoordinator.swift:125` `normalizedForActiveFlow` identity fn — [DEAD High] ~15
- `OB03AgeScreen.swift:13` `dragOffset`/`dragStartAge` unused @State — [DEAD Low] ~2

### Camera
- `CameraView.swift:13` `showPhotoLibrary` @State unused — [DEAD Med] ~1
- `Food Camera Widget/FoodCameraWidget.swift:359` `FoodCameraURL` enum unused — [DEAD Med] ~4
- `UIImage+FixedOrientation.swift` `fixedOrientation()` no callers — [DEAD Med] ~12 (whole-file; deleting file needs pbxproj — prefer empty body / DEFER file delete)
- `QuickCameraNotificationActionHandler.swift:23` `reviewAction` no-op handler — [DEAD Low] ~8

## iOS BUGS (wave 2)
- `HomeGreetingAnimations.swift:276` reduce-motion `headTopY = reduceMotion ? 4 : 4` no-op → should be `4 : 13` — [BUG Med a11y]
- `HomeFoodStoryDrawerView.swift:43` `days` recomputed (`makeDays` 2×/render) — [BUG High perf] memoize via @State+onChange (HV — non-trivial)
- DateFormatter rebuilt per call/render: `HomeStreakDrawerView:500` `dateKey`, `HomeFoodStoryDrawerView:2225/2231`, `ExistingAccountDetectedView:53`, `MindfulPauseSheet:92`, `LoggingResultDrawerBody:256` — [BUG Med perf] `static let`
- `HomeRecipesDrawer.swift:75` dead `@FocusState isPasteFocused` (no bound control) — [DEAD/BUG] remove
- `Profile/HomeProfileBentoScreen.swift:682` `CalorieHeroTile` own `heroDraftStore` ≠ bento `draftStore` → silent overwrite — [BUG High] **HV**
- `HomeProfileScreen` `saveStatusIndicator` `.saving`/`.saved` render EmptyView (no save feedback) — [BUG Med UX]
- `HomeProfileScreen.swift:1262` `releaseVersion!` force-unwrap — [BUG Low]
- `CameraService.swift:113/132` @MainActor vars mutated on `sessionQueue` bg thread — [BUG High race] **HV**
- `CameraService.swift:217` `switchCamera()` doesn't restart session → black viewfinder after flip — [BUG High] **HV** (behavioral)
- `CameraView.swift:272` `MagnifyGesture == 1.0` onset unreliable / no `.onEnded` → zoom drift — [BUG Med]
- `QuickCameraLoggingService.swift:9` `beginBackgroundTask` empty expiry handler → stuck "Analyzing" notif — [BUG Med]
- `QuickCameraPendingLogStore` no TTL/cap → unbounded UserDefaults — [BUG Low]
- `OnboardingView+SubmissionFlow.swift:143` `1...maxAttempts` traps if 0 — [BUG Low]
- `OnboardingView+BaselineFlow.swift:20` `draft.ageValue = draft.ageValue` no-op — [BUG Low]
- `OnboardingView.swift:225` `autoAdvancePermissionRouteIfNeeded` fires every route → redundant HealthKit query — [BUG Low]
- `RecipesViews.swift:765` `deleteRecipe` reuses `importErrorMessage`, not cleared on success — [BUG Low]
- `HomeRecipesDrawer.swift:194/209` asyncAfter sheet-sequencing race — [BUG Med] HV

## iOS SIMPLIFY (wave 2)
- `formatOneDecimal` dup (`HomeProgressData:634`, `HomeFlowComponents:387`[dead]) → `HomeLoggingDisplayText.formatOneDecimal` — ~4
- `preferenceSymbol` triplicated (`HomeProfileScreen:855`,`DietEditorScreen:67`,`ProfileDraftStore`[dead]) → add `PreferenceChoice.systemImage` — ~35
- `requirementCopy` dup (`BadgesTrophyCaseView:681` vs `BadgeModels:74`) — ~18
- `TutorialButtonStyle.secondary` dead branch (`HomeFirstRunTutorialView:453`) — ~15
- onboarding top-bar dup → shared `OnboardingTopBar` (`goalTopBar`/`activityTopBar` + 5 screen `topBar`s) — [SIMPLIFY High] ~120-200 (HV — broad)
- onboarding `bodyBlock`/`actionBlock`/helpers vestigial after `.planPreview` removed (`OnboardingView+RouteViews:385`) — [SIMPLIFY High] ~350 (HV — verify unreachable, careful)
- onboarding palette helper dup (`AccountRoutePalette`/`GoalValidationPalette`/`ExistingAccountPalette`) — ~100
- clipboard-detect/comet-stroke dup (`RecipesScreen` vs `HomeRecipesDrawer`) — ~50 (conservative; active area)
- `symbologyName` dup (`CameraService:343` vs `ImageVisionPipeline:207`) — ~14
- `decideLane` thresholds dup (`QuickCameraLoggingService:166` vs `MainLoggingCameraDrawerFlow:267`) — ~13
- `ImageVisionPipeline:138` calorieGuess regex recompiled per call → `static` — ~3
- `heroBackground` degenerate gradient (`HomeStreakDrawerView:340`) → solid fill — ~8
- `dietPreferenceCount`/`profilePreferencesCount` dup (`HomeProfileBentoScreen`) — ~8

---
### Apply order (safest→riskiest)
1. Backend dead/simplify/security (verify tsc+vitest). 2. iOS in-file dead code by area (verify build per batch). 3. iOS safe bug fixes (DateFormatter static, reduce-motion fix, dead-state removal). 4. iOS simplify/dedup. **Document only (no auto-fix): all HV save-path/auth/camera-behavioral/data-overwrite items.**
