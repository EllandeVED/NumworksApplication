#!/usr/bin/env bash
# CI helper: if upstream Epsilon has a newer version branch than our pin, prepare + build it.
# On failure, prints a filled agent prompt to $GITHUB_STEP_SUMMARY / stdout and exits 1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PIN_FILE="$ROOT/NumWorks/Support/epsilon-pinned-ref.txt"
PROMPT_TEMPLATE="$ROOT/NumWorks/Scripts/epsilon-agent-prompt.md"
LOG_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
LOG_FILE="${LOG_DIR}/epsilon-watch-build.log"
PROMPT_OUT="${LOG_DIR}/epsilon-agent-prompt-filled.md"

cd "$ROOT"
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

latest="$("$ROOT/NumWorks/Scripts/latest-epsilon-tag.sh")"
[[ -n "$latest" ]] || { echo "Could not resolve latest Epsilon version branch"; exit 1; }

pinned_branch=""
pinned_app=""
if [[ -f "$PIN_FILE" ]]; then
  pinned_branch="$(sed -n '1p' "$PIN_FILE" | tr -d '[:space:]')"
  pinned_app="$(sed -n '2p' "$PIN_FILE" | tr -d '[:space:]')"
fi

echo "Pinned branch: ${pinned_branch:-"(none)"}"
echo "Pinned APP_VERSION: ${pinned_app:-"(none)"}"
echo "Latest: $latest"

# First: version-* branch. Then: APP_VERSION from Makefile (warn-only on failure).
same_branch=false
if [[ -n "$pinned_branch" && "$pinned_branch" == "$latest" ]]; then
  same_branch=true
fi

if [[ "$same_branch" == "true" ]]; then
  set +e
  remote_app="$("$ROOT/NumWorks/Scripts/epsilon-app-version.sh" "$latest" 2>/tmp/epsilon-app-version.err)"
  app_status=$?
  set -e
  if [[ "$app_status" -ne 0 || -z "$remote_app" ]]; then
    echo "warning: could not read APP_VERSION for $latest; treating branch pin as current. $(tr '\n' ' ' </tmp/epsilon-app-version.err 2>/dev/null || true)"
    echo "Already on latest Epsilon version — nothing to do."
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      echo "changed=false" >> "$GITHUB_OUTPUT"
      echo "ref=$latest" >> "$GITHUB_OUTPUT"
    fi
    exit 0
  fi
  echo "Remote APP_VERSION: $remote_app"
  if [[ -n "$pinned_app" && "$pinned_app" == "$remote_app" ]]; then
    echo "Already on latest Epsilon version — nothing to do."
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      echo "changed=false" >> "$GITHUB_OUTPUT"
      echo "ref=$latest" >> "$GITHUB_OUTPUT"
    fi
    exit 0
  fi
  if [[ -z "$pinned_app" ]]; then
    echo "Pin lacks APP_VERSION; will build to record $remote_app."
  else
    echo "APP_VERSION changed $pinned_app → $remote_app on $latest."
  fi
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "changed=true" >> "$GITHUB_OUTPUT"
  echo "ref=$latest" >> "$GITHUB_OUTPUT"
fi

echo "==> Preparing Epsilon $latest"
set +e
"$ROOT/NumWorks/Scripts/prepare-epsilon.sh" "$latest" >"$LOG_FILE" 2>&1
prep_status=$?
set -e
if [[ "$prep_status" -ne 0 ]]; then
  echo "prepare-epsilon failed"
  tail -80 "$LOG_FILE" || true
else
  echo "==> Building libepsilon.a"
  set +e
  ARCHS="$(uname -m)" "$ROOT/NumWorks/Scripts/build-epsilon-lib.sh" >>"$LOG_FILE" 2>&1
  build_status=$?
  set -e
  if [[ "$build_status" -eq 0 ]]; then
    APP_VERSION=""
    set +e
    APP_VERSION="$("$ROOT/NumWorks/Scripts/epsilon-app-version.sh" --from-tree "$ROOT/NumWorks/Vendor/EpsilonSource" 2>/dev/null)"
    set -e
    if [[ -z "$APP_VERSION" ]]; then
      echo "warning: could not read APP_VERSION from EpsilonSource; pinning branch only"
    fi
    "$ROOT/NumWorks/Scripts/write-epsilon-pin.sh" "$latest" "$APP_VERSION"
    echo "SUCCESS: libepsilon.a built for $latest"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      echo "build=success" >> "$GITHUB_OUTPUT"
    fi
    exit 0
  fi
  echo "build-epsilon-lib failed"
  tail -80 "$LOG_FILE" || true
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "build=failure" >> "$GITHUB_OUTPUT"
fi

excerpt="$(tail -120 "$LOG_FILE" | sed 's/\r//g')"
# Escape for simple replacement
filled="$(
  python3 - <<'PY' "$PROMPT_TEMPLATE" "$latest" "$excerpt"
from pathlib import Path
import sys
template = Path(sys.argv[1]).read_text()
ref = sys.argv[2]
excerpt = sys.argv[3]
print(
    template.replace("{{EPSILON_REF}}", ref).replace("{{LOG_EXCERPT}}", excerpt)
)
PY
)"

prompt_out="$PROMPT_OUT"
printf '%s\n' "$filled" > "$prompt_out"
echo "$filled"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Epsilon watch failed for \`$latest\`"
    echo
    echo "Paste the following prompt into Cursor to fix the integration:"
    echo
    echo '```markdown'
    echo "$filled"
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi

echo "Filled agent prompt written to $prompt_out" >&2
exit 1
