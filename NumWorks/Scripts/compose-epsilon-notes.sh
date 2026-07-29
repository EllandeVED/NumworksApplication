#!/usr/bin/env bash
# Compose Sparkle / GitHub release notes for an automatic Epsilon-driven update.
#
# Usage:
#   ./NumWorks/Scripts/compose-epsilon-notes.sh <epsilon-tag> [output.md]
set -euo pipefail

TAG="${1:?epsilon tag required}"
OUT="${2:-}"

notes="$(cat <<EOF
This was an automatic update following a new release of the [Epsilon](https://github.com/numworks/epsilon) calculator software (version **${TAG}**).

For upstream changes, see the Epsilon release notes:
https://github.com/numworks/epsilon/releases/tag/${TAG}
EOF
)"

if [[ -n "$OUT" ]]; then
  printf '%s\n' "$notes" > "$OUT"
  echo "Wrote $OUT" >&2
else
  printf '%s\n' "$notes"
fi
