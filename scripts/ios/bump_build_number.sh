#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
PBXPROJ="$REPO_ROOT/Food App.xcodeproj/project.pbxproj"

if [[ ! -f "$PBXPROJ" ]]; then
  echo "ERROR: Could not find project file at $PBXPROJ" >&2
  exit 1
fi

CURRENT_VALUES_RAW=$(grep -E "CURRENT_PROJECT_VERSION = [0-9]+;" "$PBXPROJ" | sed -E 's/.*= ([0-9]+);/\1/')
if [[ -z "${CURRENT_VALUES_RAW:-}" ]]; then
  echo "ERROR: Could not find CURRENT_PROJECT_VERSION entries." >&2
  exit 1
fi

CURRENT_MAX=$(printf '%s\n' "$CURRENT_VALUES_RAW" | sort -n | tail -n 1)
UNIQUE_COUNT=$(printf '%s\n' "$CURRENT_VALUES_RAW" | sort -n | uniq | wc -l | tr -d '[:space:]')

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [explicit-build-number]" >&2
  exit 1
fi

if [[ $# -eq 1 ]]; then
  NEW_BUILD="$1"
  if [[ ! "$NEW_BUILD" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Explicit build number must be numeric." >&2
    exit 1
  fi
else
  NEW_BUILD=$((CURRENT_MAX + 1))
fi

perl -0pi -e "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"

if [[ "$UNIQUE_COUNT" != "1" ]]; then
  echo "Warning: project had mismatched build numbers before bump; normalized all to $NEW_BUILD." >&2
fi

echo "Build number updated: $CURRENT_MAX -> $NEW_BUILD"
