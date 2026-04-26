# iOS Sprint 5 Setup (FE-001 to FE-003)

## 1) What is implemented
- Build-configuration-based API environment keys in Xcode project:
  - Debug defaults:
    - `APIEnvironment=local`
    - `APIBaseURL=http://localhost:8080`
  - Release defaults:
    - `APIEnvironment=production`
    - `APIBaseURL` must be set to real prod endpoint before TestFlight upload:
      - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/set_release_api_base_url.sh`
- Typed API client and models for:
  - health
  - onboarding
  - parse
  - escalate
  - save
  - day-summary
- App state + navigation shell:
  - Onboarding gate on first launch
  - Persisted onboarding completion
  - Main logging shell view with backend health check

## 2) Local run steps
1. Start backend:
```bash
cd "/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend"
npm run dev
```

2. Open iOS app:
```bash
open "/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App.xcodeproj"
```

3. Run Debug on iOS Simulator.

4. In app:
- Complete onboarding form.
- Land on main shell.
- Tap "Check Backend Connection" and confirm health returns `ok`.

## 3) Environment overrides (Scheme env vars)
Use Xcode Scheme -> Run -> Arguments -> Environment Variables:
- `APP_ENV=local|staging|production`
- `API_BASE_URL_LOCAL=http://localhost:8080`
- `API_BASE_URL_STAGING=https://staging-api.example.com`
- `API_BASE_URL_PROD=https://api.example.com`
- `API_AUTH_TOKEN=dev-11111111-1111-1111-1111-111111111111` (or env-specific token)

When `APP_ENV` is set, it overrides bundle default environment.

## 4) Notes
- Debug build enables local networking ATS key for localhost development.
- The main logging screen is intentionally a Sprint 5 shell; live parse/save UI is scheduled for Sprint 6.
