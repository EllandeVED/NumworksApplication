#!/usr/bin/env bash
# Print Epsilon's APP_VERSION (e.g. 26.1.0) for a git ref or local checkout.
#
# Usage:
#   ./NumWorks/Scripts/epsilon-app-version.sh version-26
#   ./NumWorks/Scripts/epsilon-app-version.sh --from-tree NumWorks/Vendor/EpsilonSource
#
# Exit 0 and print the version on success.
# Exit 1 on failure (caller should warn, not abort the workflow).
set -euo pipefail

EPSILON_REPO_RAW="${EPSILON_REPO_RAW:-https://raw.githubusercontent.com/numworks/epsilon}"

die() { echo "error: $*" >&2; exit 1; }

extract_from_makefile() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  # APP_VERSION := 26.1.0  (allow spaces around :=)
  sed -nE 's/^[[:space:]]*APP_VERSION[[:space:]]*:=[[:space:]]*([^[:space:]]+).*/\1/p' "$file" | head -1
}

if [[ "${1:-}" == "--from-tree" ]]; then
  root="${2:?}"
  for candidate in \
    "${root}/epsilon/Makefile" \
    "${root}/Makefile"
  do
    ver="$(extract_from_makefile "$candidate" || true)"
    if [[ -n "${ver:-}" ]]; then
      printf '%s\n' "$ver"
      exit 0
    fi
  done
  die "APP_VERSION not found under ${root}"
fi

REF="${1:?ref required (branch, tag, or commit)}"

# Prefer split-layout path (Epsilon 25+); fall back to repo-root Makefile.
for path in "epsilon/Makefile" "Makefile"; do
  url="${EPSILON_REPO_RAW}/${REF}/${path}"
  body="$(curl -fsSL --max-time 20 "$url" 2>/dev/null || true)"
  if [[ -n "$body" ]]; then
    ver="$(printf '%s\n' "$body" | sed -nE 's/^[[:space:]]*APP_VERSION[[:space:]]*:=[[:space:]]*([^[:space:]]+).*/\1/p' | head -1)"
    if [[ -n "${ver:-}" ]]; then
      printf '%s\n' "$ver"
      exit 0
    fi
  fi
done

die "could not read APP_VERSION for ref ${REF}"
