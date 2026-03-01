# iOS E2E-005 - Beta Release Readiness and TestFlight Handoff

## 1) Goal
Prepare a controlled closed-beta handoff for the iOS app with clear go/no-go criteria, rollback instructions, and a repeatable feedback loop.

## 2) Acceptance criteria mapping
- TestFlight build checklist completed:
  - Covered by sections 3, 4, 5.
- Environment and rollback notes documented:
  - Covered by sections 6, 7.
- Beta feedback intake loop defined:
  - Covered by section 8.

## 3) Entry gates (must be green before packaging)
- Backend integration suite passes:
  - `DATABASE_URL_TEST='postgres://shantanuodak@localhost:5432/food_app_test' npm run test:integration`
- E2E baseline complete:
  - API E2E rows are `PASS` in `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/E2E_QA_MATRIX_MVP.md`.
  - iOS manual rows for core flow are `PASS` (IOS-E2E-01 through IOS-E2E-06).
- Required docs exist:
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/API_HANDOFF_IOS_MVP.md`
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/KNOWN_LIMITATIONS_MVP.md`
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/ALERT_RUNBOOK_MVP.md`

## 4) TestFlight packaging checklist (iOS owner)
- [ ] Confirm scheme uses the correct beta environment values in `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/AppConfiguration.swift`.
- [ ] In Xcode: Product -> Archive succeeds for the iOS target.
- [ ] In Organizer: Distribute App -> App Store Connect -> Upload succeeds.
- [ ] Add release notes containing:
  - Build number
  - Scope tested (onboarding, parse, save, day summary, escalation gate behavior)
  - Known limitations link
- [ ] Assign internal/external tester group and set expiry expectations.

## 5) Beta smoke test checklist (post-upload)
- [ ] Fresh install:
  - Complete onboarding and land on Food Log screen.
- [ ] Parse flow:
  - Enter food text and verify totals render.
- [ ] Save + retry:
  - Save once, then trigger retry path and verify no duplicate save side effects.
- [ ] Day summary:
  - Verify saved log affects correct day totals.
- [ ] Clarification path:
  - Use low-confidence input and verify clarification + escalation disabled/enabled messaging.
- [ ] Error surfaces:
  - Verify user sees actionable messages for auth/validation/network failure paths.

## 6) Environment notes
- Local/dev:
  - Base URL and flags are sourced from `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/AppConfiguration.swift`.
- Backend runtime controls to verify before beta:
  - `AI_ESCALATION_ENABLED`
  - budget limits used by fallback/escalation guard
  - auth token format expected by middleware
- Internal metrics endpoint:
  - Keep protected and key-gated; do not expose in beta user-facing UI.

## 7) Rollback playbook
- iOS rollout rollback:
  - Stop adding new testers to the beta group.
  - Expire or remove the problematic build from active testing groups in App Store Connect.
- Backend rollback:
  - Revert/deploy last known-good backend image.
  - If incident is AI-cost related, immediately disable escalation via config and keep deterministic path active.
- Communication:
  - Post incident summary to beta channel with workaround and ETA.
  - Link related runbook: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/ALERT_RUNBOOK_MVP.md`.

## 8) Feedback intake loop (defined process)
- Intake channel:
  - TestFlight feedback + one Jira intake ticket per unique issue.
- Required fields on each ticket:
  - Build number
  - Device + iOS version
  - Repro steps
  - Expected vs actual
  - Screenshot/video
  - `requestId` if API error was shown
- Triage SLA:
  - P0 within 4 hours
  - P1 within 1 business day
  - P2 batched into next sprint planning
- Weekly review:
  - Cluster feedback into themes (onboarding friction, parse quality, save reliability, summary correctness).
  - Convert top themes into backlog stories with story points.

## 9) Sign-off block
- Beta coordinator: `TBD`
- iOS owner: `TBD`
- Backend owner: `TBD`
- Go/No-Go decision: `PENDING`
- Decision date: `PENDING`
