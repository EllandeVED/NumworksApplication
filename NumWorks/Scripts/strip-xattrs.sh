#!/usr/bin/env bash
# Strip Finder/resource-fork extended attributes from the built .app.
# Without this, Release codesign fails with:
#   "resource fork, Finder information, or similar detritus not allowed"
#
# Finder can re-stamp com.apple.FinderInfo on folders under Desktop/Documents;
# we strip repeatedly and clear the bundle root explicitly.
set -euo pipefail

APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
if [[ ! -d "$APP_PATH" ]]; then
  exit 0
fi

strip_once() {
  # Bundle root first — this is what codesign often complains about.
  xattr -c "$APP_PATH" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$APP_PATH" 2>/dev/null || true
  xattr -d com.apple.ResourceFork "$APP_PATH" 2>/dev/null || true
  xattr -cr "$APP_PATH" 2>/dev/null || true
  # Some tools only clear leaf files via find.
  find "$APP_PATH" -exec xattr -c {} + 2>/dev/null || true
  # AppleDouble / resource-fork sidecars
  find "$APP_PATH" -name '._*' -delete 2>/dev/null || true
  find "$APP_PATH" -name '.DS_Store' -delete 2>/dev/null || true
  dot_clean -m "$APP_PATH" 2>/dev/null || true
}

strip_once
strip_once

if xattr -l "$APP_PATH" 2>/dev/null | grep -q 'com.apple.FinderInfo'; then
  echo "warning: com.apple.FinderInfo still present on ${APP_PATH}" >&2
  xattr -l "$APP_PATH" >&2 || true
fi

echo "Stripped extended attributes from ${APP_PATH}"
