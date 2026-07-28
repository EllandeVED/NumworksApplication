#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUMWORKS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${NUMWORKS_DIR}/Vendor/EpsilonSource"
PATCHES_DIR="${NUMWORKS_DIR}/Patches"

if [ ! -d "${VENDOR_DIR}/.git" ]; then
  echo "Epsilon source not found at ${VENDOR_DIR}" >&2
  echo "Run fetch-epsilon.sh first." >&2
  exit 1
fi

patch_count=0
while IFS= read -r patch; do
  patch_count=$((patch_count + 1))
  patch_name="$(basename "${patch}")"
  echo "Checking patch: ${patch_name}"
  if ! git -C "${VENDOR_DIR}" apply --check "${patch}"; then
    echo "Patch failed to apply: ${patch_name}" >&2
    exit 1
  fi

  echo "Applying patch: ${patch_name}"
  git -C "${VENDOR_DIR}" apply "${patch}"
done < <(find "${PATCHES_DIR}" -maxdepth 1 -name '*.patch' | sort)

if [ "${patch_count}" -eq 0 ]; then
  echo "No patches found in ${PATCHES_DIR}"
  exit 0
fi
