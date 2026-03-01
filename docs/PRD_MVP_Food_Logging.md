# PRD: Seamless AI-Assisted Food Logging (MVP)

## 1. Document Info
- Product: Food App (iOS-first)
- Version: MVP v1
- Date: February 15, 2026
- Owner: Founding Product + Engineering

## 2. Problem Statement
Users abandon food logging because current apps are slow and tedious. The MVP must make logging feel as simple as writing a note, while still generating reliable calorie and macro data.

## 3. Goals and Non-Goals
### Goals
- Reduce log time to under 10 seconds for common meals.
- Show calories/macros instantly as the user types.
- Deliver predictable AI cost per log with hard budget controls.
- Build backend primitives that can later support photo logging and menu scanning.

### Non-Goals (MVP)
- No photo parsing.
- No menu/image OCR.
- No coaching chatbot.
- No advanced social features.

## 4. Primary User Flow
1. User signs in (Apple/Google/Email). Guest mode remains feature-flagged and is deferred from MVP release scope.
2. User completes short onboarding (goal, diet preferences, allergies, units, activity level).
3. User lands on main logging screen:
   - Left: free-form text note input.
   - Right: live calorie/macros estimate.
4. User taps estimate for details (food matches, assumptions, confidence).
5. User edits if needed and saves.
6. Daily summary updates immediately.

## 5. UX Requirements
### Main Log Screen
- Input supports natural language (example: "2 eggs, toast with butter, black coffee").
- Side panel updates in under 500ms for high-confidence parser path.
- Detail drawer includes:
  - Parsed items and quantities
  - Matched nutrition entries
  - Confidence level
  - Editable fields (food, quantity, unit)

### Onboarding
Required questions:
- Goal: lose / maintain / gain
- Diet preference
- Allergies/intolerances
- Units: metric/imperial
- Activity level
Optional:
- Weekly pace target

Onboarding output config:
- Daily calorie target
- Macro split target
- Unit defaults
- Suggestion style metadata

## 6. Functional Requirements
- Parse free-form food text into structured food items.
- Compute calories, protein, carbs, fats per item and total.
- Support item-level edits before save.
- Save logs by meal timestamp.
- Provide day summary totals and target progress.
- Persist parse confidence and assumptions for transparency.

## 7. Cost-Optimized AI Strategy
### Design Principle
Use deterministic logic first; use AI only when required.

### Parse Pipeline
1. **Parse Cache**
   - Check normalized composite cache key before provider calls.
   - On hit, short-circuit and return cached result.
2. **FatSecret Provider**
   - Primary external nutrition provider on cache miss.
3. **Gemini Fallback**
   - Used when FatSecret does not return an accepted parse and fallback is enabled.
4. **Rule/Fuzzy Parser Helpers (no LLM)**
   - Detect quantity/unit/food phrase patterns.
   - Fuzzy-match to nutrition index.
   - Assign confidence score.
5. **High-Capability Model Escalation**
   - Trigger only for unresolved ambiguity after fallback or high-value complex logs.

### Routing Policy (MVP)
- Primary provider order is locked to: `cache -> fatsecret -> gemini`.
- If confidence >= 0.85: accept provider output; no escalation.
- If 0.50 <= confidence < 0.85: allow one low-cost model fallback call.
- If confidence < 0.50 after fallback: ask 1 short clarification in UI and keep save blocked.
- Escalate to expensive model only when user explicitly requests auto-resolve or clarification fails.
- Parse totals must always equal sum of returned item values.
- Parse response must include `sourcesUsed` when mixed source families are present.

### Cost Guards
- Max input length: 500 chars per log.
- One low-cost model call max per request path.
- Escalation rate target: <= 5% of logs.
- Cache normalized outputs by text hash.
- Cache nutrition matches for frequent foods.
- Feature kill switch for expensive model.
- Cache key must include parser/provider/prompt version tags to prevent silent drift.

## 8. Backend Architecture
### Services
1. **API Gateway**
   - Auth, rate limits, request validation.
2. **Parsing Service**
   - Rule parser + fuzzy matcher + confidence scoring.
3. **AI Normalizer Service**
   - Model routing (cheap vs expensive), prompt templates, JSON validation.
4. **Nutrition Service**
   - Nutrition DB lookup, unit conversion, macro calculations.
5. **Logging Service**
   - Persist log entries and revisions.
6. **Cost Observability Service**
   - Track token usage, cost, cache hit rates, per-user and global budgets.

### Event/Async Components
- Background queue for optional enrichment jobs (only when user opens details or requests improved accuracy).

## 9. Data Model (Initial)
### `users`
- `id` (uuid, pk)
- `email`
- `auth_provider`
- `created_at`

### `onboarding_profiles`
- `user_id` (uuid, pk/fk)
- `goal`
- `diet_preference`
- `allergies_json`
- `units`
- `activity_level`
- `timezone` (IANA timezone, e.g. `America/Los_Angeles`)
- `calorie_target`
- `macro_target_protein`
- `macro_target_carbs`
- `macro_target_fat`
- `created_at`
- `updated_at`

### `food_logs`
- `id` (uuid, pk)
- `user_id` (uuid, fk)
- `logged_at` (timestamp)
- `meal_type` (optional)
- `raw_text`
- `assumptions_json` (log-level assumptions summary)
- `total_calories`
- `total_protein_g`
- `total_carbs_g`
- `total_fat_g`
- `parse_confidence`
- `created_at`
- `updated_at`

### `food_log_items`
- `id` (uuid, pk)
- `food_log_id` (uuid, fk)
- `food_name`
- `quantity`
- `unit`
- `grams`
- `calories`
- `protein_g`
- `carbs_g`
- `fat_g`
- `nutrition_source_id`
- `match_confidence`
- `assumptions_json` (item-level assumptions)

### `parse_cache`
- `cache_key` (pk) = hash(
  normalized_text +
  locale +
  units +
  parser_version +
  provider_route_version +
  model_prompt_version
  )
- `normalized_json`
- `confidence`
- `parser_version`
- `provider_route_version`
- `model_prompt_version`
- `nutrition_db_version`
- `created_at`
- `last_used_at`
- `hit_count`
- `cache_scope` (`global` by default; user-scoped only for user-specific inputs such as saved recipes)

### `ai_cost_events`
- `id` (uuid, pk)
- `user_id` (uuid)
- `request_id`
- `feature` (parse_fallback/escalation/enrichment)
- `model`
- `input_tokens`
- `output_tokens`
- `estimated_cost_usd`
- `created_at`

## 10. API Contracts (MVP)

### `POST /v1/onboarding`
Request:
```json
{
  "goal": "maintain",
  "dietPreference": "vegetarian",
  "allergies": ["peanut"],
  "units": "imperial",
  "activityLevel": "moderate",
  "timezone": "America/Los_Angeles"
}
```
Response:
```json
{
  "calorieTarget": 2200,
  "macroTargets": { "protein": 140, "carbs": 220, "fat": 73 }
}
```

### `POST /v1/logs/parse`
Request:
```json
{
  "text": "2 eggs, 2 slices toast with butter, black coffee",
  "loggedAt": "2026-02-15T13:35:00Z"
}
```
Response:
```json
{
  "requestId": "req_123",
  "parseRequestId": "req_123",
  "parseVersion": "v2",
  "route": "fatsecret",
  "cacheHit": false,
  "confidence": 0.88,
  "sourcesUsed": ["fatsecret"],
  "needsClarification": false,
  "totals": { "calories": 420, "protein": 19, "carbs": 29, "fat": 24 },
  "items": [
    {
      "name": "egg",
      "amount": 2,
      "quantity": 2,
      "unitNormalized": "count",
      "unit": "count",
      "gramsPerUnit": 50,
      "calories": 144,
      "protein": 12,
      "carbs": 1,
      "fat": 10,
      "matchConfidence": 0.96,
      "nutritionSourceId": "fatsecret_food_1123",
      "needsClarification": false,
      "manualOverride": false
    },
    {
      "name": "toast",
      "amount": 2,
      "quantity": 2,
      "unitNormalized": "slice",
      "unit": "slice",
      "gramsPerUnit": 30,
      "calories": 160,
      "protein": 6,
      "carbs": 30,
      "fat": 2,
      "matchConfidence": 0.82,
      "nutritionSourceId": "fatsecret_food_998",
      "needsClarification": false,
      "manualOverride": false
    }
  ],
  "assumptions": ["Toast interpreted as white bread slices"]
}
```

### `POST /v1/logs`
Header:
- `Idempotency-Key: <uuid>`

Request:
```json
{
  "parseRequestId": "req_123",
  "parseVersion": "parser_v1.3.0",
  "parsedLog": {
    "rawText": "2 eggs, 2 slices toast with butter, black coffee",
    "loggedAt": "2026-02-15T13:35:00Z",
    "items": [
      {
        "name": "toast",
        "quantity": 2,
        "unit": "slice",
        "manualOverride": {
          "enabled": true,
          "reason": "User selected whole wheat toast",
          "editedFields": ["name"]
        }
      }
    ]
  }
}
```
Response:
```json
{
  "logId": "log_123",
  "status": "saved",
  "idempotentReplay": false
}
```

### `GET /v1/logs/day-summary?date=2026-02-15&tz=America/Los_Angeles`
Notes:
- `date` is interpreted in timezone `tz` when provided.
- If `tz` is omitted, use `onboarding_profiles.timezone`.
- Fallback timezone is `UTC` only when user timezone is unavailable.

Response:
```json
{
  "date": "2026-02-15",
  "totals": { "calories": 1840, "protein": 122, "carbs": 191, "fat": 66 },
  "targets": { "calories": 2200, "protein": 140, "carbs": 220, "fat": 73 },
  "remaining": { "calories": 360, "protein": 18, "carbs": 29, "fat": 7 }
}
```

## 11. Cost Monitoring and Budget Controls
### Metrics (must-have)
- AI calls per 100 logs
- Mean cost per log
- p95 cost per log
- Cache hit rate
- Escalation rate
- Clarification prompt rate

### Budget Rules
- Daily global AI budget cap (hard stop to deterministic mode after cap).
- Per-user soft cap with warning and graceful degraded behavior.
- Alert when:
  - Escalation rate > 8%
  - Cache hit rate < 30%
  - Cost/log increases > 20% week-over-week

## 11A. Date Integrity Rules
- Backend must reject save requests with `loggedAt` in the future relative to the user timezone.
- UI must prevent date navigation/selection into future dates.
- Error contract for future-date rejection must remain stable and user-facing copy must explain why save was blocked.

## 11B. Edit Semantics (Locked for MVP)
- Manual edit path uses provenance semantics, not forced re-parse.
- Save keeps original `parseRequestId`/`parseVersion` but persists item-level manual override metadata.
- Original provider attribution remains preserved alongside `manual` provenance for changed fields.

## 11C. Apple Health Sync Strategy (Locked for MVP)
- Sync mode is per-log writes only (no daily aggregate write mode in MVP).
- Each saved log must map to a stable Health dedupe key.
- Edit/delete flows must update or replace prior Health entries by dedupe key to avoid double counting.

## 11D. Onboarding Data Integrity
- Backend onboarding storage must support one of:
  - Mode A: persist full onboarding inputs shown in UI.
  - Mode B: persist computed targets with provenance metadata (`calculatorVersion`, `inputsHash`, `computedAt`) for reproducibility.

## 12. Cost Formula and Scenario Planning
### Formula
For any period:

`Total Cost = Sum((input_tokens/1,000,000 * input_price_per_million) + (output_tokens/1,000,000 * output_price_per_million))`

`Cost per log = Total Cost / Number of logs`

### Planning Variables
- `L`: number of logs/day
- `p_fallback`: share routed to cheap model
- `p_escalation`: share routed to expensive model
- `t_in_fallback`, `t_out_fallback`
- `t_in_escalation`, `t_out_escalation`

Approximate daily cost:

`C_day = L * (p_fallback * C_fallback_call + p_escalation * C_escalation_call)`

Where:

`C_fallback_call = (t_in_fallback/1e6 * fallback_input_price) + (t_out_fallback/1e6 * fallback_output_price)`

`C_escalation_call = (t_in_escalation/1e6 * escalation_input_price) + (t_out_escalation/1e6 * escalation_output_price)`

### Example Template (fill with current model prices)
- Assume:
  - `L = 10,000 logs/day`
  - `p_fallback = 0.30`
  - `p_escalation = 0.03`
  - `t_in_fallback = 250`, `t_out_fallback = 120`
  - `t_in_escalation = 700`, `t_out_escalation = 280`
- Plug in live pricing from your chosen models to compute exact daily burn.

## 13. Security and Privacy
- Encrypt PII at rest and in transit.
- Store only necessary raw text; enable user deletion.
- Do not send profile data fields to model unless required for parsing.
- Log AI prompts/responses with redaction safeguards.

## 14. Success Metrics (MVP)
- Time-to-log median <= 10 seconds.
- >= 70% logs resolved without any AI call.
- Escalation <= 5%.
- Parse edit rate <= 20% after week 4.
- D7 retention target defined after beta baseline.

## 15. Rollout Plan
1. Internal alpha: deterministic parser + save flow.
2. Closed beta: cheap-model fallback + cost dashboards.
3. Public MVP: add escalation path and guardrails.

## 16. Risks and Mitigations
- Risk: nutrition DB mismatch lowers trust.
  - Mitigation: show assumptions and quick edit controls.
- Risk: AI cost spikes.
  - Mitigation: hard caps, escalation throttles, cache strategy.
- Risk: ambiguous food text.
  - Mitigation: short clarification UI before expensive calls.

## 17. Implementation Checklist
- [ ] Build parser confidence scoring.
- [ ] Add parse cache with hash key normalization.
- [ ] Add `ai_cost_events` instrumentation.
- [ ] Add feature flags and kill switches.
- [ ] Ship basic cost dashboard (daily burn, cost/log, escalation).
- [ ] Run 1,000-log synthetic test to tune thresholds.

## 18. Open Decisions
- Nutrition database provider selection and licensing.
- Exact confidence scoring heuristic for parser acceptance.
- Clarification UX: inline chips vs modal prompt.
- Final model choices per route tier.

## 19. Frontend Delivery Plan (iOS End-to-End)
Execution order for MVP app experience:

1. **Environment and networking baseline**
   - Run backend locally and confirm health endpoint from iOS simulator.
   - Configure iOS app base URL + auth header strategy for local/staging/prod.
   - Add dev-safe ATS/network settings for local HTTP.

2. **Typed API layer**
   - Build API client with typed request/response models for:
     - onboarding
     - parse
     - save
     - day-summary
   - Centralize error mapping from API error envelope to user-facing states.

3. **Onboarding flow**
   - Build onboarding questions UI (goal, preference, allergies, units, activity).
   - Submit to backend and persist completion state.
   - Route user into main logging screen on success.

4. **Main logging screen**
   - Add notes-style text input.
   - Add live macro/calorie side panel.
   - Trigger parse with input debounce and loading/error states.

5. **Parse detail and correction UX**
   - Add detail drawer for items, totals, assumptions, confidence.
   - Allow user edits before save (food, quantity, unit).
   - Show clarification prompts when `needsClarification=true`.

6. **Escalation and save contract UX**
   - Add explicit “Improve estimate” action to call escalation endpoint when needed.
   - Implement strict save path using:
     - `parseRequestId`
     - `parseVersion`
     - `Idempotency-Key`
   - Handle retries and idempotency conflict messaging.

7. **Day summary and progress**
   - Build day-summary screen with totals/targets/remaining.
   - Keep summary in sync after successful save.

8. **Resilience and polish**
   - Add offline-aware states and retry handling for transient failures.
   - Add API budget/error handling (`BUDGET_EXCEEDED`, validation, auth failures).
   - Add lightweight instrumentation for parse latency and save success/failure rates.

## 20. Figma Workstream (Parallel)
- Build design system tokens (color, type scale, spacing, component states).
- Produce high-fidelity screens for:
  - onboarding
  - main logging
  - parse detail/editor
  - clarification/escalation
  - day summary
- Deliver interactive prototype for primary flow and error states.
- Handoff package should include:
  - component specs
  - spacing/redlines
  - edge-state behavior notes
  - asset export list

## 21. End-to-End MVP Definition of Done
- User can complete onboarding and reach main logging screen.
- User can type a meal and see parse totals within target latency for common logs.
- User can review details, clarify/escalate when needed, and save successfully.
- Saved logs update same-day summary immediately.
- Retry behavior is safe via idempotency.
- Known limitations are documented and accepted for MVP launch.
- iOS handoff package and launch checklist are complete and signed off.
