# E2E Performance Findings - MVP (E2E-003)

## Goal
- Keep common logging flow under 10 seconds end-to-end.

## Benchmark run
- Date: February 16, 2026
- Command:
```bash
cd "/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend"
DATABASE_URL_TEST='postgres://shantanuodak@localhost:5432/food_app_test' npm run benchmark:e2e -- --iterations 30
```
- Artifact:
  - `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/benchmarks/artifacts/e2e-performance-2026-02-16T16-22-15-174Z.json`

## Results (30 iterations)
- Parse latency:
  - p50: `9.18ms`
  - p95: `24.31ms`
- Save latency:
  - p50: `13.81ms`
  - p95: `33.76ms`
- Day-summary latency:
  - p50: `4.41ms`
  - p95: `14.83ms`
- End-to-end API chain (parse + save + summary):
  - p50: `33.87ms`
  - p95: `69.95ms`
  - max: `75.61ms`
- Target check:
  - `<10s` target met (`meetsTargetUnder10s = true`)

## Tuning changes implemented
1. Parse responsiveness improvement:
   - Debounce reduced from `~550ms` to `~400ms` for faster perceived feedback.
2. Time-to-log instrumentation:
   - iOS now tracks and displays `Time to log` after save success.
   - Telemetry now includes `timeToLogMs` on successful saves when available.
3. Reliability + performance under flaky network:
   - Offline-aware flow prevents wasteful retries while disconnected.
   - Pending save draft + idempotency key persistence avoids repeated rework.

## Notes
- The benchmark measures backend/API path latency and excludes human think/edit time.
- iOS UI now surfaces per-flow `Time to log` to validate real user path on device.
