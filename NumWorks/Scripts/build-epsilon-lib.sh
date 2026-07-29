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

if ! grep -q "EpsilonBridge" "${VENDOR_DIR}/ion/src/simulator/macos/window.mm" 2>/dev/null \
  && ! grep -q "EpsilonBridge" "${VENDOR_DIR}/ion/src/simulator/mac/window.mm" 2>/dev/null; then
  # Fall back: any adapted window.mm under the simulator tree.
  if ! grep -Rql "EpsilonBridge" "${VENDOR_DIR}/ion/src/simulator" --include='window.mm' 2>/dev/null; then
    echo "error: Epsilon has not been adapted for NumWorks." >&2
    echo "error: Run NumWorks/Scripts/prepare-epsilon.sh <ref> first." >&2
    exit 1
  fi
fi

if ! grep -q "NUMWORKS_INTEGRATION" "${VENDOR_DIR}/build/targets.simulator.macos.mak" 2>/dev/null \
  && ! grep -Rql "NUMWORKS_INTEGRATION" "${VENDOR_DIR}/build" --include='targets.simulator*mac*.mak' 2>/dev/null; then
  echo "error: Epsilon macOS makefile is missing the NumWorks libepsilon.a rules." >&2
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
  make -C "${VENDOR_DIR}" \
    PLATFORM=simulator TARGET=macos DEBUG=0 ARCH="${arch}" \
    NUMWORKS_INTEGRATION_DIR="${INTEGRATION_DIR}" \
    -j"${JOBS}" libepsilon.a
  LIB_PATHS+=("${VENDOR_DIR}/output/release/simulator/macos/${arch}/libepsilon.a")
done

mkdir -p "$(dirname "${OUTPUT_LIB}")"
if [ "${#LIB_PATHS[@]}" -eq 1 ]; then
  cp "${LIB_PATHS[0]}" "${OUTPUT_LIB}"
else
  lipo -create "${LIB_PATHS[@]}" -output "${OUTPUT_LIB}"
fi
echo "Built ${OUTPUT_LIB} for: ${ARCHS}"
