# Food App: End-to-End Engineering Handoff (Current Code State)

## 1) Purpose of this document
This is a senior-level technical handoff for the current implementation of the Food App (iOS + backend + infra). It describes:

- How the app currently works end-to-end.
- The exact parse/save/display mechanics in code.
- Data contracts and validation gates.
- Operational/deployment behavior on Render + Supabase/Postgres.
- Current complexity hotspots and required rewrite boundaries.

This is intentionally code-driven (not product-theory-driven) so a new senior engineer can quickly audit, stabilize, and refactor.

## 2) Repository topology

- iOS app code: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App`
- Backend API: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend`
- Infra config: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/render.yaml`
- Existing docs: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs`

## 3) Runtime architecture

### iOS app
- SwiftUI single-app target.
- App entry: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/Food_AppApp.swift`
- Root flow: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/ContentView.swift`
  - `OnboardingView` when onboarding incomplete.
  - `MainLoggingShellView` when onboarding complete.

### Backend
- Node + Express + TypeScript.
- App wiring: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/app.ts`
- Start: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/index.ts`
- Primary routes:
  - `/v1/logs/parse` (`parse.ts`)
  - `/v1/logs` and log CRUD (`logs.ts`)
  - `/v1/internal/dashboard/recent-parses` (`evalDashboard.ts`)

### Database
- PostgreSQL (Supabase-managed in current setup).
- Migration runner: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/scripts/migrate.ts`
- Migration engine: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/db/migrations.ts`
- Migration state table: `schema_migrations`

### Deployment
- Render web service config: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/render.yaml`
  - `rootDir: backend`
  - Build: `npm install --no-audit --no-fund && npm run build`
  - Start: `npm run migrate && npm run start`
  - Health check: `/health`

## 4) Configuration and environment model

### iOS configuration
- Source: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/AppConfiguration.swift`
- Base URL currently defaults to Render URL for all envs.
- Hard safety rail: loopback/private hosts are rejected and replaced with fallback URL.
- Supabase URL/key and Google IDs are loaded via env or Info.plist.

### Backend configuration
- Source: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/config.ts`
- Key operational flags:
  - `DATABASE_URL`, `DATABASE_SSL`
  - `AUTH_MODE` (`dev`, `supabase`, `hybrid`)
  - `PARSE_VERSION` (default `v2`)
  - `PARSE_REQUEST_TTL_HOURS` (default `24`)
  - AI/circuit/rate-limit/budget flags
  - `INTERNAL_METRICS_KEY` for internal dashboard endpoints

## 5) Current iOS app flow

### 5.1 Boot, auth, onboarding gate
- `AppStore` initializes API client, auth service, network monitor, notification scheduler, health service:
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/AppStore.swift`
- `ContentView` switches between onboarding and home based on `appStore.isOnboardingComplete`.
- `AppStore` attempts session restore and then marks `isSessionRestored`.

### 5.2 Home screen composition
- Primary surface: `MainLoggingShellView`:
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/MainLoggingShellView.swift`
- UI behavior:
  - Apple Notes-like row composer.
  - Saved rows above active rows.
  - Bottom dock actions (camera, voice, nutrition summary, streak).
  - Background tap focuses composer (`focusComposerInputFromBackgroundTap`).
  - Date swipe left/right changes active day with prefetch/cached hydration.

### 5.3 Core row model/state
- `HomeLogRow` in:
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/HomeFlowComponents.swift`
- Important fields:
  - `text`, `calories`, `parsedItems`, `isSaved`, `serverLogId`, `serverLoggedAt`
  - `parsePhase` (`idle`, `active`, `queued`, `failed`, `unresolved`)
  - Optional image fields (`imagePreviewData`, `imageRef`)

### 5.4 Parse scheduling and queueing
- User editing triggers debounced parse (`scheduleDebouncedParse` path).
- The view maintains:
  - active row being parsed
  - queued row IDs
  - parse snapshot at dispatch
  - completed per-row parse entries:
    `(rowID, parseRequestId, parseVersion, rawText, response, rowItems)`
- Critical design detail:
  - Save uses row-level `rawText` from parse-time snapshot to satisfy backend parse-reference checks.

### 5.5 Parse result application to display
- Parse response mapped into row calories and items.
- Approximate/clarification visuals supported.
- Unresolved placeholder items are represented with `nutritionSourceId == "unresolved_placeholder"`.
- Multi-row parse mapping logic attempts row-level assignment and fallback heuristics.

### 5.6 Auto-save behavior (current)
- Auto-save delay: `1.5s`.
- Eligibility currently row-driven:
  - If row has visible calories, row is save-eligible.
  - Otherwise row may still be eligible if parsed items exist.
- Auto-save implementation:
  - Builds one save request per completed row.
  - Uses persistent queue entries (`PendingSaveQueueItem`).
  - Reuses existing idempotency key for the same row where possible.
- Pending save persistence:
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/HomePendingSaveStore.swift`
  - Stored in `UserDefaults` (`app.pendingSaveQueue.v1`).

### 5.7 Save/patch/delete flows from iOS
- API client:
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/APIClient.swift`
- New row save:
  - `POST /v1/logs` with `Idempotency-Key`.
- Existing row edit:
  - `PATCH /v1/logs/:id` for in-place update (quantity fast path or full edit).
- Delete:
  - `DELETE /v1/logs/:id`.

### 5.8 Image parse and image save behavior
- Image parse: `POST /v1/logs/parse/image`.
- Save is decoupled from image upload:
  - Food log may save with `image_ref = NULL`.
  - Image upload can happen later.
  - Then `PATCH /v1/logs/:id/image-ref`.
- Deferred image upload durability:
  - `DeferredImageUploadStore` persisted to disk and drained on launch.

### 5.9 Sync status UX
- Home sync pill computes “items syncing” from:
  - unresolved pending queue entries
  - unsaved visible rows
  - pending patch/delete tasks
- Intent: do not block UX while background sync catches up.

## 6) Backend parse flow

### 6.1 Parse endpoints
- File: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/routes/parse.ts`
- Endpoints:
  - `POST /v1/logs/parse` (SSE or normal JSON path)
  - `POST /v1/logs/parse/image`
  - `POST /v1/logs/parse/escalate`

### 6.2 Parse response contract highlights
- Includes:
  - `parseRequestId`, `parseVersion`, `route`, `confidence`, `totals`, `items`
  - `needsClarification`, `clarificationQuestions`
  - optional `reasonCodes`, `retryAfterSeconds`
- Parse request is persisted in `parse_requests`.

### 6.3 Parse request provenance and TTL
- Parse request read/write service:
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/services/parseRequestService.ts`
- Staleness:
  - `isParseRequestStale()` based on `PARSE_REQUEST_TTL_HOURS` (default 24h).

## 7) Backend save flow

### 7.1 Save endpoint and validation
- File: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/routes/logs.ts`
- `POST /v1/logs` validates:
  - idempotency header required
  - parse request exists
  - parse request not stale
  - `parseVersion` matches parse request
  - normalized `rawText` matches parse request
  - logged time not in future
  - no unresolved items without manual override
  - totals match sum(items)

### 7.2 Strict idempotent persistence path
- Service: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/services/logService.ts`
- `saveFoodLogStrict` behavior:
  - transaction
  - advisory lock on `(userId, idempotencyKey)`
  - advisory lock on `(userId, parseRequestId)` when present
  - idempotency replay/conflict handling
  - duplicate guard by existing `(user_id, parse_request_id)` lookup
  - insert into `food_logs` + `food_log_items`
  - write `log_save_idempotency`

### 7.3 Patch endpoint
- `PATCH /v1/logs/:id`
  - parse refs optional
  - if provided, same validation gates as POST
  - totals/items revalidated
  - replaces item set transactionally

### 7.4 Image ref patch endpoint
- `PATCH /v1/logs/:id/image-ref`
  - lightweight image ref attach/clear endpoint
  - intentionally avoids full parsedLog payload requirements

## 8) Internal dashboard semantics (important for debugging)

### 8.1 `recent-parses` status source
- File: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/routes/evalDashboard.ts`
- `saveStatus` is computed as:
  - `saved` if joined log exists
  - `parse_only` otherwise
- Join strategy:
  - preferred by `food_logs.parse_request_id == parse_requests.request_id`
  - fallback text/time proximity matching if parse_request_id absent

### 8.2 Practical meaning of `parse_only`
`parse_only` does not automatically mean “save call failed.” It can also mean:

- Parse result never produced saveable row state on client.
- Client never fired save for that row.
- Save failed before persistence.
- Log was created but cannot be joined by current dashboard query pattern.

## 9) Data model and migrations

### 9.1 Base schema
- `0001_init_schema.sql` defines:
  - `users`
  - `onboarding_profiles`
  - `food_logs`
  - `food_log_items`
  - `parse_cache`
  - `ai_cost_events`

### 9.2 Parse/save contract schema
- `0002_parse_contracts.sql` defines:
  - `parse_requests`
  - `log_save_idempotency`

### 9.3 Parse provenance + dedupe migrations
- `0017_food_log_parse_provenance.sql`
  - adds `food_logs.parse_request_id`, `food_logs.parse_version`, indexes
- `0018_food_logs_parse_request_unique.sql`
  - dedupes existing duplicates
  - adds unique partial index:
    `(user_id, parse_request_id) where parse_request_id is not null`

## 10) Frontend contracts to preserve during rewrite

Any rewrite should preserve these UX/behavior contracts unless explicitly changed by product:

1. If a calorie value is shown to the user, that row must converge to persisted state.
2. Background tap should focus composer (no need to tap exact row).
3. Keyboard should not open automatically on initial screen load.
4. Day swipe should flush pending autosave before changing day.
5. Save must be idempotent and duplicate-safe across retries/races.
6. Image upload failure must not block nutrition save.
7. Sync state should remain visible but non-blocking.

## 11) Current complexity hotspots (why rewrite is justified)

1. `MainLoggingShellView` mixes UI, parse orchestration, save orchestration, queue persistence, patch/delete coordination, and sync UX in one file.
2. Multiple overlapping state flags (`parseTask`, `activeParseRowID`, queued rows, in-flight snapshots, completedRowParses, pending queue, pending patch tasks, etc.) increase race risk.
3. Backend save contract is strict (rawText/version/reference/totals), so small frontend state drift can drop saves.
4. Dashboard `parse_only` semantics are operationally useful but easy to misinterpret.

## 12) Senior-dev rewrite scope recommendation

### 12.1 Rewrite target
Refactor the parse/save/display pipeline into explicit layers:

- `ComposerStateMachine` (pure state transitions)
- `ParseCoordinator` (one responsibility: parse dispatch + row mapping)
- `SaveCoordinator` (one responsibility: queue, idempotency, retries)
- `HomeView` (render-only + event dispatch)

### 12.2 Non-negotiables
- Keep API contracts backward-compatible during migration.
- Keep existing data tables and idempotency semantics.
- Keep image decoupled save path.
- Ship behind feature flag for gradual cutover.

### 12.3 Suggested acceptance criteria
- Single-row happy path: parse -> visible calories -> saved < 3s median.
- Multi-row typing path: each visible calorie row eventually saved once.
- No duplicate logs for same parse request under retry/race tests.
- Day switch during debounce does not lose save.
- Force quit / relaunch with pending save resumes correctly.

## 13) Access required for incoming senior developer

Grant access to:

1. GitHub repo with push + PR merge rights.
2. Render service (`food-app-backend`) with deploy logs and env vars.
3. Supabase/Postgres project with:
   - migration execution rights
   - query console
   - table/index inspection rights
4. Internal metrics key for `/v1/internal/dashboard/*`.
5. iOS signing/TestFlight pipeline (if they will ship app builds).

## 14) Runbook: first-day validation steps for senior dev

1. Verify backend env + auth mode in Render.
2. Verify live schema migration status (`schema_migrations`, required columns/indexes).
3. Run backend integration tests locally (`npm run test:integration`).
4. Build iOS app (`xcodebuild`) and run parse/save scenarios:
   - simple text
   - low-confidence text
   - unresolved parse
   - image parse with delayed image upload
   - day swipe during pending autosave
5. Correlate iOS behavior with internal dashboard rows.

## 15) Files to read first (priority order)

1. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/MainLoggingShellView.swift`
2. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/APIClient.swift`
3. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/HomeFlowComponents.swift`
4. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/HomeLoggingSupportViews.swift`
5. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/HomePendingSaveStore.swift`
6. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/routes/parse.ts`
7. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/routes/logs.ts`
8. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/services/logService.ts`
9. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/services/parseRequestService.ts`
10. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/routes/evalDashboard.ts`
11. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/migrations/0017_food_log_parse_provenance.sql`
12. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/migrations/0018_food_logs_parse_request_unique.sql`
13. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/render.yaml`

---

## 16) Edge Cases and Bug History (Observed in real usage)

This section captures the specific issues repeatedly seen during manual testing in late April 2026 and early May 2026. These are high-context items for any senior engineer taking over.

### 16.1 `Parse only` rows visible in dashboard while user expected saved rows

Observed pattern:
- Internal dashboard showed many rows with `saveStatus = parse_only` and no calories/macros/confidence.
- Example input strings included variants like:
  - `tomatoe soup 10oz`
  - `tomatoe soup 10`
  - `2 banana`
  - `cream of mushroom soup`
  - `bounty chocolate`

Key nuance:
- `parse_only` is not always a save failure.
- In many cases those rows had no usable parsed nutrition payload, so the row never entered a saveable state on client.

Engineering impact:
- Dashboard alone cannot distinguish:
  - parse produced no saveable output
  - save never attempted
  - save attempted and failed
  - save persisted but join failed

Recommended action:
- Add explicit save-attempt telemetry tied to `parseRequestId`.
- Add parse outcome classification (`resolved`, `unresolved`, `partial_unresolved`) at dashboard level.

### 16.2 Autosave appeared inconsistent for rows visible on UI

Observed pattern:
- User saw rows displayed in app and expected persistence, but some did not persist.
- This created a trust issue: “if it is shown, it should be saved.”

Root complexity:
- Save eligibility is spread across row state (`calories`, `parsedItems`, parse phase, queue conditions).
- Parse/save state transitions happen across debounced tasks, queued rows, and per-row snapshots.

Product rule requested:
- If calories are shown, auto-save should trigger unconditionally.

Current code intent:
- `isAutoSaveEligibleEntry` allows save when `row.calories != nil`.
- Row save request builders force `needsClarification = false` for persisted visible rows.

### 16.3 Duplicate entries from retries/races

Observed pattern:
- One input occasionally resulted in duplicate saved rows.

What was added:
- Backend advisory lock by `(user, idempotencyKey)`.
- Additional advisory lock by `(user, parseRequestId)` when present.
- Existing-row reuse when same `(user, parseRequestId)` already exists.
- Unique partial index migration for `(user_id, parse_request_id)`.

Critical dependency:
- Requires migrations `0017` and `0018` to be applied in production DB.

### 16.4 Production deploy/migration drift

Observed incident:
- Render deployed new code commit, but live DB still showed migration state only through `0016_eval_runs.sql`.
- Missing `food_logs.parse_request_id` column in live DB caused behavior to resemble pre-fix state.

Risk:
- New code paths silently degrade if schema assumptions are unmet.

Required guard:
- Add startup health assertion for minimum schema version or required columns/indexes.
- Fail fast (or alert hard) when schema is behind expected app/backend contract.

### 16.5 Parse/save contract strictness causing hidden 422 failures

Current backend checks that can reject saves:
- `parseRequestId` exists and not stale.
- `parseVersion` matches parse request.
- normalized `rawText` matches parse request raw text.
- totals exactly match sum(items) after rounding.
- unresolved item without manual override is rejected.

Real-world issue:
- UI can mutate row text/items after parse; if saved payload drifts from parse provenance, backend rejects.

Mitigation currently used:
- Completed row parse snapshot stores row-level `rawText`/`parseRequestId`/`parseVersion`.

Rewrite recommendation:
- Move provenance matching into explicit per-row state machine; never build save payload from mixed/global draft state.

### 16.6 Keyboard and composer focus friction

Observed UX issue:
- User had to tap exact row area to reopen keyboard.

Requested behavior:
- Tap anywhere in empty screen area should focus last composer row and open keyboard.

Current implementation:
- Screen-level tap gesture calls `focusComposerInputFromBackgroundTap`.

Regression risk:
- Overlay/sheet/modals can intercept gestures, so this should be covered in UI tests.

### 16.7 Save + image upload coupling previously caused “looks saved but incomplete” confusion

Observed issue class:
- Image upload failures could block or obscure save semantics.

Current model:
- Nutrition save and image upload are decoupled.
- Save can succeed with `image_ref = null`.
- Photo upload retries later then patches `image_ref`.

Residual risk:
- If deferred uploader is not drained reliably on launch/auth restore, images remain unattached despite saved nutrition rows.

### 16.8 Cold-start latency from Render free tier

Observed concern:
- User asked whether instance sizing and cold starts affect app responsiveness.

Current mitigation:
- iOS API client uses longer timeout windows for onboarding/day-summary/day-logs paths.
- Render free-tier cold start still adds startup latency under inactivity periods.

Operational recommendation:
- Instrument cold-start detection and show explicit “waking server” state in app when applicable.

### 16.9 Unresolved/clarification behavior mismatch with product expectation

Product expectation:
- If something is displayed and user sees calories, persist it.
- Avoid “not saved” messaging when sync is in progress.

System complexity:
- Backend still has unresolved-item blocking logic unless item payload is transformed to saveable form.
- Frontend currently masks/normalizes clarification flags in some save paths.

Rewrite requirement:
- Define single product policy for unresolved rows:
  - either always persist draft rows with unresolved status
  - or block save but with explicit UX status and guaranteed retry/resolve path

### 16.10 Environment and auth mode confusion risk

Potential failure mode:
- iOS can point to one backend URL while engineer inspects another environment.
- Auth mode (`dev`, `supabase`, `hybrid`) differences can mask save/identity behavior.

Required checklist item:
- Every bug reproduction must capture:
  - iOS build SHA
  - backend commit SHA
  - Render service deploy ID/time
  - DB migration max ID
  - `AUTH_MODE` and `PARSE_VERSION`

### 16.11 Dark mode requirement context

Product direction requested:
- App should be dark-mode ready.
- Preferred default is system-following (or dark-first by explicit policy).

Current state:
- App entry currently sets `.preferredColorScheme(.light)` in `Food_AppApp`.

Implication:
- This is a deliberate override and conflicts with “follow system” unless changed.

### 16.12 Onboarding/Value-prop content and flow risk

Product context:
- Onboarding was considered long before core value demonstration.
- Need value statements interleaved with data entry.
- No “personalized plan” copy if backend does not deliver that feature.

Engineering impact:
- Copy and screen sequencing are product-critical and should be treated as versioned requirements, not ad hoc text edits.

### 16.13 Testing dashboard interpretation risk

Observed pain:
- Dashboard interpreted as source of truth for “save worked or not,” which is only partially true.

Recommendation:
- Add additional columns:
  - `saveAttempted` (bool)
  - `saveErrorCode` (nullable)
  - `saveLatencyMs`
  - `saveSource` (`auto`, `manual`, `retry`, `patch`)
  - `clientBuild` and `backendCommit`

---

## Appendix A: Key API request/response entities in iOS

- `ParseLogRequest`, `ParseLogResponse`
- `SaveLogRequest`, `SaveLogBody`, `SaveParsedFoodItem`
- `PatchLogRequest`
- `DaySummaryResponse`, `DayLogsResponse`

Defined in:
- `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/APIModels.swift`

## Appendix B: Save validation schema in backend

Defined in:
- `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/routes/logSchemas.ts`

Highlights:
- Non-negative numeric constraints.
- Confidence bounded 0..1.
- Input kind enum: `text|image|voice|manual`.
- Totals must equal item sums.
- Manual override requires provenance fields.
