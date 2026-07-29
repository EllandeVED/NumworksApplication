#!/usr/bin/env bash
# release.sh — one-shot NumWorks Sparkle release
#
# Builds the app, collects release notes, signs the update with Sparkle
# (Keychain EdDSA key), and publishes zip + appcast to GitHub Pages.
#
# Usage:
#   ./NumWorks/Scripts/release.sh <marketing-version> [options]
#
# Examples:
#   ./NumWorks/Scripts/release.sh 2.0.5
#   ./NumWorks/Scripts/release.sh 2.0.5 --epsilon 23.2.3
#   ./NumWorks/Scripts/release.sh 2.0.5 --epsilon latest
#   ./NumWorks/Scripts/release.sh 2.0.5 --build 12
#   ./NumWorks/Scripts/release.sh 2.0.5 --notes-file ./notes.md
#   ./NumWorks/Scripts/release.sh 2.0.5 --skip-publish
#
# Options:
#   --epsilon <ref>      prepare-epsilon.sh <ref> then rebuild libepsilon.a
#   --epsilon latest     same, using the newest numworks/epsilon version tag
#   --build <n>          CFBundleVersion (default: current + 1)
#   --notes-file <path>  Use this Markdown file as release notes
#   --configuration <c>  Debug or Release (default: Release)
#   --skip-publish       Build + sign only; do not push to gh-pages
#   -h, --help           Show help
#
# Requires: Xcode, Keychain Sparkle private key (generate_keys), git access to
# EllandeVED/NumworksApplication (gh-pages branch).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$ROOT/NumWorks.xcodeproj"
SCHEME="NumWorks"
PBXPROJ="$ROOT/NumWorks.xcodeproj/project.pbxproj"
FEED_PREFIX="https://ellandeved.github.io/NumworksApplication/"
GITHUB_REPO="EllandeVED/NumworksApplication"
PAGES_BRANCH="gh-pages"
DERIVED="${TMPDIR:-/tmp}/NumWorks-release-derived"
RELEASES="$ROOT/build/releases"
CONFIGURATION="Release"
SKIP_PUBLISH=0
NOTES_FILE=""
BUILD_NUMBER=""
VERSION=""
EPSILON_REF=""

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --build) BUILD_NUMBER="${2:?}"; shift 2 ;;
    --notes-file) NOTES_FILE="${2:?}"; shift 2 ;;
    --configuration) CONFIGURATION="${2:?}"; shift 2 ;;
    --epsilon)
      EPSILON_REF="${2:?}"
      shift 2
      ;;
    --skip-publish) SKIP_PUBLISH=1; shift ;;
    -*) die "unknown option: $1" ;;
    *)
      if [[ -z "$VERSION" ]]; then
        VERSION="$1"
        shift
      else
        die "unexpected argument: $1"
      fi
      ;;
  esac
done

[[ -n "$VERSION" ]] || die "marketing version required (e.g. 2.0.5). Try --help."
[[ -f "$PBXPROJ" ]] || die "project not found at $PBXPROJ"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "invalid version: $VERSION"

# --- Resolve current build number (NumWorks app target only) -----------------

current_build="$(
  python3 - <<'PY' "$PBXPROJ"
import re, sys
text = open(sys.argv[1]).read()
blocks = re.findall(
    r"buildSettings = \{[^{}]*COMBINE_HIDPI_IMAGES = YES;[^{}]*\};",
    text,
    flags=re.S,
)
if not blocks:
    raise SystemExit("could not find NumWorks app buildSettings")
m = re.search(r"CURRENT_PROJECT_VERSION = (\d+);", blocks[0])
print(m.group(1) if m else "0")
PY
)"

if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$((current_build + 1))"
fi

info "Version $VERSION (build $BUILD_NUMBER)  [was build $current_build]"

# --- Bump versions in project.pbxproj ----------------------------------------

info "Updating MARKETING_VERSION / CURRENT_PROJECT_VERSION"
python3 - <<PY
from pathlib import Path
import re
path = Path("$PBXPROJ")
text = path.read_text()

def bump(m):
    block = m.group(0)
    block = re.sub(
        r"CURRENT_PROJECT_VERSION = \d+;",
        "CURRENT_PROJECT_VERSION = $BUILD_NUMBER;",
        block,
    )
    block = re.sub(
        r"MARKETING_VERSION = [^;]+;",
        "MARKETING_VERSION = $VERSION;",
        block,
    )
    return block

new = re.sub(
    r"buildSettings = \{[^{}]*COMBINE_HIDPI_IMAGES = YES;[^{}]*\};",
    bump,
    text,
    flags=re.S,
)
path.write_text(new)
print("pbxproj updated")
PY

# --- Release notes -----------------------------------------------------------

mkdir -p "$RELEASES"
NOTES_OUT="$RELEASES/NumWorks-${VERSION}.md"

if [[ -n "$NOTES_FILE" ]]; then
  [[ -f "$NOTES_FILE" ]] || die "notes file not found: $NOTES_FILE"
  cp "$NOTES_FILE" "$NOTES_OUT"
else
  TMP_NOTES="$(mktemp -t numworks-notes)"
  cat > "$TMP_NOTES" <<EOF
## What's New in ${VERSION}

-
-
-
EOF
  EDITOR_CMD="${EDITOR:-${VISUAL:-nano}}"
  info "Opening editor for release notes ($EDITOR_CMD)"
  echo "    Save and quit when finished. First lines are a template."
  "$EDITOR_CMD" "$TMP_NOTES"
  # Drop trailing blank lines only; keep user content
  if ! grep -q '[^[:space:]]' "$TMP_NOTES"; then
    rm -f "$TMP_NOTES"
    die "release notes are empty"
  fi
  cp "$TMP_NOTES" "$NOTES_OUT"
  rm -f "$TMP_NOTES"
fi

info "Release notes:"
sed 's/^/    /' "$NOTES_OUT"
echo

# --- Optional Epsilon upgrade ------------------------------------------------

if [[ -n "$EPSILON_REF" ]]; then
  if [[ "$EPSILON_REF" == "latest" ]]; then
    info "Resolving latest numworks/epsilon version tag"
    EPSILON_REF="$("$ROOT/NumWorks/Scripts/latest-epsilon-tag.sh")"
    [[ -n "$EPSILON_REF" ]] || die "could not resolve latest Epsilon tag"
  fi
  info "Preparing Epsilon ${EPSILON_REF}"
  "$ROOT/NumWorks/Scripts/prepare-epsilon.sh" "$EPSILON_REF"
  info "Building libepsilon.a"
  ARCHS="${ARCHS:-$(uname -m)}" "$ROOT/NumWorks/Scripts/build-epsilon-lib.sh"
  # Record pin for CI / humans
  mkdir -p "$ROOT/NumWorks/Support"
  echo "$EPSILON_REF" > "$ROOT/NumWorks/Support/epsilon-pinned-ref.txt"
  info "Pinned Epsilon ref → NumWorks/Support/epsilon-pinned-ref.txt"
fi

# --- Build -------------------------------------------------------------------

info "Building $SCHEME ($CONFIGURATION)"
rm -rf "$DERIVED"
mkdir -p "$ROOT/build"

# Sparkle SPM artifacts sometimes carry FinderInfo xattrs that break Release codesign.
while IFS= read -r sparkle_root; do
  info "Stripping xattrs under $sparkle_root"
  xattr -cr "$sparkle_root" 2>/dev/null || true
done < <(find "$HOME/Library/Developer/Xcode/DerivedData" -type d -path '*/artifacts/sparkle/Sparkle' 2>/dev/null | head -5)

set +e
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination "platform=macOS" \
  build \
  >"$ROOT/build/xcodebuild.log" 2>&1
BUILD_STATUS=$?
set -e
tail -20 "$ROOT/build/xcodebuild.log"
if [[ "$BUILD_STATUS" -ne 0 ]] || ! grep -q '\*\* BUILD SUCCEEDED \*\*' "$ROOT/build/xcodebuild.log"; then
  die "build failed — see $ROOT/build/xcodebuild.log"
fi

APP="$DERIVED/Build/Products/${CONFIGURATION}/NumWorks.app"
[[ -d "$APP" ]] || die "app not found at $APP"

got_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
got_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$got_version" == "$VERSION" ]] || die "built marketing version is $got_version, expected $VERSION"
[[ "$got_build" == "$BUILD_NUMBER" ]] || die "built build number is $got_build, expected $BUILD_NUMBER"

info "Built NumWorks $got_version ($got_build)"

# --- Zip ---------------------------------------------------------------------

ZIP="$RELEASES/NumWorks-${VERSION}.zip"
rm -f "$ZIP"
info "Zipping → $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# --- Sparkle generate_appcast ------------------------------------------------

SPARKLE_BIN="$(
  find "$DERIVED" ~/Library/Developer/Xcode/DerivedData \
    -path '*/Sparkle/bin/generate_appcast' \
    -type f 2>/dev/null | head -1
)"
[[ -n "$SPARKLE_BIN" && -x "$SPARKLE_BIN" ]] || die "generate_appcast not found (build Sparkle via xcodebuild first)"

info "Publishing via publish-sparkle.sh"
PUBLISH_ARGS=(
  --version "$VERSION"
  --zip "$ZIP"
  --notes "$NOTES_OUT"
  --generate-appcast "$SPARKLE_BIN"
)
if [[ "$SKIP_PUBLISH" -eq 1 ]]; then
  PUBLISH_ARGS+=(--skip-publish)
else
  # GitHub Release must exist (public) before Sparkle points at its download URL.
  if command -v gh >/dev/null 2>&1; then
    info "Creating GitHub Release ${VERSION}"
    if gh release view "$VERSION" >/dev/null 2>&1; then
      gh release upload "$VERSION" "$ZIP" --clobber 2>/dev/null || true
      gh release edit "$VERSION" --title "$VERSION" --notes-file "$NOTES_OUT"
    else
      gh release create "$VERSION" --title "$VERSION" --notes-file "$NOTES_OUT" "$ZIP"
    fi
  else
    info "gh not found — Sparkle will still publish; Widgy counts need a GitHub Release asset"
  fi
fi
"$ROOT/NumWorks/Scripts/publish-sparkle.sh" "${PUBLISH_ARGS[@]}"

if [[ "$SKIP_PUBLISH" -eq 1 ]]; then
  info "Skipping publish (--skip-publish). Artifacts in $RELEASES"
  exit 0
fi

info "Waiting for GitHub Pages…"
for i in $(seq 1 12); do
  if curl -fsSL "${FEED_PREFIX}appcast.xml" 2>/dev/null | grep -q "<title>${VERSION}</title>"; then
    echo
    info "Live: ${FEED_PREFIX}appcast.xml"
    info "Zip:  ${FEED_PREFIX}NumWorks-${VERSION}.zip"
    echo
    echo "Done. Installed apps in /Applications can Check for Updates to ${VERSION}."
    exit 0
  fi
  sleep 5
done

echo
info "Pushed, but Pages has not shown ${VERSION} yet — check again in a minute:"
echo "  ${FEED_PREFIX}appcast.xml"
exit 0
