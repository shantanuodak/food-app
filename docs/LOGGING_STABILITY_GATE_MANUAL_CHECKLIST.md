# Logging Stability Gate - Manual Overnight Checklist

Date: 2026-05-01
Purpose: run this before Phase 4 cleanup. Phase 4 removes legacy parse/save branches, so this checklist is the safety gate.

## Core Rule

If a row is visibly completed in the app with calories shown, it must be saved exactly once to the correct selected day.

## How To Use This Checklist

1. Open the app on phone/TestFlight or simulator.
2. Open the testing dashboard on your phone/browser if possible.
3. For each test, type the exact input, wait until calories appear, then check the dashboard.
4. Use the issue log template at the end if anything fails.
5. Do not worry if Parse Debug has extra intermediate attempts. The key question is whether final visible rows appear in Saved Logs.

## Dashboard Checks For Every Saved Row

For each completed visible row in the app, verify:

- [ ] It appears in Saved Logs for the same selected day.
- [ ] Input text matches the visible row text closely enough.
- [ ] Calories match or are reasonably equivalent.
- [ ] It does not remain only as Parse Debug / Parse only.
- [ ] It is not duplicated unless you intentionally entered it twice.
- [ ] Sync pill disappears after save/reconciliation.

## Copy-Paste Input Bank

Use these as raw test inputs. The first small block intentionally repeats likely cached/common items; the rest are mostly new cache-miss style foods.

Cache regression set - intentionally repeats likely cached/common items:

```text
banana
diet coke
black coffee
1 chai
chipotle chicken bowl
```

Mostly new cache-miss style items:

```text
sparkling water lime 12 oz
unsweetened iced tea 16 oz
protein waffle with peanut butter
half avocado toast with egg
blueberry bagel with cream cheese
cottage cheese 150 grams with pineapple
lentil soup 12 oz
tomato basil soup 10 oz
turkey lettuce wrap
salmon rice bowl with cucumber
shrimp tacos 2 small
chicken shawarma wrap
paneer tikka 6 pieces
rajma chawal 1 bowl
poha 1 plate
upma 1 bowl
idli 3 pieces with sambar
masala dosa half
vada pav 1
pav bhaji 1 plate
khichdi 1 bowl with ghee
palak paneer 1 cup with 2 roti
chicken biryani 1 cup
veg hakka noodles 1 bowl
miso soup with tofu
sushi california roll 8 pieces
thai green curry with rice
beef burrito bowl no sour cream
caesar wrap with grilled chicken
greek salad with feta
hummus pita plate
trail mix 30 grams
granola bar chocolate chip
oreos 3 cookies
vanilla latte oat milk 12 oz
mango smoothie 16 oz
orange juice 8 oz
coke zero can
white wine 5 oz
beer ipa 12 oz
chocolate milkshake small
popcorn 3 cups
sweet potato fries 1 small order
random homemade dal with rice
mom made chicken curry 1 bowl
leftover pasta 1 cup
2 boiled eggs and toast
ceaser sald with chikn
peproni pizza 1 slice
potato chips 100 grms
buckwheat 1 portion
muesli 100 grams
```

## New Item Batch Suggestions

Use these quick batches when you want to test queue behavior with mostly uncached foods. Paste each group as multiple rows.

Batch 1 - drinks and low-calorie items:

```text
sparkling water lime 12 oz
unsweetened iced tea 16 oz
coke zero can
orange juice 8 oz
```

Batch 2 - Indian meal mix:

```text
rajma chawal 1 bowl
poha 1 plate
palak paneer 1 cup with 2 roti
chicken biryani 1 cup
```

Batch 3 - typo / fuzzy parsing mix:

```text
ceaser sald with chikn
peproni pizza 1 slice
potato chips 100 grms
greek yougurt marrinated chicken
```

Batch 4 - ambiguous homemade mix:

```text
random homemade dal with rice
mom made chicken curry 1 bowl
leftover pasta 1 cup
protein waffle with peanut butter
```

## A. Basic Text Save

A1. Single normal item
- Input: `banana`
- Action: Type and wait for calories.
- Expected: One visible row, saved once in Saved Logs.

A2. Branded/common meal
- Input: `chipotle chicken bowl`
- Action: Type and wait.
- Expected: Saved once with calories/macros.

A3. Typo correction by AI
- Input: `balck coffee`
- Action: Type and wait.
- Expected: Interprets as black coffee, saves once.

A4. Zero-calorie item
- Input: `diet coke`
- Action: Type and wait.
- Expected: Shows 0 or near-zero calories and saves once. This must not be Parse only.

A5. Tiny-calorie item
- Input: `black coffee`
- Action: Type and wait.
- Expected: Saves even if calories are tiny.

A6. Ambiguous item
- Input: `sandwich`
- Action: Type and wait.
- Expected: If calories are shown, it saves once even if confidence is low or clarification exists.

## B. Edit Before Save Settles

B1. Partial to complete word
- Input flow: type `buckwheat 1 por`, then update to `buckwheat 1 portion`.
- Expected: Final visible completed row saves. Intermediate Parse only attempts are okay only if they were never final visible completed rows.

B2. Portion change on same concept
- Input flow: type `banana`, then edit to `2 banana` before/after parse.
- Expected: Final visible value saves. No duplicate unless both rows were intentionally completed separately.

B3. Typo correction
- Input flow: type `ceaser salad`, then correct to `caesar salad`.
- Expected: Final visible corrected row saves.

B4. Brand/detail edit
- Input flow: type `coffee`, then edit to `mcdonalds black coffee`.
- Expected: Final visible row saves, not the stale earlier interpretation.

B5. Same food later as a new entry
- Input flow: enter `muesli 10 grams`, let it save, then later enter `muesli 100 grams` as a new row.
- Expected: Both save as separate rows because both are intentionally completed entries.

## C. Multi-Row Input

C1. Two rows slowly
- Input: `banana`, then new row `1 chai`.
- Expected: Both rows save once.

C2. Three rows quickly
- Input rows: `banana`, `black coffee`, `2 eggs and toast`.
- Expected: Each completed visible row saves once.

C3. Mixed confidence rows
- Input rows: `diet coke`, `sandwich`, `banana`.
- Expected: Any row showing calories saves. Clarification does not block save.

C4. Edit middle row
- Input rows: `banana`, `coffee`, `1 chai`; edit `coffee` to `black coffee`.
- Expected: Final middle row saves correctly; other rows unaffected.

## D. Date Switching

D1. Switch day during debounce
- Action: Select Today. Type `banana`, immediately switch to Yesterday before calories appear.
- Expected: `banana` saves to the original day where typing started.

D2. Switch day after calories appear
- Action: Select Today. Type `banana`, wait for calories, switch to Yesterday.
- Expected: Today still keeps/saves the row. Yesterday does not get a duplicate.

D3. Type on Yesterday
- Action: Select Yesterday. Type `black coffee`.
- Expected: Saves to Yesterday, not Today.

D4. Yesterday then return Today quickly
- Action: Select Yesterday, type `1 chai`, immediately return Today.
- Expected: Yesterday keeps/saves `1 chai`. Today does not get it.

D5. Multi-day dashboard check
- Action: Add one item Today and one item Yesterday.
- Expected: Dashboard Saved Logs date filters match the app day lists exactly.

## E. App Lifecycle

E1. Force quit after calories appear
- Action: Type `banana`, wait for calories, kill app, reopen.
- Expected: Row remains and is saved/reconciled.

E2. Force quit during parsing
- Action: Type `banana`, kill app quickly before calories appear, reopen.
- Expected: No crash. Either no row or clean recovery. No ghost duplicate.

E3. Background during save
- Action: Type `black coffee`, wait for calories, background app.
- Expected: Save completes or resumes. Sync pill clears after reconciliation.

E4. Reopen with saved rows
- Action: Save several rows, kill app, reopen.
- Expected: No disappearing/reappearing flicker, no duplicate visible rows.

E5. Reopen with pending sync
- Action: Type an item, quit quickly, reopen.
- Expected: Sync state clears only after real saved/reconciled state. No stale forever-syncing pill.

## F. Duplicate Guard

F1. Same item once
- Input: `banana`
- Expected: One saved row.

F2. Same item twice intentionally
- Input flow: Enter `banana`, wait/save, then enter another `banana` as a new row.
- Expected: Two saved rows. Intentional duplicates should not be incorrectly removed.

F3. Same item with app refresh
- Action: Enter `banana`, wait, force quit/reopen.
- Expected: Still one row, not two.

F4. Rapid edit/retry
- Action: Type/edit quickly enough to trigger multiple parses.
- Expected: No duplicate saved row for the same final visible row.

F5. Network retry if possible
- Action: Use weak/offline network during save if convenient.
- Expected: Retry does not create duplicate rows.

## G. Clarification And Low Confidence

G1. Ambiguous food
- Input: `sandwich`
- Expected: If calories show, save happens.

G2. Low-confidence homemade food
- Input: `random homemade curry`
- Expected: If calories show, save happens.

G3. Clarification true plus calories
- Input: any row that opens clarification but has calories.
- Expected: Saves anyway. Clarification is UX, not a save blocker.

G4. Clarification true without calories
- Input: if a row cannot produce calories.
- Expected: It should not pretend to be saved. No misleading completed state.

## H. Drawer Behavior

H1. Open completed row
- Action: Tap a completed row after calories are visible.
- Expected app response: Drawer opens for the exact row you tapped. Food name, calories, and macros should match the row.
- Expected save/dashboard response: Opening the drawer should not create a duplicate save. The row should still appear once in Dashboard Saved Logs.

H2. Logged time visible
- Action: Open drawer for a saved row.
- Expected app response: Drawer shows the meal logged time. The time should correspond to when the user originally logged the row, not when the drawer was opened.
- Expected save/dashboard response: Dashboard logged time should be consistent with the app row/day. No new save attempt should happen just because the drawer opened.

H3. Close drawer without changes
- Action: Open drawer, then close it without editing or confirming anything.
- Expected app response: Row remains visible and unchanged on the home screen.
- Expected save/dashboard response: No duplicate row appears in Dashboard Saved Logs. Existing saved row remains saved once.

H4. Drawer during pending save
- Action: Open drawer shortly after calories appear, while sync/save may still be pending.
- Expected app response: Drawer opens for the correct pending row and keeps the same calorie estimate. UI should not flicker, lose the row, or switch to another row.
- Expected save/dashboard response: Pending save should still finish or reconcile. Dashboard Saved Logs should show one saved row, not zero and not two.

H5. Drawer after app reopen
- Action: Save a row, force quit/reopen the app, then open the drawer for that row.
- Expected app response: Drawer opens normally with the same food, calories/macros, and logged time.
- Expected save/dashboard response: Reopening and opening the drawer should not trigger a duplicate save.

H6. Drawer for zero-calorie row
- Input: `diet coke`
- Action: Wait for 0 or near-zero calories, then open the drawer.
- Expected app response: Drawer should still open and show the zero-calorie result clearly. Zero calories should not look like a missing parse.
- Expected save/dashboard response: Row should appear once in Dashboard Saved Logs. It should not remain Parse only.

H7. Drawer for clarification row
- Input: `sandwich` or another ambiguous item.
- Action: If calories appear and clarification/drawer opens, inspect the drawer.
- Expected app response: Drawer may ask for clarification, but the visible calorie estimate should remain attached to the row.
- Expected save/dashboard response: If calories are visible, the row should still save once. Clarification should not block persistence or create duplicates.

## I. Sync Pill Behavior

I1. One pending item
- Expected: Shows `Saving 1 item` only while one item is actually pending.

I2. Multiple pending rows
- Expected: Count matches actual unique pending rows.

I3. Saved rows reconciled
- Expected: Sync pill disappears after dashboard/server has the saved row.

I4. Reopen after pending
- Expected: Sync pill does not show stale/random counts forever.

I5. Failure state
- Expected: Shows waiting/error only if a real save remains pending or failed.

Bad signs:
- `Saving 4 items` when only one visible item is new.
- Sync pill disappears while dashboard still has a final visible row as Parse only.
- Sync pill stays after dashboard Saved Logs already has the row.

## J. Dashboard Source Of Truth

J1. App Today vs Dashboard Today
- Action: Compare app Today list with Dashboard Saved Logs Today.
- Expected: Same saved rows, same count, same rough calories.

J2. App Yesterday vs Dashboard Yesterday
- Action: Compare yesterday in both places.
- Expected: Same saved rows, same count.

J3. Parse Debug semantics
- Expected: Parse Debug may have intermediate attempts. Saved Logs is the source of truth for final saved app rows.

J4. Final visible row rule
- Expected: Any final visible row with calories should exist in Saved Logs.

## K. High-Priority Bug Repro Pack

Run these in order if you only have limited time:

1. `diet coke` - must save, not Parse only.
2. `black coffee` - tiny calorie save.
3. `buckwheat 1 por` -> `buckwheat 1 portion` - final visible row saves.
4. `muesli 10 grams`, later `muesli 100 grams` - both save if both are separate completed entries.
5. Type `banana`, immediately switch day - saves to original selected day.
6. Type three rows quickly - every completed row saves once.
7. Force quit after calories show - row remains and reconciles.
8. Reopen flicker test - no disappearing/reappearing completed rows.
9. Same item twice intentionally - two rows.
10. Same item once with retry/reopen - one row.
11. Multi-row queue: `banana`, `black coffee`, `1 chai` - all save once.
12. Daily total calories after multi-row save - app total matches dashboard total.
13. Drawer from a pending/queued row - correct row, logged time visible, no duplicate.
14. Streak after real saved log - updates only from saved logs, not Parse only attempts.


## L. Tough Queue / Totals / Streak / Drawer Edge Cases

L1. Multi-entry queue, no edits
- Input rows typed together:
  - `banana`
  - `black coffee`
  - `1 chai`
- Expected: All three visible completed rows save once. Sync pill may show multiple pending items, then clears. Dashboard Saved Logs has all three rows.

L2. Multi-entry queue with one edited row
- Input rows typed together:
  - `banana`
  - `coffee`
  - `1 chai`
- Action: Edit `coffee` to `black coffee` while other rows are parsing/saving.
- Expected: `banana`, final `black coffee`, and `1 chai` save once each. Stale `coffee` should not become a final saved row unless it was separately visible/completed.

L3. Multi-entry queue plus immediate date switch
- Action: Select Today. Type rows together: `banana`, `black coffee`, `1 chai`. Immediately switch to Yesterday before all saves finish.
- Expected: The three rows save to Today, the original day where they were typed. Yesterday should not receive those rows.

L4. Multi-entry queue plus force quit
- Action: Type rows together: `banana`, `black coffee`, `1 chai`. Wait until at least one calorie appears, then force quit and reopen.
- Expected: Completed rows remain/reconcile. No duplicates. Any pending completed rows eventually appear in Saved Logs.

L5. Daily total calories after several saves
- Action: Save three known rows on Today, for example `banana`, `black coffee`, `1 chai`.
- Expected: App daily total/summary calorie number equals the sum of visible saved rows, allowing tiny rounding differences. Dashboard Saved Logs total should match app Today total.

L6. Daily total after deleting or editing if available
- Action: If delete/edit exists, change or remove one saved row.
- Expected: App total updates correctly. Dashboard Saved Logs also reflects the same final saved state after refresh.

L7. Streak does not increment from parse-only attempts
- Action: Trigger a parse attempt that does not become a saved final row, if possible.
- Expected: Streak should not increment from Parse Debug / Parse only rows. Streak should reflect actual saved logging activity.

L8. Streak increments from real saved day
- Action: Save at least one row on a day with no prior saved logs.
- Expected: Streak indicator updates only after a real saved log exists for that day.

L9. Streak across day switching
- Action: Add an item on Yesterday, then return Today.
- Expected: Streak/day indicators should not double-count or randomly change because of date navigation. Saved Logs by day remains source of truth.

L10. Drawer opens for queued row
- Action: Type a row, wait for calories, tap it while save may still be pending.
- Expected: Drawer opens for the correct row. It should show logged time. Closing drawer should not duplicate the save.

L11. Drawer opens after multi-row queue
- Action: Type `banana`, `black coffee`, `1 chai`; after calories appear, open each row drawer one by one.
- Expected: Each drawer shows the correct food, calories/macros, and logged time for that row.

L12. Drawer clarification with autosave
- Input: `sandwich` or another ambiguous item that may trigger clarification.
- Expected: If calories are visible, save still happens. Drawer/clarification UI should not block the saved row or create a duplicate.

L13. Dashboard totals vs app totals
- Action: After several saves, compare app Today list/total with Dashboard Saved Logs Today totals.
- Expected: Same row count and same total calories, allowing tiny rounding differences.

L14. Queue order does not matter, final state does
- Action: Type multiple rows quickly and watch them complete in different order.
- Expected: It is okay if rows save in a different backend order. Final visible app rows and dashboard Saved Logs should match.

## Overnight Run Order

Use this order if testing while away from the machine:

1. Run A1-A6 on Today.
2. Run B1-B5 on Today.
3. Run C1-C4 with multi-row input.
4. Run D1-D5 for date switching.
5. Run E1-E5 for app lifecycle.
6. Run F1-F5 for duplicate behavior.
7. Run G1-G4 for clarification behavior.
8. Run H1-H7 for drawer behavior.
9. Run I1-I5 while watching the sync pill.
10. Run J1-J4 by comparing app to dashboard Saved Logs.
11. Run L1-L14 for the tough queue/totals/streak/drawer checks.

## Issue Log Template

Copy this when something fails:

```text
Test ID:
Input typed:
Selected day when typed:
Exact action sequence:
What app showed:
What dashboard Saved Logs showed:
What Parse Debug showed:
Was sync pill visible? If yes, text:
Did force quit/reopen change anything?
Expected result:
Actual result:
Screenshot/video taken: yes/no
```

## Pass Criteria Before Phase 4

Phase 4 is safe only if:

- [ ] No final visible calorie row remains Parse only.
- [ ] Date switching does not orphan saves.
- [ ] Force quit/reopen does not create flicker or duplicates.
- [ ] Sync pill reflects real pending work only.
- [ ] Dashboard Saved Logs for selected day matches the app selected day.
- [ ] Intentional duplicate entries save separately.
- [ ] Accidental duplicate save attempts are guarded.
