#!/usr/bin/env bash
set -euo pipefail

# Invoked by the "EpsilonLib" external build target in Xcode.
# Builds the patched Epsilon simulator into a static library per architecture
# requested by Xcode, then merges them into a universal library at a stable
# path the app target links against:
#   Vendor/EpsilonSource/output/libepsilon.a

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUMWORKS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${NUMWORKS_DIR}/Vendor/EpsilonSource"
INTEGRATION_DIR="${NUMWORKS_DIR}/Integration"
OUTPUT_LIB="${VENDOR_DIR}/output/libepsilon.a"

# Homebrew tools (pkg-config, freetype) are not on Xcode's default PATH.
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

ACTION="${1:-build}"
if [ "${ACTION}" = "clean" ]; then
  echo "Cleaning Epsilon build output"
  rm -rf "${VENDOR_DIR}/output"
  exit 0
fi

if [ ! -d "${VENDOR_DIR}/.git" ]; then
  echo "error: Epsilon source not found at ${VENDOR_DIR}." >&2
  echo "error: Run NumWorks/Scripts/prepare-epsilon.sh <ref> first." >&2
  exit 1
fi

WINDOW_MM=""
for candidate in \
  "${VENDOR_DIR}/shared/ion/src/simulator/macos/window.mm" \
  "${VENDOR_DIR}/ion/src/simulator/macos/window.mm" \
  "${VENDOR_DIR}/ion/src/simulator/mac/window.mm"
do
  if [ -f "${candidate}" ]; then
    WINDOW_MM="${candidate}"
    break
  fi
done
if [ -z "${WINDOW_MM}" ] || ! grep -q "EpsilonBridge" "${WINDOW_MM}"; then
  echo "error: Epsilon has not been adapted for NumWorks." >&2
  echo "error: Run NumWorks/Scripts/prepare-epsilon.sh <ref> first." >&2
  exit 1
fi

MAKE_DIR="${VENDOR_DIR}"
if [ -d "${VENDOR_DIR}/epsilon" ] && [ -d "${VENDOR_DIR}/shared/ion" ]; then
  MAKE_DIR="${VENDOR_DIR}/epsilon"
fi

if ! grep -Rql "NUMWORKS_INTEGRATION" "${MAKE_DIR}/build" --include='*.mak' 2>/dev/null; then
  echo "error: Epsilon makefile is missing the NumWorks libepsilon.a rules." >&2
  echo "error: Run NumWorks/Scripts/prepare-epsilon.sh <ref> first." >&2
  exit 1
fi

# Epsilon's code generators need Python modules (lz4, ...). Upstream's
# convention is a .venv inside the source tree; the makefiles automatically
# use .venv/bin/python3 when that folder exists.
if [ ! -x "${VENDOR_DIR}/.venv/bin/python3" ]; then
  echo "Creating Python virtualenv for Epsilon code generators"
  python3 -m venv "${VENDOR_DIR}/.venv"
  "${VENDOR_DIR}/.venv/bin/pip3" install --quiet lz4 pyelftools pypng stringcase
fi

# ARCHS is exported by Xcode (e.g. "arm64" or "arm64 x86_64").
ARCHS="${ARCHS:-$(uname -m)}"
JOBS="$(sysctl -n hw.ncpu)"

LIB_PATHS=()
for arch in ${ARCHS}; do
  echo "Building Epsilon static library for ${arch}"
  make -C "${MAKE_DIR}" \
    PLATFORM=simulator TARGET=macos DEBUG=0 ARCH="${arch}" \
    PYTHON="${VENDOR_DIR}/.venv/bin/python3" \
    NUMWORKS_INTEGRATION_DIR="${INTEGRATION_DIR}" \
    -j"${JOBS}" libepsilon.a
  if [ "${MAKE_DIR}" != "${VENDOR_DIR}" ]; then
    LIB_PATHS+=("${MAKE_DIR}/output/release/macos/${arch}/libepsilon.a")
  else
    LIB_PATHS+=("${VENDOR_DIR}/output/release/simulator/macos/${arch}/libepsilon.a")
  fi
done

mkdir -p "$(dirname "${OUTPUT_LIB}")"
if [ "${#LIB_PATHS[@]}" -eq 1 ]; then
  cp "${LIB_PATHS[0]}" "${OUTPUT_LIB}"
else
  lipo -create "${LIB_PATHS[@]}" -output "${OUTPUT_LIB}"
fi
echo "Built ${OUTPUT_LIB} for: ${ARCHS}"
