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
#                        (appends a Full Changelog compare link if missing)
#   --configuration <c>  Debug or Release (default: Release)
#   --skip-publish       Dry run: build + Sparkle-sign locally only; restore
#                        project files afterward (no GitHub Release, no gh-pages)
#
# Artifacts (zip, notes, local appcast):
#   Dry run (--skip-publish): ~/Downloads/NumWorks
#   Real publish:             ~/Library/Caches/NumWorks/releases
# Override either with NUMWORKS_RELEASES_DIR.
#
# On a real publish (without --skip-publish), also creates/updates a GitHub
# Release whose tag and title are exactly the marketing version (e.g. 2.0.7).
#
# Requires: Xcode, Keychain Sparkle private key (generate_keys), git access to
# EllandeVED/NumworksApplication (gh-pages branch), and `gh` for GitHub Releases.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$ROOT/NumWorks.xcodeproj"
SCHEME="NumWorks"
PBXPROJ="$ROOT/NumWorks.xcodeproj/project.pbxproj"
FEED_PREFIX="https://ellandeved.github.io/NumworksApplication/"
GITHUB_REPO="EllandeVED/NumworksApplication"
PAGES_BRANCH="gh-pages"
DERIVED="${TMPDIR:-/tmp}/NumWorks-release-derived"
CONFIGURATION="Release"
SKIP_PUBLISH=0
NOTES_FILE=""
BUILD_NUMBER=""
VERSION=""
EPSILON_REF=""

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# --- Progress bar (hashtags) -------------------------------------------------
PROGRESS_WIDTH=24
PROGRESS_STEP=0
PROGRESS_TOTAL=1
PROGRESS_STARTED_AT=0

progress_init() {
  PROGRESS_TOTAL="$1"
  PROGRESS_STEP=0
  PROGRESS_STARTED_AT=$SECONDS
  echo
  echo "Release progress (${PROGRESS_TOTAL} steps)"
}

progress() {
  local label="${1:-}"
  PROGRESS_STEP=$((PROGRESS_STEP + 1))
  if (( PROGRESS_STEP > PROGRESS_TOTAL )); then
    PROGRESS_STEP=$PROGRESS_TOTAL
  fi
  local filled=$(( PROGRESS_STEP * PROGRESS_WIDTH / PROGRESS_TOTAL ))
  local empty=$(( PROGRESS_WIDTH - filled ))
  local bar
  bar="$(printf '%*s' "$filled" '' | tr ' ' '#')"
  bar+="$(printf '%*s' "$empty" '' | tr ' ' '-')"
  local elapsed=$((SECONDS - PROGRESS_STARTED_AT))
  printf '[%s] %d/%d  %s  (%ds)\n' "$bar" "$PROGRESS_STEP" "$PROGRESS_TOTAL" "$label" "$elapsed"
}

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

# Outside the git work tree so zips/appcasts cannot be committed by accident.
if [[ -n "${NUMWORKS_RELEASES_DIR:-}" ]]; then
  RELEASES="$NUMWORKS_RELEASES_DIR"
elif [[ "$SKIP_PUBLISH" -eq 1 ]]; then
  RELEASES="$HOME/Downloads/NumWorks"
else
  RELEASES="$HOME/Library/Caches/NumWorks/releases"
fi
export NUMWORKS_RELEASES_DIR="$RELEASES"

PIN_FILE="$ROOT/NumWorks/Support/epsilon-pinned-ref.txt"
DRY_RUN_PBX_BACKUP=""
DRY_RUN_PIN_BACKUP=""
DRY_RUN_PIN_EXISTED=0

restore_dry_run_state() {
  [[ "$SKIP_PUBLISH" -eq 1 ]] || return 0
  info "Dry run: restoring project so a later publish is unchanged by this run"
  if [[ -n "$DRY_RUN_PBX_BACKUP" && -f "$DRY_RUN_PBX_BACKUP" ]]; then
    cp "$DRY_RUN_PBX_BACKUP" "$PBXPROJ"
  fi
  if [[ "$DRY_RUN_PIN_EXISTED" -eq 1 ]]; then
    if [[ -n "$DRY_RUN_PIN_BACKUP" && -f "$DRY_RUN_PIN_BACKUP" ]]; then
      mkdir -p "$(dirname "$PIN_FILE")"
      cp "$DRY_RUN_PIN_BACKUP" "$PIN_FILE"
    fi
  else
    rm -f "$PIN_FILE"
  fi
  rm -f "$DRY_RUN_PBX_BACKUP" "$DRY_RUN_PIN_BACKUP"
}

if [[ "$SKIP_PUBLISH" -eq 1 ]]; then
  info "Dry run (--skip-publish): will not create a GitHub Release or push gh-pages"
  DRY_RUN_PBX_BACKUP="$(mktemp -t numworks-pbx)"
  cp "$PBXPROJ" "$DRY_RUN_PBX_BACKUP"
  if [[ -f "$PIN_FILE" ]]; then
    DRY_RUN_PIN_EXISTED=1
    DRY_RUN_PIN_BACKUP="$(mktemp -t numworks-pin)"
    cp "$PIN_FILE" "$DRY_RUN_PIN_BACKUP"
  fi
  trap restore_dry_run_state EXIT
fi

# Steps: bump, notes, [epsilon], build, zip, sign/publish, [wait pages]
PROGRESS_TOTAL=5
[[ -n "$EPSILON_REF" ]] && PROGRESS_TOTAL=$((PROGRESS_TOTAL + 1))
[[ "$SKIP_PUBLISH" -eq 0 ]] && PROGRESS_TOTAL=$((PROGRESS_TOTAL + 1))
progress_init "$PROGRESS_TOTAL"

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

progress "Bump version → ${VERSION} (${BUILD_NUMBER})"
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

progress "Release notes"
mkdir -p "$RELEASES"
NOTES_OUT="$RELEASES/NumWorks-${VERSION}.md"

# Previous published tag → GitHub compare / “Full Changelog” link (same style as
# GitHub’s auto-generated release notes).
resolve_previous_release_tag() {
  local prev=""
  if command -v gh >/dev/null 2>&1; then
    prev="$(
      gh release list -R "$GITHUB_REPO" --limit 30 --json tagName,isDraft,isPrerelease \
        --jq "[.[] | select(.isDraft == false and .isPrerelease == false) | .tagName] | map(select(. != \"${VERSION}\")) | .[0] // empty" \
        2>/dev/null || true
    )"
  fi
  if [[ -z "$prev" ]]; then
    prev="$(
      git -C "$ROOT" tag -l '[0-9]*' \
        | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' \
        | grep -vxF "$VERSION" \
        | sort -t . -k1,1n -k2,2n -k3,3n \
        | tail -1 || true
    )"
  fi
  printf '%s' "$prev"
}

PREV_TAG="$(resolve_previous_release_tag)"
if [[ -n "$PREV_TAG" ]]; then
  CHANGELOG_LINK="**Full Changelog**: https://github.com/${GITHUB_REPO}/compare/${PREV_TAG}...${VERSION}"
  info "Changelog range: ${PREV_TAG}...${VERSION}"
else
  CHANGELOG_LINK="**Commits**: https://github.com/${GITHUB_REPO}/commits/main"
  info "No previous release tag found — using commits link"
fi

# Optional auto bullets from commits since the previous tag (editable in the editor).
AUTO_BULLETS=""
if [[ -n "$PREV_TAG" ]] && git -C "$ROOT" rev-parse "$PREV_TAG" >/dev/null 2>&1; then
  AUTO_BULLETS="$(
    git -C "$ROOT" log "${PREV_TAG}..HEAD" --pretty=format:'- %s' --no-merges 2>/dev/null \
      | head -40 || true
  )"
fi
if [[ -z "${AUTO_BULLETS//[[:space:]]/}" ]]; then
  AUTO_BULLETS=$'-\n-\n-'
fi

append_changelog_link_if_missing() {
  local file="$1"
  if grep -Eqi '(Full Changelog|github\.com/.+/compare/|^\*\*Commits\*\*:)' "$file"; then
    return 0
  fi
  printf '\n%s\n' "$CHANGELOG_LINK" >> "$file"
}

if [[ -n "$NOTES_FILE" ]]; then
  [[ -f "$NOTES_FILE" ]] || die "notes file not found: $NOTES_FILE"
  cp "$NOTES_FILE" "$NOTES_OUT"
  append_changelog_link_if_missing "$NOTES_OUT"
else
  TMP_NOTES="$(mktemp -t numworks-notes)"
  cat > "$TMP_NOTES" <<EOF
## What's New in ${VERSION}

${AUTO_BULLETS}

${CHANGELOG_LINK}
EOF
  EDITOR_CMD="${EDITOR:-${VISUAL:-nano}}"
  info "Opening editor for release notes ($EDITOR_CMD)"
  echo "    Template includes auto commit bullets + a Full Changelog link."
  echo "    Edit freely, then save and quit."
  "$EDITOR_CMD" "$TMP_NOTES"
  if ! grep -q '[^[:space:]]' "$TMP_NOTES"; then
    rm -f "$TMP_NOTES"
    die "release notes are empty"
  fi
  append_changelog_link_if_missing "$TMP_NOTES"
  cp "$TMP_NOTES" "$NOTES_OUT"
  rm -f "$TMP_NOTES"
fi

info "Release notes:"
sed 's/^/    /' "$NOTES_OUT"
echo

# --- Optional Epsilon upgrade ------------------------------------------------

if [[ -n "$EPSILON_REF" ]]; then
  progress "Prepare & build Epsilon"
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

progress "Xcode build (${CONFIGURATION})"
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

progress "Zip app"
ZIP="$RELEASES/NumWorks-${VERSION}.zip"
rm -f "$ZIP"
info "Zipping → $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# --- Sparkle generate_appcast ------------------------------------------------

progress "Sign & publish (Sparkle)"
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
  # GitHub Release (tag + title = marketing version) must exist before Sparkle
  # enclosure URLs under …/releases/download/<version>/… work and get counted.
  command -v gh >/dev/null 2>&1 || die "gh is required to create GitHub Release ${VERSION}"
  info "Creating GitHub Release tag/title ${VERSION}"
  if gh release view "$VERSION" >/dev/null 2>&1; then
    gh release upload "$VERSION" "$ZIP" --clobber
    gh release edit "$VERSION" --title "$VERSION" --notes-file "$NOTES_OUT" --latest
  else
    gh release create "$VERSION" \
      --title "$VERSION" \
      --notes-file "$NOTES_OUT" \
      --latest \
      "$ZIP"
  fi
fi
"$ROOT/NumWorks/Scripts/publish-sparkle.sh" "${PUBLISH_ARGS[@]}"

if [[ "$SKIP_PUBLISH" -eq 1 ]]; then
  info "Dry-run artifacts kept in $RELEASES (zip / local appcast) for you to inspect"
  if [[ -f "$ZIP" ]]; then
    open -R "$ZIP"
  elif [[ -d "$RELEASES" ]]; then
    open "$RELEASES"
  fi
  echo
  echo "Done in $((SECONDS - PROGRESS_STARTED_AT))s (dry run — project files restored on exit)."
  # EXIT trap restores pbxproj + epsilon pin
  exit 0
fi

progress "Wait for GitHub Pages"
info "Waiting for GitHub Pages…"
for i in $(seq 1 12); do
  if curl -fsSL "${FEED_PREFIX}appcast.xml" 2>/dev/null | grep -q "<title>${VERSION}</title>"; then
    echo
    info "Live: ${FEED_PREFIX}appcast.xml"
    info "Zip:  ${FEED_PREFIX}NumWorks-${VERSION}.zip"
    echo
    echo "Done in $((SECONDS - PROGRESS_STARTED_AT))s. Installed apps in /Applications can Check for Updates to ${VERSION}."
    exit 0
  fi
  sleep 5
done

echo
info "Pushed, but Pages has not shown ${VERSION} yet — check again in a minute:"
echo "  ${FEED_PREFIX}appcast.xml"
echo "Elapsed: $((SECONDS - PROGRESS_STARTED_AT))s"
exit 0
