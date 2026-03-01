# E2E QA Matrix (Frontend + Backend) - MVP

## 1) Run metadata
- Last updated: February 16, 2026
- Automated suite: `backend/tests/integration.api.test.ts`
- Command used:
  - `DATABASE_URL_TEST='postgres://shantanuodak@localhost:5432/food_app_test' npm run test:integration`
- Result:
  - `1` test file passed
  - `15` tests passed
  - `0` failed

## 2) Status legend
- `PASS`: verified and currently passing
- `FAIL`: verified and currently failing
- `PENDING`: not yet executed in this cycle

## 3) Backend API E2E matrix (automated)
| ID | Flow / Failure Path | Required by E2E-001 | Owner | Type | Status | Evidence |
|---|---|---|---|---|---|---|
| API-E2E-01 | Onboarding -> parse -> save -> day-summary happy path | onboarding, parse, save, summary | Backend | Automated | PASS | `onboarding -> parse -> save -> day-summary flow` |
| API-E2E-02 | Day-summary user scoping | summary data isolation | Backend | Automated | PASS | `day-summary is user-scoped` |
| API-E2E-03 | Validation failures envelope | validation failure coverage | Backend | Automated | PASS | `validation errors return standard INVALID_INPUT envelope` |
| API-E2E-04 | Auth failures envelope | auth failure coverage | Backend | Automated | PASS | `auth failures return UNAUTHORIZED envelope` |
| API-E2E-05 | Clarification required path | clarification branch | Backend | Automated | PASS | `low-confidence text returns clarification questions` |
| API-E2E-06 | Escalation success path | escalation branch | Backend | Automated | PASS | `escalation works only on unresolved text and records ai cost event` |
| API-E2E-07 | Budget cap blocks escalation/fallback | budget failure coverage | Backend | Automated | PASS | `daily budget cap disables both fallback and escalation routes` |
| API-E2E-08 | Fallback disabled when budget insufficient | budget guard behavior | Backend | Automated | PASS | `fallback is disabled when remaining daily budget is insufficient` |
| API-E2E-09 | Idempotency replay safety | idempotency behavior | Backend | Automated | PASS | `idempotency replay returns prior success and no duplicate log` |
| API-E2E-10 | Idempotency conflict on changed payload | idempotency failure coverage | Backend | Automated | PASS | `idempotency key reuse with different payload is rejected` |
| API-E2E-11 | Save rejects invalid parse reference | parse/save contract failure | Backend | Automated | PASS | `unknown parseRequestId is rejected on save` |
| API-E2E-12 | Save transaction rollback on partial failure | atomicity hardening | Backend | Automated | PASS | `save endpoint rolls back atomically when item insert fails` |

## 4) Frontend E2E matrix (manual)
| ID | Flow / Failure Path | Required by E2E-001 | Owner | Type | Status | Evidence |
|---|---|---|---|---|---|---|
| IOS-E2E-01 | Onboarding -> main logging navigation | onboarding | iOS | Manual | PASS | Implemented in app shell and verified during Sprint 5 setup |
| IOS-E2E-02 | Parse request with live totals render | parse | iOS | Manual | PASS | Main logging screen parse flow verified in simulator |
| IOS-E2E-03 | Clarification UI appears for low confidence text | clarification | iOS | Manual | PASS | `Avocado sandwich` scenario verified |
| IOS-E2E-04 | Escalation explicit action and disabled-state messaging | escalation + budget/flag handling | iOS | Manual | PASS | FE-008 flow verified after env update |
| IOS-E2E-05 | Strict save + idempotent retry UX | save + idempotency | iOS | Manual | PASS | Save/retry behavior verified with idempotency key reuse |
| IOS-E2E-06 | Day summary updates after save | summary | iOS | Manual | PASS | FE-010 flow verified after saved-day sync patch |
| IOS-E2E-07 | API auth failure surfaced in UI | auth failure | iOS | Manual | PENDING | Run with invalid/missing bearer token in debug environment |
| IOS-E2E-08 | Invalid input error surfaced in UI | validation failure | iOS | Manual | PENDING | Run with malformed/oversized parse payload via debug path |
| IOS-E2E-09 | Offline save recovery with idempotent retry | flaky network + retry behavior | iOS | Manual | PENDING | Validate `/docs/IOS_E2E002_OFFLINE_RETRY.md` scenario |
| IOS-E2E-10 | Accessibility + localization baseline | a11y + i18n baseline | iOS | Manual | PENDING | Validate `/docs/IOS_E2E004_ACCESSIBILITY_LOCALIZATION.md` checklist |
| IOS-E2E-11 | Beta release readiness + TestFlight handoff | release operational readiness | iOS/Backend | Manual | PENDING | Validate `/docs/IOS_E2E005_BETA_READINESS.md` checklist |
| PERF-E2E-01 | Common flow API performance (<10s target) | performance baseline | Backend | Automated | PASS | `/docs/E2E_PERFORMANCE_MVP.md` and benchmark artifact |

## 5) Gaps and next actions
1. Execute pending iOS manual checks (auth, validation, offline/retry, accessibility/localization, beta readiness) and update statuses.
2. Run on-device manual `time to log` checks and append results to `/docs/E2E_PERFORMANCE_MVP.md`.
