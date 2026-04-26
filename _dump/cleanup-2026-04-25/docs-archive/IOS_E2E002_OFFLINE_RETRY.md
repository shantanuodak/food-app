# iOS Offline + Retry UX (E2E-002)

## What is implemented
- Network-aware UI state:
  - offline banner with recovery guidance
  - parse/save/retry/escalation actions disabled while offline
- Recovery messaging:
  - parse failure guidance preserves user note
  - save failure guidance explicitly says draft is preserved
- Idempotent retry persistence:
  - pending save draft (`SaveLogRequest`)
  - idempotency key
  - restored on app reopen for safe retry

## Why this satisfies E2E-002
- Recoverable network failures without data loss:
  - note text remains in editor
  - save draft + key are persisted locally
- Retry preserves idempotency behavior:
  - same `Idempotency-Key` reused for retried save
- Actionable recovery guidance:
  - UI messages explicitly tell user when/how to retry

## Manual validation steps
1. Parse a valid log and ensure non-zero totals.
2. Disable network in simulator:
   - iOS Simulator -> `Features` -> `Network` -> choose `100% Loss` (or disconnect host network).
3. Tap `Save Log`.

Expected:
- Save does not proceed.
- UI shows offline guidance.
- `Retry Last Save` remains available once network returns.

4. Re-enable network.
5. Tap `Retry Last Save`.

Expected:
- Save succeeds using same idempotency key.
- No duplicate logs are created on repeated retry.

6. Optional persistence check:
   - Go offline after a failed save, close app, reopen app.

Expected:
- App restores pending save context.
- Message: recovered pending save draft.
- Retry remains possible when network returns.
