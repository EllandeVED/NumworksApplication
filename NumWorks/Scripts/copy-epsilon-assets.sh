#!/usr/bin/env bash
set -euo pipefail

# Run-script build phase of the NumWorks app target.
# Copies the image assets that the Epsilon simulator loads at runtime with
# [NSImage imageNamed:] into the app bundle's Resources folder.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUMWORKS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_DIR="${NUMWORKS_DIR}/Vendor/EpsilonSource/ion/src/simulator/assets"
DEST_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

mkdir -p "${DEST_DIR}"

for asset in horizontal_arrow.png vertical_arrow.png round.png small_squircle.png large_squircle.png; do
  cp "${ASSETS_DIR}/${asset}" "${DEST_DIR}/"
done

# background.jpg is generated from the webp source (upstream does this with
# ImageMagick; we use a small ImageIO script to avoid that dependency).
BACKGROUND_SOURCE="${ASSETS_DIR}/background-with-shadow.webp"
BACKGROUND_DEST="${DEST_DIR}/background.jpg"
if [ ! -f "${BACKGROUND_DEST}" ] || [ "${BACKGROUND_SOURCE}" -nt "${BACKGROUND_DEST}" ]; then
  xcrun -sdk macosx swift "${SCRIPT_DIR}/generate-background-asset.swift" \
    "${BACKGROUND_SOURCE}" "${BACKGROUND_DEST}"
fi

echo "Copied Epsilon assets to ${DEST_DIR}"
