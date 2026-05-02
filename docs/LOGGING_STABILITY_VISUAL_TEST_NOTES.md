# Logging Stability Visual Test Notes

Date started: 2026-05-02
Context: Simulator visual testing with Computer Use against the iOS app home logging screen.

## Logging Rule

Record every observation, including transient issues that later recover. A recovered state can still be a UX issue if it looks broken, confusing, or unreliable while the user is watching.

## Observations So Far

### VT-001 - Multi-row queue UI appeared correctly
- Inputs attempted together:
  - `chicken shawarma wrap`
  - `sparkling water lime 12 oz`
  - `paneer tikka 6 pieces`
- Actual typed/resulting text observed:
  - First row appeared as `ken shawarma wrap`.
  - Second row appeared as `sparkling water lime 12 op`.
- App response:
  - First row showed `Looking up food`.
  - Second row showed `Queued`.
  - App displayed helper text: `Finishing current parse. New rows are queued.`
- Expected behavior:
  - New rows should queue while current parse completes.
- Status:
  - Queue UI behavior observed working.
- Notes:
  - Simulator/keyboard input fidelity changed the intended text. This may be a Computer Use/simulator typing artifact, but it should be kept in mind when interpreting test results.

### VT-002 - First queued batch row completed
- Row: `ken shawarma wrap`
- App result:
  - Completed with `680 cal`.
- Drawer result:
  - Drawer opened for the correct row.
  - Drawer showed item details, calories, macros, match confidence, and explanation.
- Expected behavior:
  - Completed row should open the correct drawer.
- Status:
  - Pass for drawer opening and row matching.

### VT-003 - Drawer did not visibly show logged time
- Row: `ken shawarma wrap`
- App result:
  - Drawer showed food name, calories, macros, match confidence, and explanation.
  - Logged time was not visible in the half-sheet view.
  - A scroll attempt did not reveal logged time.
- Expected behavior from checklist:
  - Drawer should show meal logged time.
- Status:
  - Failure / product gap unless logged time is intentionally omitted or hidden elsewhere.
- Notes:
  - This should remain on the issue list even if save behavior is otherwise correct.

### VT-004 - Queued row temporarily looked missing, then recovered
- Row: `sparkling water lime 12 op`
- Initial app response:
  - It was visible as `Queued` while `ken shawarma wrap` parsed.
  - After the first row completed, the queued row was not immediately visible in the first post-wait state, and the draft area showed a different ghost/draft text.
- Later app response:
  - The row eventually appeared as a completed row with `0 cal`.
- Expected behavior:
  - Queued row should eventually parse and save if visible/completed.
- Status:
  - Recovered, but transient UX issue noted.
- Notes:
  - This is exactly the kind of “it fixed itself later” behavior we should log. It may still feel like flicker or row loss to a user.

### VT-005 - Zero-calorie queued row completed
- Row: `sparkling water lime 12 op`
- App result:
  - Completed with `0 cal`.
- Expected behavior:
  - Zero-calorie visible rows should still be valid completed rows and should save.
- Status:
  - App-side visible completion passed.
- Follow-up needed:
  - Verify Dashboard Saved Logs contains this row, not only Parse Debug.

## Open Follow-ups

- Verify dashboard persistence for `ken shawarma wrap`.
- Verify dashboard persistence for `sparkling water lime 12 op`.
- Retest multi-row queue with cleaner input method if possible, because typed text was altered.
- Confirm whether drawer should include logged time in this build; if yes, file/fix H2.
- Continue with single-row cache-miss item after re-querying simulator state.

## Issue Severity Notes

- Missing logged time in drawer: UX/product requirement failure, not necessarily save-data failure.
- Transient queued-row disappearance/recovery: UX trust issue; may be acceptable technically but should be reduced if feasible.
- Input mutation (`oz` -> `op`, `chicken` -> `ken`): likely testing-tool/simulator typing artifact unless reproducible manually.
