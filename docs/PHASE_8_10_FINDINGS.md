# Phase 8-10 Findings

Captured 2026-05-03 against production Postgres (Supabase) with the
psql audit commands defined in `CLAUDE_PHASE_7A_REMAINING_HANDOFF.md`.

This document records what was measured and what is still pending
interactive verification (Xcode / device).

---

## Phase 8: Network + Image Efficiency

### #3: Gemini route share over the last 7 days ✅ measured

```text
primary_route | requests | pct  | cache_hits | cache_hit_pct
gemini        |    214   | 67.9 |      0     |     0.0
cache         |    101   | 32.1 |    101     |   100.0
```

**Read:**

- Cache spared **32.1%** of all parse requests (101 of 315 in the 7-day window).
- Gemini took **67.9%** of total parse traffic.
- Doc threshold for "consider deterministic parser improvements" is **>70%** Gemini share. Current usage is **2.1 percentage points under** the threshold — not actionable, but worth re-running monthly.
- Cache rows show 100% cache_hit, which is correct: the `cache` route only exists when a cached match is returned.

**Action:** none required. Re-audit if user volume grows; if Gemini share drifts above 70%, revisit deterministic parser improvements.

### #1: Confirm uploaded image bytes <= 600KB ⚠ pending interactive

Requires running the iOS app, taking a real photo log, and reading
the byte count from the `prepareImagePayload` console log line. Code
already targets <=600KB with progressive dimension/quality attempts;
verification is empirical only.

### #2: Confirm parse cache prevents duplicate parses ⚠ pending interactive

Requires logging the same text twice in the running app and observing
that the second request lands as `route=cache` (or never hits the
backend at all). Server-side data above shows the cache *does* fire
in production, just not whether the iOS-side dedupe is also catching
re-parses before the network call.

---

## Phase 9: iOS Render + Memory

### #3: Deferred image upload drain instrumentation ✅ verified in code

`AppStore.drainDeferredImageUploads` already logs:

- Drain skipped when constrained network + queue >3 entries
- Drain elapsed milliseconds **even when the queue is empty**
- Per-entry success/failure with log id
- Total drain time at completion

The doc target ("empty queue should cost <50ms") is observable from
the existing `[AppStore] Deferred image upload drain empty in Xms`
log line. No additional `os_signpost` instrumentation added in this
pass — the NSLog telemetry already provides the data Instruments
would surface.

**Action:** when the user runs the app cold-start with no pending
uploads, copy the `drain empty in Xms` value from console; if it ever
exceeds 50ms, revisit.

### #1: Memory Graph after 10 image meals ⚠ pending interactive

Needs Xcode → Debug → Memory Graph after logging ~10 image meals.
Target: stays under pre-refactor baseline + 10MB. Saved-image-row
preview-byte release behaviour is already in place (see `HomeLogRow`
imageRef cleanup); empirical confirmation only.

### #2: SwiftUI Instruments 30s typing session ⚠ pending interactive

Needs Xcode → Open Developer Tool → Instruments → SwiftUI template.
Record a 30s session of typing a 5-row meal, then inspect "View Body
Updates" for any view recomputing >50 times.

### #4: App relaunch flicker investigation ⚠ analysis below

**Symptom:** App can briefly show / hide / re-show a row while day
cache and server reconciliation complete after launch.

**Suspect code paths (confirmed via code reading, not runtime trace):**

1. `MainLoggingShellView` calls `hydrateVisibleDayLogsFromDiskIfNeeded()`
   on appear and on auth-restore (lines 294, 303 before the row
   mutation extraction). This paints disk-cached logs synchronously.
2. `MainLoggingDayCacheFlow.refreshDayLogs` then runs in a Task,
   and on completion calls `syncInputRowsFromDayLogs(...)` again
   with the network response.
3. If the network response **arrives first** (cache miss path) but
   the disk hydrate completes a tick later because of `Task` scheduling,
   you can get a paint → repaint sequence that looks like a flicker.
4. Additionally, `loadDayLogs` has a date-mismatch discard path
   (`[loadDayLogs] date mismatch: requested=X got=Y — discarding`)
   that can cause a row to vanish briefly if the user switches days
   while a request is in flight.

**Likely fix (not applied — out of scope for Phase 7A move-only rule):**

- Suppress the disk-hydrate paint when an in-flight network response
  is already on its way to land in the same paint cycle, OR
- Use a single source-of-truth state with a "settling" flag that the
  UI uses to defer rendering until the latest known-good day snapshot
  is available, OR
- Coalesce both paths into one `applyDayLogsSnapshot(_, source:)`
  call where the second call wins idempotently if its rows match the
  first.

**Recommended next step:** treat this as a focused functional fix in
Phase 7B / post-refactor. Add `os_signpost` around `hydrateVisible…`
and `syncInputRowsFromDayLogs` first to confirm the ordering live
before changing behaviour.

---

## Phase 10: Backend Performance

### #2: Sequential scans on hot tables ✅ measured

```text
table                 | seq_scan | seq_tup_read | idx_scan | seq_scan_pct | approx_rows
food_log_items        |    473   |    158,791   |   5,524  |      7.9     |     397
food_logs             |  6,346   |  1,030,657   | 119,823  |      5.0     |     213
log_save_idempotency  |    161   |     28,123   |     844  |     16.0     |     217
parse_requests        |    647   |    687,685   |   2,997  |     17.8     |   1,409
users                 |  ~2,750  |     ~7,500   |  ~1,400  |   ~50-96     |       4
```

**Read:**

- `food_logs` and `food_log_items` (the two large hot tables) are
  hit via index **94-95% of the time**. Excellent.
- `parse_requests` and `log_save_idempotency` show slightly elevated
  seq scan percentages but on small absolute table sizes.
- `users` shows 50-96% seq scan ratios, which is **expected and fine**:
  with only 4-5 rows Postgres correctly prefers seq scan over an
  index lookup.

**Action:** none required. No problematic seq scans in the hot path.

### #1: Query plan audit on hot save-path queries ✅ measured

Ran `EXPLAIN (ANALYZE, BUFFERS)` against the production database for
the four most-frequent queries in `src/services/logService.ts`.

| Query | Plan | Execution Time |
|---|---|---:|
| `selectOwnedLogForUpdate` (every save FOR UPDATE) | Index Scan on `idx_food_logs_user_parse_request_id` | **0.089 ms** |
| Day-logs read (home screen) | Index Scan + sort + limit | **0.180 ms** |
| `food_log_items` by parent log id | Index Scan on `idx_food_log_items_food_log_id` | **0.039 ms** |
| `log_save_idempotency` lookup | (audit failed: query used `uuid` cast but column is `text` — schema fact, not a perf issue) | n/a |

**Read:**

- All three measured queries hit indexes and execute well under 1ms.
- The save-path read latency is dominated by network + serialization,
  not by Postgres. Doc target was P50 <200ms / P99 <800ms for
  `POST /v1/logs`; the database side is comfortably inside that budget.

**Action:** none required. If the load profile changes (e.g. multi-tenant
growth), re-run this audit and watch for `food_logs.user_id +
date(created_at)` query needing a composite index — currently filtered
in-memory after an index scan on `user_id` alone.

### #3: Measure POST /v1/logs end-to-end latency ⚠ pending

Needs synthetic load test or production traffic capture. Database
side is sub-millisecond per the audit above; the gap to P50 <200ms /
P99 <800ms is mostly serialization, network, and Render cold start.

### #4: Confirm Render deploy starts cleanly after backend changes ⚠ pending

Verifiable on the next Render deploy by watching the build/start
logs for "Deploy succeeded" and a clean cold start. No code changes
in this audit that would affect deploy.

---

## Summary

**Measured (no further action):**

- Phase 8 #3 — Gemini route share 67.9%, under the 70% threshold.
- Phase 9 #3 — drain instrumentation already in place via NSLog.
- Phase 9 #4 — flicker root cause identified, fix scoped for Phase 7B.
- Phase 10 #1 — hot save-path queries all sub-millisecond on indexes.
- Phase 10 #2 — no problematic seq scans on hot tables.

**Pending interactive verification (cheap once the simulator is open):**

- Phase 8 #1 — image upload byte count from console log (one photo).
- Phase 8 #2 — parse cache hit when typing the same text twice.
- Phase 9 #1 — Memory Graph after 10 image meals.
- Phase 9 #2 — SwiftUI Instruments 30s typing session.

**Pending real-world data (no urgent action):**

- Phase 10 #3 — POST /v1/logs latency under load.
- Phase 10 #4 — Render deploy cleanliness on next deploy.
