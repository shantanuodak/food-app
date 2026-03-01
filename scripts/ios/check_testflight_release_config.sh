#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
PBXPROJ="$REPO_ROOT/Food App.xcodeproj/project.pbxproj"

if [[ ! -f "$PBXPROJ" ]]; then
  echo "ERROR: Could not find project file at $PBXPROJ" >&2
  exit 1
fi

TARGET_RELEASE_CONFIG_ID=$(
  awk '
    /Build configuration list for PBXNativeTarget "Food App"/ { in_list = 1; next }
    in_list && /\/\* Release \*\// { print $1; exit }
    in_list && /};/ { in_list = 0 }
  ' "$PBXPROJ"
)

if [[ -z "${TARGET_RELEASE_CONFIG_ID:-}" ]]; then
  echo "ERROR: Could not resolve Release build configuration ID for target \"Food App\"." >&2
  exit 1
fi

extract_release_value() {
  local key="$1"
  awk -v config_id="$TARGET_RELEASE_CONFIG_ID" -v key="$key" '
    $0 ~ config_id" /\\* Release \\*/ = \\{" { in_block = 1; next }
    in_block && $0 ~ "^[[:space:]]*" key " = " {
      line = $0
      sub("^[[:space:]]*" key " = \"?", "", line)
      sub("\"?;[[:space:]]*$", "", line)
      print line
      exit
    }
    in_block && $0 ~ /^[[:space:]]*name = Release;/ { in_block = 0 }
  ' "$PBXPROJ"
}

RELEASE_API_BASE_URL="$(extract_release_value API_BASE_URL)"
RELEASE_API_ENV="$(extract_release_value API_ENV)"
RELEASE_CODE_SIGN_STYLE="$(extract_release_value CODE_SIGN_STYLE)"
RELEASE_DEVELOPMENT_TEAM="$(extract_release_value DEVELOPMENT_TEAM)"
RELEASE_BUILD_NUMBER="$(extract_release_value CURRENT_PROJECT_VERSION)"

if [[ -z "$RELEASE_API_BASE_URL" ]]; then
  echo "ERROR: Release API_BASE_URL is empty." >&2
  exit 1
fi
if [[ ! "$RELEASE_API_BASE_URL" =~ ^https:// ]]; then
  echo "ERROR: Release API_BASE_URL must use HTTPS. Current value: $RELEASE_API_BASE_URL" >&2
  exit 1
fi
if [[ "$RELEASE_API_BASE_URL" =~ example|localhost|127\.0\.0\.1|0\.0\.0\.0 ]]; then
  echo "ERROR: Release API_BASE_URL still looks like a placeholder/dev endpoint: $RELEASE_API_BASE_URL" >&2
  exit 1
fi
if [[ "$RELEASE_API_BASE_URL" =~ ^https://(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.) ]]; then
  echo "ERROR: Release API_BASE_URL cannot be a private LAN IP for TestFlight: $RELEASE_API_BASE_URL" >&2
  exit 1
fi

if [[ "$RELEASE_API_ENV" != "production" ]]; then
  echo "ERROR: Release API_ENV must be production. Current value: $RELEASE_API_ENV" >&2
  exit 1
fi

if [[ "$RELEASE_CODE_SIGN_STYLE" != "Automatic" ]]; then
  echo "ERROR: Release CODE_SIGN_STYLE must be Automatic. Current value: $RELEASE_CODE_SIGN_STYLE" >&2
  exit 1
fi

if [[ -z "$RELEASE_DEVELOPMENT_TEAM" ]]; then
  echo "ERROR: Release DEVELOPMENT_TEAM is empty." >&2
  exit 1
fi

if [[ ! "$RELEASE_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Release CURRENT_PROJECT_VERSION must be numeric. Current value: $RELEASE_BUILD_NUMBER" >&2
  exit 1
fi

echo "Release config check passed."
echo "  API_BASE_URL: $RELEASE_API_BASE_URL"
echo "  API_ENV: $RELEASE_API_ENV"
echo "  CODE_SIGN_STYLE: $RELEASE_CODE_SIGN_STYLE"
echo "  DEVELOPMENT_TEAM: $RELEASE_DEVELOPMENT_TEAM"
echo "  CURRENT_PROJECT_VERSION: $RELEASE_BUILD_NUMBER"
