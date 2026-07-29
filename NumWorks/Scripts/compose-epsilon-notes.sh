#!/usr/bin/env bash
# Compose Sparkle release notes for an Epsilon-driven NumWorks update.
#
# Usage:
#   ./NumWorks/Scripts/compose-epsilon-notes.sh <epsilon-tag> [output.md]
#
# Writes Markdown:
#   ## New Epsilon version
#   NumWorks now embeds Epsilon <tag>.
#   ## Epsilon <tag> release notes
#   <upstream body from GitHub, or a link if unavailable>
set -euo pipefail

TAG="${1:?epsilon tag required}"
OUT="${2:-}"

body=""
auth_headers=(-H "Accept: application/vnd.github+json")
if [[ -n "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ]]; then
  auth_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN:-$GH_TOKEN}")
fi

# Prefer GitHub Releases API (official notes when the tag has a release).
api_url="https://api.github.com/repos/numworks/epsilon/releases/tags/${TAG}"
if body_json="$(curl -fsSL "${auth_headers[@]}" "$api_url" 2>/dev/null)"; then
  body="$(
    python3 - <<'PY' "$body_json"
import json, sys
data = json.loads(sys.argv[1])
print((data.get("body") or "").strip())
PY
  )"
fi

if [[ -z "$body" ]]; then
  # Fallback: annotated tag message via git (needs network clone — skip if heavy).
  # Use compare / releases page link instead.
  body="Official notes were not published as a GitHub Release for this tag.

See: https://github.com/numworks/epsilon/releases/tag/${TAG}
or the changelog: https://github.com/numworks/epsilon/releases"
fi

notes="$(cat <<EOF
## New Epsilon version

NumWorks now embeds **Epsilon ${TAG}**.

## Epsilon ${TAG} release notes

${body}
EOF
)"

if [[ -n "$OUT" ]]; then
  printf '%s\n' "$notes" > "$OUT"
  echo "Wrote $OUT" >&2
else
  printf '%s\n' "$notes"
fi
