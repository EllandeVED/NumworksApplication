#!/usr/bin/env bash
# Compose Sparkle / GitHub release notes for an automatic Epsilon-driven update.
#
# Usage:
#   ./NumWorks/Scripts/compose-epsilon-notes.sh <epsilon-ref> [output.md]
set -euo pipefail

REF="${1:?epsilon ref required}"
OUT="${2:-}"

notes="$(cat <<EOF
This was an automatic update following a new version of the [Epsilon](https://github.com/numworks/epsilon) calculator software (**${REF}**).

For upstream changes, see:
https://github.com/numworks/epsilon/tree/${REF}
EOF
)"

if [[ -n "$OUT" ]]; then
  printf '%s\n' "$notes" > "$OUT"
  echo "Wrote $OUT" >&2
else
  printf '%s\n' "$notes"
fi
