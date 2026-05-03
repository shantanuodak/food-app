# Phase 7 Extraction Plan

Date: 2026-05-03
Owner intent: reduce long-term complexity without changing logging behavior.

## Status

Phase 7 is not a feature pass. It is a code-shrink and extraction pass after the logging pipeline has stabilized through Phases 0-6 and the Phase 8-10 efficiency work.

Current LOC audit:

| File | Current LOC | Phase 7 target | Status |
|---|---:|---:|---|
| `Food App/MainLoggingShellView.swift` | 3,146 | <= 1,500 first, <= 800 later | Critical |
| `Food App/HomeFlowComponents.swift` | 467 | <= 800 | Pass |
| `Food App/HomeComposerView.swift` | 1,061 | <= 1,000 first, <= 800 later | Watch |
| `Food App/OnboardingView.swift` | 1,263 | <= 800 | High |
| `Food App/ContentView.swift` | 1,030 | <= 800 | Medium |
| `Food App/HomeProgressScreen.swift` | 996 | <= 800 preferred | Watch |
| `Food App/OnboardingComponents.swift` | 954 | <= 800 preferred | Watch |
| `Food App/MainLoggingDateFlow.swift` | 249 | <= 300 preferred | Pass |
| `Food App/MainLoggingDayCacheFlow.swift` | 469 | <= 500 preferred | Pass |
| `Food App/MainLoggingDrawerFlow.swift` | 380 | <= 500 preferred | Pass |
| `Food App/MainLoggingCameraDrawerFlow.swift` | 264 | <= 300 preferred | Pass |

Hard rule: this phase must not change product behavior. Every PR should be mostly move-only extraction with tiny adapter glue.

## Success Criteria

Phase 7 passes only when all of these are true:

1. `xcodebuild` succeeds.
2. Backend remains untouched unless the specific subtask is backend dead-code cleanup.
3. No behavior regression in the manual logging stability gate.
4. `MainLoggingShellView.swift` is below 1,500 LOC for Phase 7A.
5. No Swift file except `MainLoggingShellView.swift` exceeds 1,000 LOC after Phase 7A.
6. No orphaned assets or dead files remain from the extraction.
7. App can still perform: text log, multi-row autosave, edit quantity in drawer, delete row, image log, previous-day save, force-quit recovery.

Stretch target for Phase 7B:

1. `MainLoggingShellView.swift` <= 800 LOC.
2. All SwiftUI view files <= 800 LOC.
3. Coordinators <= 500 LOC each.
4. Pure helper files <= 300 LOC each.

## Non-Goals

Do not do these in Phase 7:

1. Do not redesign the home screen.
2. Do not change autosave timing.
3. Do not change parse eligibility.
4. Do not change idempotency key logic.
5. Do not change database schema.
6. Do not add new backend APIs.
7. Do not delete flags, guards, or telemetry just because they look redundant.
8. Do not mix UI polish with extraction unless the UI code is being moved unchanged.

## Branch Strategy

Use a dedicated branch:

```bash
git checkout main
git pull
git checkout -b phase-7-extraction
```

Commit one extraction slice at a time. Avoid one giant commit.

Recommended commit sequence:

1. `Extract home logging sheet presentation helpers`
2. `Extract home logging parse state reducers`
3. `Extract home logging save state reducers`
4. `Extract home logging row mutation helpers`
5. `Extract home logging image flow helpers`
6. `Split home flow components`
7. `Split onboarding shell components`
8. `Prune unused assets and dead code`
9. `Document phase 7 validation results`

## Safety Model

Each extraction PR must follow this pattern:

1. Move code into a new file.
2. Keep function names and signatures as stable as possible.
3. Preserve call sites first.
4. Build.
5. Run focused manual test for the moved area.
6. Only then simplify naming or remove duplicate wrappers.

If a moved function currently relies on `@State`, pass bindings or create a small `struct` state bundle. Do not introduce new global state.

## Proposed File Architecture

Target layout after Phase 7A:

```text
Food App/
  MainLoggingShellView.swift                  # Thin screen composition + state ownership only
  MainLoggingShellState.swift                 # Small state structs/enums for home logging
  MainLoggingShellActions.swift               # Action dispatch helpers, no UI
  MainLoggingParseFlow.swift                  # Parse scheduling, staleness, row mapping wrappers
  MainLoggingSaveFlow.swift                   # Autosave/manual save orchestration wrappers
  MainLoggingDateChangeFlow.swift             # Preserve drafts + date switching save behavior
  MainLoggingImageFlow.swift                  # Camera/image parse/save/deferred upload glue
  MainLoggingDrawerFlow.swift                 # Drawer open/close/delete/patch orchestration
  MainLoggingRowMutation.swift                # Row add/delete/edit/focus helpers
  MainLoggingTelemetryFlow.swift              # Parse/save telemetry emitters
  MainLoggingPresentation.swift               # Sheets, alerts, toolbar presentation helpers
  HomeFlowComponents.swift                    # Keep core shared models only
  HomeLogRowModels.swift                      # HomeLogRow, row phase enums, focused row types
  HomeComposerView.swift                      # Composer UI
  HomeLogRowView.swift                        # Single row UI
  HomeStreakDrawerView.swift                  # Streak drawer only
  HomeLoggingKeyboardFocus.swift              # Focus helpers if needed
```

This is intentionally conservative: it does not require rewriting `SaveCoordinator` or `ParseCoordinator`.

## Phase 7A Execution Plan

### Step 0: Baseline Snapshot

Run before any extraction:

```bash
git status --short
find "Food App" -name "*.swift" -type f -maxdepth 2 -print0 | xargs -0 wc -l | sort -nr | head -30
xcodebuild -project "Food App.xcodeproj" -scheme "Food App" -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

Record current app binary size:

```bash
du -sh ~/Library/Developer/Xcode/DerivedData/Food_App-*/Build/Products/Debug-iphonesimulator/Food\ App.app
```

Expected result:

1. Worktree clean except intentionally ignored/untracked local artifacts.
2. Build green before extraction starts.
3. LOC baseline recorded in the PR description.

### Step 1: Extract Presentation-Only Code

First extraction target: lowest behavior risk.

Move from `MainLoggingShellView.swift`:

1. Sheet presentation bodies.
2. Alert builders.
3. Drawer presentation wrappers.
4. Toolbar helpers.
5. Non-mutating computed view fragments.

Target files:

1. `MainLoggingPresentation.swift`
2. `MainLoggingDrawerFlow.swift` only if the code includes drawer actions.

Rules:

1. No save/parse logic in this step.
2. No edits to idempotency, queue, or row save state.
3. View modifiers can move as extensions on `MainLoggingShellView` if they still need private state.

Validation:

1. Build.
2. Open app.
3. Open a row drawer.
4. Close drawer.
5. Delete a row and cancel delete.
6. Delete a row and confirm delete.

Pass condition:

1. Drawer opens/closes without layout regression.
2. Native delete/done buttons still work.
3. No duplicate save created by opening/closing drawer.

### Step 2: Extract Pure Formatting and Mapping Helpers

Move helpers that do not mutate `@State`:

1. Date string formatting wrappers.
2. Row display text helpers not already moved.
3. Nutrition formatting helpers.
4. Drawer thought process helpers.
5. Parse source label helpers.
6. Calorie range formatting.

Target files:

1. `MainLoggingFormatters.swift`
2. `MainLoggingRowMapping.swift`

Rules:

1. Functions should be `nonisolated static` when possible.
2. Prefer structs/enums with static functions over `MainLoggingShellView` extensions.
3. No `@State` references inside these helpers.

Validation:

1. Build.
2. Type `banana`.
3. Confirm calories/text formatting unchanged.
4. Open drawer and confirm item names/macros/thought-process text still render.

Pass condition:

1. Visible UI strings match pre-extraction screenshots.
2. No parse/save behavior changes.

### Step 3: Extract Parse Flow Wrapper

Move parse orchestration carefully.

Candidate functions from `MainLoggingShellView.swift`:

1. Debounce scheduling.
2. In-flight parse snapshot handling.
3. Staleness guard handling.
4. Queue advancement.
5. `ParseCoordinator` cache interactions.
6. Parse telemetry emitters if tightly coupled.

Target file:

1. `MainLoggingParseFlow.swift`

Recommended pattern:

Create a small helper type:

```swift
@MainActor
struct MainLoggingParseFlow {
    var getRows: () -> [HomeLogRow]
    var setRows: ([HomeLogRow]) -> Void
    var apiClient: APIClient
    var parseCoordinator: ParseCoordinator
}
```

But only use this if it reduces complexity. If it creates awkward closure soup, prefer `extension MainLoggingShellView` in a separate file as an intermediate step.

Safer first pass:

1. Move parse-related methods into `MainLoggingParseFlow.swift` as `extension MainLoggingShellView`.
2. Build.
3. Only later convert to a standalone helper.

Validation:

1. Single row: `banana` saves.
2. Rapid edit: type `buckwheat 1 por`, change to `buckwheat 1 portion`, then `buckwheat 2 portion`.
3. Multi-row: `banana`, `black coffee`, `1 chai`.
4. Date-switch edge: type a row, switch day before parse finishes, return.

Pass condition:

1. Edited final row saves final text.
2. Visible calorie rows save.
3. Parse-only rows only appear when no save attempt should have happened.
4. Switching date does not strand saveable rows.

### Step 4: Extract Save Flow Wrapper

Move save orchestration after parse extraction is stable.

Candidate functions:

1. `scheduleAutoSave`
2. `autoSaveIfNeeded`
3. `flushQueuedPendingSavesIfNeeded`
4. `submitSave`
5. `handleSubmitSaveSuccess`
6. `handleSubmitSaveFailure`
7. Pending queue helpers
8. Save telemetry emitters
9. `promoteSavedRow`
10. `promoteInputRow`

Target files:

1. `MainLoggingSaveFlow.swift`
2. `MainLoggingPendingQueueFlow.swift`
3. `MainLoggingTelemetryFlow.swift`

Rules:

1. Keep `SaveCoordinator` as the owner of durable queue semantics.
2. Do not create a second queue abstraction.
3. Do not change `SaveLogRequest` generation in the same commit as moving save submission.
4. Never change idempotency key generation without a separate test-focused commit.

Validation:

1. Single row autosave.
2. Multi-row autosave with 5 rows.
3. Duplicate guard: type same item twice as two separate rows and confirm two saved logs when intended.
4. Retry path: simulate offline, type row, return online, verify save.
5. Dashboard saved logs match app Today list.

Pass condition:

1. No stuck `Syncing` state after healthy saves.
2. No duplicate save for one row.
3. Two intentional duplicate meals still save as two rows.
4. `food_logs` rows match app rows for selected day.

### Step 5: Extract Date Change Flow

This area caused real bugs, so isolate it after save/parse are stable.

Candidate functions:

1. Preserve draft rows by date.
2. Persist date-change drafts.
3. Remove preserved draft.
4. Restore preserved rows.
5. Day cache invalidation around date changes.

Target file:

1. `MainLoggingDateChangeFlow.swift`

Validation:

1. Type row, immediately swipe to yesterday.
2. Type row on yesterday, return today.
3. Type multiple rows, switch date during parse queue.
4. Force quit after switching date during a pending save.

Pass condition:

1. No visible calorie row is lost.
2. Drafts restore on correct day.
3. Saved logs land on the intended day.
4. Dashboard Saved Logs by day matches app selected day.

### Step 6: Extract Image Flow

Candidate functions:

1. Camera open/dismiss.
2. Image parse.
3. Image payload preparation.
4. Deferred image upload retry scheduling.
5. Image context clearing.

Target file:

1. `MainLoggingImageFlow.swift`

Rules:

1. Do not change image compression settings here unless the commit is explicitly Phase 8.
2. Preserve decoupled save behavior: nutrition saves even if image upload fails.
3. Keep deferred upload store behavior unchanged.

Validation:

1. Photo meal parse.
2. Save photo meal.
3. Force quit after save before image upload if possible.
4. Reopen and verify deferred image upload drains.
5. Confirm image preview memory is cleared after image ref exists.

Pass condition:

1. Nutrition row saves even if image upload fails.
2. Image attaches eventually when storage works.
3. No stuck pending photo row.

### Step 7: Split `HomeFlowComponents.swift`

Current file is 2,325 LOC. Split by responsibility.

Proposed split:

1. `HomeLogRowModels.swift`
   - `HomeLogRow`
   - row phase enums
   - row factory helpers only if model-centric
2. `HomeComposerView.swift`
   - composer UI
   - input row list rendering
3. `HomeLogRowView.swift`
   - individual row view
   - row actions UI
4. `HomeStreakDrawerView.swift`
   - streak drawer and streak-specific subviews
5. `HomeLoggingKeyboardFocus.swift`
   - keyboard/focus utilities if needed

Rules:

1. Move models first, views second.
2. Keep public/internal access minimal.
3. Do not change row layout in this pass.

Validation:

1. Home screen displays saved rows.
2. Empty space tap still focuses keyboard.
3. Camera/mic/keyboard/flame dock still appears.
4. Streak drawer opens and refreshes after a save.

Pass condition:

1. No visual regression in home screen layout.
2. Streak value updates after logging.
3. Keyboard focus behavior remains intact.

### Step 8: Split `OnboardingView.swift`

Current file is 1,263 LOC. This should be less risky than logging but still user-facing.

Target files:

1. `OnboardingShellView.swift`
2. `OnboardingNavigationActions.swift`
3. `OnboardingPermissionFlow.swift`
4. `OnboardingProfileSubmission.swift`

Rules:

1. Do not change screen order.
2. Do not change copy in this phase.
3. Do not change onboarding persistence keys.
4. Do not touch paywall/permission policy unless already broken.

Validation:

1. Reset onboarding.
2. Complete onboarding start to finish.
3. Create account/sign in path still works.
4. App lands on home screen.
5. Relaunch app and confirm onboarding is not shown again.

Pass condition:

1. No stuck onboarding route.
2. No missing required profile submission data.
3. Home screen loads after completion.

### Step 9: Split `ContentView.swift`

Current file is 1,030 LOC. Reduce below 800.

Target files:

1. `RootAppShellView.swift`
2. `SettingsView.swift` or `AccountDebugView.swift` if that code lives in `ContentView`
3. `AuthGateView.swift`
4. `HealthSettingsSection.swift`

Validation:

1. Logged-out launch.
2. Logged-in launch.
3. Sign out.
4. Sign back in.
5. Apple Health toggle still works.

Pass condition:

1. Auth state transitions unchanged.
2. Onboarding vs home route unchanged.
3. Settings/debug affordances still accessible.

### Step 10: Asset and Package Audit

Run asset audit:

```bash
find "Food App/Assets.xcassets" -name "*.imageset" -type d | while read dir; do
  name=$(basename "$dir" .imageset)
  hits=$(rg -l "\"$name\"|Image\(\"$name\"\)|UIImage\(named: \"$name\"\)" "Food App" -g '*.swift' | wc -l | tr -d ' ')
  if [ "$hits" -eq 0 ]; then echo "UNUSED: $name"; else echo "USED: $name ($hits)"; fi
done
```

Current audit result on 2026-05-03:

1. `IntroFood1` used.
2. `IntroFood2` used.
3. `ios_light_rd_na` used.
4. `food_photo_demo` used.

Run package audit:

```bash
grep -A2 "XCRemoteSwiftPackageReference" "Food App.xcodeproj/project.pbxproj" | grep "repositoryURL"
rg "^import " "Food App" -g '*.swift' | sort -u
```

Rules:

1. Remove package only if no import and no project reference needs it.
2. Build after each package removal.
3. Do not remove auth/camera/storage packages unless verified unused.

### Step 11: Backend Dead-Code Audit

Do this only after iOS extraction is stable.

Preferred path:

```bash
cd backend
npx ts-prune --error
```

If `ts-prune` is not installed, either:

1. Add it as a dev dependency in a separate commit, or
2. Skip and document as pending.

Rules:

1. Do not remove exported route/service functions used dynamically by Express.
2. Do not remove migrations.
3. Do not remove scripts used by Render or release runbooks.

Validation:

1. `npm run build`
2. `npm test`
3. `npm run test:integration`
4. Render deploy still starts.

## Required Validation After Every PR

Run:

```bash
git diff --check
xcodebuild -project "Food App.xcodeproj" -scheme "Food App" -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

For backend-touching PRs, also run:

```bash
cd backend
npm run build
npm test
npm run test:integration
```

Run LOC check:

```bash
find "Food App" -name "*.swift" -type f -maxdepth 2 -print0 | xargs -0 wc -l | sort -nr | head -30
```

## Required Manual QA Before Merging Phase 7A

Use the app and dashboard together.

### Text Logging

1. Type `banana`.
2. Expected app: calories appear and row remains visible.
3. Expected dashboard: row appears in Saved Logs for Today.

### Multi-Row Queue

1. Type:
   - `banana`
   - `black coffee`
   - `1 chai`
   - `2 eggs and toast`
2. Expected app: all rows get calories and save.
3. Expected dashboard: all rows appear in Saved Logs, not Parse Debug only.

### Rapid Edit

1. Type `buckwheat 1 por`.
2. Change to `buckwheat 1 portion`.
3. Change to `buckwheat 2 portion`.
4. Expected app: final visible row has final calories.
5. Expected dashboard: final saved row matches final displayed text. Intermediate parse-only rows are acceptable only if they were not displayed as final saved rows.

### Previous Day Edge

1. Type `greek yogurt`.
2. Switch to yesterday before parse/save finishes.
3. Return to today.
4. Expected app: visible row is not lost.
5. Expected dashboard: saved day matches the row's intended day.

### Drawer Edit

1. Open row drawer.
2. Use serving stepper.
3. Close drawer.
4. Expected app: calories update.
5. Expected dashboard: existing saved row updates, no duplicate row.

### Delete

1. Delete a saved row.
2. Expected app: row disappears and totals update.
3. Expected dashboard: row removed from Saved Logs or no longer counted for that day.

### Image Logging

1. Log a photo meal.
2. Expected app: nutrition saves even if image attach is delayed.
3. Expected dashboard: saved nutrition row exists.
4. Expected storage behavior: image attaches eventually when upload succeeds.

### Force Quit Recovery

1. Type and save one row.
2. Force quit immediately after calories appear.
3. Reopen app.
4. Expected app: row is either saved or recovers and saves.
5. Expected dashboard: no duplicate row from recovery.

### Streak/Progress

1. Save a row for today.
2. Open streak/progress UI.
3. Expected app: streak/progress reflect saved logs only.
4. Expected dashboard: Parse Debug rows do not count as saved streak activity.

## Merge Gate

Do not merge Phase 7A unless:

1. Build passes.
2. Manual QA above passes.
3. LOC targets for the PR slice improve or stay flat.
4. No new parse-only/save mismatch appears in dashboard.
5. No untracked generated/debug folders are committed accidentally.
6. PR description includes before/after LOC for touched files.

## Rollback Plan

If any extraction breaks logging:

1. Revert only the last extraction commit.
2. Do not patch forward inside a broken extraction unless the fix is obvious and tiny.
3. Re-run build and the affected manual QA slice.
4. Keep the branch alive; do not reset `main`.

If a bug appears after merge:

1. Revert the specific extraction PR.
2. Keep later unrelated commits if they are clean.
3. Open a follow-up with root cause and missing test case.

## Recommended First PR

Start with the lowest-risk move:

Title: `Phase 7A: Extract logging presentation helpers`

Scope:

1. Move sheet/alert/presentation-only helpers from `MainLoggingShellView.swift`.
2. Do not touch parse/save/date/image logic.
3. Build and manually verify drawer open/close/delete.

Expected result:

1. `MainLoggingShellView.swift` decreases by a few hundred lines.
2. No behavior change.
3. Confidence increases before touching parse/save code.

## Current Blockers

1. `MainLoggingShellView.swift` is still too large for safe one-shot extraction.
2. There is no XCTest target for iOS behavior, so manual QA is mandatory.
3. Some state is still owned directly by `MainLoggingShellView`; extraction should begin as file-split extensions before converting to standalone helper objects.
4. `dump/` is currently untracked locally and must stay out of Phase 7 commits unless explicitly reviewed.

## Odds And Ends Checklist

This is the final cleanup gate before calling Phase 7 done. It exists because the extraction itself can pass a build while still leaving the project harder to work with.

### Repository Hygiene

1. Run `git status --short`.
2. Confirm only intentional files are staged.
3. Confirm `dump/` is not staged.
4. Confirm no screenshots, simulator recordings, temporary logs, generated HTML mockups, or local debug scripts are staged.
5. Confirm no `.DS_Store` changes are staged.
6. Confirm no Xcode user-state files are staged unless deliberately needed.
7. Run `git diff --check` before every commit.

Expected result:

1. The Phase 7 PR contains source/docs changes only.
2. The diff is reviewable by responsibility slice.
3. There are no accidental local artifacts.

### Project File Hygiene

1. If new Swift files are added, confirm they are part of the app target.
2. Build once after each new file group is added.
3. Open Xcode project navigator and verify files appear in sensible groups.
4. Confirm deleted/moved files do not leave broken project references.
5. Confirm no duplicate Swift type names were created during extraction.

Expected result:

1. Clean Xcode build.
2. No red missing-file references in Xcode.
3. No duplicate symbol errors.

### Behavior Parity

1. The app should still show exactly the same home screen behavior after extraction.
2. Visible rows with calorie values should still save.
3. Parse-only dashboard rows should remain diagnostic attempts, not app-visible saved logs.
4. Saved Logs dashboard tab should still match the app's selected day.
5. Drawer serving steppers should still update calories and avoid duplicate logs.
6. Streak/progress UI should still count saved logs only.
7. Date switching should not strand a row that has a valid parse result.

Expected result:

1. The user cannot tell Phase 7 happened from the product UI.
2. The developer can tell Phase 7 happened from smaller files and cleaner ownership.

### Documentation Hygiene

1. Update this file with final before/after LOC.
2. Update `docs/LOGGING_REFACTOR_EXECUTION_PLAN.md` with Phase 7 completion notes.
3. If a flow ownership boundary changes, update any nearby comments/runbooks that describe the old location.
4. If anything is intentionally deferred, add it under a clear `Pending` heading rather than leaving it implied.

Expected result:

1. A senior developer can open the docs and immediately understand what moved.
2. The next thread does not need to rediscover Phase 7 decisions.

### Release Evidence

Every Phase 7 PR description should include:

1. Files moved or split.
2. Before/after LOC for major files.
3. Build command and result.
4. Manual QA scenarios run.
5. Known risks.
6. Rollback commit/PR strategy.

Suggested PR evidence block:

```text
Validation:
- git diff --check: pass
- iOS Debug simulator build: pass
- Manual QA: text log, rapid edit, drawer stepper, date switch, delete

LOC:
- MainLoggingShellView.swift: 5,580 -> X
- HomeFlowComponents.swift: 2,325 -> X

Risk:
- Move-only extraction; no intended behavior change.
```

## Definition of Done

Phase 7A is done when:

1. `MainLoggingShellView.swift` <= 1,500 LOC.
2. `HomeFlowComponents.swift` <= 1,000 LOC.
3. `OnboardingView.swift` <= 1,000 LOC, preferably <= 800.
4. `ContentView.swift` <= 1,000 LOC, preferably <= 800.
5. All validation commands pass.
6. Manual QA passes.
7. Execution plan is updated with final LOC and validation notes.

Phase 7B is done when:

1. `MainLoggingShellView.swift` <= 800 LOC.
2. All SwiftUI view files <= 800 LOC.
3. Coordinators <= 500 LOC.
4. Pure helpers <= 300 LOC.
5. Dead asset/package audit is clean.
