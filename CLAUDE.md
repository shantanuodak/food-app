# Food App — Working Notes for Claude Sessions

This file is read by Claude at the start of every session. Keep it short
and focused on rules that have caught real production bugs.

## Save-path verification rule

Any change touching parse, save, autosave, image upload, `food_logs`,
`food_log_items`, or the iOS save flow (`MainLoggingShellView.submitSave`,
`prepareSaveRequestForNetwork`, `autoSaveIfNeeded`, `scheduleAutoSave`,
`buildRowSaveRequest`, or `ImageStorageService`) is **not done** until the
following has been performed and the result pasted in the response:

1. Build the iOS app with `xcodebuild` against an iOS Simulator.
2. Save a real meal end-to-end through the app — at minimum a text save,
   plus an image save if the change touched any image path.
3. Run this query against the production Supabase DB and paste the row:
   ```sql
   SELECT id, created_at, input_kind, image_ref, total_calories,
          LEFT(raw_text, 60) AS preview
   FROM food_logs
   WHERE user_id = (SELECT id FROM users WHERE email = '<your-email>')
   ORDER BY created_at DESC
   LIMIT 5;
   ```
4. For image saves, **explicitly check that `image_ref` is non-null**. A
   row with `image_ref = NULL` after an image-mode save means the upload
   silently failed — do not declare the change verified.

Why this rule exists: between 2026-04-16 and 2026-04-29, every "image"-
mode food_log was being persisted with `image_ref = NULL` because the
Supabase storage bucket had never been provisioned. Multiple sessions
shipped save-related changes and called the work done because
`xcodebuild` was green, without ever verifying that a row landed with the
photo attached. The bug surfaced loudly only when a separate fix
(`32ed2b7`, "Stabilize pending saves") removed a race that had been
silently swallowing the upload error — at which point image saves stopped
landing entirely. xcodebuild-green is necessary, not sufficient.

## Image upload is decoupled from save

After the fix in commit 0443246, `ImageStorageService.uploadJPEG`
failures no longer block `food_logs` from being persisted. The flow:

1. `prepareSaveRequestForNetwork` attempts the upload inline.
2. On success: the request goes out with `image_ref` populated.
3. On any failure (missing bucket, expired Supabase JWT, RLS misconfig,
   network blip): the bytes are stashed in `deferredImageUploads` (an
   in-memory dict keyed by idempotency key) and the save proceeds with
   `image_ref = nil`.
4. Once `submitSave` succeeds, `scheduleDeferredImageUploadRetry`:
   - Persists the bytes to disk via `DeferredImageUploadStore` (keyed by
     `logId`) BEFORE the upload attempt.
   - Runs the upload + `PATCH /v1/logs/:id/image-ref` in a detached task.
   - On success: removes the disk entry.
   - On failure: leaves the disk entry; `AppStore.drainDeferredImageUploads`
     picks it up next launch (or whenever `isSessionRestored` flips true).

The disk store (`Food App/DeferredImageUploadStore.swift`) caps at 50
entries with a 14-day TTL — bounded disk use even if storage is
permanently broken. `Food_AppApp.swift` calls
`drainDeferredImageUploads` once via `.task` and re-runs it whenever
`isSessionRestored` becomes true (covers cold-start before auth).

When debugging "my photo didn't attach":
- Check `food_logs.image_ref` — if it's NULL, both inline upload and
  the deferred retry failed.
- Look at `NSLog` output for `[MainLogging] Deferred image upload retry
  failed; persisted for next launch` (in-session retry failure) or
  `[AppStore] Drain retry failed` (launch-time retry failure).
- Inspect on-disk pending uploads:
  `~/Library/Developer/CoreSimulator/.../Application Support/DeferredImageUploads/`
- Most likely cause: Supabase storage bucket `food-images` doesn't exist,
  its RLS policies don't match the iOS user's `auth.uid()`, or the
  Supabase JWT used for the upload is missing storage scope.

## Schema cheat sheet (high-traffic tables)

- `users(id UUID, email TEXT)` — `email` is unique
- `parse_requests(request_id TEXT PK, user_id, raw_text, primary_route, cache_hit, created_at)` — every `/v1/logs/parse*` lands a row here
- `food_logs(id UUID, user_id, raw_text, total_calories, ..., input_kind, image_ref, parse_request_id, created_at)` — final meal records
- `food_log_items(food_log_id, food_name, quantity, unit, grams, calories, ...)` — line items, cascade-deleted with parent
- `log_save_idempotency(idempotency_key, user_id, payload_hash, log_id, response_json)` — every save POST creates a row here, even on retry

`parse_requests` row but no `food_logs` row → save POST never reached server (or 401'd before reaching the route).
`log_save_idempotency` row but no `food_logs` row → server-side insert failed mid-transaction.
Both → save succeeded.

## Production DB access

`backend/.env` has `DATABASE_URL` for the Supabase project. The harness
gates `psql` invocations against this URL — expect to ask the user "go"
once before running diagnostics, or have them add `Bash(psql:*)` to
`.claude/settings.local.json` for the session.

## iOS build verification

```bash
cd "Food App" && xcodebuild build \
  -project "Food App.xcodeproj" \
  -scheme "Food App" \
  -destination "generic/platform=iOS Simulator"
```

Use this rather than building inside Xcode. Concurrent edits + Xcode's
live indexer are a known source of `swbuild.tmp` filesystem-level errors
that look like real build failures but aren't.
