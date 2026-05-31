# Human-Verify Notes — bugs found but NOT auto-fixed

## ⚠️ SESSION UPDATE (worked through together after the overnight run — READ FIRST)
**Fixed + verified on the branch (each its own commit, tests green):**
- Backend: rate-limiter memory cap; notification timezone (IANA) + device-token validation; evalDashboard empty-list counter.
- iOS perf: cached 2 fixed-config `DateFormatter`s.

**Investigated → NOT REAL (false positives — do NOT chase these):**
- 🟢 `image_ref = NULL` on save failure (was the headline #1) — the durable pending-save *queue* persists the photo bytes (`PendingSaveQueueItem.imageUploadData` is `Codable`), so they survive a relaunch and the re-save re-uploads. The audit only saw the ephemeral in-memory dict and missed the queue.
- 🟢 "ghost rows" in `handleServerBackedRowCleared` — only runs for rows already saved on the server (no in-flight POST to ghost), and it deliberately *removes* the row from delete-tracking (opposite intent to its sibling). Discarding the keys is correct.

**Still open (minor, your call):** reduce-motion `4:4` value (needs a design decision). The remaining save-path / auth / camera items below are UNVERIFIED — given 2 of 2 checked turned out false-positive, treat them skeptically and ping me to verify any specific one before changing safety-critical code.

---


These were surfaced during the e2e review but **deliberately left untouched** because they
touch the save/parse/image path, auth, camera behavior, or otherwise need a behavioral
decision the build alone can't validate (per CLAUDE.md save-path rule). Each needs your eyes
+ a real device/sim test before fixing. Line numbers are approximate (from the audit at
`e71e52d`; some files shifted slightly during dead-code removal — grep the symbol).

Priority key: 🔴 high (data loss / silent failure / races) · 🟠 medium · 🟡 low/polish.

---

## 🔴 Save-path / data-integrity (matches prior production incidents)

1. **Deferred image bytes are NOT persisted to disk on a save *failure*** — `MainLoggingSaveFlow.swift` (`prepareSaveRequestForNetwork` catch). On upload failure the bytes go to the in-memory `deferredImageUploads` dict but `DeferredImageUploadStore` (disk) is only written from the *success* path. If the first save fails and the app relaunches before the queue flush, the image is lost → `image_ref = NULL`. This is the exact shape of the 2026-04 incident. Consider persisting to the disk store (keyed by idempotency key) inside the catch, migrating to `logId` on success.

2. **`SaveCoordinator.upsertPendingItem` matches `idempotencyKey` OR `rowID`** (~`SaveCoordinator.swift:150`). When a row has both a promoted (already-saved) queue entry and a fresh edit, the `rowID` branch can overwrite the promoted item's request with the edit while keeping the old `serverLogId` → a PATCH may go out with stale data, or a double-save. Prefer exact `idempotencyKey` match; only fall back to `rowID` when no key match exists.

3. **`autoSavedParseIDs.insert` happens before `await submitSave`, and is never cleared on failure** (~`MainLoggingSaveFlow.swift:219`). A transient network failure permanently marks the parse as "auto-saved", so future auto-save ticks skip the row (durable queue still retries, but the row looks stuck). On failure, remove the id from `autoSavedParseIDs` (gated on `SaveErrorPolicy.isNonRetryable == false`).

4. **`handleServerBackedRowCleared` discards `removePendingSaveQueueItems`'s return value** (`MainLoggingRowMutationFlow.swift:~148`). The removed keys are never unioned into `locallyDeletedPendingSaveKeys`, so a late in-flight save can resurrect a ghost row after a swipe-delete. `removeLocalRowFromDetails` does this correctly — mirror it.

5. **`reconcilePendingQueue` compares `loggedAt` by exact string equality** (~`SaveCoordinator.swift:339`). ISO8601 format skew (`...12.000Z` vs `...12Z`) leaves the pending item un-reconciled → the bottom "syncing" pill stays visible after the meal is already saved. Normalize both timestamps (or compare within a tolerance) before matching.

6. **`clearPendingSaveContext()` on a successful text parse can drop in-flight save context** (`MainLoggingParseFlow.swift:~281`). If a new parse lands between tapping Save and `submitSave` starting, `retryLastSave()` is silently swallowed (data not lost — queue is durable — but UX implies an error). Skip `clearPendingSaveContext()` when `isSaving == true`.

## 🔴 Auth / session (the overnight-logout area)

7. **`AuthService` single-flight joiner reuses the *first* caller's `metadata`** (~`AuthService.swift:837`). A second caller joining an in-flight refresh receives a session built from the first caller's profile metadata. Harmless today (one shared session) but a latent bug if multiple providers/metadata are introduced. Rebuild `makeAuthSession` with the joiner's own metadata after the task completes.

8. **`startMirroringSupabaseAuthState` Task is not stored/cancelled** (~`AuthService.swift:930`). Leaks the `authStateChanges` stream for any non-singleton `AuthService` (tests/previews). Store the handle; `deinit { mirroringTask?.cancel() }`.

9. **`runWithStartupTimeout` detached task strong-captures `self`** (~`AuthService.swift:224`). Keeps a non-singleton `AuthService` alive until the timeout. Capture `[weak self]`.

## 🔴 Profile / camera (data overwrite + concurrency)

10. **`CalorieHeroTile` creates its own `ProfileDraftStore`** separate from the bento screen's shared `draftStore` (`HomeProfileBentoScreen.swift`, `CalorieHeroTile`). Editing the goal via the hero tile writes to a different store than Diet/Body edits → last-writer-wins can silently overwrite a draft. Thread the shared `draftStore` in instead of `@StateObject`-ing a new one.

11. **`CameraService` mutates `@MainActor` `@Published` vars from the `sessionQueue` background thread** (`CameraService.swift:~113/132` — `videoDeviceInput`, `currentCameraPosition`). Unsynchronised cross-thread mutation (Swift-6 actor violation). Capture locals inside the `sessionQueue.sync`, assign on the MainActor after.

12. **`switchCamera()` reconfigures but never restarts a stopped session** (`CameraService.swift:~217`). After capture→stop, flipping the camera can leave the viewfinder black until another path calls `startSession()`. Call `startSession()` at the end of `switchCamera()` (guarded against double-start).

## 🟠 Medium

13. **Double-tap on "Save meal" can double-present the sheet** (`MainLoggingDrawerFlow.swift:~38/253`) — two `DispatchQueue.main.asyncAfter` blocks 350ms apart with no debounce; can yield a duplicate save sheet. Use a single cancellable `Task` instead of raw asyncAfter.

14. **Reduce-Motion handler is a no-op** (`HomeGreetingAnimations.swift:~277`): `headTopY = reduceMotion ? 4 : 4` — both branches assign `4`, so toggling Reduce Motion does nothing (head can be stuck mid-animation). It's clearly a typo, but the correct "hidden/rest" value depends on your intent (the loop animates `headTopY`) — likely `: 13`. **Left for you to confirm the value.**

15. **`HomeProfileScreen.saveStatusIndicator` renders `EmptyView` for `.saving` and `.saved`** — users get no save-progress/confirmation feedback (only the error triangle). The state machine drives those cases but nothing surfaces them. Same in `ProfileSaveStatusIndicator`.

16. **`QuickCameraLoggingService` background-task expiry handler is empty** (`:9`) — if iOS kills the background parse, no failure notification is posted and the "Analyzing…" notification can stick. Post a failure status + `endBackgroundTask` in the expiry handler.

17. **SSE streaming parse path** had errors fully swallowed — *fixed in backend commit* (added `console.error`). Noted here only for completeness.

## 🟡 Low / polish (recommended, not applied)

- **`DateFormatter` rebuilt per call/render** (perf): `HomeStreakDrawerView.dateKey`, `HomeFoodStoryDrawerView` (FoodStoryDayBuilder title/dateTitle), `ExistingAccountDetectedView.daysSinceCreated`, `MindfulPauseSheet.dateKey`, `LoggingResultDrawerBody.timeFormatter`. Promote to `private static let` (watch for per-call timezone params — those can't be fully static).
- **`QuickCameraPendingLogStore`**: no TTL/size cap → unbounded UserDefaults growth. Add an N-day eviction in `loadAll()`.
- **`MagnifyGesture` zoom onset** (`CameraView.swift:~272`): `== 1.0` first-event detection is unreliable; add `.onEnded` to snapshot `baseZoomFactor`.
- **Force-unwraps to tidy**: `ImageStorageService.swift:97/151` (`message!` → `?? default`), `HomeProfileScreen` `releaseVersion!`, `AppConfiguration.swift` `URL(string:)!`.
- **Backend remainder** (low-risk, can be applied with tests): rate-limiter bucket-size cap (`parseRateLimiterService`/`recipeImportRateLimiterService`); DNS-resolution timeout in `recipeImportService.assertResolvedHostIsPublic`; tighten `DELETE /devices/:token` to `min(32)`; add IANA timezone `.refine()` to notification preferences; `evalDashboard.ts:535` `||`→`??`. **CSP** (`app.ts:139`, `contentSecurityPolicy:false`) — re-enable with a dashboard-scoped nonce; left out to avoid breaking the dashboard.

## 🧰 Project hygiene (do in Xcode)
- **Duplicate font entries in Copy Bundle Resources**: `InstrumentSerif-Italic.ttf` and `InstrumentSerif-Regular.ttf` are listed twice (build warning every compile). Remove the dupes in Build Phases.
- **Empty/removed file**: `HomeFlowComponents.swift` was deleted (dead). If Xcode shows a stale red reference, remove it.
