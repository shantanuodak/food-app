# API Handoff: iOS Integration (MVP Backend)

## 1) Document Info
- Product: Food App (iOS-first)
- Scope: MVP backend contract for iOS integration
- Source of truth:
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/PRD_MVP_Food_Logging.md`
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/IMPLEMENTATION_SPEC_MVP.md`
- Backend implementation reference:
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/routes/onboarding.ts`
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/routes/parse.ts`
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/src/routes/logs.ts`
- Date: February 16, 2026

## 2) Base URL and Auth
- Base URL (local): `http://localhost:8080`
- Required auth on user endpoints (config-driven):
  - `AUTH_MODE=dev`: `Authorization: Bearer dev-<uuid>`
  - `AUTH_MODE=supabase`: `Authorization: Bearer <supabase_jwt>`
  - `AUTH_MODE=hybrid`: both token types accepted

## 3) Global Conventions
- Request/response content type: `application/json`
- Request ID:
  - Optional request header: `x-request-id`
  - Always returned in response header: `x-request-id`
- Error envelope:
```json
{
  "error": {
    "code": "INVALID_INPUT",
    "message": "text exceeds max length (500)",
    "requestId": "8d0de2ec-4dc9-4f74-a24a-8ee76c8d8aeb"
  }
}
```

## 4) Endpoint Contracts

### 4.1 `GET /health`
- Auth: none
- Response:
```json
{
  "status": "ok"
}
```

### 4.2 `POST /v1/onboarding`
- Auth: required
- Request:
```json
{
  "goal": "maintain",
  "dietPreference": "none",
  "allergies": [],
  "units": "imperial",
  "activityLevel": "moderate",
  "timezone": "America/Los_Angeles"
}
```
- Response:
```json
{
  "calorieTarget": 2200,
  "macroTargets": {
    "protein": 138,
    "carbs": 220,
    "fat": 86
  }
}
```
- Notes:
  - Upsert behavior: calling again updates same profile, no duplicates.

### 4.3 `POST /v1/logs/parse`
- Auth: required
- Request:
```json
{
  "text": "2 eggs, 2 slices toast, black coffee",
  "loggedAt": "2026-02-15T13:35:00.000Z"
}
```
- Response (example):
```json
{
  "requestId": "72d8e1b6-ff2b-4eca-a8f2-7641a3752880",
  "parseRequestId": "72d8e1b6-ff2b-4eca-a8f2-7641a3752880",
  "parseVersion": "v1",
  "route": "deterministic",
  "cacheHit": false,
  "fallbackUsed": false,
  "fallbackModel": null,
  "budget": {
    "dailyLimitUsd": 0.5,
    "dailyUsedTodayUsd": 0,
    "userSoftCapUsd": 0.1,
    "userUsedTodayUsd": 0,
    "userSoftCapExceeded": false,
    "fallbackAllowed": true
  },
  "needsClarification": false,
  "clarificationQuestions": [],
  "parseDurationMs": 21.4,
  "loggedAt": "2026-02-15T13:35:00.000Z",
  "confidence": 0.971,
  "totals": {
    "calories": 306,
    "protein": 18.9,
    "carbs": 29.2,
    "fat": 11.6
  },
  "items": [
    {
      "name": "egg",
      "quantity": 2,
      "unit": "count",
      "grams": 100,
      "calories": 144,
      "protein": 12.6,
      "carbs": 1.2,
      "fat": 9.6,
      "matchConfidence": 1,
      "nutritionSourceId": "seed_egg"
    }
  ],
  "assumptions": []
}
```
- Response headers:
  - `x-parse-route: deterministic`
  - `x-parse-duration-ms: <number>`
  - `x-parse-cache: hit|miss`
  - `x-parse-fallback: used|not_used`
  - `x-parse-clarification: needed|not_needed`

### 4.4 `POST /v1/logs/parse/escalate`
- Auth: required
- Request:
```json
{
  "parseRequestId": "72d8e1b6-ff2b-4eca-a8f2-7641a3752880",
  "loggedAt": "2026-02-15T13:35:00.000Z"
}
```
- Success response (example):
```json
{
  "requestId": "f4a8ba17-6a9d-4c5c-b49a-7ad2ec9ba147",
  "parseRequestId": "72d8e1b6-ff2b-4eca-a8f2-7641a3752880",
  "parseVersion": "v1",
  "route": "escalation",
  "escalationUsed": true,
  "model": "mock-strong-normalizer-v1",
  "budget": {
    "dailyLimitUsd": 0.5,
    "dailyUsedTodayUsd": 0.003,
    "userSoftCapUsd": 0.1,
    "userUsedTodayUsd": 0.003,
    "userSoftCapExceeded": false,
    "escalationAllowed": true
  },
  "parseDurationMs": 30.1,
  "loggedAt": "2026-02-15T13:35:00.000Z",
  "confidence": 0.64,
  "totals": {
    "calories": 0,
    "protein": 0,
    "carbs": 0,
    "fat": 0
  },
  "items": [],
  "assumptions": []
}
```
- Notes:
  - Requires `AI_ESCALATION_ENABLED=true`.
  - Allowed only when primary parse still has `needsClarification=true`.

### 4.5 `POST /v1/logs`
- Auth: required
- Required header:
  - `Idempotency-Key: <stable-unique-key>`
- Required request:
```json
{
  "parseRequestId": "72d8e1b6-ff2b-4eca-a8f2-7641a3752880",
  "parseVersion": "v1",
  "parsedLog": {
    "rawText": "2 eggs, 2 slices toast, black coffee",
    "loggedAt": "2026-02-15T13:35:00.000Z",
    "confidence": 0.971,
    "totals": {
      "calories": 306,
      "protein": 18.9,
      "carbs": 29.2,
      "fat": 11.6
    },
    "items": [
      {
        "name": "egg",
        "quantity": 2,
        "unit": "count",
        "grams": 100,
        "calories": 144,
        "protein": 12.6,
        "carbs": 1.2,
        "fat": 9.6,
        "nutritionSourceId": "seed_egg",
        "matchConfidence": 1
      }
    ]
  }
}
```
- Success response:
```json
{
  "logId": "d6baafe4-2d96-4d72-b1ba-d4876a3357a3",
  "status": "saved"
}
```
- Idempotency behavior:
  - Same key + same payload -> `200` with original response
  - Same key + different payload -> `409 IDEMPOTENCY_CONFLICT`

### 4.6 `GET /v1/logs/day-summary?date=YYYY-MM-DD&tz=IANA_TIMEZONE(optional)`
- Auth: required
- Query:
  - `date` required, format `YYYY-MM-DD`
  - `tz` optional, IANA timezone (`America/Los_Angeles`)
- Response:
```json
{
  "date": "2026-02-15",
  "timezone": "America/Los_Angeles",
  "totals": {
    "calories": 306,
    "protein": 18.9,
    "carbs": 29.2,
    "fat": 11.6
  },
  "targets": {
    "calories": 2200,
    "protein": 138,
    "carbs": 220,
    "fat": 86
  },
  "remaining": {
    "calories": 1894,
    "protein": 119.1,
    "carbs": 190.8,
    "fat": 74.4
  }
}
```

## 5) Error Cases iOS Must Handle
- `401 UNAUTHORIZED`
  - Missing bearer token
  - Invalid token format
  - Token user id not valid UUID
- `400 INVALID_INPUT`
  - Validation failures (e.g., `text` empty or >500 chars, bad date format)
- `400 MISSING_IDEMPOTENCY_KEY`
  - Missing `Idempotency-Key` on `POST /v1/logs`
- `409 IDEMPOTENCY_CONFLICT`
  - Same key reused with changed payload
- `409 ESCALATION_NOT_REQUIRED`
  - Escalation requested but primary parse does not need it
- `422 INVALID_PARSE_REFERENCE`
  - Unknown/stale/mismatched `parseRequestId` or parse version mismatch
- `403 ESCALATION_DISABLED`
  - Escalation feature flag disabled
- `429 BUDGET_EXCEEDED`
  - Daily AI budget cap hit
- `429 RATE_LIMITED`
  - Parse request rate exceeded (`Retry-After` header included)
- `404 PROFILE_NOT_FOUND`
  - Day summary called before onboarding exists
- `500 INTERNAL_ERROR`
  - Unexpected server error

## 6) iOS Integration Notes
- Parse-save contract is strict:
  - save payload must be derived from parse response (`parseRequestId`, `parseVersion`, `rawText` aligned)
- For reliable retries:
  - generate one idempotency key per intended save action and reuse that same key on retry
- Clarification UX:
  - if `needsClarification=true`, render `clarificationQuestions` and do not auto-save
- Escalation UX:
  - explicit user action should call `POST /v1/logs/parse/escalate`

## 7) Non-iOS Internal Endpoints
- `GET /v1/internal/metrics`
- `GET /v1/internal/alerts`
- Both require `x-internal-metrics-key`, intended for backend/ops only.
