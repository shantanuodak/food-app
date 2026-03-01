# iOS TestFlight Daily Workflow

Date: March 1, 2026  
Owner: iOS + Backend  
Scope: manual Xcode upload to internal TestFlight testers with one build per day.

Primary release gate:
1. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/IOS_TESTFLIGHT_RELEASE_CHECKLIST.md`

## 1) One-time setup (done once)

1. Confirm App Store Connect app exists for bundle ID `com.shantanu.foodapp`.
2. Keep one internal tester group as default.
3. Confirm target signing is automatic with correct team in Xcode.
4. Set release API URL in project config:
```bash
"/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/set_release_api_base_url.sh" "https://<your-prod-api-domain>"
```
5. Verify release config:
```bash
"/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/check_testflight_release_config.sh"
```

## 2) Daily release loop (every TestFlight upload)

1. Run pre-upload backend + config gate:
```bash
"/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/testflight_preupload_gate.sh"
```
2. Bump iOS build number:
```bash
"/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/bump_build_number.sh"
```
3. Manual iOS physical-device smoke:
   - launch
   - sign-in
   - onboarding submit
   - parse
   - save
   - day summary
4. Archive + upload:
   - Xcode destination: `Any iOS Device (arm64)`
   - `Product -> Archive`
   - Organizer: `Distribute App -> App Store Connect -> Upload`
5. App Store Connect:
   - wait for processing
   - assign to internal tester group
   - paste release notes from template:
     - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/templates/TESTFLIGHT_RELEASE_NOTES_TEMPLATE.md`
6. Post-upload smoke on TestFlight build:
   - launch/sign-in/onboarding/parse/save/day summary
   - if failing, stop rollout and upload next build number fix

## 3) Cadence policy

1. Default: one TestFlight upload per day.
2. Exception: one additional emergency build only for critical blockers.
3. Keep internal testers only until stability is consistently green.

## 4) Non-negotiable rules

1. Never ship with placeholder/local release API URL.
2. Never reuse a build number.
3. Never bypass backend gate for production-auth or network-impacting changes.
4. Never release from local-only or uncommitted fixes.

