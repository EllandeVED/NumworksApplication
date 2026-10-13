#!/usr/bin/env bash
# Write NumWorks/Support/epsilon-pinned-ref.txt as:
#   line 1: git ref (version-N branch)
#   line 2: APP_VERSION (optional; omitted if unknown)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PIN_FILE="${3:-$ROOT/NumWorks/Support/epsilon-pinned-ref.txt}"
REF="${1:?}"
APP_VERSION="${2:-}"

mkdir -p "$(dirname "$PIN_FILE")"
if [[ -n "$APP_VERSION" ]]; then
  printf '%s\n%s\n' "$REF" "$APP_VERSION" > "$PIN_FILE"
else
  printf '%s\n' "$REF" > "$PIN_FILE"
fi
