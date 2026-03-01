# Backend Release Checklist (MVP)

Use this checklist before promoting backend to staging/prod.

## 1) Preconditions
- Postgres reachable from backend runtime.
- `.env` configured with:
  - `DATABASE_URL`
  - `PARSE_VERSION`
  - `PARSE_CACHE_SCHEMA_VERSION`
  - `PARSE_PROVIDER_ROUTE_VERSION`
  - `PARSE_PROMPT_VERSION`
  - `AI_DAILY_BUDGET_USD`
  - `AI_USER_SOFT_CAP_USD`
  - `AI_FALLBACK_COST_USD`

## 2) One-command preflight
Run:

```bash
cd "/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend"
npm run release:backend
```

This command runs:
1. TypeScript build
2. Unit tests
3. Integration tests
4. Release preflight checks:
  - config namespace sanity
  - DB connectivity
  - migration state (no pending migrations)

## 3) Deploy
```bash
cd "/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend"
npm run start
```

## 4) Post-deploy smoke
```bash
curl -i http://localhost:8080/health
```

Expected:
- `HTTP/1.1 200 OK`
- `{"status":"ok"}`

## 5) Rollback trigger conditions
- Any preflight failure.
- Health endpoint not returning `200`.
- Parse route returning sustained `5xx` for baseline deterministic traffic.
