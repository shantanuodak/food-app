# iOS UI Framework Plan v1 (Flow-First, Design-Later)

## 1) Objective
Build all core app flows and screen frameworks first, with minimal visual styling, so Figma design can be applied later without changing behavior or API contracts.

## 2) Source of Truth
- `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/UI Workflow Brainstorming.md`
- `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/PRD_MVP_Food_Logging.md`
- `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/IMPLEMENTATION_SPEC_MVP.md`
- `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/JIRA_BACKLOG_MVP.md`

## 3) Execution Rules
1. Behavior first, visuals second.
2. Every screen must ship with `default`, `loading`, `error`, and `disabled` states where applicable.
3. API contracts remain unchanged while screens evolve.
4. Navigation and state transitions must be explicit and testable.
5. Keep components reusable and named by role, not by visual style.

## 4) Screen Inventory (Framework Scope)

### 4.1 Onboarding (from UI Workflow Brainstorming)
1. `OB_01_Welcome`
2. `OB_02_Goal`
3. `OB_03_Baseline`
4. `OB_04_Activity`
5. `OB_05_Pace`
6. `OB_06_Preferences_Optional`
7. `OB_07_Plan_Preview`
8. `OB_08_Account`
9. `OB_09_Permissions`
10. `OB_10_Ready`

### 4.2 In-App Core Logging (from MVP PRD/spec)
1. `HM_01_LogComposer` (notes input + parse trigger)
2. `HM_02_ParseSummary` (totals/confidence/route)
3. `HM_03_ParseDetailsDrawer` (item edits + assumptions)
4. `HM_04_ClarificationEscalation` (questions + escalate actions)
5. `HM_05_SaveRetryState` (idempotent save/retry states)
6. `HM_06_DaySummary` (totals/targets/remaining for selected date)
7. `HM_07_GlobalErrorBanner` (API envelope surfaced to user)

## 5) Canonical Navigation Map
1. App launch -> `OB_01_Welcome`
2. `OB_01_Welcome` primary -> `OB_02_Goal`
3. `OB_02_Goal` -> `OB_03_Baseline`
4. `OB_03_Baseline` -> `OB_04_Activity`
5. `OB_04_Activity` -> `OB_05_Pace`
6. `OB_05_Pace` -> `OB_06_Preferences_Optional`
7. `OB_06_Preferences_Optional` continue/skip -> `OB_07_Plan_Preview`
8. `OB_07_Plan_Preview` looks-good -> `OB_08_Account`
9. `OB_08_Account` success -> `OB_09_Permissions`
10. `OB_09_Permissions` continue -> `OB_10_Ready`
11. `OB_10_Ready` primary -> `HM_01_LogComposer`
12. In-app logging loop: `HM_01` -> `HM_02` -> `HM_03/HM_04` -> `HM_05` -> `HM_06`

## 6) Screen Contracts (Build Checklist)

| Screen | Inputs | Actions | Outputs |
|---|---|---|---|
| `OB_01_Welcome` | none | Start / Existing-account | route forward |
| `OB_02_Goal` | selected goal | choose goal, continue, back | onboarding draft update |
| `OB_03_Baseline` | age/sex/height/weight | edit fields, continue, back | validation + maintenance estimate token |
| `OB_04_Activity` | activity option | select, continue, back | updated calorie token |
| `OB_05_Pace` | pace option | select, continue, back | projected milestone token |
| `OB_06_Preferences_Optional` | chips[] | select chips, continue, skip | preference draft update |
| `OB_07_Plan_Preview` | computed targets | looks-good / adjust / back | go account or back edit |
| `OB_08_Account` | provider choice | Apple/Google/Email, back | loading/success/error |
| `OB_09_Permissions` | health + notif states | allow/deny + continue | permission statuses persisted |
| `OB_10_Ready` | none | log-first-meal / explore | enter home |
| `HM_01_LogComposer` | text input | parse now, open details | parse request state |
| `HM_02_ParseSummary` | parse response | inspect confidence/totals | ready for edit/save |
| `HM_03_ParseDetailsDrawer` | parse items | edit item fields | save payload draft |
| `HM_04_ClarificationEscalation` | clarification payload | escalate parse | resolved parse or blocked state |
| `HM_05_SaveRetryState` | save payload + idempotency key | save, retry last save | save success/error/replay |
| `HM_06_DaySummary` | selected date | refresh/date change | totals/targets/remaining |

## 7) Implementation Phases

### Phase A: App Flow Coordinator
- Create route enums and one source of navigation truth.
- Add onboarding draft state model (in-memory + persistence).
- Add debug route jump support for QA.
- Exit criteria: can navigate through all screens with placeholder content.

### Phase B: Onboarding Framework (OB_01 to OB_10)
- Implement all 10 onboarding screens as wireframes.
- Enforce progress rules from brainstorming doc (`OB_02` to `OB_07`).
- Wire back navigation exactly per spec.
- Exit criteria: full onboarding prototype works end-to-end in app.

### Phase C: Main Logging Framework (HM_01 to HM_06)
- Keep existing parse/save/day-summary logic.
- Refactor into explicit screen modules and state reducers.
- Normalize empty/loading/error variants per screen.
- Exit criteria: full meal logging path works with current backend.

### Phase D: QA States + Contract Guards
- Add force-state debug toggles for auth, validation, offline, budget.
- Ensure each screen has deterministic UI for known error codes.
- Exit criteria: E2E manual checks can be executed without custom hacks.

### Phase E: Figma-Ready Handoff
- Freeze component IDs and screen IDs.
- Document where design tokens will be applied.
- Exit criteria: design pass can proceed without logic rewrites.

## 8) Deliverables
1. `AppFlow` routing/state module.
2. `Onboarding` screen modules for `OB_01...OB_10`.
3. `Home` screen modules for `HM_01...HM_06`.
4. UI state matrix doc for all screen states.
5. Design handoff anchor doc mapping Figma frames to code screens.

## 9) Suggested Build Order (Immediate)
1. Build `OB_01` + route shell.
2. Add `OB_02...OB_07` with progress + value-card placeholders.
3. Add `OB_08...OB_10` account/permissions/ready framework.
4. Integrate with existing `HM_*` flow.
5. Add debug toggles for forced states.

## 10) Out of Scope for This Phase
1. High-fidelity visual polish.
2. Final motion tuning for production.
3. Paywall flow.
4. New backend features beyond existing contracts.
