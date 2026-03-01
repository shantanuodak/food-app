# Known Limitations: MVP Backend

## 1) Scope Limitations (Intentional MVP)
- No photo-based food parsing.
- No menu OCR / restaurant menu scanning.
- No conversational coaching assistant.
- No social features.

## 2) API/Product Limitations (Current Implementation)
- Auth supports dev/supabase/hybrid token modes, but session-based refresh handling is still owned by client auth flow.
- RLS policies are enabled in schema, but backend currently uses trusted DB role access (no per-query `request.jwt.claim.sub` propagation).
- Parse confidence and nutrition matching run on a small seed dataset (not full production nutrition catalog).
- Clarification prompts are generated from parse assumptions and simple heuristics; deeper context-aware follow-up is planned.
- Parse output currently provides log-level assumptions; item-level assumption detail is not fully exposed.
- Parse cache uses normalized input text and current parser behavior; cache invalidation/versioning is basic in MVP.

## 3) Operational Limitations
- Internal metrics/alerts endpoints use shared header key; no per-role auth layer yet.
- Alerting is exposed via internal API and runbook; external alert delivery integrations (Slack/PagerDuty) are not wired in this repo.
- Replay benchmark harness is local/script-based and not yet scheduled in CI.

## 4) Data and Reliability Tradeoffs
- Food matching quality is strongest for common foods/phrases; uncommon restaurant dishes may fall back to clarification.
- Budget caps are global per-day and user soft-cap based; advanced tenant-level budget partitioning is not included.
- No historical model-performance comparison API yet; comparisons are via saved benchmark artifacts.

## 5) Planned Follow-ups
- Expand auth/session telemetry and token refresh diagnostics.
- Add strict DB-role runtime validation for RLS claim propagation path.
- Expand nutrition catalog and matching strategy.
- Add richer clarification workflow with prior user context.
- Add external monitoring integrations and automated alert notifications.
