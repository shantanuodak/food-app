# iOS TestFlight Release Checklist (Launch Gate)

Date: February 22, 2026  
Owner: iOS + Backend  
Purpose: single source of truth for TestFlight/pre-prod release readiness.

Docs index:
1. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/README.md`

## 1) Release policy (must follow)

1. No release on "quick fixes" that are not codified in source control.
2. Any auth/network production fix must have a backend test or iOS validation step added to this checklist.
3. `AUTH_MODE=supabase` is required for pre-prod/prod.
4. `AUTH_DEBUG_ERRORS=false` is required for pre-prod/prod.

## 2) One-time prerequisites

1. Apple Developer Program is active for the Apple ID used in Xcode.
2. App record exists in App Store Connect for the target bundle identifier.
3. Signing team is set in Xcode target `Food App` with `Automatically manage signing` ON.
4. Supabase project is configured with Google provider enabled.
5. Release API URL is set once using:
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/set_release_api_base_url.sh`

## 3) Canonical config matrix (do not drift)

1. Local simulator:
   - `APP_ENV=local`
   - `API_BASE_URL_SIMULATOR=http://localhost:8080`
   - Scheme pre-action auto-starts backend via launchd.
2. Local physical phone:
   - `APP_ENV=local`
   - `API_BASE_URL_LOCAL=http://<LAN_IP>:8080`
3. Staging:
   - `APP_ENV=staging`
   - `API_BASE_URL_STAGING=https://<staging_api_domain>`
4. TestFlight/production:
   - `APP_ENV=production`
   - `API_BASE_URL_PROD=https://<prod_api_domain>`

Reference files:
1. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/AppConfiguration.swift`
2. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App.xcodeproj/xcshareddata/xcschemes/Food App.xcscheme`
3. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/.env.example`

## 4) Backend launch gate (must pass)

Run from `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend`:

1. `npm ci`
2. `npm run build`
3. `npm test`
4. `npm run test:integration`
5. `npm run migrate`
6. `npm run dev`
7. `curl -s http://localhost:8080/health`

Expected:
1. Build and tests pass.
2. Health endpoint returns `{"status":"ok"}`.

Automation option:
1. Run one command from repo root to execute release config + backend gate:
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/testflight_preupload_gate.sh`

## 5) Auth hard checks (must pass)

Backend env:
1. `AUTH_MODE=supabase`
2. `AUTH_DEBUG_ERRORS=false`
3. `SUPABASE_JWT_ISSUER=https://<PROJECT_REF>.supabase.co/auth/v1`
4. `SUPABASE_JWT_AUDIENCE=authenticated`
5. Either `SUPABASE_JWT_SECRET` (HS256 projects) or `SUPABASE_JWKS_URL`/issuer JWKS (asymmetric projects).

Verifier capability:
1. Supabase JWT verification supports `RS256` and `ES256`.

iOS behavior:
1. Google sign-in must exchange to Supabase session successfully.
2. No fallback dev token path should be active in release configuration.
3. If Apple/Email auth is not implemented for launch, those options must be hidden or clearly non-interactive in release builds.

## 6) iOS pre-archive gate (must pass)

Project: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App.xcodeproj`

1. Target `Food App` -> `Signing & Capabilities`:
   - Correct team
   - Automatically manage signing ON
2. `Version` and `Build` incremented.
3. Release API URL is a real HTTPS endpoint.
   - Validate with:
     - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/check_testflight_release_config.sh`
4. Bump build number with:
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/bump_build_number.sh`
5. Run on physical device against release-equivalent backend and verify:
   - onboarding completion
   - Google sign-in and post-auth onboarding submit
   - parse flow
   - save flow
   - day summary flow
   - restart onboarding flow
6. Confirm no red debug/auth diagnostic text appears in UI.

## 7) Archive and upload

1. Xcode destination: `Any iOS Device (arm64)`.
2. `Product` -> `Archive`.
3. Organizer -> `Distribute App` -> `App Store Connect` -> `Upload`.
4. Wait for processing in App Store Connect -> TestFlight.

## 8) TestFlight rollout gate

1. Internal testers first.
2. Execute smoke checks on TestFlight build:
   - app launch
   - sign-in
   - onboarding submit
   - parse/save/day-summary
3. Add release notes including known limitations.
   - template:
     - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/templates/TESTFLIGHT_RELEASE_NOTES_TEMPLATE.md`
4. Add external testers only after internal pass.

## 9) Daily cadence policy

1. Default: one TestFlight upload per day.
2. Emergency exception: one extra upload for critical blocker fixes.
3. Keep internal tester group as default distribution scope.

## 10) No-go conditions (do not release)

1. Any placeholder API domain remains in production config.
2. Backend health is unstable or requires manual ad-hoc restarts.
3. `AUTH_MODE` is not `supabase` in pre-prod/prod.
4. `AUTH_DEBUG_ERRORS=true` in pre-prod/prod.
5. Any core flow fails: sign-in, onboarding submit, parse, save, day summary.

## 11) Fast triage references

1. Backend setup and auth reference:
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/README.md`
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/docs/SUPABASE_SETUP.md`
2. Strict run order:
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/STRICT_LAUNCH_RUNBOOK_MVP.md`
3. Daily workflow:
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/IOS_TESTFLIGHT_DAILY_WORKFLOW.md`
4. Script helpers:
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/check_testflight_release_config.sh`
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/set_release_api_base_url.sh`
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/bump_build_number.sh`
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/testflight_preupload_gate.sh`
5. Local Xcode backend pre-action logs:
   - `/tmp/foodapp-xcode-build.log`
   - `/tmp/foodapp-xcode-backend.log`
