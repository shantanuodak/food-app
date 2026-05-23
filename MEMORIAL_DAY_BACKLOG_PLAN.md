# Memorial Day Backlog — Plan & Design Spec

**Status:** Planned, not started
**Owner:** Claude (Opus 4.7) implements; user tests on device via TestFlight
**Created:** 2026-05-22 (Memorial Day weekend)
**Estimated:** ~22–28h Claude focused work, ~10–14 days wall-clock with TestFlight cycles
**Source:** 18-item handwritten backlog from user, captured in `/Food App/MEMORIAL_DAY_BACKLOG_RAW.md` (verbatim)

---

## How to read this document

Each item below has the same shape so reviewers can scan consistently:

- **Problem** — what the user said, condensed to one paragraph
- **Design spec** — concrete visual / motion / copy direction
- **Implementation** — files to touch and the shape of the change
- **Files affected** — table of paths + action (CREATE / MODIFY)
- **Edge cases** — surfaces that often break with this change
- **Test cases** — acceptance checks; pass/fail are unambiguous
- **Risks** — what can go wrong + the rollback story
- **Out of scope** — adjacent things deliberately deferred

The plan is grouped into **eight phases** by surface area, not by user priority. Each phase ships as a single TestFlight push so the user can validate before moving on.

---

## Phase index & dependencies

```
Phase A (Onboarding/Tutorial)        ──┐
   ├── Item 1, 2, 14                   │
                                       │
Phase B (Logging UX)                   │
   ├── Item 4, 13                      │
                                       │
Phase C (Drawer & Serving)             ├──→ Phase H (Validation + TestFlight rollout)
   ├── Item 10, 11, 12                 │
                                       │
Phase D (Camera)         ◄─ V3.1 ──────┤
   ├── Item 9                          │
                                       │
Phase E (Error/Retry UX)               │
   ├── Item 3, 8                       │
                                       │
Phase F (Profile / Insights)           │
   ├── Item 5, 6, 7                    │
                                       │
Phase G (Visual chrome)                │
   ├── Item 15, 16, 17, 18          ───┘
```

**Recommended order to ship:**

1. **Phase E** (error/retry UX — quick wins, no design risk)
2. **Phase D** (camera primary-lens fix — small, isolated)
3. **Phase G** (visual chrome — badge button, graph icon, saved button, widget — all independent)
4. **Phase B** (logging tips popup, Gemini de-mention)
5. **Phase A** (tutorial v2 + day-swipe layer — depends on testing tutorial flow on real device)
6. **Phase C** (drawer + native pickers — biggest visual rework)
7. **Phase F** (profile restraint + bento → graphs relocation — touches the in-flight Bento Profile initiative; do last)
8. **Phase H** (validation + family rollout)

Phases ship independently; each ends with a clean commit. Rollback is per-phase.

---

## Phase A — Onboarding & tutorial v2

Items: **1, 2, 14**.
Estimated: ~3h Claude, ~30 min user testing per cycle.

### Item 1: Tutorial v2 — non-interactable, Next / Next / Done

#### Problem
Currently after onboarding, when a new user lands on the home screen, the `HomeCoachCardTutorialOverlay` (defined in [HomeFirstRunTutorialView.swift:112](Food%20App/Food%20App/HomeFirstRunTutorialView.swift)) shows three steps where the primary CTAs do real things — "Try typing" focuses the composer, "Try camera" opens the camera, "Open progress" opens the progress sheet. The user wants the tutorial to be **passive**: the user just reads each card and taps **Next**, **Next**, **Done**. After Done, the tutorial dismisses and the day-swipe overlay (Item 2) appears.

#### Design spec
- Keep the existing coach-card visual language: 28pt corner radius, warm cream fill (#FEFCF7), 20pt padding, 14pt shadow.
- Keep the three step previews (composer / camera / progress) and step-dot indicator at the bottom.
- Replace the per-step button pair with a **single full-width primary CTA**:
  - Step 1: `Next` (brand orange #EE7A21 background, white text, 46pt height, full width)
  - Step 2: `Next` (same style)
  - Step 3: `Done` (same style)
- Keep the secondary `Skip` button visible on all three steps as a small text-only link in the top-right (next to the existing X). Tapping `Skip` finishes the tutorial without entering the day-swipe overlay (Item 2).
- Transition between steps: 250ms spring (response: 0.32, damping: 0.88) crossfade — same as current.
- On `Done`, fade the tutorial card out (220ms ease-out) and *immediately* fade-in the day-swipe overlay (220ms ease-out). No gap, no flash.

#### Implementation
- In `HomeCoachCardTutorialOverlay.buttons` ([HomeFirstRunTutorialView.swift:228](Food%20App/Food%20App/HomeFirstRunTutorialView.swift)) replace the per-step `HStack(spacing: 10) { secondary; primary }` with a single primary button that just advances `step` (or calls `onFinish` on step 3).
- Remove the `onFocusComposer` / `onOpenCamera` / `onOpenProgress` closures from the overlay's call sites in [MainLoggingShellBody.swift:519](Food%20App/Food%20App/MainLoggingShellBody.swift) — they're no longer used.
- Add a `onFinish` follow-up: after `finishHomeTutorial` runs, set a new `@State var isDaySwipeTutorialPresented = true`.
- Persist `UserDefaults` flag `homeTutorialShownKey` only after the user reaches `Done` (or `Skip` from any step). That matches current behavior.

#### Files affected
| File | Action |
|---|---|
| `Food App/HomeFirstRunTutorialView.swift` | MODIFY — collapse buttons to single Next/Done |
| `Food App/MainLoggingShellBody.swift` | MODIFY — drop unused closures, trigger day-swipe layer on finish |
| `Food App/MainLoggingShellView.swift` | MODIFY — add `isDaySwipeTutorialPresented` state |

#### Edge cases
- **Replay from admin** (`replayHomeTutorialFromAdmin` notification, [MainLoggingShellBody.swift:543](Food%20App/Food%20App/MainLoggingShellBody.swift)) — admin replay should not trigger the day-swipe overlay; user explicitly invoked the tutorial, they've seen days already.
- **Skip mid-tutorial** — must still mark `homeTutorialShownKey` true so it doesn't auto-show again on the next cold start.
- **Tutorial fires while a sheet is presented** — currently guarded by `selectedCameraSource == nil, !isQuickCameraCaptureActive, !isVoiceOverlayPresented` in `autoPresentHomeTutorialIfNeeded`. Leave guard intact.
- **VoiceOver users** — the modal trait is already set. Each card should announce step number + title. Step changes should announce the new card's content (currently relies on natural focus update).
- **Reduce motion** — already handled at the entrance animation. Cross-step transitions should respect it too (drop the spring, use a 180ms ease-out).

#### Test cases
1. Fresh install → complete onboarding → home screen renders → tutorial step 1 appears in ~300ms.
2. Tap `Next` on step 1 → step 2 slides in, step dots advance.
3. Tap `Next` on step 2 → step 3.
4. Tap `Done` → tutorial fades, day-swipe overlay fades in (Item 2).
5. Restart app → tutorial does NOT reappear.
6. Open Profile → debug "Replay tutorial" button → tutorial shows again, but tapping `Done` does NOT show day-swipe overlay.
7. Tap `Skip` on step 1 → tutorial closes, day-swipe overlay does NOT appear, no second auto-show.
8. VoiceOver on: step changes announce new title and step number.
9. Reduce Motion on: transitions are simple fades, no spring overshoot.

#### Risks
- Day-swipe overlay timing — if it fires before the tutorial fully fades, two overlays could briefly co-exist. Mitigation: gate the day-swipe presentation behind the tutorial's fade-out completion (`DispatchQueue.main.asyncAfter(deadline: .now() + 0.24)`).
- Rollback: this is two small file edits. Revert the commit if anything looks wrong.

#### Out of scope
- Localizing tutorial copy (English-only stays for now).
- Per-step illustrations beyond the existing SF Symbol previews.

---

### Item 2: Day-swipe interactive tutorial

#### Problem
After the user taps `Done` on tutorial step 3, they have no way of knowing that they can swipe left/right between days. The day swipe is wired in [MainLoggingShellBody.swift:48-74](Food%20App/Food%20App/MainLoggingShellBody.swift) via a `DragGesture(minimumDistance: 15)` on the scrollview, but it's invisible. We want a one-time interactive overlay that teaches the gesture by making the user perform it.

#### Design spec
- Dim layer: `Color.black.opacity(0.36)` over the whole screen, ignoring safe areas.
- Center stack:
  - **Arrow art**: SF Symbol `chevron.compact.left` at 64pt weight black, white, with a subtle left-right oscillation (translate ±8px on x-axis, 1.4s autoreverse ease-in-out) and a soft 1.2s autoreverse opacity pulse (0.6 → 1.0).
  - **Headline** (below arrow, 32pt InstrumentSerif italic, white): "Swipe left to see tomorrow"
  - **Subtext** (16pt SF Rounded medium, white@0.78): "Days slide horizontally. You can browse past or future."
- Bottom: small "Skip" link (14pt SF Rounded semibold, white@0.62), tappable, ends the overlay without acknowledgement.
- On successful left swipe: arrow flips horizontally (200ms), headline crossfades (220ms) to "Now swipe right to come back", subtext updates accordingly.
- On successful right swipe: 320ms fade-out + scale to 1.04, then dismiss. Persist `UserDefaults.standard.set(true, forKey: "daySwipeTutorialShownKey")`.
- Swipe threshold: same as the underlying gesture (15pt minimum-distance, dominant axis = horizontal) so the tutorial only "counts" a real swipe.
- Reduce motion: drop the arrow oscillation and the scale-on-dismiss; keep the crossfade.

#### Implementation
- Create `Food App/DaySwipeTutorialOverlay.swift` — a `ZStack` overlay view modifier identical in shape to `HomeCoachCardTutorialHostModifier`.
- State machine: `enum DaySwipeTutorialPhase { case promptLeft, promptRight, dismissing }`. Start in `.promptLeft`.
- Attach a `DragGesture(minimumDistance: 15)` *to the overlay itself* (not the underlying scroll view) — when an axis-locked horizontal drag of >40pt is detected with the right sign, advance the phase.
- The overlay must **not block** the underlying day-swipe gesture: when it advances, also let the real swipe animation play (forward the gesture or trigger a programmatic day shift via existing `handleSwipeTransition`).
- After phase `.dismissing`, set `isDaySwipeTutorialPresented = false` after the fade completes.

#### Files affected
| File | Action |
|---|---|
| `Food App/DaySwipeTutorialOverlay.swift` | CREATE |
| `Food App/MainLoggingShellView.swift` | MODIFY — add state + present overlay |
| `Food App/MainLoggingShellBody.swift` | MODIFY — host overlay above bottom dock, below toasts |

#### Edge cases
- **Today is the last available day** — if `selectedSummaryDate == clamped(today)`, swiping left would attempt to go forward which is clamped. In that case, the tutorial should first guide the user to swipe RIGHT (past), then LEFT (today). Swap the prompt order based on the clamping.
- **Sheet is open when overlay would appear** — if anything else is presented (calendar, profile, etc.), defer the overlay until the sheet is dismissed. Use the same gating pattern as the tutorial auto-present.
- **User performs the wrong direction first** — give haptic `.warning` notification, keep the prompt unchanged, don't dismiss the overlay or count it as progress.
- **User scrolls vertically** — vertical drags should not advance the tutorial. The existing `swipeAxis` lock already handles this.
- **VoiceOver** — entire overlay should be one accessibility element with combined label "Day swipe tutorial. Swipe left to see tomorrow. Swipe right to dismiss."

#### Test cases
1. Complete tutorial → day-swipe overlay appears with chevron pointing left.
2. Swipe left → day shifts to tomorrow, prompt updates to "swipe right".
3. Swipe right → day shifts back to today, overlay fades, never reappears.
4. Restart app → overlay does NOT reappear.
5. Replay tutorial from admin → does NOT trigger day-swipe overlay.
6. Swipe vertically while overlay is up → no acknowledgement, prompt stays.
7. Tap `Skip` mid-overlay → overlay dismisses, persists shown=true, no further prompt.
8. VoiceOver on: overlay announces full instruction; swipe-right via accessibility action dismisses it.

#### Risks
- **Gesture forwarding bug** — if the overlay swallows the gesture without letting the day actually advance, the user gets the visual prompt but the underlying day stays static (broken UX). Mitigation: forward via NotificationCenter or call `handleSwipeTransition(value)` directly.
- **The user dismisses by tapping outside, expecting that to work** — currently `.contentShape(Rectangle()).onTapGesture` would dismiss. We *don't* want tap-to-dismiss (defeats the educational goal). Add an explicit `Skip` link instead.

#### Out of scope
- Animating the actual content beneath the overlay (the regular day swipe animation is enough).
- Multiple replay opportunities — show once, then never again.

---

### Item 14: Same as Item 2 — covered above (handwritten backlog had this listed separately in #14; we collapsed them).

---

## Phase B — Logging UX polish

Items: **4, 13**.
Estimated: ~2h Claude.

### Item 4: Logging tips popup (replace inline row)

#### Problem
When the user types a vague entry (e.g., "sandwich"), the app surfaces logging tips as an inline row inside the day list. The user finds this "row" treatment awkward and wants a popup with a clear call-to-action and a skip option.

#### Design spec
- Trigger: same as today (after a vague-entry signal — `needsClarification` or `isApproximate` on a fresh entry).
- Form: bottom sheet using `.presentationDetents([.height(180)])` (or a custom inline overlay if a sheet feels too heavy).
- Card style (matches FoodLoggingTipsView language):
  - Background: warm cream gradient `#FAE1C9 → #FFF9F0 → #F4EADE`, 24pt corner radius, 1pt border `rgba(72,45,24,0.11)`.
  - Header text: "Make logs more accurate" (28pt InstrumentSerif italic, ink #241914).
  - Body: "Adding a portion, brand, or size gives a better calorie estimate." (14pt SF Rounded medium, muted #776A61, 2-line max).
  - Primary CTA: `Show me tips` (full width, brand orange fill, white text, 48pt height, 16pt corner radius).
  - Secondary CTA: `Skip for now` (text-only, 14pt SF Rounded semibold, muted ink).
- Motion: slide-in from bottom over 260ms ease-out (sheet default). Dismiss by tapping outside, tapping `Skip`, or pulling down.
- Frequency: at most once per session per row. Persist a per-row "tips suggested" flag in memory so re-parses don't re-trigger.
- Tap `Show me tips` → dismiss the popup → open the existing `FoodLoggingTipsView` as a sheet (already wired at `isLoggingTipsPresented`).

#### Implementation
- Add new state in `MainLoggingShellView`: `@State var loggingTipsPromptRow: HomeLogRow.ID?`.
- Surface trigger: in the parse-complete handler in `MainLoggingParseFlow.swift`, when the result for a row has `needsClarification == true` AND the row hasn't been prompted in this session, set the state.
- New view: `Food App/LoggingTipsPromptSheet.swift` — the 180pt sheet body.
- Hook into shell body via `.sheet(item: $loggingTipsPromptRow) { row in LoggingTipsPromptSheet(...) }`.

#### Files affected
| File | Action |
|---|---|
| `Food App/LoggingTipsPromptSheet.swift` | CREATE |
| `Food App/MainLoggingShellView.swift` | MODIFY — add state |
| `Food App/MainLoggingShellBody.swift` | MODIFY — wire sheet |
| `Food App/MainLoggingParseFlow.swift` | MODIFY — set state on vague parse |

#### Edge cases
- **Multiple vague entries in one session** — only show the popup for the first one in a session; subsequent vague entries surface a small inline "Add more detail?" caption instead (out of scope for v1 — defer to backlog).
- **User skips, then enters another vague row** — respect the skip; don't reprompt for 24h (persist a date in UserDefaults).
- **User dismisses by drag-down** — same as `Skip for now`.
- **Sheet collision** — if any other sheet is presenting, defer the prompt until current sheet dismisses.
- **Dark mode** — adjust cream tones; `ColorScheme.dark` should use a dark warm surface (`#2A1F18`) with the same brand orange CTA.

#### Test cases
1. Type "sandwich" → parse completes → popup slides up in ~300ms.
2. Tap `Show me tips` → popup dismisses → FoodLoggingTipsView sheet opens.
3. Tap `Skip for now` → popup dismisses → no follow-up for 24h.
4. Re-type "salad" (different row) → no popup (24h skip honored).
5. Wait 24h → re-type "fries" → popup appears.
6. Parse a specific entry "1 turkey sandwich with mayo on wheat" → no popup (parse is confident).
7. VoiceOver on: card announces "Make logs more accurate" + body + actions.
8. Dynamic Type at accessibility1: card grows vertically without truncating body.

#### Risks
- **False positives** — if `needsClarification` fires too aggressively (e.g., on common foods), the popup becomes spammy. Mitigation: require the parse confidence to be below a strict threshold (currently the same threshold used for the inline marker). Telemetry-light: log popup-shown count, check vs popup-followed count after a day of testing.

#### Out of scope
- Personalized tips ("you often forget portion size" — needs telemetry).
- Localizing copy.

---

### Item 13: Remove "Gemini Nutrition Database" mention + enrich thought process

#### Problem
The thought-process UI surfaces "Gemini" as the source. The user wants to keep the thought process (and make it richer) but stop branding it with the upstream LLM name.

#### Design spec
- Replace "Gemini" with neutral language:
  - `sourceDisplayName("gemini")` → `"AI nutrition estimate"` (was `"Gemini"`)
  - `sourceReferenceLabel` for "gemini" → `"AI-driven nutrition estimate"`
  - `upstreamNutritionSourceDisplayName` for "gemini" → `"AI nutrition database"`
- In `thoughtProcessText`, make the body richer. Today's template (paraphrased):
  > `Interpreted "salad" as multiple items: salad, dressing. Used Gemini nutrition data to estimate 320 kcal total.`
  Replace with:
  > `Detected "salad" as a mixed item: salad + dressing. Estimated 320 kcal from typical serving sizes and ingredient ratios. Confidence is high based on item names and detected portion language.`
  For low-confidence rows:
  > `… Marked as approximate because the description left portion size unclear. Add a count or size to tighten the estimate.`
- Tone: explain *how* the estimate was reached without claiming "AI black box". No proper nouns for vendors.

#### Implementation
- In [HomeLoggingDisplayText.swift](Food%20App/Food%20App/HomeLoggingDisplayText.swift), update the three return sites for "Gemini" (lines 7, 20, 78).
- In `thoughtProcessText` (line 93), expand the per-item and multi-item templates. Add a "Why this estimate" line that surfaces what the parser keyed on (count, brand, place if extracted). Use the existing `ParsedFoodItem.explanation` field where present.
- Audit other call sites: grep for `"Gemini"` to make sure no other UI surfaces it.

#### Files affected
| File | Action |
|---|---|
| `Food App/HomeLoggingDisplayText.swift` | MODIFY — replace strings + enrich templates |
| (Audit) any other `.swift` mentioning "Gemini" | MODIFY if found |

#### Edge cases
- **API responses still send `source: "gemini"`** — that's fine; only the display layer changes. Don't touch backend or stored data.
- **Cached rows from before the change** — they render via the same display function on read, so they get the new label automatically.
- **Multilingual support** — keep strings ASCII for now; localization will come later.
- **Parse explanation missing** — `ParsedFoodItem.explanation` is optional; the template must fall back gracefully.

#### Test cases
1. Log "1 cup oatmeal" → drawer shows thought process without the word "Gemini".
2. Log "snack" (vague) → thought process explains why it's approximate.
3. Open a meal from yesterday (cached) → thought process uses new wording.
4. Search the iOS app bundle's strings — "Gemini" should appear 0 times (`grep -rn "Gemini" "Food App/"`).
5. VoiceOver reads thought process — no "Gemini" announced.

#### Risks
- **Trivial.** Pure string-and-template change. Rollback = revert the commit.

#### Out of scope
- Backend rename of the `source_id` (would invalidate caches).
- Showing model version or provider info anywhere in the UI.

---

## Phase C — Drawer redesign + native pickers

Items: **10, 11, 12**.
Estimated: ~6h Claude across 2 sessions. Highest design risk.

### Item 10: Logging drawer redesign (image + calorie drawers)

#### Problem
Two drawers exist and feel inconsistent:
- **(a)** Post-photo drawer (`CameraResultDrawerView`, shown after taking a picture).
- **(b)** Row-level calorie-edit drawer (`MainLoggingRowCalorieDetailsSheet`, opens when user taps calories on a logged row).

The user wants both to be "cleaner, with better differentiation between categories", and to share a visual language.

#### Design spec
Unified pattern, top to bottom:

1. **Header (image variant only)**: image thumbnail 64pt rounded square (8pt corner) → primary food name (20pt SF Rounded heavy ink) → `Total: 480 kcal` (14pt SF Rounded semibold muted). 16pt vertical padding, 16pt horizontal.
2. **Header (calorie variant)**: meal name + total kcal, no thumbnail. Same typography.
3. **Macro pills row** (both variants): three chips, equal width, 8pt gap:
   - Protein chip: `28g` over `Protein` label. Background `#E9E4FF`, ink `#3D2E96`.
   - Carbs chip: `52g` over `Carbs` label. Background `#DAF3E1`, ink `#1E5C36`.
   - Fat chip: `14g` over `Fat` label. Background `#FFE7E1`, ink `#933520`.
   Chip is 76pt height, 20pt corner radius, 8pt vertical padding.
4. **Per-item list**: each food item gets a row with:
   - Item name (16pt SF Rounded semibold ink)
   - Compact stack of quantity + serving-type pickers (Item 11/12 — see below)
   - Right side: kcal for that item (14pt SF Rounded semibold ink), small chevron if expandable
   - Row background: `.white.opacity(0.62)` over the warm-cream drawer background, 16pt corner radius, 1pt warm border.
5. **Footer actions**: stack of buttons, 12pt vertical gap:
   - Primary: `Log it` (brand orange fill, white text, 52pt height, 16pt corner radius, full width minus 32pt horizontal padding).
   - Secondary: `Save as meal` (16pt corner radius pill, brand orange text, white background, 1pt brand orange border).
   - Tertiary: `Retry` (only on parse error states, see Item 3) + `Discard` (text-only, 13pt SF Rounded semibold, muted red `#933520`).

**Drawer chrome**:
- Both variants present at `.presentationDetents([.medium, .large])` with drag indicator and 24pt corner radius (matches existing).
- Inline overlay variant (camera capture path — see [MainLoggingShellBody.swift:579](Food%20App/Food%20App/MainLoggingShellBody.swift)) gets a hand-drawn capsule drag indicator + 24pt top corners (already in place).

**Motion**:
- Item-row press: 90ms scale to 0.985 + opacity 0.95, then restore. Spring (response: 0.22, damping: 0.78).
- Drawer open: standard sheet (260ms ease-out from bottom).

#### Implementation
- Refactor `CameraResultDrawerView.swift` into a shared `LoggingDrawerScaffold` view that takes header, macro pills, item list, and actions as slot content. Both drawers compose this scaffold.
- Calorie-edit drawer (`MainLoggingRowCalorieDetailsSheet` in `MainLoggingDrawerFlow.swift`) is rewritten to use the same scaffold.
- Add `MacroChip.swift` with the three pill styles.
- Add `LoggingDrawerItemRow.swift` for the per-item row.

#### Files affected
| File | Action |
|---|---|
| `Food App/CameraResultDrawerView.swift` | MODIFY — adopt scaffold |
| `Food App/MainLoggingDrawerFlow.swift` | MODIFY — calorie sheet adopts scaffold |
| `Food App/LoggingDrawerScaffold.swift` | CREATE |
| `Food App/LoggingDrawerItemRow.swift` | CREATE |
| `Food App/MacroChip.swift` | CREATE |

#### Edge cases
- **No image path** (text-only or voice entry) — drawer must look correct without a thumbnail. Show the meal name centered with 20pt vertical padding instead.
- **Mixed-item parse with 8+ items** — scaffold must scroll. Outer ScrollView, not LazyVStack (low count expected, max ~12).
- **Long item names** — truncate after 2 lines with tail ellipsis, full text on tap.
- **Zero-macro items** — chips show "0g" not "—". Visually muted: chip background drops to 0.5 opacity.
- **Drawer opens while keyboard is shown** — keyboard must dismiss first. Wire via `.scrollDismissesKeyboard(.interactively)` if not already.

#### Test cases
1. Take photo of food → drawer shows thumbnail + name + macros + items + actions in correct order.
2. Open calorie-edit on a saved row → drawer shows same layout WITHOUT thumbnail.
3. Edit a serving size (Item 11/12) → kcal updates in real time.
4. Tap `Log it` → drawer dismisses, log appears in day list.
5. Tap `Save as meal` → saved meals sheet opens with the current items pre-filled.
6. VoiceOver: each item row announces "Item N: turkey sandwich, 320 kcal, 1 sandwich".
7. Dynamic Type at accessibility1: chips grow, item rows wrap; no truncation of macros.

#### Risks
- **Touching the camera drawer destabilizes the V3.1 hotfix v6 inline overlay** (`isCameraAnalysisSheetPresentedOverCover`, see [MainLoggingShellBody.swift:384](Food%20App/Food%20App/MainLoggingShellBody.swift)). Mitigation: keep the scaffold's outer wrapper untouched; only swap the inner content. Manual device test required before merge.
- **Calorie edit drawer save flow** — it's per-row, not per-meal. Make sure the macros displayed reflect the row's current edits, not stale parse data.

#### Out of scope
- Drag-and-drop reordering of items.
- Per-item expand to show "thought process" inline (keep the existing tap-to-open behavior).
- Animating macro values when they change (defer; cosmetic only).

---

### Items 11 & 12: Native serving-size picker (qty + type)

#### Problem
Today serving size is edited via a 0.5-increment stepper, quantity only. If the app detects "1 cup" but the user actually had a glass, they can't change `cup → glass`. They also can't go below 0.5 or pick custom fractions easily.

#### Design spec
Inside each `LoggingDrawerItemRow`:

- **Quantity picker**: a tappable chip (40pt height, 18pt corner radius, white background, ink text, brand orange border) showing the current quantity (e.g., `1.5`). Tap to expand a SwiftUI `Picker(style: .wheel)` inline beneath the row. Wheel options: a curated list `[¼, ⅓, ½, ¾, 1, 1.25, 1.5, 2, 2.5, 3, 4, 5, custom…]`. `custom…` opens a small numeric keypad sheet for arbitrary decimals.
- **Unit picker**: adjacent chip, same style, showing current unit (`cup`). Tap to expand a SwiftUI `Picker(style: .wheel)` with: `cup, glass, bowl, slice, piece, half, whole, tablespoon, teaspoon, ounce, gram, milliliter, fluid ounce, scoop, can, bottle, packet, serving`.
- **Suggested tag**: when both pickers show the parser's inferred values, a subtle 11pt SF Rounded bold label `Suggested` (brand orange) sits below the chip pair. Tag disappears once the user changes either picker.
- **Wheel chrome**: native `.wheelPickerStyle()`, 120pt height when expanded, surrounded by the cream drawer background. Tap the chip again to collapse.
- **Live macro update**: changing either picker recalculates per-item macros and total kcal via the existing serving-scale logic. Update happens immediately on selection change (no commit button).

#### Implementation
- Add `Food App/ServingPicker.swift` with two views: `ServingQuantityPicker` and `ServingUnitPicker`. Both backed by SwiftUI `Picker`.
- The expand/collapse uses `withAnimation(.spring(response: 0.28, dampingFraction: 0.85))` and a `@State var isExpanded` per picker (only one expanded at a time per row — closing one when the other opens).
- Custom quantity: present a small `.sheet(isPresented: $isCustomQuantityPresented) { NumericKeypadSheet(... ) }` with a numeric keypad and decimal allowed.
- Per-item macro recalculation: extend `ParsedFoodItem` with a `customServing` overlay (don't mutate the parse result; track as a side struct). When recomputing totals, use the overlay if present.

#### Files affected
| File | Action |
|---|---|
| `Food App/ServingPicker.swift` | CREATE |
| `Food App/ServingUnitOption.swift` | CREATE — the enum + display names |
| `Food App/NumericKeypadSheet.swift` | CREATE |
| `Food App/LoggingDrawerItemRow.swift` | MODIFY — embed the pickers |
| `Food App/HomeLoggingServingOptionUtils.swift` | MODIFY — recalc helpers |
| Parser model (likely `ParseModels.swift` or similar) | MODIFY — add `customServing` overlay |

#### Edge cases
- **Backend doesn't know "glass"** — the unit is a display layer only. The persisted log uses the converted gram value via a static conversion table (cup → 240g, glass → 250g, bowl → 350g, etc. — defaults are stand-ins until we get real data).
- **Conversion is approximate** — show a subtle helper line on first-time use: `Converted using typical sizes. Will improve with feedback.`
- **Unit doesn't have a sensible kcal scale** (e.g., "serving" for a homemade meal) — pickers should still allow it; kcal stays unchanged (treat as "1 serving = current calorie count").
- **Custom decimal**: must allow `0.1` to `99.9`, two decimal places max. Numeric keyboard, no negative numbers.
- **Persistence**: changing quantity/unit and saving the log must persist the chosen unit on the row so re-opening shows the user's choice, not the parser's inference. New column on `food_log_items` (`user_unit TEXT`, `user_quantity NUMERIC`) — backend backlog item.

#### Test cases
1. Take photo of a glass of milk → parser says "1 cup milk" → drawer shows `1` + `cup`, with "Suggested" tag.
2. Tap unit chip → wheel expands with `cup` selected → scroll to `glass` → wheel snaps → tag disappears, kcal updates to reflect 250g.
3. Tap quantity chip → wheel expands → scroll to `1.5` → kcal scales to 1.5×.
4. Tap quantity chip again → tap `custom…` → keypad sheet → type `0.33` → confirm → chip shows `0.33`.
5. Tap unit chip → wheel expands → quantity wheel collapses if it was open.
6. VoiceOver: chip announces "Quantity, 1 cup. Tap to change. Suggested.". After change: "Quantity, 1.5 glass."
7. Restart app, open the same log → user-chosen quantity + unit are preserved.

#### Risks
- **Backend persistence not in place** — for v1, store the user's choice locally only (UserDefaults keyed by `food_log_item.id`). Backend column is a follow-up.
- **Conversion table accuracy** — for v1, use canonical defaults from FDA portion data. Don't claim precision in copy.
- **iOS 16 wheel picker styling** — `wheelPickerStyle` on iOS 16 has slight color quirks. Test on the lowest supported iOS version.

#### Out of scope
- Brand-aware portion sizes (e.g., "Starbucks tall" vs "Starbucks grande").
- Photo-based portion size estimation.
- Persisting user-chosen unit conversion table per user.

---

## Phase D — Camera (primary lens only)

Items: **9**.
Estimated: ~30 min Claude.

### Item 9: Use primary camera, not wide-angle

#### Problem
The user feels the camera shows a wider field of view than expected. Today, [CameraService.swift:283-298](Food%20App/Food%20App/CameraService.swift) selects `.builtInTripleCamera` (Pro models) or `.builtInDualWideCamera`, both of which are *virtual* devices that auto-switch between the main 1× wide-angle lens and the 0.5× ultra-wide lens. On close subjects (barcodes, labels, food close-ups), iOS swaps to the ultra-wide for macro — which the user perceives as "wide angle".

#### Design spec
- No UI changes. Pure capture-config change.
- Use **only the primary 1× wide-angle camera** (`.builtInWideAngleCamera`). Drop the multi-camera virtual device.
- Tradeoff documented: loses iOS auto-macro engage on iPhone 13 Pro+ for very close subjects. Acceptable per user feedback.
- If barcode/label parse rates degrade for close-up packaging, revisit by giving the user an explicit "macro mode" toggle in the camera (out of scope here).

#### Implementation
- In `CameraService.swift`'s `bestDevice(for:)` ([CameraService.swift:283](Food%20App/Food%20App/CameraService.swift)), reorder the device discovery:
  ```swift
  // Use the primary 1x camera only. Per user feedback (2026-05-22),
  // the auto-switch to ultra-wide on close subjects looks like
  // "the wrong camera" even though it is technically the macro lane.
  if let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
      return wide
  }
  return AVCaptureDevice.default(for: .video)
  ```
  Drop the `.builtInTripleCamera` and `.builtInDualWideCamera` branches.

#### Files affected
| File | Action |
|---|---|
| `Food App/CameraService.swift` | MODIFY — single-lens device selection |

#### Edge cases
- **Older devices** that only have `.builtInWideAngleCamera` — already covered (fallback was already wide).
- **Front camera switch** — if the camera UI offers front-camera flip, the front camera is `.builtInWideAngleCamera` (with position `.front`) — unchanged.
- **Barcode scanning at close distance** — the live metadata output ([CameraService.swift:302](Food%20App/Food%20App/CameraService.swift)) keeps working, just without macro auto-focus. The user can step back ~12 cm and barcodes still scan.

#### Test cases
1. Open camera → take a photo of a normal food plate → field of view matches what you see in the iOS Camera app's 1× mode.
2. Try a barcode at ~10 cm → focus may struggle on iPhone Pro models; ~15 cm works.
3. Test on iPhone SE (single-lens) — no regression.
4. Test on iPhone 15 Pro (triple-camera) — no auto-zoom to ultra-wide.

#### Risks
- **Barcode parse rates may dip** on iPhone Pro models for close-up packaging. Watch the lane distribution after rollout. If `image_barcode` saves drop noticeably, plan a follow-up to expose a `Macro` toggle.

#### Out of scope
- A manual macro toggle.
- Switching to `.builtInDualCamera` for non-ultra-wide cases (it's a different virtual device).

---

## Phase E — Error / retry UX

Items: **3, 8**.
Estimated: ~1.5h Claude.

### Item 3: Parse-failure inline text (replace red retry card)

#### Problem
On parse failure, the row shows a red rounded card with `Couldn't parse — tap Retry` and a separate red Retry pill button (see [MainLoggingCameraDrawerFlow.swift:11-67](Food%20App/Food%20App/MainLoggingCameraDrawerFlow.swift)). The user finds this "really ugly" and wants the retry to look like the offline/syncing caption — quiet inline text with an underlined `Retry` link at the same vertical location.

#### Design spec
- Drop the red rounded card and the pill button.
- New treatment: under the row's primary text, add a caption line:
  - Text: `Couldn't parse · ` (12pt SF Rounded semibold, muted #776A61)
  - Link: `Retry` (12pt SF Rounded semibold, brand orange, underlined)
  - Tap target on `Retry`: expand 8pt around the text via `hitSlop`-equivalent (`.padding(.vertical, 6).contentShape(Rectangle())`) — meets 44×44pt min via tap area.
- Same vertical location as the offline/syncing caption (currently at [HomeFlowComponents.swift:151](Food%20App/Food%20App/HomeFlowComponents.swift)).
- While retrying: replace `Retry` with a tiny inline spinner (`.controlSize(.mini)`) + the text `Retrying…`. No layout shift.
- Tone: not red, not alarming. Just inform + recover.

#### Implementation
- Replace `unresolvedItemRow` body in [MainLoggingCameraDrawerFlow.swift:11](Food%20App/Food%20App/MainLoggingCameraDrawerFlow.swift) with the inline caption pattern.
- Reuse the same retry logic (`retryUnresolvedItem`); only the chrome changes.

#### Files affected
| File | Action |
|---|---|
| `Food App/MainLoggingCameraDrawerFlow.swift` | MODIFY — rewrite `unresolvedItemRow` |

#### Edge cases
- **Multiple items in a row, one failed** — only the failed item shows the caption. Successfully-parsed items render normally.
- **Network failure vs parse failure** — different wording: network → `Offline · Retry`, parse → `Couldn't parse · Retry`. The string is dynamic based on error type.
- **Retry succeeds** — caption disappears, item renders as a normal parsed item.
- **Retry fails again** — caption stays. No exponential backoff (user-driven).
- **VoiceOver** — the caption is one accessibility element with label "Could not parse turkey sandwich. Tap to retry." plus the Retry action exposed.

#### Test cases
1. Force a parse failure (airplane mode, or kill backend) → row shows quiet caption with underlined `Retry`.
2. Tap `Retry` → spinner shows, caption text changes to `Retrying…`.
3. After server returns → caption disappears, item renders normally.
4. Retry fails → caption returns to `Couldn't parse · Retry`.
5. Compare to offline caption — both look like siblings (same font, weight, color family).
6. VoiceOver navigates to the row → announces the failure + Retry action.

#### Risks
- **Visual hierarchy** — make sure the caption isn't so quiet that users miss it entirely. Use the brand-orange underline on `Retry` to draw the eye.

#### Out of scope
- Differentiating server errors (4xx vs 5xx) in copy.
- Auto-retry with backoff.

---

### Item 8: Rewards screen retry message

#### Problem
The user sees a `retry` message in the rewards screen most of the time and wants to know what's causing it.

#### Investigation plan (Claude does this in <30 min)
- Open `BadgesTrophyCaseView` and `HomeStreakDrawerView`. Find any retry surface.
- Likely culprits:
  - The streak count fails to load on first appear because `HealthKitService.fetchTodaySteps()` or `appStore.refreshCurrentStreak` hasn't completed yet. The view shows a retry text while loading.
  - A network call fails (badge sync, leaderboard) and the view defaults to a retry CTA.
  - The badges list rendering depends on a `currentStreakDays` value that's `nil` until a debounced fetch completes.
- Capture a screenshot from the user (request via the popup) to confirm which surface is showing the retry.

#### Design spec (assuming the cause is a slow first-load)
- Replace `retry` text with a skeleton loader (shimmer rectangles at the same dimensions as the rewards content).
- If the load actually fails (network error), show an inline `Couldn't load badges · Retry` caption (matches Item 3 treatment).

#### Implementation
- Locate the retry message:
  ```
  grep -rn "retry\|Retry" --include="*.swift" "Food App/Food App/" | grep -i "reward\|badge\|streak\|trophy"
  ```
- Inspect the offending view's load lifecycle. Replace blocking-retry copy with skeleton; surface real errors via Item 3's caption pattern.

#### Files affected
| File | Action |
|---|---|
| TBD after investigation | MODIFY |

#### Edge cases
- **HealthKit not authorized** — show a permissions-prompt instead of a retry message.
- **Cold start** — first 1-2 seconds load might show skeleton; that's expected.

#### Test cases
1. Open rewards screen on a fresh launch → skeleton briefly, then content. No `retry` text seen.
2. Kill network → open rewards → caption `Couldn't load badges · Retry` appears, not the legacy `retry` text.
3. Restore network → tap `Retry` → content loads.

#### Risks
- **Hidden cause** — if the retry text is coming from a completely different source than expected, the investigation step needs more time. Budget +1h if so.

#### Out of scope
- Redesigning the rewards screen layout (separate work).

---

## Phase F — Profile / Insights

Items: **5, 6, 7**.
Estimated: ~5h Claude across 2 sessions. **Touches the in-flight Bento Profile initiative.**

### Item 5: Sign-up duplicate-email screen redesign

#### Problem
When a user signs up with an email already in use, they see a screen offering "use existing profile" vs "update profile with new info". The user wants that screen redesigned. The current implementation lives at [ExistingAccountDetectedView.swift](Food%20App/Food%20App/ExistingAccountDetectedView.swift) (per the V3.1 polish plan, this view is recent).

#### Design spec
- Full-screen view, cream gradient background, top-aligned hero block, bottom-aligned action stack.
- Hero (top, 24pt horizontal padding, ~120pt from safe-area top):
  - Title: `Welcome back, [Name]` (32pt InstrumentSerif italic, ink #241914)
  - Subtitle: `We found your account. 47 meals logged, 7-day streak.` (16pt SF Rounded medium, muted #776A61)
- Visual differentiator (middle): a small "your data" preview card — 16pt corner radius, white@0.72, listing 3 stats:
  - Total meals logged (last 30 days)
  - Last active date
  - Goal progress (e.g., calorie target adherence %)
- Action stack (bottom, 32pt horizontal padding, stacked vertically with 12pt gap):
  - Primary: `Continue with my existing account` (brand orange fill, white text, 52pt height, 16pt corner radius)
  - Secondary: `Update my profile with new info` (white background, brand orange text + border, same dimensions)
  - Tertiary: `Cancel — back to sign up` (text-only, 14pt muted ink)
- Safe-area aware: 32pt bottom padding above the home indicator.

#### Implementation
- Refactor `ExistingAccountDetectedView.swift` to the new layout.
- The "your data" stats come from the existing `check-identity` endpoint payload (mealCount, lastActiveAt).
- Add streak count to the endpoint payload (if not present yet).

#### Files affected
| File | Action |
|---|---|
| `Food App/ExistingAccountDetectedView.swift` | MODIFY |
| `backend/src/routes/auth.ts` (or equiv) | MODIFY — extend response with streak |

#### Edge cases
- **Empty data state** — if the existing account has 0 meals, hide the stats card, show a smaller "You have an account but no meals logged yet" caption.
- **Stale name** — if `displayName` is empty, fall back to `Welcome back`.
- **Update profile path** — must NOT touch `food_logs` (per V3.1 plan constraint). The backend endpoint that handles this is already wired; the iOS side just calls it.
- **Cancel goes back to onboarding start** — make sure the back stack is correct.

#### Test cases
1. Sign up with an existing email → screen renders with name + stats.
2. Tap `Continue with existing` → home screen with all old data intact.
3. Tap `Update profile with new info` → existing data preserved + profile fields updated.
4. Tap `Cancel` → back to onboarding entry, no auto-login.
5. Account with 0 meals → stats card hidden, layout adapts.
6. VoiceOver: hero announced first, then stats, then action labels.

#### Risks
- **Endpoint contract** — if the backend doesn't return streak yet, ship in two phases (backend first, iOS second). Otherwise the iOS will show `0-day streak` for a real 7-day streak user.

#### Out of scope
- Multi-account selection (if a user has multiple profiles tied to one identity).

---

### Item 6: Profile section UI — tone down the color

#### Problem
The bento profile dashboard ([HomeProfileBentoScreen.swift](Food%20App/Food%20App/Profile/HomeProfileBentoScreen.swift)) is "too colorful". Maintain some color, but tone it down.

#### Design spec — restraint principles

**Before** (per memory + current code):
- Many tiles, each with its own colored gradient background
- Pencil-edit affordances using brand orange
- KPI numbers in tile-specific accent colors
- High visual energy across the grid

**After**:
- Replace per-tile colored gradients with a **single unified cream surface** (`#FFFBF5` background) for every tile. The grid feels like a single material divided by spacing, not a mosaic.
- Tile borders: 1pt warm border `rgba(72,45,24,0.11)` instead of colored borders.
- Keep color **only** for:
  - **KPI numbers** (e.g., goal calorie target, weight) — in brand orange `#EE7A21`
  - **Action affordances** — small chevron/pencil icons in brand orange
  - **Macro-specific chips** when displayed (use the protein/carbs/fat chip palette from Item 10)
  - **Streak ring** (Activity-style ring at the top — keep the green/orange progress fill)
- Typography hierarchy strengthens via:
  - Tile titles in 13pt SF Rounded bold uppercase, tracking 1.0, muted ink
  - Tile KPI in 28-32pt SF Rounded heavy, ink
  - Tile sublabel in 13pt SF Rounded semibold, muted ink

**Specific element removal**:
- Per-tile colored gradient backgrounds → replaced with unified cream.
- Decorative emoji glyphs on tiles (if any) → replaced with thin-stroke SF Symbols in ink.

**What stays colored**:
- Streak ring (motivational, the core wow moment)
- Brand orange CTAs (`Edit body`, `Edit goals`, etc.)
- Macro chips when shown
- Achievement badges (when surfaced from profile)

#### Implementation
- Audit every tile in `HomeProfileBentoScreen.swift`, every child editor in `Profile/Editors/`, and replace per-tile color tokens with unified ones.
- Move the bento color palette into a single `BentoProfileTokens.swift` enum so future restraint tweaks are one-file edits.
- The streak ring stays in its own tile.
- Editors (`BodyEditorScreen`, `DietEditorScreen`, `TargetsEditorScreen`) get matching restraint — same cream surface, brand orange only for CTAs.

#### Files affected
| File | Action |
|---|---|
| `Food App/Profile/HomeProfileBentoScreen.swift` | MODIFY — strip per-tile gradients |
| `Food App/Profile/Editors/BodyEditorScreen.swift` | MODIFY |
| `Food App/Profile/Editors/DietEditorScreen.swift` | MODIFY |
| `Food App/Profile/Editors/TargetsEditorScreen.swift` | MODIFY |
| `Food App/Profile/BentoProfileTokens.swift` | CREATE |

#### Edge cases
- **Dark mode** — cream surface becomes a warm dark `#2A1F18`. Ink inverts to `#FAEDD8`. Brand orange stays.
- **VoiceOver** — no behavior change, just visual.
- **Dynamic Type at accessibility1** — tiles still need to fit two columns on iPhone SE. Verify nothing wraps weirdly.
- **The streak ring tile** — keep its current visual weight; it's the focal point now.

#### Test cases
1. Open profile from home → cream-toned grid, brand orange only on KPIs + actions.
2. Tap a tile → editor opens with matching restraint.
3. Streak ring still has its colored progress fill.
4. Dark mode → equivalent restraint with warm dark surface.
5. Dynamic Type accessibility1 → grid stays readable, no clipped text.
6. Side-by-side screenshot vs before — clearly calmer.

#### Risks
- **The user may not want full restraint** — some color signals the app's personality. After the first cut, expect a feedback round. Calibrate after TestFlight.
- **Editor screens are mid-refactor** (per Bento Profile memory) — coordinate so we don't undo recent editor work.

#### Out of scope
- Bento layout changes (only color/tone changes here).
- Per-tile customization (user explicitly said NOT needed).

---

### Item 7: Move Daily Targets bento card to graphs section

#### Problem
The Daily Targets bento card lives in the profile/bento dashboard. The user wants it moved to the graphs/Insights section, with Daily Targets at the top and the segmented controller for other graphs below.

#### Design spec
- Remove the Daily Targets tile from `HomeProfileBentoScreen.swift`.
- In `HomeProgressScreen.swift` (the Insights screen), restructure the layout:
  1. **Top** — Daily Targets card (full-width, 16pt corner radius). Shows today's progress toward calorie, protein, carbs, fat targets. Use compact bars with `0/N` style.
  2. **Below** — existing segmented control (W/M/6M/Y picker) for the rest of the charts.
- Daily Targets card visual:
  - Title: `Today's targets` (16pt SF Rounded heavy, ink)
  - 4 horizontal bars stacked, 8pt vertical gap:
    - Calories (brand orange fill)
    - Protein (`#3D2E96`)
    - Carbs (`#1E5C36`)
    - Fat (`#933520`)
  - Each bar: label on left (`Calories · 1,250 / 1,800`), bar centered, percentage on right.
- Below the card: a small `Edit targets` link (brand orange, underlined) → opens the existing TargetsEditorScreen.

#### Implementation
- Move the existing `caloriesHeroCard` content from `HomeProgressCards.swift:35` (or the bento tile equivalent) into a new top-of-screen card in `HomeProgressScreen.swift`.
- Delete the Daily Targets tile from `HomeProfileBentoScreen.swift`.
- Surface the existing `targetsEditorBinding` (or equivalent) for the `Edit targets` link.

#### Files affected
| File | Action |
|---|---|
| `Food App/HomeProgressScreen.swift` | MODIFY — add Daily Targets card on top |
| `Food App/HomeProgressCards.swift` | MODIFY — extract a reusable `DailyTargetsCard` |
| `Food App/Profile/HomeProfileBentoScreen.swift` | MODIFY — remove Daily Targets tile |

#### Edge cases
- **Targets not set** — show a placeholder card: `Set your daily targets` with a CTA. Same dimensions.
- **Bento grid becomes uneven after the tile removal** — re-flow the remaining tiles. If an odd-tile gap appears, swap the order or merge two smaller tiles into a wider one.
- **Insights → Daily Targets → Edit targets → back** — back navigation preserves the segmented control's selected range.

#### Test cases
1. Open Insights → top card shows today's progress for all 4 macros.
2. Open profile bento → no Daily Targets tile.
3. Open Insights, tap `Edit targets` → TargetsEditorScreen opens.
4. Edit a target, save, return → card reflects new target.
5. Empty state (no targets set) → placeholder card with CTA.

#### Risks
- **Bento grid re-flow** — without the Daily Targets tile, layout may look unbalanced. Mitigation: prototype the bento without the tile first, fill the gap with an existing tile resized to span 2 cells.

#### Out of scope
- Animating the bar fills (cosmetic, defer).
- Per-meal target tracking (only daily).

---

## Phase G — Visual chrome (badges, icons, widgets, saved button)

Items: **15, 16, 17, 18**.
Estimated: ~4h Claude across one session. All independent of each other.

### Item 15: Badge celebration screen — keep visible, add fun button

#### Problem
`StreakAchievementPopup` auto-dismisses after 3.5s. The user wants it to stay until they tap a white button at the bottom — and the button copy should be "something fun", not "Okay I understand".

#### Design spec
- Remove the 3.5s auto-dismiss timer.
- Keep `onTapGesture` to dismiss (tap-anywhere stays as a secondary path).
- Add a primary CTA button at the bottom:
  - Style: white fill, ink text `#241914`, 52pt height, full-width minus 32pt horizontal padding, 16pt corner radius.
  - Position: 32pt above the safe-area bottom inset.
  - Subtle drop shadow: `Color.black.opacity(0.16)`, radius 16, y 6.
  - Tap target: meets 44×44pt easily (52pt height).
- Copy options (pick one — recommended **"Let's go"**):
  1. **Let's go** — energetic, forward-looking. (recommended)
  2. **Heck yeah** — enthusiastic, casual.
  3. **Onward** — gentle momentum.
  4. **Stack it up** — playful, food-pun adjacent.
  5. **More to come** — implies streak continues.
  6. **Bring it on** — competitive vibe.

#### Implementation
- In [StreakAchievementPopup.swift:186](Food%20App/Food%20App/StreakAchievementPopup.swift), remove the `dismissTask` 3.5s auto-dismiss block.
- Replace the `Text("Tap to dismiss")` line (line 78) with a full-width white pill button.
- Wire the button's action to `dismissNow()`.

#### Files affected
| File | Action |
|---|---|
| `Food App/StreakAchievementPopup.swift` | MODIFY |

#### Edge cases
- **Reduce motion on** — entrance is already shorter; dismiss animation stays the same (220ms fade).
- **Multiple badges earned in one save** — the popup is presented via `.fullScreenCover(item: $triggeredBadgeAchievement)` in [MainLoggingShellBody.swift:154](Food%20App/Food%20App/MainLoggingShellBody.swift). If multiple badges fire, they'd queue — keep the current per-badge behavior.
- **VoiceOver** — button label is the copy ("Let's go"). Accessibility hint: "Dismiss this celebration."
- **User backgrounds the app** — popup stays modally presented; on return, button is still tappable. Acceptable.

#### Test cases
1. Earn a badge → popup appears with confetti + medal animation.
2. Wait 10 seconds → popup is STILL visible (no auto-dismiss).
3. Tap the white `Let's go` button → popup dismisses smoothly.
4. Earn another badge → popup re-appears.
5. Tap anywhere on the popup (not the button) → also dismisses (fallback path).
6. VoiceOver: button announced as "Let's go button. Dismiss this celebration."

#### Risks
- **Modal blocks navigation** — same as today (it's already a `.fullScreenCover`). No new risk.

#### Out of scope
- Sharing the badge to social.
- Recapping milestones beyond the current badge.

---

### Item 16: Graph icon replacement

#### Problem
The bottom-right dock icon is `chart.bar.fill` (three-bar bar chart, see [MainLoggingDockViews.swift:48](Food%20App/Food%20App/MainLoggingDockViews.swift)). User says it looks "weird".

#### Design spec — three candidates
1. **`chart.line.uptrend.xyaxis`** — line trend with upward arrow. **Recommended.** Signals "progress over time", which matches the Insights screen's actual content (charts of trends, not bars). Most readable at 16pt size.
2. **`chart.xyaxis.line`** — line chart on axes. Less directional, more analytical. OK fallback.
3. **`waveform.path.ecg`** — vital-signs style. Health-app coded, distinctive, but may feel medical / Apple-Health-imitating.

**Recommendation: `chart.line.uptrend.xyaxis`.** The upward-trend semiotics fits a food-tracking app where progress is the point.

- Keep all other dock-button properties: same 60pt outer frame, 48pt inner badge, brand orange tint `Color(red: 0.95, green: 0.47, blue: 0.11)`, ultraThinMaterial shell, same `bottomDockButton` styling.

#### Implementation
- In [MainLoggingDockViews.swift:48](Food%20App/Food%20App/MainLoggingDockViews.swift), change `systemImage: "chart.bar.fill"` to `systemImage: "chart.line.uptrend.xyaxis"`.

#### Files affected
| File | Action |
|---|---|
| `Food App/MainLoggingDockViews.swift` | MODIFY — one line |

#### Edge cases
- **Icon rendering on iOS 16** — `chart.line.uptrend.xyaxis` is available iOS 16+; verify the deployment target.
- **VoiceOver label** — already says "Open progress charts". Keep as-is.

#### Test cases
1. Home screen → dock bottom-right icon is the line-uptrend icon, not bars.
2. Tap → opens HomeProgressScreen (same behavior).
3. Compare visual weight to camera/mic icons → should feel similar (no oversized icon).

#### Risks
- **None.** Trivial change.

#### Out of scope
- Animating the icon (no animation here).

---

### Item 17: Widgets fix (drawer mismatch, height stability, lock-screen calorie bug, tab labels)

This item is **four sub-tasks** wrapped into one.

#### Problem A — Widget drawer doesn't reflect the actual widget
`WidgetSetupGuideView` ([WidgetSetupGuideView.swift](Food%20App/Food%20App/WidgetSetupGuideView.swift)) shows preview widgets with hardcoded mock data (`Text("842")` literal). The user wants the preview to mirror what the real widget shows on the home screen — same layout, same actual data.

#### Problem B — Add Daily Widget card height changes per step
The `interactiveStepCard` in `WidgetSetupGuideView` ([WidgetSetupGuideView.swift:186](Food%20App/Food%20App/WidgetSetupGuideView.swift)) grows vertically as the step text changes between the 4 steps. The user wants a consistent height.

#### Problem C — Lock-screen widget shows wrong calories / clipped on small phones
`FoodCameraWidgetView.calorieProgressAccessory` ([FoodCameraWidget.swift:184](Food%20App/Food%20Camera%20Widget/FoodCameraWidget.swift)) renders the calorie number alongside a fork-knife icon. On small lock screens (iPhone SE, mini), 3-digit numbers like "842" get clipped to "8" via SwiftUI's truncation in a tight HStack.

#### Problem D — Tab labels "Home" / "Lock" should be "Home Screen" / "Lock Screen"
The mode picker in `WidgetSetupGuideView` ([WidgetSetupGuideView.swift:159](Food%20App/Food%20App/WidgetSetupGuideView.swift)) uses `mode.rawValue` ("Home" / "Lock") instead of the existing `eyebrow` strings ("Home Screen" / "Lock Screen").

#### Design spec

**A — Widget preview reflects actual widget content**
- Inject the current `FoodWidgetCaloriesSnapshot` (read from the shared app group) into the preview strip.
- Render the real consumed / target calories and macros in the small home-screen preview.
- Lock-screen preview uses the same snapshot.
- If snapshot is unavailable (first launch), fall back to placeholder values like "1,250 / 1,770" with a subtle `Sample data` label.

**B — Fixed card height**
- Wrap the per-step text container in a fixed-height block: `.frame(minHeight: 64, alignment: .topLeading)`.
- Long-step text wraps to 3 lines max (`.lineLimit(3)`) with `.minimumScaleFactor(0.92)` to absorb minor overflow without resizing the card.
- Set the entire card a `.frame(minHeight: 280)` so step-to-step changes don't shift the layout.

**C — Lock-screen widget calorie display**
- Restructure `calorieProgressAccessory`:
  - Drop the fork-knife icon from `accessoryRectangular` (it's redundant — the widget icon is already shown by iOS).
  - Use two lines: `842 kcal` on line 1, progress bar + `of 1,770` on line 2.
  - Use `.minimumScaleFactor(0.72)` and `.lineLimit(1)` to prevent clipping.
  - Test on iPhone SE 3rd gen (smallest current lock-screen widget area).

**D — Tab labels**
- In `WidgetGuideMode`, change `rawValue` to `"Home Screen"` / `"Lock Screen"` (the existing `eyebrow` strings).
- Or simpler: in the modePicker, use `mode.eyebrow` instead of `mode.rawValue` for the button text.

#### Implementation
- A: Read `FoodWidgetCaloriesSnapshot` from the shared `UserDefaults(suiteName:)` in `WidgetSetupGuideView`, pass it down to the preview strip, render real values.
- B: One-line `.frame(minHeight:)` add to both the step text container and the outer card.
- C: Refactor `calorieProgressAccessory` to a vertical stack, drop the icon, add `minimumScaleFactor`.
- D: One-line change in `modePicker`.

#### Files affected
| File | Action |
|---|---|
| `Food App/WidgetSetupGuideView.swift` | MODIFY — A, B, D |
| `Food Camera Widget/FoodCameraWidget.swift` | MODIFY — C |

#### Edge cases
- **Snapshot is empty** (no logs today) → preview shows `0 / 1,770 kcal` with empty progress bar. Tag as `Live preview`.
- **Snapshot is stale** (>1h old) → still render the snapshot; refresh on app foreground (via existing snapshot refresh in `AppStore`).
- **Lock screen accessory at large size class** — iPhone 16 Pro Max lock screen has more room; still apply the new layout (no need to revert to icon).
- **iOS 16 vs iOS 17 widget container backgrounds** — keep the existing `.containerBackground(.fill.tertiary, for: .widget)` modifier.

#### Test cases
1. Open Profile → Widgets drawer → preview shows the user's actual calories (e.g., their real 1,250 today).
2. Tap the next/previous step buttons → card height stays the same.
3. Add the lock-screen widget on iPhone SE → calories display fully (3-digit shows as "842" not "8").
4. Add the lock-screen widget on iPhone 16 Pro Max → same layout, also unclipped.
5. Mode picker → buttons say "Home Screen" and "Lock Screen", not "Home" and "Lock".
6. With no meals logged today → preview shows `0 / target` cleanly.

#### Risks
- **Widget extension talks to app group via UserDefaults** — make sure the iOS app reads from the same suite as the extension writes to. App group ID: `group.com.shantanu.foodapp` ([FoodCameraWidget.swift:6](Food%20App/Food%20Camera%20Widget/FoodCameraWidget.swift)).
- **Widget refresh timeline** — `getTimeline` returns `policy: .after(30 min)`. Snapshot updates after each save via app code; verify the snapshot write call exists (search for `widget.dailyCaloriesSnapshot`).

#### Out of scope
- New widget sizes.
- Live activity widget.
- Interactive widget actions (camera/mic shortcuts already work).

---

### Item 18: Saved meals button — always visible, no bookmark icon

#### Problem
The "Saved" chip (bookmark icon + word "Saved") only appears in the dock when the keyboard is up ([MainLoggingDockViews.swift:67-96](Food%20App/Food%20App/MainLoggingDockViews.swift)). The user wants it always visible, without the word "Saved", with an icon that's not the bookmark.

#### Design spec
- **Always visible**: render the saved-meals button as a 48pt circle dock button (matching camera/mic style), not a pill chip.
- **Icon recommendation**: `tray.full.fill` — semantically "things you've stashed", visually distinct from bookmark. Alternates considered:
  - `square.stack.fill` — stack of items; OK but more abstract
  - `folder.fill` — too "file system"
  - `heart.fill` — emotion-coded; conflicts with future "favorites" semantics
- **Placement**: in the right-side cluster, *between* the streak trophy and the chart button. Order from left to right: `[streak][saved][chart]`. Reasoning: the streak is the "history" / motivational anchor; saved meals is a "recall" affordance; chart is "analytics". They group naturally.
- **Color**: brand orange `Color(red: 0.95, green: 0.47, blue: 0.11)` to match the chart button (both are right-side action affordances).
- **No label**: the icon stands on its own.
- **Accessibility label**: "Open saved meals".

#### Implementation
- In [MainLoggingDockViews.swift:44](Food%20App/Food%20App/MainLoggingDockViews.swift), the right-side `HStack(spacing: 12) { streakDockIndicator; bottomDockButton(... "chart...") }` becomes:
  ```
  HStack(spacing: 12) {
      streakDockIndicator
      bottomDockButton(systemImage: "tray.full.fill", color: ..., accessibilityLabel: "Open saved meals") {
          isSavedMealsPresented = true
      }
      bottomDockButton(systemImage: "chart.line.uptrend.xyaxis", color: ..., accessibilityLabel: "Open progress charts") {
          isProgressChartsPresented = true
      }
  }
  ```
- Remove the keyboard-only `savedMealsKeyboardChip` and the `if isKeyboardVisible` branch (lines 57-60).
- Update the `MainLoggingBottomDock` `@Binding var isSavedMealsPresented: Bool` is already in place, so the binding works.

#### Files affected
| File | Action |
|---|---|
| `Food App/MainLoggingDockViews.swift` | MODIFY |

#### Edge cases
- **Layout collision** — 4 buttons + 1 streak indicator + 2 left buttons = a lot on small screens. Measure on iPhone SE (375pt width). Spacing budget: `60pt × 5 = 300pt` plus `12pt × 3 spacers = 36pt` plus side padding 16pt × 2 = 32pt; total 368pt — fits with 7pt to spare. If tight, reduce the central `Spacer(minLength: 12)` to 8pt.
- **VoiceOver order** — left to right: camera, mic, [spacer], streak, saved, chart. Should announce in that order.
- **Keyboard up** — saved button stays visible (this is the user's main ask); the dock should not jump positions when the keyboard appears.
- **Streak indicator's number badge** — the small 20pt badge with the streak count must not overlap the saved button's tap target. The streak's 8pt padding on the badge keeps it inside the 60pt frame.

#### Test cases
1. Home screen, no keyboard → dock shows camera, mic, streak, saved (tray icon), chart.
2. Tap text input → keyboard slides up → dock layout does NOT shift; saved button stays.
3. Tap saved button → SavedMealsScreen sheet opens.
4. Compare to before screenshot: saved button is now where the user expects, always there.
5. iPhone SE width → no overflow, no truncation.
6. VoiceOver: navigates left-to-right through dock; saved button reads "Open saved meals".

#### Risks
- **Visual crowding on small phones** — measured above; should be OK. If tight, reduce the central spacer.
- **The keyboard-up moment** — keyboard chip used to be a hint that pressing Save would open saved meals. Without it, the user may not realize. Mitigation: the always-visible button covers the same affordance.

#### Out of scope
- New saved-meal interactions.
- Customizing the icon per user choice.

---

## Phase H — Validation pass + family rollout

Items: **(implicit — closeout)**.
Estimated: ~30 min Claude + 1-2h user testing.

#### What Claude does
- Pull production DB metrics:
  - `food_logs` `input_kind` distribution before/after these changes
  - Any new error spikes (parse failures, save failures)
  - Lane distribution still healthy (barcode, label, vision)
- Generate a release-notes diff against `main`.

#### What the user does
- Test 10-15 real meals on TestFlight build covering all phases.
- Invite 3-5 family/friends if confidence is high.
- Watch DB + feedback channel for one week.

#### Acceptance
- All 18 backlog items have shipped and been confirmed working on device.
- No new crash reports.
- No regression in save/parse success rates.

---

## Sequencing & dependencies (cheat sheet)

| Phase | Depends on | Ships with | TestFlight cycles |
|---|---|---|---|
| E (Error/Retry UX) | nothing | 1 push | 1 |
| D (Camera lens) | nothing | 1 push | 1 |
| G (Visual chrome) | nothing | 1 push (bundled) | 1 |
| B (Tips popup + Gemini) | nothing | 1 push | 1 |
| A (Tutorial v2) | nothing (but ideally after Bs/Gs are visible) | 1 push | 1 |
| C (Drawer + pickers) | A (so tutorial matches) | 1 push | 2 (drawer + pickers shake out bugs) |
| F (Profile + bento) | C (uses macro chips) | 1 push | 2 |
| H (Validation) | E,D,G,B,A,C,F all merged | — | — |

**Total TestFlight cycles**: ~8 across 10-14 days.

---

## Risks that span the whole plan

1. **Touching the in-flight Bento Profile initiative (Item 6, 7)** — the user has paused Bento at Step 4. Phase F may collide with that. Mitigation: do Phase F last; reconfirm with the user before starting that Bento is OK to revisit.
2. **V3.1 polish plan overlap** — Items 9 (camera lens) and the V3.1 plan's "Camera v2" (custom AVCaptureSession) already exist in the codebase. Phase D is a config tweak on top of what's already there; no conflict.
3. **Profile redesign sentiment** — the user said "tone down but maintain some color". A first pass that overshoots into "too sterile" is likely; budget a second iteration after the user reviews on device.
4. **Drawer redesign + new pickers in the same phase** — large change. Split into Phase C1 (scaffold + visual) and Phase C2 (native pickers) if device testing surfaces too much at once.

---

## Out of scope (Memorial Day, capture as backlog)

- Personalized tips ("you forget portion size on lunch"). Needs telemetry.
- Brand-aware portions ("Starbucks tall"). Needs partner data.
- Photo-based portion estimation. Needs ML work.
- Multi-account / household support.
- Localization beyond English.
- Live activity widget.
- Sharing badges to social.
- iPad / landscape adaptive layout (user explicitly said NOT needed in Bento).

---

## Stop conditions

Stop and reassess if:
- **Phase C drawer redesign takes more than 8h Claude work total** — split it into smaller pieces.
- **Phase F destabilizes Bento Profile** — back out, ship the rest, return to F separately with user oversight.
- **A real-device crash surfaces in any phase** — fix immediately before stacking the next phase on top.
- **The user pivots priorities mid-week** — re-plan; don't push through a plan that's no longer the highest value.
- **TestFlight feedback finds a class of bugs not anticipated** — pivot to fix those before continuing.

---

## Commit message templates

```
Phase E: parse-failure inline retry caption + investigate rewards retry text
Phase D: camera defaults to primary 1x lens
Phase G: badge popup button + graph icon + saved-dock + widget fixes
Phase B: logging-tips popup + de-mention Gemini in thought process
Phase A: tutorial v2 (next/next/done) + day-swipe interactive tutorial
Phase C: unified logging drawer scaffold + macro chips + per-item rows
Phase C2: native serving qty + unit pickers (collapsible wheels)
Phase F1: Daily Targets card relocated to Insights top
Phase F2: profile bento restraint pass (cream + brand accent only)
Phase F3: existing-account-detected screen redesign
Phase H: validation pass + family rollout
```

End of plan.
