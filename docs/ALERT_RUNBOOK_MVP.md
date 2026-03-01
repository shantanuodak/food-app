# Alert Runbook: Food Logging MVP Backend

This runbook is linked from `/v1/internal/alerts` responses and covers the three MVP anomaly alerts.

## Escalation rate high
Anchor: `#escalation-rate-high`

Trigger:
- Alert key: `ESCALATION_RATE_HIGH`
- Condition: escalation rate in last 15 minutes is greater than `0.08` (8%).

What it means:
- Too many requests require expensive escalation.
- Deterministic parse and fallback quality may have regressed.

Immediate checks:
1. Check recent parse inputs for new phrase patterns not handled by deterministic parser.
2. Check fallback model output validation failures.
3. Verify `AI_FALLBACK_CONFIDENCE_MIN` and `AI_FALLBACK_CONFIDENCE_MAX` were not changed unexpectedly.

Mitigation:
1. Temporarily disable escalation (`AI_ESCALATION_ENABLED=false`) if spend risk is high.
2. Patch deterministic parser rules for top failing phrases.
3. Re-run replay tests before re-enabling escalation.

## Cache hit ratio low
Anchor: `#cache-hit-ratio-low`

Trigger:
- Alert key: `CACHE_HIT_RATIO_LOW`
- Condition: cache hit ratio in last 24 hours is less than `0.30` (30%).

What it means:
- Similar user inputs are not reusing cache effectively.
- Parse latency and cost may increase.

Immediate checks:
1. Confirm normalization rules are stable (spacing/punctuation/lowercasing).
2. Confirm parser version or route version did not change unintentionally.
3. Verify parse cache read/write operations are succeeding.

Mitigation:
1. Fix normalization drift.
2. Backfill common phrases into cache if needed.
3. Reduce unnecessary parser-version bumps.

## Cost per log drift high
Anchor: `#cost-per-log-drift-high`

Trigger:
- Alert key: `COST_PER_LOG_DRIFT_HIGH`
- Condition: 24-hour cost/log is more than 20% above target.

What it means:
- AI cost efficiency regressed compared to expected target.

Immediate checks:
1. Check fallback and escalation rates in the same 24-hour window.
2. Check token usage changes (`ai_tokens_input_total`, `ai_tokens_output_total`).
3. Confirm model routing and per-call cost assumptions.

Mitigation:
1. Tighten fallback routing window.
2. Lower escalation usage or require clarification first.
3. Update target cost if product intentionally changed behavior.

## False-positive review checklist
1. Volume guard: ignore alerts with insufficient sample size.
2. Deployment timing: ignore first 15 minutes after release restart.
3. One-off load test windows: annotate and suppress expected spikes.
4. Confirm DB clock and timezone are UTC-consistent.
