# Cheapest Deployment Runbook: Supabase Free + Render Free

Date: March 1, 2026  
Goal: get a public HTTPS backend URL for internal TestFlight at lowest cost.

## 0) Expected outcome

1. Public backend URL: `https://<render-service>.onrender.com`
2. Health check works:
   - `GET /health` returns `{"status":"ok"}`
3. iOS release config uses that URL for TestFlight upload.

## 1) Create Supabase (free) project

1. In Supabase, create a new project.
2. In `Project Settings -> Database`, copy connection string.
3. In `Project Settings -> API`, copy:
   - Project URL (`https://<project-ref>.supabase.co`)
   - JWT secret or JWKS-based issuer values
4. Enable Google provider for auth if needed for your current iOS flow.

## 2) Apply backend DB migrations to Supabase

Run from:
`/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend`

```bash
set -a
source .env
set +a
npm run migrate
```

If your local `.env` points to a different DB, run migrations using a temporary env file with the new Supabase `DATABASE_URL`.

## 3) Prepare Render service (free)

Repo already contains a Render blueprint:
1. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/render.yaml`

Render service settings in blueprint:
1. `rootDir=backend`
2. `buildCommand=npm ci && npm run build`
3. `startCommand=npm run migrate && npm run start`
4. `healthCheckPath=/health`
5. `plan=free`

## 4) Set Render environment variables

Use this template:
1. `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/backend/.env.render.example`

Minimum required values before first deploy:
1. `DATABASE_URL`
2. `DATABASE_SSL=true`
3. `AUTH_MODE=supabase`
4. `SUPABASE_JWT_ISSUER`
5. `SUPABASE_JWT_AUDIENCE=authenticated`
6. One of:
   - `SUPABASE_JWT_SECRET` (HS256), or
   - `SUPABASE_JWKS_URL` + issuer (asymmetric)
7. `INTERNAL_METRICS_KEY` (any strong random value)

Strongly recommended for cheapest stable beta:
1. `AI_ESCALATION_ENABLED=false`
2. Conservative AI budget defaults from template.

## 5) Deploy and verify backend

1. Trigger deploy in Render.
2. Wait until service is healthy.
3. Verify:

```bash
curl -i https://<render-service>.onrender.com/health
```

Expected:
1. `HTTP 200`
2. body includes `{"status":"ok"}`

## 6) Wire iOS Release URL to deployed backend

From project root:
`/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App`

```bash
"/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/set_release_api_base_url.sh" "https://<render-service>.onrender.com"
"/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/check_testflight_release_config.sh"
```

## 7) Run TestFlight pre-upload gate

```bash
"/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/scripts/ios/testflight_preupload_gate.sh"
```

Then continue with:
1. physical-device iOS smoke
2. archive/upload in Xcode
3. internal tester rollout

## 8) Free-tier caveats (important)

1. Render free web services can cold start after idle; first request may be slow.
2. For frequent internal testing, move only backend web service to paid starter when cold starts become disruptive.
3. Keep Supabase on free tier initially; upgrade only when usage/limits become actual blockers.

