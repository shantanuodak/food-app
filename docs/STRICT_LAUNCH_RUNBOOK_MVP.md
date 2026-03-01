# Strict Launch Runbook (MVP)

Date: February 21, 2026  
Owner flow: Backend -> iOS -> Beta rollout -> Monitoring -> Go/No-Go

TestFlight/pre-prod release gate SSOT:
1. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/IOS_TESTFLIGHT_RELEASE_CHECKLIST.md`

## 1) Hard Preconditions
All must be true before release work starts.

1. Backend migration status is current (through `0004_timezone_and_rls.sql`).
2. Backend test gates are green:
   - `npm test`
   - `npm run test:integration`
3. Supabase connection and writes are verified from local backend.
4. iOS main flows are working in simulator/device.

## 2) Backend Release Sequence (Strict Order)

Run from `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend`.

1. Install and compile
```bash
npm ci
npm run build
```

2. Run fast suite
```bash
npm test
```

3. Run integration suite (DB-backed)
```bash
npm run test:integration
```

4. Apply migrations
```bash
npm run migrate
```

5. Start backend
```bash
npm run dev
```

6. Health check
```bash
curl -s http://localhost:8080/health
```
Expected: `{"status":"ok"}`

7. Parse smoke check
```bash
curl -s -X POST "http://localhost:8080/v1/logs/parse" \
  -H "Authorization: Bearer dev-11111111-1111-1111-1111-111111111111" \
  -H "Content-Type: application/json" \
  --data '{"text":"Milkshake","loggedAt":"2026-02-21T17:30:00.000Z"}'
```
Expected: `200`, includes `parseRequestId`, `parseVersion`, `items`, `totals`.

8. Save smoke check
```bash
curl -s -X POST "http://localhost:8080/v1/logs" \
  -H "Authorization: Bearer dev-11111111-1111-1111-1111-111111111111" \
  -H "Idempotency-Key: launch-smoke-001" \
  -H "Content-Type: application/json" \
  --data '<paste parse-derived payload>'
```
Expected: `200`, `{ "logId": "...", "status": "saved" }`.

9. Supabase DB verification
```sql
select id, raw_text, created_at
from public.food_logs
order by created_at desc
limit 10;
```
Expected: latest smoke row present.

## 3) Production Env Values Checklist

In backend `.env` (production/staging), verify:

```env
DATABASE_URL=postgresql://...
DATABASE_SSL=true
AUTH_MODE=supabase
SUPABASE_JWT_SECRET=...
SUPABASE_JWT_ISSUER=https://<PROJECT_REF>.supabase.co/auth/v1
SUPABASE_JWT_AUDIENCE=authenticated
RLS_STRICT_MODE=false
PARSE_RATE_LIMIT_ENABLED=true
GEMINI_CIRCUIT_BREAKER_ENABLED=true
```

Notes:
1. Use `AUTH_MODE=hybrid` only during transition.
2. Set `RLS_STRICT_MODE=true` only when backend DB role is non-`postgres`.

## 4) iOS Release Sequence (Strict Order)

Run from project root `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App`.

1. Confirm config in `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/AppConfiguration.swift`:
   - correct `APIEnvironment`
   - correct `API_BASE_URL_*`
   - correct auth token source for target environment

2. Manual smoke in simulator/device:
   - onboarding
   - parse
   - save
   - day summary
   - retry/no duplicate save

3. Execute pending manual rows from:
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/E2E_QA_MATRIX_MVP.md`
   - complete `IOS-E2E-07` to `IOS-E2E-11`

4. Archive and upload in Xcode:
   - Product -> Archive
   - Organizer -> Distribute App -> App Store Connect -> Upload

5. If CLI archive is needed, first fix local Xcode selection:
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 5) TestFlight Handoff Sequence

1. Add release notes:
   - build number
   - tested scope
   - known limitations link
2. Assign tester groups.
3. Run launch gate checklist before/after upload:
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/IOS_TESTFLIGHT_RELEASE_CHECKLIST.md`
4. Run post-upload smoke checklist from:
   - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/IOS_E2E005_BETA_READINESS.md`

## 6) 24h Monitoring After Beta Push

1. Watch backend health and parse errors every 2-4 hours.
2. Review `food_logs` insert volume and failed saves.
3. Check metrics endpoint for route split and budget behavior.
4. Track Gemini 429 behavior; ensure circuit breaker is preventing retry storms.

## 7) Go/No-Go Gate

Ship only if all are true:
1. Backend tests green (`npm test`, `npm run test:integration`).
2. Migration current and verified in Supabase.
3. iOS pending E2E rows marked PASS.
4. TestFlight upload successful.
5. Beta smoke checklist PASS.

## 8) Rollback

If release fails:
1. Stop adding testers / pause rollout in App Store Connect.
2. Revert backend deploy to previous known-good version.
3. If AI route instability: keep deterministic path by disabling fallback/escalation flags.
4. Post incident summary with request IDs and ETA.
