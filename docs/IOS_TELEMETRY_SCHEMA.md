# iOS Telemetry Event Schema (FE-004)

## Purpose
Track parse/save UX reliability with client-side duration and failure context.

## Event transport
- Current hook emits JSON to app logs with prefix: `[telemetry]`
- Source file: `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/Telemetry.swift`

## Common schema
Each telemetry event uses this shape:

```json
{
  "eventName": "parse_request",
  "feature": "parse",
  "outcome": "success",
  "durationMs": 142,
  "timestamp": "2026-02-16T18:22:33.123Z",
  "environment": "local",
  "backendRequestId": "72d8e1b6-ff2b-4eca-a8f2-7641a3752880",
  "backendErrorCode": null,
  "httpStatusCode": null,
  "parseRequestId": "72d8e1b6-ff2b-4eca-a8f2-7641a3752880",
  "parseVersion": "v1",
  "details": {
    "route": "deterministic"
  }
}
```

## Event names
- `parse_request`
  - Success/failure for parse calls.
  - Includes parse route/cache/fallback/clarification flags in `details` on success.
- `save_log`
  - Success/failure for save calls.
  - Includes retry flag and item count in `details`.

## Failure metadata
- For API errors, `backendRequestId`, `backendErrorCode`, and `httpStatusCode` are populated from backend error envelope when available.
- This satisfies FE-004 requirement to include backend request ID on failures.

## Example: parse failure
```json
{
  "eventName": "parse_request",
  "feature": "parse",
  "outcome": "failure",
  "durationMs": 311,
  "timestamp": "2026-02-16T18:23:02.900Z",
  "environment": "local",
  "backendRequestId": "2aaf358d-9191-41ac-8b34-8a8aa7b04e23",
  "backendErrorCode": "UNAUTHORIZED",
  "httpStatusCode": 401,
  "parseRequestId": null,
  "parseVersion": null,
  "details": {
    "uiApplied": "true",
    "errorMessage": "Token does not contain valid user id"
  }
}
```

## Example: save failure
```json
{
  "eventName": "save_log",
  "feature": "save",
  "outcome": "failure",
  "durationMs": 188,
  "timestamp": "2026-02-16T18:24:30.217Z",
  "environment": "local",
  "backendRequestId": "4ac530466e98-....",
  "backendErrorCode": "INVALID_PARSE_REFERENCE",
  "httpStatusCode": 422,
  "parseRequestId": "72d8e1b6-ff2b-4eca-a8f2-7641a3752880",
  "parseVersion": "v1",
  "details": {
    "isRetry": "false",
    "itemsCount": "3",
    "rawTextLength": "44",
    "errorMessage": "This parsed draft is stale. Parse again, then save."
  }
}
```

## Quick validation
1. Run app from Xcode.
2. Trigger parse success and save success.
3. Trigger one parse/save failure (for example with invalid auth token or stale parse reference).
4. Open Xcode console and confirm lines prefixed with `[telemetry]`.
5. Confirm each line includes:
   - `eventName` (`parse_request` or `save_log`)
   - `outcome` (`success` or `failure`)
   - `durationMs`
   - `backendRequestId` on API failures when backend returns one
