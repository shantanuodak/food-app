# Claude Handoff Prompt: Phase 7A Remaining Extraction + Next Work

Use this as the complete working prompt for the next coding agent. The goal is to continue the logging refactor safely from the current repo state without needing the prior Codex thread.

## Role

You are a senior iOS/SwiftUI engineer working in the Food App repo. Your job is to continue Phase 7A extraction and then report what remains. Prioritize correctness and behavior parity over speed. This is a stabilized logging pipeline, so do not casually change parse/save semantics while extracting files.

## Current Repo Context

Workspace/repo root:

```bash
/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App
```

Current branch at handoff time:

```text
main
```

Recent relevant commits:

```text
0c137a4 Update phase 7 parse extraction notes
6c16ef2 Extract logging parse flow
5eaa773 Update phase 7 drawer extraction notes
1dbbc7e Extract logging camera drawer flow
df0d177 Extract logging drawer flow
826901e Extract logging image payload flow
13fe984 Lower deployment target to iOS 18 with glass effect fallback
2233cd0 Extract logging input source flow
6fe907a Extract logging telemetry flow
82e4820 Extract logging pending save flow
bce92ac Update phase 7 flow extraction notes
718d116 Extract logging day cache flow
```

Current known local dirty state before you start:

```text
 M Food App.xcodeproj/project.pbxproj
?? dump/
```

Important: the `Food App.xcodeproj/project.pbxproj` change is believed to be an unrelated Xcode/Claude build number bump. Do not modify, revert, or commit it unless the user explicitly asks. The `dump/` folder is untracked local/debug material. Do not commit it.

## Current Phase Status

Phase 7A is in progress. It is an extraction/code-shrink phase, not a behavior-change phase.

Completed Phase 7A slices:

1. Extracted presentation views.
2. Extracted home status strip.
3. Removed unused logging detail panels.
4. Split row models.
5. Split home composer.
6. Split streak drawer.
7. Moved `RollingNumberText` into shared file.
8. Extracted shell-only enums.
9. Prepared logging shell for flow extensions.
10. Extracted date navigation/preserved-draft flow.
11. Extracted day cache/loading/reconciliation flow.
12. Extracted pending-save context helpers.
13. Extracted telemetry helpers.
14. Extracted input-source actions.
15. Extracted image payload helpers.
16. Extracted drawer/row-detail helpers.
17. Extracted camera drawer flow.
18. Extracted text parse scheduling/row mapping flow.

Current LOC snapshot:

```text
2310 Food App/MainLoggingShellView.swift
 467 Food App/HomeFlowComponents.swift
1263 Food App/OnboardingView.swift
1030 Food App/ContentView.swift
 996 Food App/HomeProgressScreen.swift
 954 Food App/OnboardingComponents.swift
 840 Food App/MainLoggingParseFlow.swift
 469 Food App/MainLoggingDayCacheFlow.swift
 380 Food App/MainLoggingDrawerFlow.swift
 264 Food App/MainLoggingCameraDrawerFlow.swift
 249 Food App/MainLoggingDateFlow.swift
```

Phase 7A target:

1. `MainLoggingShellView.swift` below 1,500 LOC first.
2. `OnboardingView.swift` below 1,000 LOC, preferably below 800.
3. `ContentView.swift` below 1,000 LOC, preferably below 800.
4. No new Swift file above 1,000 LOC.
5. Preserve user-visible behavior.

Phase 7B target after Phase 7A:

1. `MainLoggingShellView.swift` below 800 LOC.
2. All SwiftUI view files below 800 LOC.
3. Coordinators below 500 LOC.
4. Pure helper files below 300 LOC where reasonable.

## Non-Negotiable Rules

1. Phase 7A must be move-only unless a tiny adapter is required for compilation.
2. Do not change autosave timing.
3. Do not change parse eligibility.
4. Do not change idempotency key generation.
5. Do not change database schema.
6. Do not add backend APIs.
7. Do not mix UI polish with extraction.
8. Do not touch the project file build-number bump unless required to add new Swift files to the target; if you must touch it, isolate and explain the exact reason.
9. Do not commit `dump/`.
10. Do not revert user/other-agent changes.
11. Commit one extraction slice at a time.
12. Build after each meaningful extraction slice.

## Validation Commands

Run these after each extraction slice:

```bash
git diff --check
xcodebuild -project "Food App.xcodeproj" -scheme "Food App" -configuration Debug -destination 'generic/platform=iOS Simulator' build
find "Food App" -maxdepth 2 -name "*.swift" -type f -print0 | xargs -0 wc -l | sort -nr | head -30
```

If backend is touched, also run:

```bash
cd backend
npm run build
npm test
npm run test:integration
```

Prefer not to touch backend during Phase 7A unless explicitly doing the later backend dead-code audit.

## Required Manual QA After Risky Slices

Use app + testing dashboard together.

1. Text log: type `banana`; calories appear; Saved Logs dashboard for Today contains `banana`.
2. Multi-row queue: type `banana`, `black coffee`, `1 chai`, `2 eggs and toast`; all visible calorie rows save.
3. Rapid edit: type `buckwheat 1 por`, change to `buckwheat 1 portion`, then `buckwheat 2 portion`; final visible row should save final displayed text. Intermediate parse debug rows are acceptable only if they were diagnostic attempts, not app-visible saved rows.
4. Previous-day edge: type `greek yogurt`, switch to yesterday before parse/save finishes, return today; row should not be lost and saved day should be correct.
5. Drawer edit: open row drawer, use serving stepper, close drawer; calories update and existing saved row updates without creating an unintended duplicate.
6. Delete: delete saved row; row disappears and totals update; dashboard saved log should be removed/not counted.
7. Image log: photo meal saves nutrition even if image attachment is delayed.
8. Force quit recovery: type/save one row, force quit immediately after calories appear, reopen; row should be saved or recover and save, with no duplicate.
9. Streak/progress: streak/progress count saved logs only, not parse-debug rows.
10. Dashboard Saved Logs tab for selected day should match app selected day.

## Known Product/Behavior Context

The user has been fighting a major parse/save/display ambiguity. Keep this mental model:

1. Parse Debug rows are diagnostic attempts.
2. Saved Logs are the source of truth.
3. If the app displays a row with calories as final/visible, the user expects it to save.
4. If a user edits an active draft before the save window finishes, the final visible edited row should be what saves.
5. If a user intentionally creates two separate rows with similar text, both should save.
6. If a user changes serving size in the drawer, that should patch/update the existing saved row, not create a duplicate.
7. Intermediate parse attempts may appear in Parse Debug, but they should not be confused with saved rows.
8. The bottom sync pill was intentionally de-emphasized; do not reintroduce noisy sync UX during extraction.

Known bug still under discussion and likely not solved by pure extraction:

1. Edit-to-new-entry behavior: user types an item, calories show, then edits it; sometimes this creates another entry and backend saves both. This is a save/edit semantics issue, not Phase 7A extraction unless you are explicitly asked to fix behavior.
2. Flicker after app relaunch: app can briefly show/hide/re-show a row while day cache/server reconciliation completes. This may need targeted state reconciliation later, but do not change it during move-only extraction unless instructed.
3. `Syncing 1/2/3 items` loader can feel random/noisy in multi-row entry. This is product/UX behavior and should not be changed during extraction.

## Remaining Phase 7A Work: Recommended Order

### Part 1: Save Flow Extraction

This is the next major target. Extract from `MainLoggingShellView.swift` into new file(s), starting as `extension MainLoggingShellView`.

Target new file:

```text
Food App/MainLoggingSaveFlow.swift
```

Potential secondary file only if needed:

```text
Food App/MainLoggingPatchFlow.swift
```

Candidate functions currently remaining in `MainLoggingShellView.swift`:

```text
startSaveFlow
handleQuantityFastPathUpdate
schedulePatchUpdate
performPatchUpdate
submitRowPatch
scheduleAutoSaveTask
cancelAutoSaveTask
retryLastSave
scheduleAutoSave
rescheduleAutoSaveAfterActiveSave
autoSaveIfNeeded
flushQueuedPendingSavesIfNeeded
flushPendingAutoSaveIfEligible
isAutoSaveEligibleEntry
buildRowSaveRequest
buildDateChangeDraftSaveRequest
fallbackSaveItem
autoSaveContentFingerprint
normalizedInputKind
requestWithImageRef
prepareSaveRequestForNetwork
submitSave
handleSubmitSaveSuccess
handleSubmitSaveFailure
shouldDiscardCompletedSave
deleteLateArrivingSave
promoteSavedRow
promoteInputRow
syncSavedLogToAppleHealthIfEnabled
deleteSavedLogFromAppleHealthIfEnabled
```

Move strategy:

1. Move save/autosave orchestration first into `MainLoggingSaveFlow.swift`.
2. Keep function names/signatures unchanged.
3. Keep `SaveCoordinator` as the durable queue owner.
4. Do not create a second queue abstraction.
5. Do not modify `SaveLogRequest` shape or idempotency generation.
6. Do not change autosave delay or debounce timing.
7. Build.
8. Commit as `Extract logging save flow`.

Expected result:

1. `MainLoggingShellView.swift` should drop significantly, likely below or near the 1,500 LOC Phase 7A target.
2. Behavior should be unchanged.

Validation for this slice:

1. Single row autosave.
2. Multi-row autosave with 5 rows.
3. Intentional duplicate meals as separate rows save separately.
4. Drawer serving update patches, no duplicate.
5. Dashboard Saved Logs match app Today.

### Part 2: Row Mutation / Delete / Focus Extraction

After save flow is stable, extract row mutation helpers if shell is still above target.

Target file:

```text
Food App/MainLoggingRowMutationFlow.swift
```

Candidate functions:

```text
pendingSyncKey
focusComposerInputFromBackgroundTap
refreshNutritionStateForVisibleDay
refreshNutritionStateAfterProgressChange
handleServerBackedRowCleared
serverBackedDeleteContext
clearTransientWorkForDeletedRow
deleteServerBackedRow
restoreDeletedRow
removeDeletedLogFromVisibleDayLogs
refreshDayAfterMutation
hydrateVisibleDayLogsFromDiskIfNeeded
bootstrapAuthenticatedHomeIfNeeded
```

Rules:

1. Keep UI behavior unchanged.
2. Empty-space tap should still focus the last row and open the keyboard.
3. Deleting saved rows should still clear transient parse/save state.
4. Build and commit separately as `Extract logging row mutation flow`.

### Part 3: Escalation Flow Extraction

If still needed, extract advanced AI/escalation helpers.

Target file:

```text
Food App/MainLoggingEscalationFlow.swift
```

Candidate functions:

```text
canEscalate
escalationDisabledReason
startEscalationFlow
escalateCurrentParse
buildSaveDraftRequest
```

Rules:

1. Do not change advanced AI availability logic.
2. Do not change paywall/plan gating.
3. Build and commit separately.

### Part 4: Onboarding Split — DEFERRED TO PHASE 7B

Status: deferred from Phase 7A on 2026-05-03 (decision recorded after
save/row-mutation/escalation extractions landed).

Reason for deferral: `OnboardingView.swift` declares ~20 `private func`s
and ~32 `private var`s. Swift `private` is file-restricted, so an
`extension OnboardingView` in a separate file cannot reach them. A
clean split therefore requires either (a) an explicit pre-step that
relaxes those modifiers from `private` to `internal`, or (b) moving
related state and functions together as tightly-coupled units. Neither
option fits Phase 7A rule #1 ("move-only unless a tiny adapter is
required for compilation") — twenty access-control flips per file is
not a tiny adapter, and re-grouping state is a structural change.

Phase 7B explicitly accepts more invasive cleanup ("All SwiftUI view
files below 800 LOC", "Reduce the logging shell to state ownership
plus screen composition"). Onboarding belongs there.

If picked up in Phase 7B, the suggested target files remain:

```text
Food App/OnboardingShellView.swift
Food App/OnboardingNavigationActions.swift
Food App/OnboardingPermissionFlow.swift
Food App/OnboardingProfileSubmission.swift
```

And the original constraints still apply:

1. Do not change onboarding screen order.
2. Do not change copy.
3. Do not change persistence keys.
4. Do not change permission/paywall policy.
5. Reset onboarding and manually run through the full flow.

Validation when this is eventually done:

1. Reset onboarding.
2. Complete onboarding start to finish.
3. App lands on home screen.
4. Relaunch app and confirm onboarding does not show again.

### Part 5: ContentView Split

Current `ContentView.swift` is 1,030 LOC. Phase 7A target is below 1,000, preferably below 800.

Suggested target files:

```text
Food App/RootAppShellView.swift
Food App/AuthGateView.swift
Food App/SettingsView.swift
Food App/HealthSettingsSection.swift
```

Rules:

1. Do not change auth state transitions.
2. Do not change onboarding vs home routing.
3. Do not remove settings/debug affordances.
4. Do not alter Apple Health behavior.

Validation:

1. Logged-out launch.
2. Logged-in launch.
3. Sign out.
4. Sign back in.
5. Apple Health toggles still work.

### Part 6: Asset and Package Audit

Only do after source extraction is stable.

Asset audit command:

```bash
find "Food App/Assets.xcassets" -name "*.imageset" -type d | while read dir; do
  name=$(basename "$dir" .imageset)
  hits=$(rg -l "\"$name\"|Image\(\"$name\"\)|UIImage\(named: \"$name\"\)" "Food App" -g '*.swift' | wc -l | tr -d ' ')
  if [ "$hits" -eq 0 ]; then echo "UNUSED: $name"; else echo "USED: $name ($hits)"; fi
done
```

Current known used assets as of 2026-05-03:

```text
IntroFood1
IntroFood2
ios_light_rd_na
food_photo_demo
```

Package audit commands:

```bash
grep -A2 "XCRemoteSwiftPackageReference" "Food App.xcodeproj/project.pbxproj" | grep "repositoryURL"
rg "^import " "Food App" -g '*.swift' | sort -u
```

Rules:

1. Remove a package only if no import/reference needs it.
2. Build after each package removal.
3. Do not remove auth/camera/storage packages unless verified unused.

### Part 7: Backend Dead-Code Audit

Only do this after iOS extraction is stable.

Command:

```bash
cd backend
npx ts-prune --error
```

If `ts-prune` is not installed:

1. Either add it as a dev dependency in a separate commit, or
2. Skip and document as pending.

Rules:

1. Do not remove Express route handlers used dynamically.
2. Do not remove migrations.
3. Do not remove scripts used by Render/release runbooks.

Validation if backend touched:

```bash
cd backend
npm run build
npm test
npm run test:integration
```

## Phase 8-10 Remaining / Follow-On Work

The docs currently mark Phases 8-10 as partially complete. Do not mix these into Phase 7A extraction commits unless the user asks, but report them as pending/follow-on.

## Overall Pending Refactor Work

This is the high-level backlog across all remaining phases. Use this as the north star when deciding what to do after each slice.

### Phase 7A: Extraction

Status: pending/in progress.

Remaining work:

1. Extract save flow from `MainLoggingShellView.swift`.
2. Extract row mutation/delete/focus helpers.
3. Extract escalation/advanced AI helpers if needed.
4. Split `OnboardingView.swift`.
5. Split `ContentView.swift`.
6. Run asset/package audit.
7. Optionally run backend dead-code audit after iOS extraction is stable.

Acceptance:

1. `MainLoggingShellView.swift` <= 1,500 LOC.
2. `OnboardingView.swift` <= 1,000 LOC, preferably <= 800.
3. `ContentView.swift` <= 1,000 LOC, preferably <= 800.
4. No new Swift file exceeds 1,000 LOC.
5. Product behavior remains unchanged.

Immediate next step:

1. Finish save-flow extraction first. This is the largest remaining complexity inside `MainLoggingShellView.swift` and should make the rest easier.

### Phase 7B: Deeper Cleanup

Status: pending after Phase 7A.

Remaining work:

1. Bring all major SwiftUI files under 800 LOC.
2. Bring `MainLoggingShellView.swift` under 800 LOC.
3. Keep coordinators under 500 LOC.
4. Keep pure helper files around/under 300 LOC where reasonable.
5. Reduce the logging shell to state ownership plus screen composition.

Acceptance:

1. All SwiftUI view files are small enough for safe review.
2. Flow ownership is obvious from filenames.
3. No behavior changes are introduced during cleanup.

### Phase 8: Network + Image Efficiency

Status: partially complete.

Already done:

1. Image compression path exists.
2. Parse cache exists.
3. Render warmup ping exists.

Pending:

1. Confirm real uploaded image bytes are <600KB.
2. Confirm parse cache prevents duplicate backend parse requests when cache should hit.
3. Audit Gemini route share/cost.
4. Add deterministic parser improvements only if Gemini usage is high and no accuracy regression is expected.

Acceptance:

1. Uploaded meal photos are consistently below the target size.
2. Repeated parse inputs do not create unnecessary backend parse rows.
3. Gemini usage drops only through safe parser improvements.

### Phase 9: iOS Render + Memory

Status: partially complete.

Already done:

1. Saved image rows release preview bytes after upload.
2. Deferred upload drain avoids expensive constrained batches.

Pending:

1. Run Xcode Memory Graph with 10 image meals.
2. Run SwiftUI Instruments during a 30s typing session.
3. Verify deferred upload drain cost is low when queue is empty.
4. Investigate app relaunch flicker if still present.

Acceptance:

1. Logging 10 image meals stays under pre-refactor baseline + 10MB.
2. Typing does not trigger excessive SwiftUI rerenders.
3. Empty deferred-upload drain is cheap.
4. Relaunch reconciliation does not visibly flicker or lose rows.

### Phase 10: Backend Performance

Status: partially complete.

Already done:

1. DB pool max is configurable.
2. Hot save-path queries use prepared statements.

Pending:

1. Run query plan audit for hot save queries.
2. Confirm no sequential scans on large tables.
3. Measure `POST /v1/logs` latency.
4. Confirm Render deploy/start remains clean.

Acceptance:

1. `POST /v1/logs` target latency: P50 <200ms, P99 <800ms.
2. No problematic sequential scans in hot paths.
3. Render deploy and startup remain reliable.

### Functional Follow-Up Outside Move-Only Extraction

Status: pending unless explicitly prioritized.

Known issue:

1. Edit-after-calories bug: editing a visible parsed row can create/save multiple entries.

Desired behavior:

1. Save only the latest stabilized version of the same active draft.
2. Still save intentional separate rows, even if text is similar.
3. Drawer serving-stepper changes should patch the existing saved row.
4. Saved Logs should match the app selected day.
5. Parse Debug should remain diagnostic, not the source of truth.

Important constraint:

1. Do not solve this by reintroducing confidence/clarification save blockers. Prior product decision: if a calorie value is shown in the app, save should be attempted unless that same draft is superseded by a newer edit.

### Phase 8: Network + Image Efficiency

Already completed/partially completed:

1. Image parse payload prep targets <= 600KB with progressive dimension/quality attempts.
2. `ParseCoordinator` has 50-entry, 30-minute same-row cache keyed by row ID/logged timestamp.
3. App launch fires background HEAD `/health` warmup.

Potential follow-on:

1. Verify uploaded image bytes are actually < 600KB in real photo tests.
2. Verify cache effectiveness: repeated parse of same raw text should not create extra server parse request when cache should hit.
3. Audit Gemini route share in backend parse requests. If Gemini route share is >70%, consider deterministic parser improvements in a separate behavior-focused task.

### Phase 9: iOS Render + Memory

Already completed/partially completed:

1. Saved image rows release preview bytes after `imageRef` exists.
2. Deferred upload drain skips expensive/constrained batches larger than 3 entries.

Potential follow-on:

1. Use Xcode Memory Graph after logging 10 image meals; memory should stay under pre-refactor baseline + 10MB.
2. Use SwiftUI Instruments for 30s typing session; investigate excessive body recomputation.
3. Add/verify signposts around deferred image upload drain; empty queue should cost <50ms.
4. Investigate flicker on force-quit/reopen if it remains after extraction. This is likely day-cache/server reconciliation ordering.

### Phase 10: Backend Performance

Already completed/partially completed:

1. `DATABASE_POOL_MAX` is configurable with default 10.
2. Hot save-path queries use named prepared statements.

Potential follow-on:

1. Run query plan audit on hot `logService.ts` queries.
2. Confirm no sequential scans on large tables.
3. Measure `POST /v1/logs` latency; target P50 <200ms, P99 <800ms.
4. Confirm Render deploy starts cleanly after backend changes.

## Commit Hygiene

Use small commits. Suggested next commit sequence:

```text
Extract logging save flow
Extract logging row mutation flow
Extract logging escalation flow
Split onboarding shell flow
Split root content/auth flow
Update phase 7 remaining extraction notes
```

Before each commit:

```bash
git status --short
git diff --check
```

Stage only intended files. Avoid staging:

```text
Food App.xcodeproj/project.pbxproj   # unless new file target membership requires it; explain if staged
dump/
.DS_Store
screenshots
simulator recordings
temporary logs
```

If adding new Swift files requires `project.pbxproj` changes, separate those target-membership changes from unrelated build-number noise as much as possible. If the project file already has unrelated build-number edits, do not revert them without user approval.

## Expected Final Report Back To User

After each slice, report:

1. Current phase.
2. What was extracted.
3. Files changed.
4. Before/after LOC for major files.
5. Build result.
6. Manual QA run or explicitly not run.
7. Remaining risks.
8. Uncommitted/unpushed changes.

Example concise report:

```text
Current phase: Phase 7A.
Completed: save-flow extraction.
Files: MainLoggingShellView.swift, MainLoggingSaveFlow.swift.
LOC: MainLoggingShellView.swift 2,310 -> 1,420.
Validation: git diff --check passed; iOS Debug simulator build passed.
Manual QA: not run yet / ran text log + rapid edit + drawer stepper.
Untouched local changes: project.pbxproj build number, dump/.
Next: row mutation extraction or onboarding split.
```

## If You Decide To Fix The Edit/Duplicate Bug Later

Do not do this as part of move-only Phase 7A unless the user explicitly prioritizes it. If asked, treat it as a separate functional patch.

Likely desired behavior:

1. Active draft row has a stabilization/save window.
2. If user edits before stabilization completes, older parse results should not save as final rows.
3. Save should bind to the row identity that produced the visible final calorie display.
4. If user creates a new row intentionally, that new row should save separately even if text is similar.
5. Drawer serving-stepper changes should patch existing saved row by `serverLogId`, not create a new save.
6. Parse attempts may still exist diagnostically, but Saved Logs must match app-visible saved rows.

Do not solve this by blocking saves on confidence or clarification. Prior product decision: if calorie value is shown in the app, save should be attempted unconditionally unless the row is superseded by a newer edit of the same draft.
