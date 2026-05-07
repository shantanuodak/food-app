# Food App — Handoff Notes (2026-05-06)

Hand-off context for continuing work after the recent push. Combines work
landed in the last ~5 days (Apr 30 → May 6) with what's still pending.
Everything below is grounded in actual commits and PR state — no
speculation.

> **Read this first**: `Food App/CLAUDE.md` contains the project's
> hard rules (save-path verification, image-upload decoupling,
> coordinator-first architecture). Those rules supersede anything here
> when they conflict.

---

## 1. Stack at a glance

- **iOS app**: SwiftUI, deployment target iOS 18, lives in `Food App/`.
  Auth via Apple Sign In + Google Sign In only (no email/password). Auth
  flows through Supabase. App Store Connect ID submitted for TestFlight
  beta review on 2026-05-06.
- **Backend**: Node + TypeScript, Express, Supabase Postgres, deployed
  on Render. `backend/` directory. Auto-deploys on every push to
  `origin/main`.
- **Test data + admin**: Internal testing dashboard at
  `backend/src/testing-dashboard/index.html`, served behind an internal
  metrics key. Routes in `backend/src/routes/evalDashboard.ts`.

### Architecture orientation
- iOS logging is coordinator-first as of Phase 4 (2026-05-02):
  `ParseCoordinator` owns parse snapshots, `SaveCoordinator` owns the
  pending-save queue / save execution / retry / deferred image uploads.
  `MainLoggingShellView` orchestrates UI but should not reintroduce
  feature-flagged save/parse fallback branches.
- Image uploads are decoupled from save (commit `0443246`): inline
  upload attempts first; on any failure the bytes go to
  `deferredImageUploads` (in-memory) and a disk-backed
  `DeferredImageUploadStore` (capped 50 entries / 14-day TTL). Drains
  on next launch via `AppStore.drainDeferredImageUploads`.
- Day transitions preserve in-flight drafts via
  `preservedDraftRowsByDate` keyed by `yyyy-MM-dd`. The recent dup-fix
  (commit `d578836`) added a `serverLogId == nil` guard to
  `captureDateChangeDraftRows` and `preserveCurrentDraftRowsForDateChange`
  so tap-to-edit rows can't be re-POSTed as background drafts.

---

## 2. Recent work timeline (last 30 commits, newest first)

```
a22e935  Add user filter to testing dashboard Saved Logs tab    ← just deployed
db17d73  Add Apple-Health-style Steps card to Insights
fb8ed65  Add focused editors for Body / Diet / Targets reachable from bento
14f214f  Rename HomeProfileScreen title from Profile to Settings
e3abba0  Polish bento dashboard accessibility (VoiceOver, reduce motion, Dynamic Type)
939bc1b  Replace Profile sheet with bento dashboard
ce62bbb  Redesign Insights charts: Apple-Health-style cards, range-aware bars, light-mode tokens
d578836  Skip re-POSTing tap-to-edit rows on day change to prevent duplicate food_logs
2a5cca8  Ignore Claude Code per-machine settings.local.json
42e4a76  Quiet Swift 6 strict-concurrency warnings in camera, speech, APIClient
5b6d765  Add Insights navigation and per-allergen icons in profile
79dcb64  Apply brand orange gradient to home screen headline
4ff77bf  Wire first-launch tutorial into MainLoggingShellView
3eae979  Stable saved-first row order in mergeRowsPreservingVisibleOrder
3759582  Patch saved-row text edits instead of POSTing duplicates (Piece C)
03d9e2b  Drop superseded autosave requests to prevent edit-duplicate rows
0eef70e  Fix streak button needing 2-3 taps to open drawer
e383220  Run prepareImagePayload off main thread + add autoreleasepool
19518e2  Close out Phase 9 #1 with Memory Graph results
d74c27b  Close out Phase 8 #1 and #2 with measured data
c26f8fd  Mark Phase 7A complete and link Phase 8-10 findings
76955d8  Capture Phase 8-10 audit findings
c78b5a5  Add ts-prune audit baseline (Phase 7A Part 7)
727b288  Extract HomeProfileScreen from ContentView
7845584  Remove unused GoogleSignInSwift package product
7ce79fe  Defer Phase 7A Part 4 (onboarding split) to Phase 7B
558b417  Extract logging escalation flow
fc8cd83  Extract logging row mutation flow
0673b39  Extract logging save flow
0c137a4  Update phase 7 parse extraction notes
```

### Themes

**A. Duplicate-row prevention in food_logs (HIGH-PRIORITY series)**
The most-touched area. Three compounding bugs in the iOS save path
landed fixes in this window. Each was caused by a different race;
they're now layered defenses:
- `03d9e2b` — Edit-during-parse race: superseded autosave requests
  dropped before they POST.
- `3759582` (Piece C) — Tap-then-edit-text: PATCHes the saved row
  instead of POSTing a duplicate.
- `d578836` — **Tap-then-day-swipe**: `serverLogId == nil` guard added
  to day-change capture/preserve. Without this, tapping a saved row to
  select text (which demotes `isSaved → false` but leaves
  `serverLogId` populated) and then accidentally swiping days caused a
  background re-POST. **This was filed in this session**; verification
  per the save-path rule was performed by the user before merge.

**B. Profile → Bento dashboard rework**
- `727b288` first extracted `HomeProfileScreen` from `ContentView`.
- `939bc1b` replaced the Profile sheet entirely with a bento-style
  dashboard.
- `e3abba0` polished a11y (VoiceOver labels, reduced-motion respect,
  Dynamic Type scaling).
- `fb8ed65` added focused editors for Body / Diet / Targets reachable
  from bento tiles.
- `14f214f` renamed the screen title from "Profile" to "Settings".

**C. Insights tab**
- `ce62bbb` redesigned charts in Apple-Health style: range-aware bars,
  light-mode tokens.
- `db17d73` added the Steps card with W/M aggregation rules:
  daily-sum bars, average **excludes zero-step days** to avoid biasing
  averages downward when the user's Apple Watch was off.
- Apple Health auth state is shared between Steps + Weight cards via a
  `canReadWeight` flag — single "Connect Apple Health" CTA covers both.

**D. Phase 7-10 audit / cleanup (architecture)**
- `0673b39`, `fc8cd83`, `558b417` — extracted save / row-mutation /
  escalation flows out of `MainLoggingShellView` into dedicated files
  (Phase 7A Parts 1–3). Part 4 (onboarding split) was deferred to
  Phase 7B (`7ce79fe`).
- `c78b5a5` baselined dead-code audit via `ts-prune`.
- `76955d8`, `c26f8fd`, `d74c27b`, `19518e2` captured + closed audit
  findings for Phases 8-10 (memory graph, measured perf data, etc.).

**E. Onboarding tutorial (TipKit)**
- `4ff77bf` wired a first-launch tutorial into
  `MainLoggingShellView`. Branch `feat/tutorial-tipkit` (PR #8) has the
  TipKit-based variant pending review.

**F. Misc polish**
- `0eef70e` — Streak drawer now opens on first tap (was 2-3 taps).
- `e383220` — `prepareImagePayload` moved off main thread, wrapped in
  `autoreleasepool` to avoid memory spikes on big photos.
- `42e4a76` — Swift 6 strict-concurrency warnings cleaned up in
  camera, speech, APIClient.
- `79dcb64` — Brand orange gradient on home headline.

**G. Backend dashboard (just deployed today)**
- `a22e935` — `GET /v1/internal/dashboard/saved-logs` now accepts an
  optional `userEmail` filter. New endpoint
  `GET /v1/internal/dashboard/users` returns active users for the
  picker. Frontend tab gains a `<select>` and a User column. Used by
  QA to scope nutrition-parse evaluation to a specific account.
  **Pushed to origin/main 2026-05-06; Render auto-deploy in flight at
  time of writing.**

---

## 3. Open PRs (7) — pending review/merge

Listed by PR number; titles are accurate and self-explanatory.

| PR  | Title                                                              | Branch                                       |
|-----|--------------------------------------------------------------------|----------------------------------------------|
| #10 | Diet/allergies explanations with inline disclosure (Tier 1 #10)    | `feat/diet-allergies-explanations`           |
| #9  | L10n voice rewrite + onboarding sweep (Tier 1 #1)                  | `feat/l10n-voice-rewrite`                    |
| #8  | Add first-launch tutorial via TipKit (Tier 1 #6)                   | `feat/tutorial-tipkit`                       |
| #7  | Add Insights hub: 4 nutrition charts over 30d (Tier 1 #8)          | `feat/profile-cleanup-and-insights`          |
| #6  | Content audit — L10n voice direction + 15 samples for approval     | `chore/content-audit-and-voice-sample`       |
| #5  | Add user feedback form (Tier 1 #7)                                 | `feat/feedback-form`                         |
| #3  | Add save-health monitor to surface stuck-save regressions          | `feat/save-health-monitor`                   |

**Numbering note**: PR #1, #2, #4 are missing — already merged or
closed. Use `gh pr view <N>` for full bodies.

**Suggested merge order** (lowest interdependency first):
1. **PR #6** (content audit) — pure docs/voice direction, no code risk.
2. **PR #5** (feedback form) — additive feature, no save-path change.
3. **PR #3** (save-health monitor) — additive observability; safe.
4. **PR #9** (L10n voice rewrite) — touches user-visible strings; bake
   alongside PR #6's voice direction.
5. **PR #10** (diet/allergies explanations) — UI-only; depends on
   nothing.
6. **PR #8** (TipKit tutorial) — already partially landed via
   `4ff77bf` on main; reconcile before merging.
7. **PR #7** (Insights hub) — overlaps with `ce62bbb` + `db17d73`
   that already landed. Likely needs rebase + dedup before merge.

---

## 4. Branches without PRs

A few feature branches exist on origin without PRs filed yet:

- `feat/persistent-deferred-image-uploads` — local-disk persistence
  for deferred image uploads survives app kill/restart. Likely
  already largely merged via `0443246` (image-upload decouple) but
  may have refinements not yet open as a PR. Worth diffing against
  main.
- `chore/streak-drawer-redesign` — older redesign exploration; the
  current streak drawer (post `0eef70e` and the Figma redesign) may
  have superseded this branch. Verify before deleting.
- `integration/tier-1` — integration branch that merges in Tier 1
  feature branches (currently has `feat/diet-allergies-explanations`
  merged in). This is a staging branch for batched Tier 1 release —
  do NOT merge directly to main; merge the individual PRs instead.

---

## 5. Current local state

```
M  Food App.xcodeproj/project.pbxproj    ← Xcode IDE auto-touch only
```

The `project.pbxproj` modification is Xcode's auto-touch from opening
the project (file ordering shuffle, no real config change). Safe to
discard with `git checkout -- "Food App.xcodeproj/project.pbxproj"`
unless something was deliberately added to the project.

Everything else is committed and pushed. Local `main` matches
`origin/main` at `a22e935`.

There's also an untracked, gitignored
`.claude/settings.local.json` containing a project-scoped Claude Code
PreToolUse hook that routes Bash commands through `rtk` (a CLI proxy
that token-compresses git/build/test output). Personal optimization,
not team-shared. Safe to ignore for handoff purposes; if Codex wants
the same setup, see notes in §8.

---

## 6. Operational rules from `Food App/CLAUDE.md` (do not violate)

These are project-specific hard rules that have caught real production
bugs. Pulled here so Codex sees them immediately.

### Save-path verification rule
Any change touching parse, save, autosave, image upload, `food_logs`,
`food_log_items`, or the iOS save flow (`MainLoggingShellView.submitSave`,
`prepareSaveRequestForNetwork`, `autoSaveIfNeeded`, `scheduleAutoSave`,
`buildRowSaveRequest`, `ImageStorageService`, or anything in
`MainLoggingDateFlow.swift` / `MainLoggingDayCacheFlow.swift` that
flows into `submitSave`) is **not done** until:

1. iOS app builds with `xcodebuild` against an iOS Simulator (CLI, not
   Xcode GUI — concurrent edits + Xcode's live indexer cause
   `swbuild.tmp` filesystem-level errors that look like real failures
   but aren't).
2. A real meal is saved end-to-end through the app. Text-mode at
   minimum; image-mode if any image path was touched.
3. The following SQL is run and the result pasted in the response:
   ```sql
   SELECT id, created_at, input_kind, image_ref, total_calories,
          LEFT(raw_text, 60) AS preview
   FROM food_logs
   WHERE user_id = (SELECT id FROM users WHERE email = '<your-email>')
   ORDER BY created_at DESC
   LIMIT 5;
   ```
4. For image saves, **explicitly verify `image_ref` is non-null**.
   Null = upload silently failed. Was an actual prod bug for ~2 weeks.

### Build verification command
```bash
cd "Food App" && xcodebuild build \
  -project "Food App.xcodeproj" \
  -scheme "Food App" \
  -destination "generic/platform=iOS Simulator"
```

### Production DB access
`backend/.env` has `DATABASE_URL` for the Supabase project. The
Claude Code harness gates `psql` against this URL — expect to ask
the user "go" once before running diagnostics, or add `Bash(psql:*)`
to `.claude/settings.local.json` for the session.

---

## 7. Pending work (ranked by priority)

### P0 — In flight today
- **TestFlight beta build under Apple review** (submitted 2026-05-06).
  Build is for External Testing. Sign-In Information was left blank
  with reviewer notes explaining Apple Sign In / Google Sign In are
  the only auth methods (no email/password exists in the iOS auth
  surface — `AccountProvider` enum has only `.apple` and `.google`).
  Apple's beta review typically returns within 24h.
- **Backend deploy of `a22e935`** (Saved Logs user filter) is in
  flight on Render. Validate post-deploy:
  ```bash
  curl -H "x-internal-metrics-key: $KEY" \
    "https://<render-url>/v1/internal/dashboard/users" | jq '.users | length'
  ```
  Should return ≥ 1 with `sodak@welldocinc.com` present.

### P1 — Auth surface gap (raised today, no fix landed)
The iOS app gates everything behind sign-in but only exposes Apple +
Google. This means:
- App Store proper review (when you submit for production release,
  not just TestFlight beta) will be harder to pass — reviewers may
  reject "we couldn't sign in with our test Apple ID."
- Internal QA can't easily script automated test runs (no
  programmatic credential entry).

Options ranked by effort:
1. **Add an email/password fallback** to onboarding behind a feature
   flag. Supabase already supports it (server-side); just needs a UI
   surface in `OB08AccountScreen.swift` + `AuthService.signIn(with:)`
   to dispatch to a third case `.email`.
2. **Add a hidden review-mode demo account** — a debug-build-only
   button on the welcome screen that signs in as a pre-provisioned
   test user. Lowest user-visible risk, simplest fix, but won't help
   real users who want email/password.
3. **Live with it** — add reviewer notes per build, accept reviewer
   roulette. Currently doing this.

### P2 — Tier 1 release batch (PRs #5–#10)
Seven PRs blocking the "Tier 1" release batch. See §3 for ordering.
The `integration/tier-1` branch is the staging target.

### P3 — Outstanding architectural cleanups
- **Phase 7A Part 4** (onboarding split, deferred via `7ce79fe`)
  — `OnboardingView` and friends still need extracting into a
  dedicated module like the logging extractions in `0673b39` /
  `fc8cd83` / `558b417` did.
- **`Food App.xcodeproj/project.pbxproj`** churn — Xcode keeps
  auto-touching this on every open. Worth investigating if a target
  config setting causes it (e.g. file ordering not deterministic).
- **`chore/streak-drawer-redesign` branch** — likely superseded;
  decide whether to merge or delete.

### P4 — Backend / dashboard polish
- The new `/users` endpoint (PR `a22e935`) is unauthenticated beyond
  the internal metrics key — same posture as the rest of the
  dashboard, but worth flagging for any future security review.
- The dashboard `Saved Logs` row table could expose `parseRequestId`
  as a clickable link to the corresponding parse-request detail view
  if that view exists; currently it's just a copyable id-chip.

---

## 8. Tooling / dev environment notes

- **rtk** (`brew install rtk`) is installed locally. Per-project
  Claude Code hook in `.claude/settings.local.json` (gitignored —
  see `2a5cca8`). The hook routes Bash tool calls through
  `rtk hook claude`, which token-compresses git/build/test output
  before it reaches the model context. Concretely:
  - `rtk err xcodebuild ...` filters Xcode output to errors only
    (251-line green build → 0 lines).
  - `rtk git diff` / `rtk git log` strip per-file boilerplate.
  - Run `rtk gain --graph` to see actual savings on your workflow.
  - Codex can install the same way: `brew install rtk` then
    `rtk init -g` (it'll print a settings.json snippet to add
    manually since Claude Code's settings file isn't auto-patched).
- **`xcodebuild` from CLI is preferred over Xcode GUI** for the
  reasons in §6.
- **The build database** (`~/Library/Developer/Xcode/DerivedData/Food_App-.../Build/Intermediates.noindex/XCBuildData/build.db`)
  can get locked when GUI + CLI builds race. Symptom: `unable to
  attach DB: database is locked`. Fix: quit Xcode entirely, retry, or
  `rm -rf ~/Library/Developer/Xcode/DerivedData/Food_App-*` for full
  clean.

---

## 9. Schema cheat sheet (high-traffic tables)

```
users(id UUID, email TEXT)                        — email is unique
parse_requests(request_id TEXT PK, user_id, raw_text, primary_route, cache_hit, created_at)
food_logs(id UUID, user_id, raw_text, total_calories, ..., input_kind, image_ref, parse_request_id, created_at)
food_log_items(food_log_id, food_name, quantity, unit, grams, calories, ...)
log_save_idempotency(idempotency_key, user_id, payload_hash, log_id, response_json)
```

Diagnostic patterns:
- `parse_requests` row but no `food_logs` row → save POST never
  reached server (or 401'd before reaching the route).
- `log_save_idempotency` row but no `food_logs` row → server-side
  insert failed mid-transaction.
- Both → save succeeded.

---

## 10. Quick "where do I look for X" index

| Need to look at...               | File / location                                                    |
|----------------------------------|--------------------------------------------------------------------|
| Logging UI orchestration         | `Food App/MainLoggingShellView.swift`                              |
| Save flow                        | `Food App/SaveCoordinator.swift` + `Food App/MainLoggingSaveFlow.swift` |
| Parse flow                       | `Food App/ParseCoordinator.swift` + `Food App/MainLoggingParseFlow.swift` |
| Day transitions / preserve drafts| `Food App/MainLoggingDateFlow.swift`                               |
| Day cache + sync                 | `Food App/MainLoggingDayCacheFlow.swift`                           |
| Auth                             | `Food App/AuthService.swift`, `Food App/AppStore.swift`            |
| Image storage                    | `Food App/ImageStorageService.swift`, `Food App/DeferredImageUploadStore.swift` |
| Onboarding screens               | `Food App/OB01*.swift` … `Food App/OB09*.swift`                    |
| Profile / Settings               | `Food App/HomeProfileScreen.swift` (extracted from ContentView)    |
| Streak drawer                    | `Food App/HomeFlowComponents.swift` (`HomeStreakDrawerView`)       |
| Backend save                     | `backend/src/routes/logs.ts`, `backend/src/services/logService.ts` |
| Backend parse                    | `backend/src/routes/logs.ts` parse endpoints                       |
| Backend streak                   | `backend/src/services/streakService.ts`                            |
| Internal testing dashboard       | `backend/src/routes/evalDashboard.ts` + `backend/src/testing-dashboard/index.html` |

---

*Generated 2026-05-06. Re-run any of the §2 git log queries to refresh
the timeline section.*
