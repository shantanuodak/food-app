#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <https://your-production-api-domain>" >&2
  exit 1
fi

RELEASE_URL="$1"
if [[ ! "$RELEASE_URL" =~ ^https:// ]]; then
  echo "ERROR: Release URL must start with https:// (got: $RELEASE_URL)" >&2
  exit 1
fi
if [[ "$RELEASE_URL" =~ example|localhost|127\.0\.0\.1|0\.0\.0\.0 ]]; then
  echo "ERROR: Release URL looks like a placeholder/dev endpoint (got: $RELEASE_URL)" >&2
  exit 1
fi

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

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

awk -v config_id="$TARGET_RELEASE_CONFIG_ID" -v url="$RELEASE_URL" '
  $0 ~ config_id" /\\* Release \\*/ = \\{" { in_block = 1 }
  in_block && $0 ~ /^[[:space:]]*API_BASE_URL = / {
    sub(/API_BASE_URL = .*/, "API_BASE_URL = \"" url "\";")
    updated = 1
  }
  { print }
  in_block && $0 ~ /^[[:space:]]*name = Release;/ { in_block = 0 }
  END {
    if (!updated) {
      exit 7
    }
  }
' "$PBXPROJ" > "$TMP_FILE" || {
  echo "ERROR: Could not update API_BASE_URL in Release configuration." >&2
  exit 1
}

mv "$TMP_FILE" "$PBXPROJ"
trap - EXIT

"$SCRIPT_DIR/check_testflight_release_config.sh" >/dev/null
echo "Updated Release API_BASE_URL to: $RELEASE_URL"
