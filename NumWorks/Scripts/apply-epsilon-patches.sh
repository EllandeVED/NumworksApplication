#!/usr/bin/env bash
# Adapt the Epsilon checkout for NumWorks (resilient hooks, not line-exact patches).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUMWORKS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${NUMWORKS_DIR}/Vendor/EpsilonSource"

if [ ! -d "${VENDOR_DIR}/.git" ] && [ ! -d "${VENDOR_DIR}/ion" ]; then
  echo "Epsilon source not found at ${VENDOR_DIR}" >&2
  echo "Run fetch-epsilon.sh first." >&2
  exit 1
fi

python3 "${SCRIPT_DIR}/adapt-epsilon.py" "${VENDOR_DIR}"
