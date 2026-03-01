# Supabase Setup Guide

This guide moves backend persistence from local Postgres to Supabase Postgres.

## 1) Create a Supabase project
- Create a new project in Supabase.
- Save the DB password you set during project creation.

## 2) Configure backend env
In `backend/.env`, set:

```env
DATABASE_URL=postgresql://postgres:<PASSWORD>@db.<PROJECT_REF>.supabase.co:5432/postgres
DATABASE_SSL=true
AUTH_MODE=supabase
SUPABASE_JWT_SECRET=<project_jwt_secret>
SUPABASE_JWT_ISSUER=https://<PROJECT_REF>.supabase.co/auth/v1
SUPABASE_JWT_AUDIENCE=authenticated
RLS_STRICT_MODE=false
```

Notes:
- Use the direct DB host from Supabase connection settings.
- Keep `DATABASE_URL_TEST` pointed to local test DB unless you want integration tests against Supabase.

## 3) Run schema migrations
From `backend`:

```bash
npm run migrate
```

This applies:
- `migrations/0001_init_schema.sql`
- `migrations/0002_parse_contracts.sql`
- `migrations/0003_alert_signal_columns.sql`
- `migrations/0004_timezone_and_rls.sql`

## 4) Verify tables in Supabase SQL editor
Run:

```sql
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in (
    'users',
    'onboarding_profiles',
    'food_logs',
    'food_log_items',
    'parse_cache',
    'parse_requests',
    'log_save_idempotency',
    'ai_cost_events'
  )
order by table_name;
```

## 5) Run backend
From `backend`:

```bash
npm run dev
```

Health check:

```bash
curl http://localhost:8080/health
```

## 6) Production notes
- Keep Gemini and FatSecret API credentials only in backend env.
- Use `AUTH_MODE=hybrid` only during staged rollout (dev token + Supabase JWT accepted).
- Use `AUTH_MODE=supabase` for production.
- Keep `AUTH_BEARER_DEV_PREFIX` only for local/dev workflows.
- Optional hardening: set `RLS_STRICT_MODE=true` only when backend uses a non-`postgres` DB role.
