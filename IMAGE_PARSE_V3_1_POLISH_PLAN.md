# Image Parse V3.1 — Polish & Robustness

**Status:** Planned, not started
**Owner:** Claude (Opus 4.7) implements; user tests on device
**Created:** 2026-05-20, post V3 backend live + label-lane proof in prod
**Estimated:** ~7-10h Claude focused work, ~4-7 days wall-clock with TestFlight cycles

---

## What we're building and why

V3 shipped: lane router, cuisine prompts, Gemini 3.1 Flash Lite, EXIF fix, eval-rigging removed. Label lane confirmed working in production (Chobani Greek Yogurt save).

V3.1 is the **polish layer** that makes the V3 stack feel like a real product. Six items, six phases, in dependency order:

| # | Phase | Claude time | User time | Calendar |
|---|---|---|---|---|
| 0 | Backend `userService` email leak fix + cleanup | ~30 min | ~5 min | Same day |
| 1 | Camera v2 foundation (AVCaptureSession) | 3-5h across 2 sessions | 30 min/cycle × 2-3 | 2-3 days |
| 2 | Live viewfinder detection overlay | ~1h (builds on Phase 1) | 15 min | Same day as Phase 1 final ship |
| 3 | Mode icon row + first-launch tip | ~30 min | 10 min | Same iOS push as Phase 1/2 |
| 4 | Lane status indicator in drawer | ~30 min | 10 min | Same iOS push as Phase 1/2 |
| 5 | Onboarding duplicate-account fix | 3-4h across 2 sessions | 30 min/cycle × 2 | 1-2 days |
| 6 | Validation pass + friends/family rollout | ~30 min Claude + your testing | 1-2h | 1 day |

**Total Claude implementation: ~9-12h. Total user time: ~4-6h across calendar. Wall-clock: ~5-7 days.**

---

## Dependency graph

```
Phase 0 (backend) ────────────────────────┐
                                          │
Phase 1 (camera v2 foundation)            │
       │                                  │
       ├──→ Phase 2 (live overlay)        ├──→ Phase 6 (validation + rollout)
       ├──→ Phase 3 (icons + tip)         │
       └──→ Phase 4 (drawer indicator)    │
                                          │
Phase 5 (onboarding) ─────────────────────┘
```

Phases 1-4 all touch the camera/drawer surface — bundle into a single TestFlight push.
Phase 5 is its own iOS push (different surface).
Phase 0 is backend-only, ships independently.

---

## Phase 0: Backend userService email leak fix

**Goal:** Stop new pollution of `<UUID>@dev.local` rows for real users + clean up the existing 52.

**Time:** Claude ~30 min, user ~5 min verify.

### What I do

1. Edit `backend/src/services/userService.ts` — add the "synthetic email override" CASE to the UPSERT clause:

```sql
SET email = CASE
  WHEN users.email LIKE '%@dev.local' AND EXCLUDED.email NOT LIKE '%@dev.local'
    THEN EXCLUDED.email
  ELSE COALESCE(NULLIF(users.email, ''), EXCLUDED.email)
END
```

2. Add unit test in `backend/tests/userService.unit.test.ts` (new file or extend existing): verify a synthetic `@dev.local` email gets overwritten by a real email on second call.

3. Run `npm test` and `npm run build` — must pass.

4. Run the cleanup SQL against prod DB (with `BEGIN`/`COMMIT` wrap):

```sql
BEGIN;
DELETE FROM food_logs WHERE user_id IN (SELECT id FROM users WHERE email LIKE '%@dev.local');
DELETE FROM parse_requests WHERE user_id IN (SELECT id FROM users WHERE email LIKE '%@dev.local');
DELETE FROM image_parse_attempts WHERE user_id IN (SELECT id FROM users WHERE email LIKE '%@dev.local');
DELETE FROM log_save_idempotency WHERE user_id IN (SELECT id FROM users WHERE email LIKE '%@dev.local');
DELETE FROM users WHERE email LIKE '%@dev.local';
SELECT 'remaining_users' AS metric, COUNT(*) FROM users;
-- inspect — should be 6 if we got rid of all pollution
COMMIT;
```

5. Commit + push.

### What you do

- Quick sanity check: query `SELECT COUNT(*) FROM users` — should show ~6, not 58.
- Render auto-deploys on push.

### Acceptance

- Tests green
- Cleanup commit pushed and deployed
- `users` table shows only real accounts
- Next time a synthetic `@dev.local` email tries to land, it gets overwritten on the second ensureUserExists call

### Risks

- Cleanup is destructive — `BEGIN`/`COMMIT` wrap allows rollback if something looks wrong.
- The 8 stray food_logs in the dev.local bucket are deleted forever (acceptable — they're test data).

### Commit message

`Phase 0: heal synthetic <UUID>@dev.local emails on UPSERT + cleanup 52 polluted rows`

---

## Phase 1: Camera v2 foundation (AVCaptureSession)

**Goal:** Replace `UIImagePickerController` (for camera capture only) with a custom AVCaptureSession-based view that has tap-to-focus, macro auto-engage, and HEIF support. Keep `UIImagePickerController` (or upgrade to `PHPickerViewController` if cheap) for photo library selection.

**Time:** Claude ~3-5h across 2 sessions (initial implementation + post-test fixes), user ~30 min per TestFlight cycle × 2-3 cycles.

### What I do

#### Session 1 (initial implementation, ~2-3h)

1. Create `Food App/CustomCameraView.swift`:
   - `UIViewControllerRepresentable` wrapping a custom UIKit camera VC
   - `AVCaptureSession` configured for `.photo` preset (or `.hd1920x1080` minimum)
   - `AVCaptureVideoPreviewLayer` for the viewfinder
   - `AVCapturePhotoOutput` for stills
   - Lifecycle handled: start session on appear, stop on disappear

2. Implement tap-to-focus:
   - `UITapGestureRecognizer` on preview view
   - Convert tap point to capture device point via `videoPreviewLayer.captureDevicePointConverted(fromLayerPoint:)`
   - Set `device.focusPointOfInterest` + `device.focusMode = .autoFocus`
   - Show brief yellow square animation at tap location for visual feedback

3. Enable macro auto-engage (iOS 15+ iPhone 13 Pro+):
   - Set `device.automaticallyAdjustsVideoHDREnabled = true`
   - Set `device.activePrimaryConstituentDeviceSwitchingBehavior = .auto` (modern API)
   - Auto-switches to ultra-wide for macro distance

4. Continuous autofocus by default:
   - `device.focusMode = .continuousAutoFocus`
   - `device.exposureMode = .continuousAutoExposure`

5. Photo capture:
   - Trigger button → `photoOutput.capturePhoto(with: settings, delegate: self)`
   - HEIF settings: `AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])` if supported, fall back to JPEG
   - In delegate `photoOutput(_:didFinishProcessingPhoto:error:)`, convert to `UIImage` and call the same handler as today's flow

6. Replace the existing camera invocation site (find via `imagePickerSourceType: UIImagePickerController.SourceType = .camera`):
   - When user taps "Camera," present `CustomCameraView` instead of `UIImagePickerController`
   - Keep `UIImagePickerController` (or PHPickerViewController if simple swap) for library picks

7. Permissions:
   - Already have `NSCameraUsageDescription` in Info.plist (used by UIImagePickerController) — verify still present
   - Request `AVCaptureDevice.requestAccess(for: .video)` on first appear if not granted

#### Session 2 (post-test fixes, ~1-2h)

After first device test, iterate on whatever you find. Likely issues to expect:
- Orientation handling — the `AVCaptureVideoPreviewLayer.connection?.videoRotationAngle` needs setting per device rotation
- Photo output orientation — `photo.metadata` may need explicit handling
- iPad split-view if you support it
- Permission denial state — graceful "open Settings" prompt

### What you do

- After session 1 commit + push: pull, archive, upload to TestFlight, install on device, take 5-10 photos (food + barcode + label). Report what looks wrong.
- After session 2 fixes: same cycle.

### Files affected

| File | Action |
|---|---|
| `Food App/CustomCameraView.swift` | CREATE |
| `Food App/CustomCameraView+FocusAnimation.swift` | CREATE (small helper) |
| `Food App/HomeLoggingSupportViews.swift` | MODIFY — `HomeImagePicker` routes camera to new view |
| `Food App/MainLoggingShellView.swift` | MODIFY — wire the new picker entry |
| `Food App/MainLoggingCameraDrawerFlow.swift` | NO CHANGE — receives `UIImage` same as before |
| `Food App/Info.plist` | VERIFY only — camera permission string already present |

### Verification

1. Photo capture works (basic)
2. Tap-to-focus visibly shows focus square and locks focus
3. Macro auto-engages when you get close to a barcode (visible in viewfinder — image zooms slightly)
4. Compare barcode parse latency vs old `UIImagePickerController`:
   - Old: ~5-10% of barcode attempts fell below 0.95 confidence due to soft focus → vision lane
   - New: should be ~95%+ barcode lane fire rate on close-up packaged items
5. Memory stable — no leaks on session start/stop cycles
6. Run `xcodebuild build` between sessions to catch compile errors fast

### Risks

- **AVCaptureSession lifecycle is finicky** — must stop on disappear or session keeps camera locked. Will set up `viewDidDisappear` + `applicationWillResignActive` notifications.
- **Macro mode is iPhone 13 Pro+ only** — older devices just won't engage it (graceful)
- **First device test will likely surface 1-2 bugs** — that's why session 2 is budgeted

### Rollback

Custom camera is opt-in via a single call site. If issues are severe, revert that one call site to `UIImagePickerController` and the rest of V3 keeps working. Single-commit rollback.

### Commit messages

- Session 1: `Phase 1: AVCaptureSession-based custom camera with tap-to-focus + macro`
- Session 2 (fixes): `Phase 1 fixes: <specific issues found in device testing>`

---

## Phase 2: Live viewfinder detection overlay

**Goal:** Show "📊 Barcode detected — tap to capture" or "📋 Nutrition label detected — tap to capture" in the viewfinder when iOS Vision detects them in real-time.

**Time:** Claude ~1h (depends on Phase 1's AVCaptureSession existing), user ~15 min testing.

### What I do

1. Add `AVCaptureMetadataOutput` to the session in `CustomCameraView`:
   ```swift
   let metadataOutput = AVCaptureMetadataOutput()
   session.addOutput(metadataOutput)
   metadataOutput.metadataObjectTypes = [.ean13, .ean8, .upce, .code128]
   metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
   ```

2. Implement `metadataOutputDidOutput(_:from:connection:)`:
   - When barcode object received → update `@State var detectedBarcode: AVMetadataMachineReadableCodeObject?`
   - When no barcodes for 500ms → clear the state (debounce)

3. Add SwiftUI overlay above `CustomCameraView`:
   - When `detectedBarcode != nil` → show pill at top: "📊 Barcode detected — tap shutter"
   - Subtle animation (fade in/out)

4. Add live OCR via `VNRecognizeTextRequest` on a throttled basis (every ~500ms on a still frame extracted from the preview):
   - Throttle aggressively — don't run every frame, costs battery + CPU
   - When detected text contains "Nutrition Facts" / "Calories" / "Total Fat" tokens (2+ matches) → show "📋 Nutrition label detected — tap shutter"

5. Visual feedback: a brief yellow outline appears around the detected barcode in the viewfinder (using `metadataObject.bounds` mapped to view coordinates).

### What you do

- Pull, archive, push to TestFlight
- Point camera at:
  - A Diet Coke can barcode → should see "📊 Barcode detected" within ~1s
  - A nutrition label panel → should see "📋 Nutrition label detected" within ~1-2s
  - A plate of food → nothing extra (just food camera, default behavior)
- Report any false positives (e.g., label overlay showing on random text)

### Files affected

| File | Action |
|---|---|
| `Food App/CustomCameraView.swift` | MODIFY — add metadata output + OCR throttling + overlay |
| `Food App/CameraViewfinderOverlay.swift` | CREATE — SwiftUI overlay components |

### Verification

1. Barcode detection works in <1s on clear UPC
2. Label detection works in 1-2s on clear Nutrition Facts panel
3. No detection overlay on random food photos
4. No battery drain over a 60s viewfinder session (test by leaving camera open and watching battery indicator)

### Risks

- **Live OCR is expensive** — every-frame `VNRecognizeTextRequest` would melt the device. Throttle to ~500ms or use a downscaled preview frame. Aggressive throttle is key.
- **False positives on text-heavy backgrounds** — restaurant menus, food packaging with marketing text. Will tune the "Nutrition Facts" token threshold high enough to avoid these.

### Commit message

`Phase 2: live viewfinder detection — barcode + label overlay with throttled VNRecognizeText`

---

## Phase 3: Mode icon row + first-launch tip

**Goal:** Communicate the three lanes without lecturing — small icon row at top of camera screen + one-time first-launch tip.

**Time:** Claude ~30 min, user ~10 min testing.

### What I do

1. Add `CameraModeIconRow.swift` — a tiny SwiftUI view with three icons across the top:
   ```
   📊 Barcode     📋 Label     🍽 Food
        Auto-detected
   ```
   No tap targets — purely informational. ~24pt height.

2. Embed in `CustomCameraView` overlay (top of viewfinder, below status bar).

3. First-launch tip:
   - Check `UserDefaults.standard.bool(forKey: "cameraTipShown")` — if false, show overlay sheet on first camera open:
     > **Quick tip**
     >
     > For packaged items, point at the barcode or nutrition label — the app will auto-detect and use the fastest lookup.
     >
     > For meals, just take the photo.
     >
     > [Got it]
   - On dismiss, set the flag to true. Never show again.

### What you do

- Pull, push to TestFlight
- Open camera as a "new user" (delete and reinstall the app, or clear UserDefaults) — verify tip shows once and only once
- Verify icon row looks clean, doesn't crowd the viewfinder

### Files affected

| File | Action |
|---|---|
| `Food App/CameraModeIconRow.swift` | CREATE |
| `Food App/CameraFirstLaunchTip.swift` | CREATE |
| `Food App/CustomCameraView.swift` | MODIFY — embed both overlays |

### Acceptance

- Icon row visible, doesn't obstruct shooting
- First-launch tip appears once for new users
- Tip is dismissable, doesn't reappear on subsequent opens

### Risks

- Trivial. Localization of tip text might come up later (skip for now)

### Commit message

`Phase 3: camera mode icon row + first-launch tip`

---

## Phase 4: Lane status indicator in drawer

**Goal:** Once the user taps shutter, the analyzing drawer shows lane-specific status text instead of generic "analyzing."

**Time:** Claude ~30 min, user ~10 min testing.

### What I do

1. In `MainLoggingCameraDrawerFlow.parseAndUpdateDrawer`, after `decideLane(visionResult:)` runs (line ~155 of the file), update drawer state with the lane:

```swift
let lane = decideLane(visionResult: visionResult)
withAnimation {
    cameraDrawerState = .analyzing(image, lane: lane)  // pass lane through
}
```

2. Add `lane` to the `.analyzing` enum case in the drawer state.

3. In the drawer view's `.analyzing` rendering, switch on lane and show the right copy:
   - `.barcode` → "Scanning barcode…"
   - `.label` → "Reading nutrition label…"
   - `.vision` → "Analyzing your meal…"

4. Same for `QuickCameraLoggingService` if it presents an analyzing UI somewhere (probably it's notification-based, so just a one-line tweak to the analyzing notification text).

### What you do

- Pull, push to TestFlight
- Take 3 photos:
  - Diet Coke can → drawer should say "Scanning barcode…"
  - Nutrition label close-up → "Reading nutrition label…"
  - Any meal → "Analyzing your meal…"

### Files affected

| File | Action |
|---|---|
| `Food App/MainLoggingCameraDrawerFlow.swift` | MODIFY — pass lane to drawer state |
| `Food App/CameraResultDrawerView.swift` | MODIFY — render lane-specific text |
| `Food App/QuickCameraNotificationService.swift` | MODIFY — lane-specific analyzing notification |

### Acceptance

- Drawer shows correct lane text in <500ms after capture
- No flash/flicker between generic "analyzing" and lane text
- All three lanes produce their distinct copy

### Commit message

`Phase 4: lane-specific status text in analyzing drawer`

---

## Phase 5: Onboarding duplicate-account fix

**Goal:** Existing users who accidentally start the Sign Up flow can recover without losing their existing account or data.

**Time:** Claude ~3-4h across 2 sessions, user ~30 min per cycle × 2.

### What I do

#### Session 1 (backend + button visibility, ~1.5h)

1. **Sign-in button visibility** (`Food App/OnboardingWelcomeView.swift` or similar — need to find the entry screen):
   - Add a prominent "Sign In" button in the top-right of the welcome screen
   - Keep the existing "Already have an account?" footer link
   - Ensure both respect `safeAreaInsets` and aren't hidden under the iOS 18 home indicator
   - Two paths to the same place

2. **Backend endpoint** `backend/src/routes/auth.ts` (or extend `parse.ts`):
   ```ts
   POST /v1/auth/check-identity
   Body: { provider: 'apple' | 'google', idToken: string }
   ```
   - Validates the OAuth token
   - Looks up the corresponding user in `auth.users` AND `app.users`
   - Returns:
     ```json
     {
       "exists": true,
       "userId": "...",
       "displayName": "...",
       "mealCount": 47,
       "lastActiveAt": "2026-05-18T..."
     }
     ```
   - Or `{ "exists": false }` if no match.

3. Add unit test for the endpoint.

#### Session 2 (iOS UX + wiring, ~1.5-2h)

4. **New SwiftUI screen** `Food App/ExistingAccountDetectedView.swift`:
   ```
   Welcome back, [Name]!
   You already have an account with 47 meals logged and goals set up.
   
   [ Continue with my existing account ]   ← primary CTA
   [ Update my profile with new info ]      ← secondary
   [ Cancel ]                               ← tertiary
   ```

5. **Wire onboarding submit → OAuth → check-identity → branch:**
   - User completes onboarding flow (name, height, weight, goals, etc. — held in memory)
   - User taps "Continue with Apple/Google" at the end
   - iOS receives OAuth callback with `idToken`
   - iOS POSTs to `/v1/auth/check-identity` BEFORE creating the user
   - If `exists: true` → navigate to `ExistingAccountDetectedView` with the data
     - "Continue with existing" → sign in, discard the in-memory onboarding data, go to home
     - "Update profile with new info" → sign in, PATCH the existing user's profile with the in-memory onboarding fields (height, weight, goals — NEVER food_logs), then go to home
     - "Cancel" → back to onboarding entry
   - If `exists: false` → existing flow continues, create user with the onboarding data

6. **Important constraint:** The "Update profile with new info" path must touch ONLY `users.profile_json` or equivalent, NEVER `food_logs`. Add a regression test.

### What you do

#### After Session 1
- Pull, push to TestFlight
- On the onboarding welcome screen, verify Sign In button is prominent and tappable (top-right + footer link)

#### After Session 2
- Test scenario A: brand new user → Sign Up flow → OAuth → completes normally → no "existing account detected" screen
- Test scenario B: existing user → accidentally taps Sign Up → fills onboarding → OAuth with the same Apple/Google identity used before → sees "Welcome back" screen → taps "Continue with existing" → lands on home with all old data intact
- Test scenario C: same as B but taps "Update profile with new info" → existing data preserved, profile reflects new onboarding fields
- Test scenario D: same as B but taps "Cancel" → back to onboarding start

### Files affected

| File | Action |
|---|---|
| `Food App/OnboardingWelcomeView.swift` (or equiv) | MODIFY — add prominent Sign In |
| `Food App/ExistingAccountDetectedView.swift` | CREATE |
| `Food App/OnboardingCoordinator.swift` (or equiv) | MODIFY — branch on identity check result |
| `Food App/APIClient.swift` | MODIFY — add `checkIdentity(provider:idToken:)` method |
| `backend/src/routes/auth.ts` | CREATE or MODIFY — add `/check-identity` endpoint |
| `backend/src/services/userService.ts` | MODIFY — add `findUserByOAuthIdentity()` |
| `backend/tests/auth.unit.test.ts` | CREATE or EXTEND |

### Acceptance

- All 4 test scenarios above pass
- food_logs of existing user are NEVER touched in any path
- Sign In button is visible and tappable from welcome screen

### Risks

- **OAuth flow varies between Apple and Google** — Apple's "Hide my email" gives you a private relay address that's stable per user but doesn't match the user's real email. The check-identity must compare against the OAuth `sub` (subject ID), not just email.
- **Race condition** — if the user signs in BEFORE the identity check returns, you could create a duplicate. Wire the check synchronously before the Supabase signIn call.

### Commit messages

- Session 1: `Phase 5a: sign-in button visibility + /v1/auth/check-identity endpoint`
- Session 2: `Phase 5b: existing-account-detected screen + onboarding branch logic`

---

## Phase 6: Validation pass + friends/family rollout

**Goal:** Confirm everything from Phases 0-5 is solid, then expand TestFlight to 3-5 friends/family.

**Time:** Claude ~30 min validation queries + helping interpret results, user ~1-2h doing real-world testing.

### What I do

1. Pull recent activity from prod DB:
   - `food_logs` distribution by `input_kind` for the user — should see `image_barcode`, `image_label`, `image`, `text` all represented
   - Image parse attempt latencies — vision lane should be <8s p95
   - Any failed parses — investigate root cause

2. Check that the V3.1 changes didn't regress anything:
   - Existing `food_logs` saves still work
   - No spike in error rates
   - No new `@dev.local` rows

3. Help interpret any issues you surface during your testing.

### What you do

1. **Final personal validation** — log 10-15 real meals across:
   - 2-3 barcode items (different brands)
   - 2-3 nutrition label photos
   - 4-5 prepared meals (different cuisines if possible)
   - 2-3 text logs

2. **Pick 3-5 forgiving friends/family.** Bias toward technical / honest reporters.

3. **Set up a feedback channel** — pick one:
   - Notion page
   - Google Form
   - Dedicated iMessage group
   - Email alias

4. **Compose the invite message:**
   > Hey — beta-testing my food logging app. Early days, things may break. Please tell me what's broken (screenshots help).
   >
   > Particularly want to know: does the camera find barcodes / nutrition labels automatically? Do meals get identified correctly?
   >
   > Beta invite link: [TestFlight URL]
   >
   > Thanks 🙏

5. **Watch the inbox + DB.** Run the lane-distribution query weekly to see what's actually firing for real users.

### Acceptance

- 3-5 testers installed and have logged at least 3 meals each within a week
- No crash reports from testers
- Lane distribution in `food_logs` shows barcode + label + vision all firing
- Feedback channel has at least one useful piece of feedback

---

## How sessions break down

Realistic Claude session structure across this plan:

| Session | Phases | Time |
|---|---|---|
| 1 | Phase 0 + Phase 4 (small wins, warm-up) | ~1h |
| 2 | Phase 1 session 1 (camera v2 foundation) | ~2.5h |
| 3 | Phase 1 session 2 (camera fixes after device test) | ~1.5h |
| 4 | Phase 2 + Phase 3 (live overlay + icons + tip) | ~1.5h |
| 5 | Phase 5 session 1 (backend + sign-in button) | ~1.5h |
| 6 | Phase 5 session 2 (existing-account screen + wiring) | ~1.5h |
| 7 | Phase 6 (validation + rollout help) | ~30 min |

**Total: ~10h Claude work across 7 sessions, ~5-7 days calendar.**

---

## What we're NOT doing in V3.1

Explicitly out of scope, capture for backlog if/when relevant:

1. **Server-side OCR fallback** (Phase 9 of original V3 plan) — when iOS Vision OCR misses a label
2. **RAG with user history** for personalization — needs telemetry collection first
3. **Backend OCR for non-label vision lane** — vision lane stays Gemini-only
4. **Real chain restaurant database** (Chipotle, Sweetgreen, etc.) — needs Nutritionix or curated work
5. **Streaming SSE responses** — bigger UX rework, not in this polish layer
6. **iOS widget improvements** — quick camera widget keeps current behavior
7. **Apple HealthKit deeper integration** — separate effort
8. **Multi-photo / multi-angle support** for complex meals — defer

---

## Stop conditions

Stop and reassess if:

- **Camera v2 takes more than 8h of Claude work total** — means there's something architecturally wrong; consider keeping `UIImagePickerController` and shipping the rest
- **Real-device crashes in Phase 1 testing** — fix immediately before adding Phase 2-3 on top
- **Friends/family find a class of bugs we didn't anticipate** — pivot priority to fix those before continuing the plan
- **Render env or backend goes down** — pause iOS work, fix infrastructure first
- **You decide the polish isn't worth the time** — totally valid. The V3 stack works today. This plan is "make it feel great" not "make it work."

---

## Quick reference: commit history at end of V3.1

```
Phase 0: heal synthetic <UUID>@dev.local emails on UPSERT + cleanup 52 polluted rows
Phase 4: lane-specific status text in analyzing drawer
Phase 1: AVCaptureSession-based custom camera with tap-to-focus + macro
Phase 1 fixes: <device-specific issues>
Phase 2: live viewfinder detection — barcode + label overlay
Phase 3: camera mode icon row + first-launch tip
Phase 5a: sign-in button visibility + /v1/auth/check-identity endpoint
Phase 5b: existing-account-detected screen + onboarding branch logic
```

---

## When to start

When you're ready. I'd recommend:

1. **Tonight or next opportunity:** Phase 0 (30 min Claude work, no testing required)
2. **Next dedicated session:** Phase 1 session 1
3. **Subsequent sessions:** the rest in dependency order

Each phase ships independently with its own commit. You can pause at any phase boundary and the app stays in a working state.

End of plan.
