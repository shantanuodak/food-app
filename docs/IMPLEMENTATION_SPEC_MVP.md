# Implementation Spec: Food Logging MVP (Backend First)

## 1. Document Info
- Related PRD: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/docs/PRD_MVP_Food_Logging.md`
- Version: v1
- Date: February 15, 2026

## 2. Delivery Strategy
- Build order: data model -> deterministic parser -> parse API -> save/summaries -> AI fallback -> cost observability -> hard budget controls.
- Release in 3 milestones so deterministic logging works before AI integration.

## 3. Architecture Decisions
- API style: REST JSON.
- Database: PostgreSQL 15+.
- Backend runtime: Node.js + TypeScript (Express/Fastify acceptable; team to choose one and keep API contracts stable).
- Queue: lightweight job queue for optional enrichment only.
- Cache: Redis preferred; DB cache fallback acceptable for MVP.

## 4. Service Boundaries
### 4.1 API Service
- Responsibilities:
  - Authn/authz
  - Input validation
  - Request ID propagation
  - Rate limiting
- Endpoints:
  - `POST /v1/onboarding`
  - `POST /v1/logs/parse`
  - `POST /v1/logs`
  - `GET /v1/logs/day-summary`

### 4.2 Parser Service (Deterministic)
- Responsibilities:
  - Tokenize text into food segments
  - Extract quantities/units
  - Fuzzy match food names to nutrition entries
  - Emit normalized items + confidence
- SLA:
  - p50 < 250ms for short logs
  - p95 < 500ms

### 4.3 AI Normalizer Service
- Responsibilities:
  - Low-cost model fallback for medium confidence
  - Optional escalation path (feature-flagged)
  - Strict JSON schema validation for model output
  - Persist usage/cost event for each call
- Guarantees:
  - Max one fallback call on primary parse path
  - Escalation off by default in early beta

### 4.4 Nutrition Service
- Responsibilities:
  - Unit normalization to grams
  - Macro and calorie calculations
  - Source tracking (`nutrition_source_id`)
- Constraint:
  - No LLM usage for numeric calculations

### 4.5 Cost Observability
- Responsibilities:
  - Track tokens, model, estimated USD, route tier
  - Maintain per-day budget counters
  - Expose internal metrics endpoint/dashboard feed

## 5. Data Contract Details
### 5.1 Parse Response Item Schema
```json
{
  "name": "egg",
  "amount": 2,
  "quantity": 2,
  "unitNormalized": "count",
  "unit": "count",
  "gramsPerUnit": 50,
  "grams": 100,
  "calories": 144,
  "protein": 12.6,
  "carbs": 1.1,
  "fat": 9.5,
  "matchConfidence": 0.96,
  "nutritionSourceId": "fatsecret_food_1123",
  "needsClarification": false,
  "manualOverride": false,
  "assumptions": []
}
```

### 5.1A Parse Response Top-Level Additions (Additive)
```json
{
  "requestId": "req_123",
  "parseRequestId": "req_123",
  "parseVersion": "v2",
  "route": "fatsecret",
  "cacheHit": false,
  "sourcesUsed": ["fatsecret"],
  "needsClarification": false
}
```

### 5.2 Assumptions Schema
```json
{
  "assumptions": [
    "Toast interpreted as white bread slice"
  ],
  "items": [
    {
      "name": "butter",
      "assumptions": [
        "Interpreted as salted butter, 1 tsp per slice"
      ]
    }
  ]
}
```

### 5.3 Error Format
```json
{
  "error": {
    "code": "INVALID_INPUT",
    "message": "text exceeds max length",
    "requestId": "req_123"
  }
}
```

### 5.4 Parse-to-Save Contract
- `POST /v1/logs` must include:
  - `parseRequestId` returned by `POST /v1/logs/parse`
  - `parseVersion` returned by parse route
- `POST /v1/logs` must require `Idempotency-Key` header.
- Save payload supports additive manual override shape:
  ```json
  {
    "manualOverride": {
      "enabled": true,
      "reason": "User corrected serving",
      "editedFields": ["quantity", "unit"]
    }
  }
  ```
- Server behavior:
  - same idempotency key + same payload => return prior success response
  - same idempotency key + different payload => `409 CONFLICT`
  - stale/unknown `parseRequestId` => `422 UNPROCESSABLE_ENTITY`
  - incompatible parse reference and override policy => `422 UNPROCESSABLE_ENTITY`
  - `needsClarification=true` items without override resolution remain save-blocking

## 6. Confidence and Routing Algorithm (v1)
### 6.1 Deterministic Confidence Score
- Score range: `0.0 - 1.0`
- Weighted formula:
  - Food name match quality: 45%
  - Quantity/unit parse quality: 25%
  - Portion plausibility check: 15%
  - Parser coverage of input text: 15%

`confidence = 0.45*m + 0.25*q + 0.15*p + 0.15*c`

Where all sub-scores are normalized in `[0,1]`.

### 6.2 Routing Rules
- `confidence >= 0.85`: accept deterministic output.
- `0.50 <= confidence < 0.85`: run low-cost normalization once.
- `< 0.50` after fallback: return clarification prompt payload.
- Escalation only if:
  - user clicks `Improve estimate`, and
  - feature flag `ai_escalation_enabled = true`, and
  - daily budget not exceeded.

### 6.3 Clarification Payload
```json
{
  "needsClarification": true,
  "questions": [
    "How many slices of toast?",
    "Was milk added to coffee?"
  ]
}
```

### 6.4 Reliability and Future-Date Validation Rules
- Parse debounce should be scoped at row level where possible to avoid re-parsing unchanged rows.
- Backend validates `loggedAt` against user timezone and rejects future dates.
- Future-date rejections use stable error envelope shape for UI mapping.

## 7. Database Implementation Plan
### 7.1 DDL Scope
- Create tables from PRD:
  - `users`
  - `onboarding_profiles`
  - `food_logs`
  - `food_log_items`
  - `parse_cache`
  - `ai_cost_events`
- Add indexes:
  - `food_logs(user_id, logged_at)`
  - `food_log_items(food_log_id)`
  - `ai_cost_events(created_at)`
  - `ai_cost_events(user_id, created_at)`
  - `parse_cache(last_used_at)`

### 7.2 Constraints
- Foreign keys enforced.
- `parse_confidence` and `match_confidence` check `0 <= value <= 1`.
- `estimated_cost_usd >= 0`.
- Persist assumptions at both levels:
  - `food_logs.assumptions_json` for log-level summary assumptions
  - `food_log_items.assumptions_json` for per-item assumptions

### 7.3 Onboarding Integrity Storage Modes
- Mode A (full-input): store all onboarding input fields used by UI.
- Mode B (computed+provenance): store computed targets and provenance metadata:
  - `calculator_version`
  - `inputs_hash`
  - `computed_at`
- One mode must be selected per environment and auditable.

## 8. Caching Plan
- Canonical key (SHA-256):
  - `normalized_text`
  - `locale`
  - `units`
  - `parser_version`
  - `provider_route_version`
  - `model_prompt_version`
  - `nutrition_db_version`
- Cache scope:
  - default `global`
  - user-scoped only when parse input is user-specific (for example saved custom recipes)
- Normalized input text rules:
  - lowercase
  - trimmed whitespace
  - punctuation collapsed
  - Unicode normalized (NFKD), strip combining marks and zero-width spaces
- Cache TTL:
  - hot parse results: 30 days
  - nutrition lookup fragments: 90 days
- Invalidation:
  - parser version bump invalidates prior parser outputs
  - provider route/prompt/model version bump invalidates prior AI-routed outputs
  - nutrition DB version bump invalidates nutrition-derived entries
  - operational global purge remains available for emergency policy changes

## 9. Budget and Kill Switch Controls
- Env/config:
  - `AI_DAILY_BUDGET_USD`
  - `AI_USER_SOFT_CAP_USD`
  - `AI_ESCALATION_ENABLED`
  - `AI_FALLBACK_ENABLED`
- Runtime behavior:
  - If global daily budget exceeded: fallback/escalation disabled, deterministic-only mode.
  - If user soft cap exceeded: show warning flag in response metadata.
  - Budget counters must be updated atomically to avoid overspend under concurrency.

## 10. Observability Spec
### 10.1 Required Metrics
- `parse_requests_total`
- `parse_deterministic_total`
- `parse_fallback_total`
- `parse_escalation_total`
- `parse_clarification_total`
- `ai_tokens_input_total`
- `ai_tokens_output_total`
- `ai_estimated_cost_usd_total`
- `cache_hit_ratio`

### 10.2 Alerts
- Escalation rate > 8% (15 min window)
- Cost per log > target by 20% (24h window)
- Cache hit ratio < 30% (24h window)

## 11. Security/Compliance Implementation
- Encrypt DB at rest and TLS in transit.
- PII logging policy:
  - never log raw auth tokens
  - redact email in app logs
- Prompt logging:
  - redact user-identifiable fields before persistence
- User deletion:
  - hard-delete logs and profile on account deletion request

## 11A. Apple Health Sync Strategy
- Locked MVP mode: per-log writes only.
- No daily aggregate write mode in MVP.
- Every saved log must map to a stable `healthWriteKey`.
- Edit/delete flows must upsert/replace prior Health writes by `healthWriteKey` to avoid double counting.

## 12. Milestones and Tasks
### Milestone 1: Core Logging Without AI (Week 1-2)
- [ ] Create DB migrations and indexes
- [ ] Build onboarding endpoints and persistence
- [ ] Build deterministic parser v1
- [ ] Build parse and save endpoints
- [ ] Build daily summary endpoint
- Exit criteria:
  - Users can onboard, parse, edit, and save logs
  - No AI dependency

### Milestone 2: Low-Cost AI Fallback + Caching (Week 3)
- [ ] Add parse cache layer
- [ ] Add AI fallback route with strict schema validation
- [ ] Add clarification response path
- [ ] Add `ai_cost_events` writes
- Exit criteria:
  - Fallback route operational
  - Parse cache hit ratio visible
  - Cost events recorded

### Milestone 3: Budget Controls + Reliability (Week 4)
- [ ] Add daily budget enforcement
- [ ] Add escalation feature flag path
- [ ] Add metrics and alert wiring
- [ ] Run 1,000-log replay for threshold tuning
- Exit criteria:
  - Deterministic-only safe mode works
  - Alerts fire correctly in test

## 13. Test Plan
### 13.1 Unit Tests
- Quantity/unit parser cases (fractions, pluralization, mixed units)
- Confidence score calculation bounds
- Nutrition arithmetic and rounding

### 13.2 Integration Tests
- `POST /v1/logs/parse` deterministic path
- Fallback path with mock AI response
- Clarification path
- Budget cap path (AI disabled after cap)
- Idempotency behavior for `POST /v1/logs` (replay + conflict)
- Stale `parseRequestId` rejection path
- Day summary timezone boundary path (`tz` and profile-timezone default)

### 13.3 Load/Replay Tests
- Replay 1,000 representative logs
- Validate:
  - median latency
  - cost/log
  - fallback and escalation rates

## 14. Definition of Done (MVP Backend)
- All MVP endpoints deployed and versioned.
- Deterministic parse handles at least 70% of sample logs with acceptable output.
- Cost events and dashboards operational.
- Budget caps and kill switches verified.
- API docs published for iOS client integration.
