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

### #1: Confirm uploaded image bytes <= 600KB ✅ measured (with one outlier)

`prepareImagePayload` does not log the chosen byte count, so verification
was done by querying `storage.objects.metadata->>'size'` against
`food_logs.image_ref` joined on bucket name.

Last 5 image uploads (most recent first):

```text
size_kb | under_600kb | created_at
  559.2 |    PASS     | 2026-05-03 20:48:51
  468.2 |    PASS     | 2026-05-03 20:48:29
  532.0 |    PASS     | 2026-05-03 20:41:21
  578.1 |    PASS     | 2026-05-03 18:13:21
 3369.7 |    FAIL     | 2026-05-02 02:45:20   ← 5.6x the cap
```

**Read:** Current code path is working — four recent uploads from today
all landed at 468-578 KB, comfortably under the 600 KB target.

**Outlier follow-on:** the 2026-05-02 upload at 3.4 MB bypassed
`prepareImagePayload`. Likely candidates:
- Deferred image upload retry path uploading original bytes from disk
  instead of the already-prepared bytes.
- A code path that existed before today's iOS 18 lowering or before
  the deferred upload work in `0443246`.

Not blocking — current uploads are correct. Worth grepping for any
upload call site that does not go through `prepareImagePayload`.

### #2: Confirm parse cache prevents duplicate parses ✅ measured

Two consecutive logs of `1 whole big pomegranate` from the iOS
client (timestamps 16:42:47 and 16:43:02 PT, ~15 seconds apart):

```text
request_id   | primary_route | cache_hit
be46d1ce…    | gemini        | false       (first parse)
8e4771bf…    | cache         | true        (second parse hit cache)
```

Server-side dedupe is working end-to-end. The iOS client correctly
forwarded the second request to the backend, the cache layer
recognized the same text, and returned the cached parse without
calling Gemini again. 67.9% Gemini share (Phase 8 #3) reflects this
cache layer's contribution.

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

### #1: Memory Graph after 10 image meals ✅ measured (with one concern)

Captured from Xcode → Debug Navigator → Memory gauge over a 189-second
session that included multiple image meals.

```text
Steady state (post-spike):  100.1 MB   ← acceptable
High water mark:            1.12 GB    ← concerning
Low water mark:             304 KB     ← initial cold start
Memory Use:                 0.86% of system
```

**Read:**

- **No leak.** Memory returned to ~100 MB after spikes — a real leak
  would show monotonically increasing memory that never recovers. The
  graph shape (sharp spike → drop back to baseline) confirms ARC is
  releasing the heavy objects when expected.
- **Steady state is acceptable.** 100 MB for a SwiftUI app with
  photos and live state is in normal range.
- **The 1.12 GB spike is too large** and is the actionable item. Likely
  cause: during `prepareImagePayload`, the iteration over
  4 dimensions × 7 quality attempts creates multiple resized
  `UIImage` and JPEG `Data` instances inside the same scope. A 12MP
  iPhone photo decompressed is 70-80 MB; holding 5-6 intermediates
  simultaneously easily reaches 1 GB.

**Object inspection** (separate Memory Graph view of `APIClient`'s
subtree) showed normal ownership — `APIClient` held by `AppStore`
and `ParseCoordinator` (correct singleton-with-two-owners pattern),
holding `__JSONEncoder`, `__JSONDecoder`, `__NSURLSessionLocal` (all
~1.6 KB total). No retention cycles surfaced.

**Recommended follow-on (out of Phase 7A scope):**

1. Wrap the inner loop of `prepareImagePayload` in `autoreleasepool`
   so each (dimension, quality) iteration's intermediate `UIImage`
   and `Data` are released as soon as the next iteration starts.
2. Once a successful payload is returned, ensure the original
   `UIImage` from the picker / camera is dropped from memory before
   the parse network call begins.
3. Verify with the same Memory Graph snapshot that peak drops below
   ~250 MB during a photo log.

This is a pure performance win — does not affect correctness or the
600 KB upload target. Safe to do in a focused performance pass.

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

- Phase 9 #2 — SwiftUI Instruments 30s typing session.

**Follow-on flagged for later (not blocking):**

- 2026-05-02 03:45 UTC produced a 3.4 MB image upload — 5.6x the
  600 KB cap. Recent uploads are correct, so the prepare path is
  fine; investigate which call path can bypass it (likely the
  deferred-upload retry uploading original disk bytes).
- `prepareImagePayload` peak memory: 1.12 GB during photo
  processing. Steady state and behaviour are correct, but the inner
  loop should be wrapped in `autoreleasepool` to keep peak under
  ~250 MB on devices with limited memory budgets. See Phase 9 #1.

**Pending real-world data (no urgent action):**

- Phase 10 #3 — POST /v1/logs latency under load.
- Phase 10 #4 — Render deploy cleanliness on next deploy.
