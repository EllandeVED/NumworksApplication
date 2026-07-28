#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $(basename "$0") <ref>" >&2
  echo "  ref: Epsilon tag, branch, or commit" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUMWORKS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${NUMWORKS_DIR}/Vendor/EpsilonSource"
EPSILON_REPO="${EPSILON_REPO:-https://github.com/numworks/epsilon.git}"
REF="$1"

if [ ! -d "${VENDOR_DIR}/.git" ]; then
  echo "Cloning Epsilon into ${VENDOR_DIR}"
  git clone "${EPSILON_REPO}" "${VENDOR_DIR}"
fi

echo "Fetching from ${EPSILON_REPO}"
git -C "${VENDOR_DIR}" fetch --tags origin

echo "Resetting and cleaning ${VENDOR_DIR}"
git -C "${VENDOR_DIR}" reset --hard
# Keep the Python virtualenv used by Epsilon's code generators (see
# build-epsilon-lib.sh, which creates it on demand).
git -C "${VENDOR_DIR}" clean -fdx -e .venv

echo "Checking out ${REF}"
git -C "${VENDOR_DIR}" checkout "${REF}"

RESOLVED="$(git -C "${VENDOR_DIR}" rev-parse HEAD)"
echo "Epsilon resolved commit: ${RESOLVED}"
