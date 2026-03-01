#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
BACKEND_DIR="$REPO_ROOT/backend"
RELEASE_CHECK_SCRIPT="$SCRIPT_DIR/check_testflight_release_config.sh"
BACKEND_LOG="/tmp/foodapp-testflight-preupload.log"

SKIP_INSTALL=0
SKIP_INTEGRATION=0
SKIP_MIGRATE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    --skip-integration)
      SKIP_INTEGRATION=1
      shift
      ;;
    --skip-migrate)
      SKIP_MIGRATE=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--skip-install] [--skip-integration] [--skip-migrate]" >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$BACKEND_DIR" ]]; then
  echo "ERROR: Could not find backend directory at $BACKEND_DIR" >&2
  exit 1
fi

echo "1/6 Checking Release config..."
"$RELEASE_CHECK_SCRIPT"

pushd "$BACKEND_DIR" >/dev/null

if [[ -f ".env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source ".env"
  set +a
fi

if [[ "$SKIP_INSTALL" -eq 0 ]]; then
  echo "2/6 Running npm ci..."
  npm ci
else
  echo "2/6 Skipping npm ci (--skip-install)."
fi

echo "3/6 Running backend build + tests..."
npm run build
npm test

if [[ "$SKIP_INTEGRATION" -eq 0 ]]; then
  npm run test:integration
else
  echo "Integration tests skipped (--skip-integration)."
fi

if [[ "$SKIP_MIGRATE" -eq 0 ]]; then
  echo "4/6 Running migrations..."
  npm run migrate
else
  echo "4/6 Migration skipped (--skip-migrate)."
fi

echo "5/6 Verifying health endpoint with backend dev server..."
npm run dev >"$BACKEND_LOG" 2>&1 &
DEV_PID=$!
cleanup() {
  if [[ -n "${DEV_PID:-}" ]]; then
    kill "$DEV_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

HEALTH_OK=0
for _ in $(seq 1 30); do
  if curl -fsS "http://localhost:8080/health" >/tmp/foodapp-health.json 2>/dev/null; then
    HEALTH_OK=1
    break
  fi
  sleep 1
done

if [[ "$HEALTH_OK" -ne 1 ]]; then
  echo "ERROR: /health did not become ready. Last backend log lines:" >&2
  tail -n 80 "$BACKEND_LOG" >&2 || true
  exit 1
fi

echo "Health response:"
cat /tmp/foodapp-health.json

cleanup
trap - EXIT
popd >/dev/null

echo "6/6 Pre-upload gate passed."
echo "Manual checks still required before archive:"
echo "  - Physical-device iOS smoke (launch/sign-in/onboarding/parse/save/day summary)"
echo "  - Verify no debug/auth diagnostic UI in release flow"
