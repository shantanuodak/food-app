# Jira Backlog: Food Logging MVP (End-to-End)

## 1. Usage Notes
- Scope: End-to-end MVP (backend + iOS frontend + design + launch readiness).
- Source docs:
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/PRD_MVP_Food_Logging.md`
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/IMPLEMENTATION_SPEC_MVP.md`
- Sizing: Fibonacci story points.
- Priority scale: P0 (must), P1 (high), P2 (normal).

## 2. Epics
- `EPIC-1` Foundation and Data Layer
- `EPIC-2` Deterministic Parse and Log APIs
- `EPIC-3` AI Fallback and Clarification Flow
- `EPIC-4` Cost Controls and Observability
- `EPIC-5` Quality, Replay Tests, and Launch Readiness
- `EPIC-6` iOS App Foundation and Networking
- `EPIC-7` iOS Onboarding and Logging Experience
- `EPIC-8` Design System and Figma Handoff
- `EPIC-9` End-to-End QA and Beta Launch Readiness
- `EPIC-10` Requirements Delta Alignment (2026-02-28)

## 3. Ticket List

### EPIC-1: Foundation and Data Layer

#### BE-001 Create initial database schema migration
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: None
- Description: Add initial Postgres schema for users, onboarding profiles, food logs, food log items, parse cache, and AI cost events.
- Acceptance Criteria:
  - Migration creates all MVP tables and constraints.
  - Foreign keys and confidence checks are enforced.
  - Indexes exist for `food_logs`, `food_log_items`, `parse_cache`, and `ai_cost_events`.
  - Migration is idempotent in local dev.

#### BE-002 Add migration runner and local DB bootstrap
- Type: Story
- Priority: P0
- Points: 3
- Dependencies: BE-001
- Description: Ensure backend service can apply schema on startup/dev command.
- Acceptance Criteria:
  - One command applies pending migrations.
  - Fresh local environment can boot with DB ready.
  - Failure logs are actionable and include migration name.

#### BE-003 Implement auth middleware and request identity propagation
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: BE-002
- Description: Validate user auth token and propagate `user_id` + `request_id`.
- Acceptance Criteria:
  - Unauthorized requests to protected endpoints return 401.
  - Valid token maps to `user_id` in request context.
  - `request_id` is present in logs and error responses.

#### BE-004 Add API validation/error envelope standard
- Type: Story
- Priority: P0
- Points: 3
- Dependencies: BE-003
- Description: Standardize input validation and consistent API error envelope.
- Acceptance Criteria:
  - Invalid payloads return 400 with structured error body.
  - Error response includes machine code and human-readable message.
  - Response format matches implementation spec.

### EPIC-2: Deterministic Parse and Log APIs

#### BE-005 Implement onboarding endpoint `POST /v1/onboarding`
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: BE-004
- Description: Persist onboarding answers and return computed targets.
- Acceptance Criteria:
  - Stores onboarding profile per user.
  - Returns calorie and macro targets.
  - Re-running endpoint updates profile without duplicates.
  - Onboarding persistence follows one locked integrity mode:
    - Mode A: full onboarding inputs, or
    - Mode B: computed targets with provenance metadata (`calculatorVersion`, `inputsHash`, `computedAt`).
  - Stored mode is auditable in API/DB logs.

#### BE-006 Build deterministic parser v1 (quantities, units, food phrases)
- Type: Story
- Priority: P0
- Points: 8
- Dependencies: BE-004
- Description: Parse free text into food segments and basic quantity/unit extraction.
- Acceptance Criteria:
  - Handles common patterns (`2 eggs`, `1 cup rice`, `black coffee`).
  - Outputs normalized intermediate items.
  - Includes parser coverage metadata.

#### BE-007 Implement fuzzy food matching and confidence scoring
- Type: Story
- Priority: P0
- Points: 8
- Dependencies: BE-006
- Description: Match parsed phrases to nutrition source IDs and compute confidence.
- Acceptance Criteria:
  - Confidence is bounded in `[0,1]`.
  - Weighted scoring formula follows implementation spec.
  - Unknown items are flagged with low confidence and assumptions.

#### BE-008 Build nutrition calculation service (no AI arithmetic)
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: BE-007
- Description: Convert units to grams and compute calories/macros deterministically.
- Acceptance Criteria:
  - Totals match item sums within rounding rules.
  - Negative values are blocked.
  - Response includes per-item and total macros.

#### BE-009 Implement parse endpoint `POST /v1/logs/parse` deterministic path
- Type: Story
- Priority: P0
- Points: 8
- Dependencies: BE-008
- Description: Expose parser + nutrition results with assumptions and confidence.
- Acceptance Criteria:
  - Request text length limit enforced (500 chars).
  - Deterministic-only path returns result in target schema.
  - p95 latency under 500ms on benchmark set.

#### BE-010 Implement save endpoint `POST /v1/logs`
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: BE-009
- Description: Persist parsed log and items.
- Acceptance Criteria:
  - Creates one `food_logs` row and N `food_log_items` rows atomically.
  - Returns stable `logId`.
  - Rollback occurs on partial insert failure.
  - Save accepts additive `manualOverride` item metadata without breaking existing clients.
  - Original provider attribution is retained when manual override provenance is present.

#### BE-011 Implement summary endpoint `GET /v1/logs/day-summary`
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: BE-010
- Description: Return totals, targets, and remaining macros for a date.
- Acceptance Criteria:
  - Date-based aggregation is user-scoped.
  - Targets are loaded from onboarding profile.
  - Response shape matches PRD contract.
  - Save paths reject future-date `loggedAt` relative to user timezone with stable error code.

### EPIC-3: AI Fallback and Clarification Flow

#### BE-012 Implement parse-cache read/write strategy
- Type: Story
- Priority: P1
- Points: 5
- Dependencies: BE-009
- Description: Hash normalized text and reuse cached parse output.
- Acceptance Criteria:
  - Cache key includes normalized text + locale + units + parser/provider/prompt version tags.
  - User scoping is only applied for user-specific parse contexts.
  - Hit count and last-used timestamps are updated.
  - Cache hit ratio metric is emitted.
  - Operational global purge and version namespace invalidation are supported.

#### BE-013 Integrate low-cost model fallback in parse routing
- Type: Story
- Priority: P1
- Points: 8
- Dependencies: BE-007, BE-012
- Description: Route medium-confidence logs to one fallback AI normalization call.
- Acceptance Criteria:
  - Trigger only for `0.50 <= confidence < 0.85`.
  - Maximum one fallback call per parse request.
  - Invalid model JSON is rejected and does not corrupt output.
  - Additive parse response fields are emitted without breaking existing clients:
    - top-level `sourcesUsed`
    - per-item `amount`, `unitNormalized`, `gramsPerUnit`, `needsClarification`, `manualOverride`
  - Totals are always validated as sum of items.

#### BE-014 Add clarification response path
- Type: Story
- Priority: P1
- Points: 3
- Dependencies: BE-013
- Description: Return minimal clarification prompts when confidence remains too low.
- Acceptance Criteria:
  - Response includes `needsClarification=true`.
  - Contains 1-2 focused follow-up questions.
  - Does not invoke escalation automatically.

#### BE-015 Add optional escalation endpoint/flag path
- Type: Story
- Priority: P2
- Points: 5
- Dependencies: BE-014
- Description: Enable explicit user-triggered advanced parse improvement.
- Acceptance Criteria:
  - Guarded by `AI_ESCALATION_ENABLED`.
  - Refuses escalation when budget is exceeded.
  - Writes audit/cost event for each escalation call.

### EPIC-4: Cost Controls and Observability

#### BE-016 Persist AI usage events in `ai_cost_events`
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: BE-013
- Description: Log model, tokens, feature route, and estimated cost for each AI call.
- Acceptance Criteria:
  - Every fallback/escalation call writes an event.
  - Event includes user, request ID, and timestamps.
  - Estimated cost formula is unit-tested.

#### BE-017 Add budget enforcement middleware/guard
- Type: Story
- Priority: P0
- Points: 8
- Dependencies: BE-016
- Description: Disable AI routes when daily/global budget is hit.
- Acceptance Criteria:
  - Global hard cap disables fallback + escalation.
  - User soft cap is returned in response metadata.
  - Deterministic mode remains available when AI disabled.

#### BE-018 Add metrics instrumentation endpoint/feed
- Type: Story
- Priority: P1
- Points: 5
- Dependencies: BE-016
- Description: Expose operational and cost metrics for dashboarding.
- Acceptance Criteria:
  - Metrics include route counts, token counts, cost totals, cache hit ratio.
  - Endpoint is protected/internal-only.
  - Metric names align with implementation spec.

#### BE-019 Configure alert rules for cost and routing anomalies
- Type: Story
- Priority: P1
- Points: 3
- Dependencies: BE-018
- Description: Set alert thresholds for escalation rate, cache hit ratio, and cost/log drift.
- Acceptance Criteria:
  - Alerts configured and test-triggered in staging.
  - Runbook links attached to alert descriptions.
  - False positive review completed.

### EPIC-5: Quality, Replay Tests, and Launch Readiness

#### BE-020 Unit tests for parser + confidence scoring
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: BE-007
- Description: Add deterministic tests for parsing and confidence boundaries.
- Acceptance Criteria:
  - Covers quantities, units, edge tokens, and unknown foods.
  - Confidence checks include lower/upper bounds and threshold edges.
  - CI executes tests automatically.

#### BE-021 Integration tests for onboarding/log/summary APIs
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: BE-011
- Description: Validate API behavior and persistence end to end.
- Acceptance Criteria:
  - Tests for happy path and validation errors.
  - Tests verify transactionality on save endpoint.
  - Tests run against isolated test database.

#### BE-022 Integration tests for AI fallback/clarification/budget paths
- Type: Story
- Priority: P1
- Points: 8
- Dependencies: BE-017
- Description: Verify routing and cost guard behaviors with mocked AI provider.
- Acceptance Criteria:
  - Medium confidence triggers fallback once.
  - Budget cap disables AI routes.
  - Clarification response returned for unresolved low confidence.

#### BE-023 Build 1,000-log replay benchmark harness
- Type: Story
- Priority: P1
- Points: 8
- Dependencies: BE-022
- Description: Replay representative logs to tune thresholds and estimate cost/log.
- Acceptance Criteria:
  - Report includes latency, fallback rate, escalation rate, and cost/log.
  - Output can be rerun after threshold changes.
  - Benchmark artifacts saved for comparison.

#### BE-024 Launch checklist and API handoff package for iOS
- Type: Story
- Priority: P1
- Points: 3
- Dependencies: BE-021, BE-022, BE-023
- Description: Publish stable API contracts and launch-readiness status.
- Acceptance Criteria:
  - API docs finalized with examples and error cases.
  - Known limitations are documented.
  - iOS integration checklist signed off.

### EPIC-6: iOS App Foundation and Networking

#### FE-001 Configure iOS environments and API base URL strategy
- Type: Story
- Priority: P0
- Points: 3
- Dependencies: BE-024
- Description: Set up local/staging/prod API base URL handling and development network permissions.
- Acceptance Criteria:
  - App can switch API base URL by build configuration.
  - Local simulator can reach backend successfully.
  - Environment config is documented for team onboarding.

#### FE-002 Build typed API client and error mapping layer
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: FE-001
- Description: Implement reusable networking client and typed models for onboarding/parse/save/summary.
- Acceptance Criteria:
  - API client supports auth headers and JSON encoding/decoding.
  - Shared error mapper converts API error envelope to UI states.
  - Unit tests cover decoding and common error mapping paths.

#### FE-003 Add app state and navigation shell
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: FE-002
- Description: Build root navigation and app state for onboarding completion and main logging entry.
- Acceptance Criteria:
  - App routes user to onboarding when profile not completed.
  - Completed onboarding routes to main logging screen.
  - Navigation state persists across app restarts.

#### FE-004 Add frontend telemetry hooks for latency and failure events
- Type: Story
- Priority: P1
- Points: 3
- Dependencies: FE-002
- Description: Emit client-side timing and error events for parse/save UX monitoring.
- Acceptance Criteria:
  - Parse and save events include success/failure + duration.
  - Error event includes backend request ID when available.
  - Event schema documented for analytics ingestion.

### EPIC-7: iOS Onboarding and Logging Experience

#### FE-005 Build onboarding UI flow and submission
- Type: Story
- Priority: P0
- Points: 8
- Dependencies: FE-003
- Description: Implement onboarding screens and submit answers to backend.
- Acceptance Criteria:
  - User can complete required questions and submit.
  - Success state stores onboarding completion locally.
  - Validation and submit failures show clear inline errors.

#### FE-006 Build main logging screen with debounced parse
- Type: Story
- Priority: P0
- Points: 8
- Dependencies: FE-002, FE-005
- Description: Implement notes-style input and live calories/macros panel powered by parse API.
- Acceptance Criteria:
  - Parse requests are debounced while typing.
  - Debounce behavior avoids re-parsing unchanged rows when row-level context is available.
  - Loading, success, and error states are visible.
  - Response confidence and totals are displayed.

#### FE-007 Build parse detail drawer and manual edit controls
- Type: Story
- Priority: P1
- Points: 8
- Dependencies: FE-006
- Description: Show parsed items/assumptions/confidence and allow item-level correction before save.
- Acceptance Criteria:
  - Drawer shows item list, assumptions, and confidence.
  - User can edit quantity/unit/item name before save.
  - Edited payload remains contract-compatible with save endpoint.

#### FE-008 Implement clarification and escalation UX
- Type: Story
- Priority: P1
- Points: 5
- Dependencies: FE-006, BE-015
- Description: Handle low-confidence clarifications and explicit escalation flow.
- Acceptance Criteria:
  - Clarification questions render when `needsClarification=true`.
  - Escalation call is explicit user action.
  - Escalation disabled/budget-exceeded states are handled in UI.

#### FE-009 Implement strict save flow with idempotent retries
- Type: Story
- Priority: P0
- Points: 8
- Dependencies: FE-006, BE-010
- Description: Save parsed logs with strict parse contract and idempotency-key retry safety.
- Acceptance Criteria:
  - Save sends `parseRequestId`, `parseVersion`, and `Idempotency-Key`.
  - Retry with same key safely replays prior success.
  - Conflict/invalid-reference errors are handled clearly in UI.
  - Manual edit payload includes `manualOverride` provenance metadata when applicable.
  - UI preserves original provider attribution while showing manual override state.

#### FE-010 Build day summary screen and progress widgets
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: FE-009, BE-011
- Description: Show totals, targets, and remaining macros for selected day.
- Acceptance Criteria:
  - Summary data loads and refreshes after save.
  - Empty state is handled for no logs.
  - Targets and remaining values are clearly visualized.
  - UI blocks future-date navigation/selection relative to user timezone.

### EPIC-8: Design System and Figma Handoff

#### DS-001 Define MVP design tokens and component primitives in Figma
- Type: Story
- Priority: P0
- Points: 3
- Dependencies: None
- Description: Establish color/type/spacing system and reusable component primitives.
- Acceptance Criteria:
  - Token sheet exists in Figma and is versioned.
  - Core components have default/active/error states.
  - Engineering-ready naming is used for tokens/components.

#### DS-002 Produce high-fidelity screens for all core flows
- Type: Story
- Priority: P0
- Points: 8
- Dependencies: DS-001
- Description: Create hi-fi screens for onboarding, logging, details, clarification/escalation, and summary.
- Acceptance Criteria:
  - All MVP screens represented in a single flow.
  - Error/loading/empty states are included.
  - Copy and interaction intent match PRD language.

#### DS-003 Build interactive Figma prototype for user flow walkthrough
- Type: Story
- Priority: P1
- Points: 5
- Dependencies: DS-002
- Description: Create clickable prototype for full onboarding-to-save-to-summary journey.
- Acceptance Criteria:
  - Prototype supports end-to-end scenario walkthrough.
  - Clarification and escalation branches are represented.
  - Team can review UX before UI implementation freeze.

#### DS-004 Deliver engineering handoff package from Figma
- Type: Story
- Priority: P1
- Points: 3
- Dependencies: DS-003
- Description: Prepare redlines, spacing specs, and asset exports for implementation.
- Acceptance Criteria:
  - Component specs and spacing rules are documented.
  - Asset export list is complete.
  - Handoff links are published in project docs.

### EPIC-9: End-to-End QA and Beta Launch Readiness

#### E2E-001 Create end-to-end QA test matrix (frontend + backend)
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: FE-010
- Description: Define and execute E2E matrix across happy paths and major failure paths.
- Acceptance Criteria:
  - Matrix covers onboarding, parse, save, summary, clarification, escalation.
  - Includes auth, validation, budget, and idempotency failure cases.
  - Includes mixed-source totals attribution and additive parse-contract compatibility cases.
  - Includes future-date rejection/prevention and timezone boundary cases.
  - Results are tracked with pass/fail and owner.

#### E2E-002 Add offline/retry UX and flaky-network handling
- Type: Story
- Priority: P1
- Points: 5
- Dependencies: FE-009
- Description: Improve reliability under poor network by adding retry strategy and user messaging.
- Acceptance Criteria:
  - Network failure states are recoverable without data loss.
  - Retry logic preserves idempotency-key behavior.
  - User receives actionable recovery guidance.
  - Includes manual override save retries and parse-reference compatibility failure handling.
  - Includes Apple Health dedupe verification across retry/edit flows.

### EPIC-10: Requirements Delta Alignment (2026-02-28)

#### BE-025 Onboarding provenance storage contract
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: BE-005
- Description: Enforce onboarding integrity mode and auditability for stored onboarding outputs.
- Acceptance Criteria:
  - Full-input mode or computed-provenance mode is explicitly selected and enforced.
  - Provenance metadata is persisted and retrievable for audit.
  - Integration tests verify reproducibility behavior.

#### BE-026 Parse response source attribution and deterministic v2 additive fields
- Type: Story
- Priority: P0
- Points: 8
- Dependencies: BE-013
- Description: Add mixed-source attribution and deterministic additive parse item fields.
- Acceptance Criteria:
  - Parse response includes `sourcesUsed` source-family set.
  - Items include additive fields (`amount`, `unitNormalized`, `gramsPerUnit`, `needsClarification`, `manualOverride`).
  - Existing parse fields remain available for compatibility.
  - Totals-from-items invariant is enforced server-side.

#### BE-027 Clarification gating enforcement at item-level
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: BE-026
- Description: Mark unresolved items and block save until clarified or manually overridden.
- Acceptance Criteria:
  - Affected items are flagged `needsClarification=true`.
  - Save remains blocked unless unresolved items are resolved by parse or allowed override policy.
  - Error responses include actionable machine code and user-friendly message.

#### BE-028 Save contract manual override provenance and compatibility validation
- Type: Story
- Priority: P0
- Points: 8
- Dependencies: BE-010, BE-026
- Description: Validate parse reference compatibility and persist manual overrides with provenance.
- Acceptance Criteria:
  - Save accepts allowed manual override shape and persists provenance.
  - Incompatible `parseRequestId`/`parseVersion` combinations are rejected with `422`.
  - Original provider attribution remains preserved for analytics.

#### BE-029 Future-date backend enforcement by timezone
- Type: Story
- Priority: P0
- Points: 3
- Dependencies: BE-011
- Description: Reject saves that target future dates in user-local timezone.
- Acceptance Criteria:
  - Future `loggedAt` relative to user timezone returns deterministic error code.
  - Integration tests cover timezone edges near midnight and DST transitions.

#### BE-030 HealthKit write dedupe contract service
- Type: Story
- Priority: P1
- Points: 8
- Dependencies: BE-010
- Description: Lock per-log Health sync with stable dedupe key and replace semantics.
- Acceptance Criteria:
  - Health write path uses stable per-log key.
  - Save retries and log edits replace/upsert existing Health records.
  - No daily-aggregate write mode is active in MVP.

#### BE-031 Cache key v2 composite namespace and purge hooks
- Type: Story
- Priority: P1
- Points: 5
- Dependencies: BE-012
- Description: Move parse cache to composite key v2 with provider/prompt namespace controls.
- Acceptance Criteria:
  - Cache key includes locale, units, parser version, provider route version, prompt version.
  - Version bump invalidation behavior is documented and tested.
  - Operational purge path is available for policy incidents.

#### FE-011 Row-level parse debounce and unchanged-row protection
- Type: Story
- Priority: P0
- Points: 5
- Dependencies: FE-006
- Description: Avoid unnecessary parses by row-level debounce and unchanged-row short-circuiting.
- Acceptance Criteria:
  - Unchanged rows are not re-parsed.
  - Debounce remains responsive while reducing duplicate parse calls.
  - Telemetry shows parse call reduction under typing scenarios.

#### FE-012 Future date lock in swipe/date picker (timezone-correct)
- Type: Story
- Priority: P0
- Points: 3
- Dependencies: FE-010, BE-029
- Description: Prevent future date navigation and selection on iOS log/snapshot views.
- Acceptance Criteria:
  - User cannot navigate/select future dates.
  - UI and backend date logic remain timezone-consistent.

#### FE-013 Manual override UX and payload provenance
- Type: Story
- Priority: P0
- Points: 8
- Dependencies: FE-007, BE-028
- Description: Surface manual override semantics in details UI and save payload contract.
- Acceptance Criteria:
  - Manual edits capture provenance metadata (`reason`, `editedFields`, enabled flag).
  - UI indicates manual overrides while preserving source attribution context.
  - Payload remains backward compatible for existing endpoints.

#### FE-014 Mixed-source attribution rendering in details
- Type: Story
- Priority: P1
- Points: 3
- Dependencies: FE-007, BE-026
- Description: Render mixed-source totals and source families in parse details UX.
- Acceptance Criteria:
  - UI displays `sourcesUsed` and per-item source families clearly.
  - Mixed-source rows are distinguishable in detail view.

#### FE-015 Health sync dedupe status UX
- Type: Story
- Priority: P1
- Points: 5
- Dependencies: FE-010, BE-030
- Description: Show safe health sync status for write/replace flows without save regressions.
- Acceptance Criteria:
  - Health sync success/failure states are visible and non-blocking to log save.
  - Retry/edit flows do not duplicate Health entries.

#### FE-016 Camera ingestion wiring
- Type: Story
- Priority: P1
- Points: 8
- Dependencies: FE-006
- Description: Connect camera/photo/file menu actions to ingestion pipelines.
- Acceptance Criteria:
  - Take photo, photo library, and file attachment flows execute end-to-end.
  - Failures return actionable UI states.

#### FE-017 Voice capture end-to-end flow
- Type: Story
- Priority: P2
- Points: 8
- Dependencies: FE-006
- Description: Complete voice capture-to-parse flow with robust error handling.
- Acceptance Criteria:
  - Voice entry can populate parse input and trigger normal parse/save flow.
  - Permission and capture failure paths are handled cleanly.

#### E2E-003 Performance pass for end-to-end logging flow
- Type: Story
- Priority: P1
- Points: 5
- Dependencies: FE-006, FE-009
- Description: Tune frontend/backend interactions to keep common log flow under target time.
- Acceptance Criteria:
  - Time-to-log target under 10 seconds on benchmark devices.
  - Parse panel perceived responsiveness meets UX expectations.
  - Performance findings and tuning changes are documented.

#### E2E-004 Accessibility and localization baseline
- Type: Story
- Priority: P2
- Points: 8
- Dependencies: FE-010
- Description: Add baseline accessibility support and localization scaffolding for MVP screens.
- Acceptance Criteria:
  - VoiceOver labels exist on primary interactive controls.
  - Dynamic type and contrast checks pass on key screens.
  - Localization keys are externalized for visible strings.

#### E2E-005 Beta release readiness and TestFlight handoff
- Type: Story
- Priority: P0
- Points: 3
- Dependencies: E2E-001, E2E-002, E2E-003
- Description: Prepare release checklist, environment config, and handoff for closed beta.
- Acceptance Criteria:
  - TestFlight build checklist completed.
  - Environment and rollback notes documented.
  - Beta feedback intake loop is defined.

## 4. Suggested Sprint Cut

### Sprint 1 (Core foundation)
- BE-001, BE-002, BE-003, BE-004, BE-005, BE-006

### Sprint 2 (Deterministic MVP)
- BE-007, BE-008, BE-009, BE-010, BE-011, BE-020, BE-021

### Sprint 3 (AI + cost controls)
- BE-012, BE-013, BE-014, BE-016, BE-017, BE-018, BE-022

### Sprint 4 (Hardening + launch prep)
- BE-015, BE-019, BE-023, BE-024

### Sprint 5 (Frontend foundation + design baseline)
- FE-001, FE-002, FE-003, DS-001, DS-002
- Target points: 27

### Sprint 6 (Core iOS experience)
- FE-005, FE-006, FE-007, FE-009, DS-003
- Target points: 37

### Sprint 7 (Clarification/escalation + summary + reliability)
- FE-008, FE-010, FE-004, E2E-001, E2E-002, DS-004
- Target points: 26

### Sprint 8 (Performance + launch readiness)
- E2E-003, E2E-004, E2E-005
- Target points: 16

### Sprint A (Contract correctness + safety)
- BE-025, BE-026, BE-027, BE-029, FE-012

### Sprint B (Edit semantics + cache correctness)
- BE-028, BE-031, FE-011, FE-013, FE-014

### Sprint C (Health + input expansion)
- BE-030, FE-015, FE-016, FE-017

### Sprint D (E2E hardening)
- E2E-001 (expanded), E2E-002 (expanded), BE-022 regression extension

## 5. Definition of Ready (for each ticket)
- Clear endpoint/table/module scope.
- Acceptance criteria are testable.
- Dependencies identified.
- Story sized.

## 6. Definition of Done (for each ticket)
- Code merged to main with tests passing.
- Monitoring/logging added where relevant.
- API/docs updated where relevant.
- No open P0 bug linked to ticket.
