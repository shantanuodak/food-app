# UI Workflow Brainstorming

## Onboarding Flow Spec (Pre-App)
Version: `v1`  
Scope: onboarding only, ends before user enters Home.  
Paywall: excluded for now.

## Global Rules
1. Theme defaults to `System` (inherits device light/dark).
2. Onboarding supports both themes automatically.
3. Progress indicator visible on screens `OB_02` to `OB_07`.
4. Pattern on each data screen: `Question -> Input -> Instant value card -> Continue`.
5. Primary button label is always `Continue` unless specified.
6. One main decision per screen.
7. “Skip” allowed only on preferences screen.

## Frame Order (Build These)
1. `OB_01_Welcome`
2. `OB_02_Goal`
3. `OB_03_Baseline`
4. `OB_04_Activity`
5. `OB_05_Tracking_Style`
6. `OB_06_Preferences_Optional`
7. `OB_07_Setup_Preview`
8. `OB_08_Account`
9. `OB_09_Permissions`
10. `OB_10_Ready`

## Screen Content

### OB_01_Welcome
- Headline: `Log your food with less effort`
- Subhead: `Set up tracking in under 2 minutes.`
- Primary CTA: `Start`
- Secondary CTA: `I already have an account`
- Footer note: `You can edit everything later.`

### OB_02_Goal
- Headline: `What’s your goal right now?`
- Subhead: `We’ll use this to focus your food logging insights.`
- Options: `Lose fat`, `Maintain weight`, `Gain muscle`
- Value card title: `Tracking focus`
- Value card body: `Great, we’ll tailor your summaries for [Goal].`
- CTA: `Continue`
- Back: enabled

### OB_03_Baseline
- Headline: `Let’s set your baseline`
- Subhead: `This helps us improve calorie and macro estimates while you log.`
- Fields: `Age`, `Sex`, `Height`, `Current weight`
- Value card title: `Estimate quality`
- Value card body: `Nice, your entries can now be estimated more accurately.`
- CTA: `Continue`
- Back: enabled
- Validation copy: `Please complete all fields.`

### OB_04_Activity
- Headline: `How active are you most days?`
- Subhead: `This helps us put your logged calories in the right daily context.`
- Options: `Mostly sitting`, `Lightly active`, `Moderately active`, `Very active`
- Value card title: `Activity context added`
- Value card body: `Your daily summaries will now reflect this activity level.`
- CTA: `Continue`
- Back: enabled

### OB_05_Tracking_Style
- Headline: `How detailed should tracking be?`
- Subhead: `Choose how much detail you want to see while logging.`
- Options: `Simple logging`, `Calories + macros`, `Detailed breakdown`
- Value card title: `Tracking style selected`
- Value card body: `Perfect, we’ll show [Tracking Style] by default.`
- CTA: `Continue`
- Back: enabled

### OB_06_Preferences_Optional
- Headline: `Any preferences?`
- Subhead: `Optional, but this helps us tailor suggestions.`
- Chips: `High protein`, `Vegetarian`, `Vegan`, `Low carb`, `No preference`
- Value card title: `Personalization`
- Value card body: `We’ll prioritize foods and matches that fit your preferences.`
- Primary CTA: `Continue`
- Secondary CTA: `Skip for now`
- Back: enabled

### OB_07_Setup_Preview
- Headline: `Your logging setup is ready`
- Subhead: `You can start logging food now and adjust these anytime.`
- Card labels: `Daily calorie guide`, `Macro tracking`, `Preference filters`, `Reminders`
- Trend label: `Your progress updates as you log`
- Note: `You can change all of this later in Settings.`
- Primary CTA: `Start logging`
- Secondary CTA: `Edit setup`
- Back: enabled

### OB_08_Account
- Headline: `Save your setup`
- Subhead: `Keep your progress synced across devices.`
- Buttons: `Continue with Apple`, `Continue with Google`, `Use email instead`
- Note: `No spam. Just account essentials.`
- Back: enabled

### OB_09_Permissions
- Headline: `Get more from the app`
- Subhead: `Optional permissions that make tracking easier.`
- Block 1 title: `Apple Health`
- Block 1 body: `Sync activity and energy data automatically.`
- Block 1 actions: `Connect Health`, `Not now`
- Block 2 title: `Notifications`
- Block 2 body: `Helpful reminders to stay consistent.`
- Block 2 actions: `Enable reminders`, `Not now`
- Primary CTA: `Continue to app`
- Back: enabled

### OB_10_Ready
- Headline: `You’re all set`
- Subhead: `Log your first meal to start your streak.`
- Primary CTA: `Log first meal`
- Secondary CTA: `Explore app`

## Progress Step Labels
1. Goal
2. Baseline
3. Activity
4. Tracking Style
5. Preferences
6. Setup
7. Finish

## Dynamic Tokens
1. `[Goal]`
2. `[Tracking Style]`
3. `[X] kcal/day`
4. `[Protein g]`
5. `[Carbs g]`
6. `[Fat g]`

## Figma Checklist (Onboarding Only)

### File and Section
1. Page name: `01_Onboarding_v1`
2. Section name: `ONBOARDING_FLOW`
3. Frame size: `iPhone 16 Pro` (or your chosen canonical size, use one consistently)
4. Theme variants per frame: `System-Light` and `System-Dark` preview states

### Frame Naming (Exact)
1. `OB_01_Welcome`
2. `OB_02_Goal`
3. `OB_03_Baseline`
4. `OB_04_Activity`
5. `OB_05_Tracking_Style`
6. `OB_06_Preferences_Optional`
7. `OB_07_Setup_Preview`
8. `OB_08_Account`
9. `OB_09_Permissions`
10. `OB_10_Ready`

### Layer Naming Standard
1. `TopBar`
2. `Progress` (hidden on `OB_01`, `OB_08`, `OB_10`)
3. `Content`
4. `Title`
5. `Subtitle`
6. `InputGroup` (or `OptionGroup` / `ChipGroup`)
7. `ValueCard` (title + body)
8. `PrimaryCTA`
9. `SecondaryCTA` (if exists)
10. `BackCTA` (except `OB_01`)
11. `FooterNote` (if exists)

### Core Components to Create First
1. `cmp/topbar/default`
2. `cmp/progress/stepper_7`
3. `cmp/button/primary`
4. `cmp/button/secondary`
5. `cmp/button/provider_apple`
6. `cmp/button/provider_google`
7. `cmp/input/text`
8. `cmp/input/number`
9. `cmp/option/tile_single_select`
10. `cmp/chip/multi_select`
11. `cmp/card/value_feedback`
12. `cmp/card/logging_metric`
13. `cmp/permission/block`
14. `cmp/nav/back_fab`

### Variables and Tokens (Minimum)
1. `color/bg/base`
2. `color/bg/elevated`
3. `color/text/primary`
4. `color/text/secondary`
5. `color/brand/primary`
6. `color/border/default`
7. `space/4,8,12,16,20,24,32`
8. `radius/12,16,20,full`
9. `type/title`
10. `type/body`
11. `type/caption`
12. `theme/mode` with values: `system`, `light`, `dark`

### Prototype Wiring (Exact)
1. `OB_01_Welcome` primary -> `OB_02_Goal`
2. `OB_02_Goal` continue -> `OB_03_Baseline`
3. `OB_03_Baseline` continue -> `OB_04_Activity`
4. `OB_04_Activity` continue -> `OB_05_Tracking_Style`
5. `OB_05_Tracking_Style` continue -> `OB_06_Preferences_Optional`
6. `OB_06_Preferences_Optional` continue/skip -> `OB_07_Setup_Preview`
7. `OB_07_Setup_Preview` start logging -> `OB_08_Account`
8. `OB_08_Account` success -> `OB_09_Permissions`
9. `OB_09_Permissions` continue -> `OB_10_Ready`
10. `OB_10_Ready` primary -> `HOME_ENTRY_PLACEHOLDER`

### Back Navigation Wiring
1. `OB_02` back -> `OB_01`
2. `OB_03` back -> `OB_02`
3. `OB_04` back -> `OB_03`
4. `OB_05_Tracking_Style` back -> `OB_04`
5. `OB_06` back -> `OB_05_Tracking_Style`
6. `OB_07_Setup_Preview` back -> `OB_06`
7. `OB_08` back -> `OB_07`
8. `OB_09` back -> `OB_08`
9. `OB_10` no back

### Per-Screen Content Slots
1. `Title`
2. `Subtitle`
3. `ValueCard/Label`
4. `ValueCard/Body`
5. `PrimaryCTA/Label`
6. `SecondaryCTA/Label`
7. `FooterNote`

### States to Include (Must Design)
1. `Default`
2. `Selected option`
3. `Disabled continue` (before valid input)
4. `Validation error` (baseline fields)
5. `Loading` (account continue)
6. `Permission denied info` (permissions screen)

### QA Checklist Before Handoff
1. All 10 frames use same spacing grid.
2. Continue button position is consistent across all screens.
3. Text fits in both Light and Dark without contrast issues.
4. `theme/mode=system` previewed in both light and dark contexts.
5. Every frame has forward and back prototype links (except defined exceptions).
6. Dynamic placeholders exist: `[Goal]`, `[Tracking Style]`, `[X kcal]`, `[Protein]`, `[Carbs]`, `[Fat]`.

## Home Input Interaction Update (Post-Onboarding)
Purpose: implementation notes for the coding thread after onboarding is complete.

### Bottom Action Dock
1. Keep `mic`, `camera`, and `plus` in a fixed bottom dock above the keyboard/safe area.
2. Dock remains visible when keyboard is closed and when keyboard is open.
3. Typing is the default mode if no icon is selected.

### Keyboard Behavior
1. Home screen loads with keyboard closed.
2. Input field is visible but not focused on load.
3. Keyboard opens only when user taps the text input (typing intent).
4. Keyboard does not auto-open when entering Home.

### Mode Behavior
1. Default mode: text input mode with no icon selected.
2. Tapping `mic` enters voice mode and highlights `mic`.
3. Tapping `camera` enters camera mode and highlights `camera`.
4. Tapping `plus` opens manual add options and highlights `plus` while active.
5. If the user starts typing while another mode is active, return to text mode automatically.
6. After voice/camera inserts a result, keep keyboard closed unless the user taps input again.

### AI Calorie Estimate Placement
1. Show estimated calories as plain text on the right side of the active input row.
2. Attach a small AI icon next to the calorie number.
3. Keep the estimate visually subtle (not dominant brand color).

### Confidence-Based Confirmation Drawer
1. High confidence (`>= 0.85`): show inline calories only; no interruption.
2. Medium confidence (`0.60` to `0.84`): keep inline estimate and auto-open compact confirmation drawer after a short pause.
3. Low confidence (`< 0.60`) or ambiguity: auto-open full confirmation drawer and require confirmation before logging.
4. If user continues typing, update the same drawer state instead of opening multiple drawers.
