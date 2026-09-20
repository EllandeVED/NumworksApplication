#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $(basename "$0") <ref>" >&2
  echo "  ref: Epsilon tag, branch, commit, or 'latest'" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUMWORKS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${NUMWORKS_DIR}/Vendor/EpsilonSource"
REF="$1"

if [ "${REF}" = "latest" ]; then
  REF="$("${SCRIPT_DIR}/latest-epsilon-tag.sh")"
  echo "Latest Epsilon version branch: ${REF}"
fi

"${SCRIPT_DIR}/fetch-epsilon.sh" "${REF}"
"${SCRIPT_DIR}/adapt-epsilon.sh"

RESOLVED="$(git -C "${VENDOR_DIR}" rev-parse HEAD)"
echo "Prepared Epsilon at commit: ${RESOLVED}"
echo "Adapted with: ${SCRIPT_DIR}/adapt-epsilon.py"
