# Food App Backend (Sprint 1 Scaffold)

## Prerequisites
- Node.js 20+
- PostgreSQL 15+

## Setup
1. Copy `.env.example` to `.env` and set values.
2. Install dependencies:
   - `npm install`
3. Run migrations:
   - `npm run migrate`
4. Run service:
   - `npm run dev`

## Supabase Setup (recommended next)
1. Create a Supabase project.
2. In Supabase, open `Project Settings -> Database -> Connection string`.
3. Use the connection string in backend `.env`:
   - `DATABASE_URL=postgresql://postgres:<PASSWORD>@db.<PROJECT_REF>.supabase.co:5432/postgres`
   - `DATABASE_SSL=true`
4. Run migrations from backend folder:
   - `npm run migrate`
5. Start backend:
   - `npm run dev`

Detailed checklist: `docs/SUPABASE_SETUP.md`

## Cheapest hosted beta path (TestFlight)
Use Supabase Free + Render Free deployment runbook:
1. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/CHEAP_DEPLOYMENT_RENDER_SUPABASE.md`

## Gemini Flash Integration
- Set `GEMINI_API_KEY` in `.env` to enable real Gemini Flash calls for fallback/escalation parsing.
- Default model env is `GEMINI_FLASH_MODEL=gemini-2.5-flash`.
- Fallback route model can be overridden with `AI_FALLBACK_MODEL_NAME`.
- Escalation route model can be overridden with `AI_ESCALATION_MODEL_NAME`.
- If `GEMINI_API_KEY` is not set, backend uses local mock normalization fallback so local development still works.

## FatSecret Platform Integration
- Set `FATSECRET_CLIENT_ID` and `FATSECRET_CLIENT_SECRET` in `.env` to enable FatSecret lookup in primary parse flow.
- Optional tuning:
  - `FATSECRET_ENABLED` (default `true`)
  - `FATSECRET_SCOPE` (default `basic`)
  - `FATSECRET_OAUTH_URL` (default `https://oauth.fatsecret.com/connect/token`)
  - `FATSECRET_API_BASE_URL` (default `https://platform.fatsecret.com/rest`)
  - `FATSECRET_REGION` (default `US`)
  - `FATSECRET_LANGUAGE` (optional locale code)
  - `FATSECRET_SEARCH_MAX_RESULTS` (default `8`)
  - `FATSECRET_MIN_COVERAGE` (default `0.6`)
  - `FATSECRET_MIN_CONFIDENCE` (default `0.72`)
  - `FATSECRET_TIMEOUT_MS` (default `8000`)
- Key protection:
  - Keep FatSecret credentials server-side only in backend env.
  - Never hardcode or ship credentials in iOS/frontend code.
  - Do not log credential values.
- Smoke test after credentials are set:
  - `npm run smoke:fatsecret -- "2 eggs and toast"`
  - Expected: output route should be `fatsecret` for at least one common food phrase.
  - Smoke output includes route/cache/fallback/clarification metadata and full parsed item payload
    (`name`, `quantity`, `unit`, `grams`, `calories`, `protein`, `carbs`, `fat`, `matchConfidence`, `nutritionSourceId`).
  - Smoke script uses a unique cache scope each run by default, so it verifies live provider behavior.
  - Optional override:
    - `FATSECRET_SMOKE_CACHE_SCOPE=<scope> npm run smoke:fatsecret -- "2 eggs and toast"`

## Auth modes
- `AUTH_MODE=dev` (default): accepts bearer token `dev-<uuid>`.
- `AUTH_MODE=supabase`: accepts Supabase JWT only (configure `SUPABASE_JWT_SECRET` for HS256 or `SUPABASE_JWKS_URL`/`SUPABASE_JWT_ISSUER` for asymmetric keys).
- `AUTH_MODE=hybrid`: accepts both dev token and Supabase JWT (use for staged rollout).

Supabase JWT vars:
- `SUPABASE_JWT_SECRET` (for HS256 projects)
- `SUPABASE_JWT_ISSUER` (example: `https://<PROJECT_REF>.supabase.co/auth/v1`)
- `SUPABASE_JWKS_URL` (optional explicit JWKS endpoint; defaults to `<SUPABASE_JWT_ISSUER>/.well-known/jwks.json`)
- `SUPABASE_JWT_AUDIENCE` (default: `authenticated`)
- `SUPABASE_JWT_CLOCK_SKEW_SECONDS` (default: `30`)
- Supported asymmetric JWT algorithms: `RS256`, `ES256`
- `AUTH_DEBUG_ERRORS` (default: `false`, dev-only; include token claim diagnostics in 401 responses)
- `RLS_STRICT_MODE` (optional safety check; blocks startup if using `postgres` role in non-dev auth modes)

RLS hardening:
- Backend now propagates request claims to Postgres session settings on every DB query:
  - `request.jwt.claim.sub`
  - `request.jwt.claim.role`
  - `request.jwt.claim.email`
- This enables Supabase-style RLS policies that depend on `current_setting('request.jwt.claim.sub', true)`.
- Recommended production posture:
  - `AUTH_MODE=supabase` (or `hybrid` during rollout)
  - non-`postgres` DB role
  - `RLS_STRICT_MODE=true`

## Endpoints
- `GET /health`
- `POST /v1/onboarding`
- `POST /v1/logs/parse`
- `POST /v1/logs/parse/escalate` (explicit user-triggered)
- `POST /v1/logs`
- `GET /v1/logs/day-summary?date=YYYY-MM-DD`
- `GET /v1/internal/metrics` (internal key required)
- `GET /v1/internal/alerts` (internal key required)

`POST /v1/logs/parse` cache behavior:
- First time for a text input: `cacheHit=false` and header `x-parse-cache: miss`
- Repeated same text: `cacheHit=true` and header `x-parse-cache: hit`
- Cache scope is per user + parse version to avoid cross-user reuse surprises.
- Optional debug mode: set `DEBUG_PARSE_CACHE_KEY=true` to include `cacheDebug` in parse response (`scope`, `normalizedText`, `textHash`).
- Returns `parseRequestId` and `parseVersion` for later save/escalation calls.
- Parse rate limit guard:
  - `PARSE_RATE_LIMIT_ENABLED=true`
  - `PARSE_RATE_LIMIT_WINDOW_MS=60000`
  - `PARSE_RATE_LIMIT_MAX_REQUESTS=24`
  - returns `429 RATE_LIMITED` with `Retry-After` when exceeded.

`POST /v1/logs/parse` fallback behavior:
- Parse flow is: cache hit returns cached result; cache miss runs provider chain `FatSecret -> Gemini`.
- FatSecret step is attempted only when enabled (`FATSECRET_ENABLED=true`) and OAuth credentials are configured.
- Gemini step is attempted when FatSecret does not produce an accepted parse and AI fallback is enabled.
- Response includes `fallbackUsed` and `fallbackModel`.
- Header `x-parse-fallback` is `used` or `not_used`.
- When fallback is used, one `ai_cost_events` row is recorded with `feature='parse_fallback'`.
- Parse budget is tracked and returned in response for monitoring; primary parse does not hard-block on budget.
- Gemini 429 circuit breaker:
  - `GEMINI_CIRCUIT_BREAKER_ENABLED=true`
  - `GEMINI_CIRCUIT_BREAKER_CONSECUTIVE_429=5`
  - `GEMINI_CIRCUIT_BREAKER_COOLDOWN_MS=20000`
  - opens after repeated 429s and temporarily skips Gemini calls.

`POST /v1/logs/parse` clarification behavior:
- Clarification is enabled for low-confidence or unresolved parse outputs.
- Response returns:
  - `needsClarification: true|false`
  - `clarificationQuestions: string[]` (up to 2 questions)
- Header `x-parse-clarification` is `needed` or `not_needed`.

`POST /v1/logs/parse/escalate` behavior:
- Requires explicit client call (e.g. user clicked Improve Estimate).
- Requires `parseRequestId` from a prior parse response.
- `parseRequestId` must be clarification-needed (`needsClarification=true`) and not stale.
- Returns `409 ESCALATION_NOT_REQUIRED` when primary parse did not require escalation.
- Guarded by `AI_ESCALATION_ENABLED=true`.
- Refuses if daily AI budget (`AI_DAILY_BUDGET_USD`) would be exceeded.
- Records one `ai_cost_events` row with `feature='escalation'` per successful call.
- Response includes budget metadata and `userSoftCapExceeded` warning flag.

`POST /v1/logs` strict contract:
- Requires `Idempotency-Key` header.
- Requires body fields:
  - `parseRequestId`
  - `parseVersion`
  - `parsedLog`
- `parseRequestId` must exist, belong to the same user, and not be stale.
- Same idempotency key + same payload returns prior success response.
- Same idempotency key + different payload returns `409 IDEMPOTENCY_CONFLICT`.

`GET /v1/logs/day-summary` timezone behavior:
- Query supports optional `tz` (`GET /v1/logs/day-summary?date=YYYY-MM-DD&tz=America/Los_Angeles`).
- If `tz` is omitted, backend uses `onboarding_profiles.timezone`.
- Fallback timezone is `UTC`.

`GET /v1/internal/metrics`:
- Protected by header: `x-internal-metrics-key: <INTERNAL_METRICS_KEY>`.
- Returns required metrics:
  - `parse_requests_total`
  - `parse_fallback_total`
  - `parse_escalation_total`
  - `parse_clarification_total`
  - `ai_tokens_input_total`
  - `ai_tokens_output_total`
  - `ai_estimated_cost_usd_total`
  - `cache_hit_ratio`

`GET /v1/internal/alerts`:
- Protected by header: `x-internal-metrics-key: <INTERNAL_METRICS_KEY>`.
- Returns alert status for:
  - `ESCALATION_RATE_HIGH` (15m, threshold default 8%)
  - `CACHE_HIT_RATIO_LOW` (24h, threshold default 30%)
  - `COST_PER_LOG_DRIFT_HIGH` (24h, threshold default +20% vs target)
- Each alert includes `runbook` link to `/docs/ALERT_RUNBOOK_MVP.md`.

## Integration tests
- Set `DATABASE_URL_TEST` to an isolated test database.
- Run:
  - `npm run test:integration`
- Note:
  - Integration tests run only through `npm run test:integration` (`RUN_INTEGRATION_TESTS=true`).
  - Default `npm test` runs fast unit tests only.

## Replay benchmark (BE-023)
- Run 1,000-log replay:
  - `npm run benchmark:replay -- --count 1000 --label baseline`
- Optional knobs:
  - `--seed 42` (deterministic sample mix)
  - `--no-escalate` (disable escalation path in simulation)
  - `--output-dir ./benchmarks/artifacts`
- Output artifacts:
  - `backend/benchmarks/artifacts/replay-<timestamp>-<label>.json`
  - `backend/benchmarks/artifacts/replay-latest.json`
  - `backend/benchmarks/artifacts/replay-runs.ndjson` (append-only summary index)
- Report includes:
  - latency p50/p95
  - fallback rate
  - escalation rate
  - cost per log
