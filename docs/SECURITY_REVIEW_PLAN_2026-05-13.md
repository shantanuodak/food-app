# Security Review Plan - 2026-05-13

This document parks the initial cybersecurity review so we can return to it later without mixing it into image parsing work.

## Scope Reviewed

- Express backend routes and middleware
- Nutrition testing dashboard frontend
- Supabase/Postgres migrations and RLS posture
- AI cost controls for Gemini/image/text parsing
- iOS/Xcode configuration, entitlements, auth storage, and bundled config
- Dependency audit for production backend packages

## Confirmed High-Priority Risks

### 1. Testing dashboard is publicly served

File: `backend/src/app.ts`

`/testing-dashboard` serves the admin/testing UI to anyone who knows the URL. API calls still require `INTERNAL_METRICS_KEY`, but the page exposes internal workflows and endpoint shapes.

Recommended fix:
- Protect the dashboard route itself with admin auth, IP allowlisting, or remove it from production hosting.
- Longer term: host the dashboard as a separate admin app behind proper authentication.

### 2. Internal dashboard key is stored in browser sessionStorage

File: `backend/src/testing-dashboard/index.html`

The dashboard stores `INTERNAL_METRICS_KEY` in `sessionStorage`. If dashboard XSS exists now or later, the key can be stolen and used to run admin/costly endpoints.

Recommended fix:
- Replace static key auth with admin Supabase JWT/session auth.
- If using cookies, use `HttpOnly`, `Secure`, and `SameSite`.
- Do not keep high-privilege internal keys in browser storage.

### 3. AI cost abuse is possible through authenticated account churn

Files:
- `backend/src/routes/parse.ts`
- `backend/src/services/parseRateLimiterService.ts`
- `backend/src/services/aiCostService.ts`

Current protections:
- User-scoped in-memory parse rate limit.
- Global daily AI budget guard.
- Per-user soft cap is tracked.
- Image upload size is bounded.

Remaining risk:
- In-memory rate limits reset on deploy/restart.
- A malicious user could create multiple accounts.
- Costly dashboard/admin routes can run Gemini if internal key is compromised.

Recommended fix:
- Move rate limiting to persistent storage such as Postgres or Redis.
- Add limits by user, IP, device/app instance, route, and image parse specifically.
- Enforce per-user soft cap before expensive AI calls, not only after usage is recorded.
- Add tighter controls for prompt lab, benchmark runs, and eval routes.

### 4. Production DB role may bypass RLS

File: `backend/src/db.ts`

`RLS_STRICT_MODE` exists, but production Render config does not currently enable it. If `DATABASE_URL` uses the `postgres` role, RLS becomes a weak backstop because `postgres` can bypass policies.

Recommended fix:
- Create a least-privilege backend database role.
- Use that role in production `DATABASE_URL`.
- Set `RLS_STRICT_MODE=true`.
- Verify production fails to boot if the backend accidentally uses `postgres`.

### 5. Newer tables do not all have RLS

Files: `backend/migrations/*`

Older user-owned tables have RLS policies. Newer tables such as feedback, notifications, roadmap, and benchmark tables need explicit RLS posture.

Recommended fix:
- Add RLS policies for:
  - `user_feedback`
  - `notification_devices`
  - `notification_preferences`
  - `notification_deliveries`
  - any other user-owned notification tables
- For CMS/admin tables such as roadmap, benchmark cases, benchmark runs, and notification templates, either:
  - keep access only through backend admin routes, or
  - add explicit admin/service policies if accessed directly.

## Medium-Priority Risks

### 6. Production dependency audit found one high advisory

Command run:

```bash
npm audit --omit=dev --json
```

Finding:
- `path-to-regexp`
- Advisory: `GHSA-37ch-88jc-xwx2`
- Issue: Regular Expression Denial of Service
- Severity: high

Recommended fix:
- Update the dependency tree safely, likely via Express/router dependency updates.
- Run backend unit and integration tests after update.

### 7. Backend lacks standard security headers

File: `backend/src/app.ts`

Recommended fix:
- Add `helmet`.
- Configure CSP carefully for the testing dashboard.
- Include `nosniff`, frame protections, referrer policy, and conservative cross-origin policies.

### 8. Dashboard has some unsafe innerHTML error paths

File: `backend/src/testing-dashboard/index.html`

Most user/server values are escaped, but some `e.message` insertions use `innerHTML` directly.

Recommended fix:
- Replace those with `textContent`, or consistently pass through `escapeHtml`.

### 9. iOS release code still has a dev fallback token path

File: `Food App/AppConfiguration.swift`

Supabase configuration prevents dev-token use in normal production, but the fallback token should not exist in release code.

Recommended fix:
- Compile fallback auth only in `DEBUG`.
- Make release builds require a real Supabase session.

## Important Principle

Users cannot be prevented from inspecting shipped client code. Web JavaScript is visible, and iOS binaries can be reverse engineered. The secure model is:

- Assume client code is public.
- Never put server secrets in the app or dashboard frontend.
- Enforce authorization, cost controls, and data isolation on the backend/database.

## Suggested Remediation Order

1. Lock down or remove `/testing-dashboard` from public production.
2. Replace browser-stored `INTERNAL_METRICS_KEY` with admin auth.
3. Add persistent AI rate limits and hard per-user/image route caps.
4. Add RLS for newer user-owned tables.
5. Move production DB to a least-privilege role and enable `RLS_STRICT_MODE=true`.
6. Add Helmet/CSP and fix dashboard `innerHTML` error paths.
7. Remove iOS release fallback dev token path.
8. Patch dependency audit finding and rerun backend tests.

