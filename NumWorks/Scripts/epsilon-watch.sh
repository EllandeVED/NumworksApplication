#!/usr/bin/env bash
# CI helper: if upstream Epsilon has a newer version tag than our pin, prepare + build it.
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
[[ -n "$latest" ]] || { echo "Could not resolve latest Epsilon tag"; exit 1; }

pinned=""
if [[ -f "$PIN_FILE" ]]; then
  pinned="$(tr -d '[:space:]' < "$PIN_FILE")"
fi

echo "Pinned: ${pinned:-"(none)"}"
echo "Latest: $latest"

if [[ -n "$pinned" && "$pinned" == "$latest" ]]; then
  echo "Already on latest Epsilon tag — nothing to do."
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "changed=false" >> "$GITHUB_OUTPUT"
    echo "ref=$latest" >> "$GITHUB_OUTPUT"
  fi
  exit 0
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
    echo "$latest" > "$PIN_FILE"
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
