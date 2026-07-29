#!/usr/bin/env bash
# Build a testable NumWorks update for a new Epsilon tag (no Sparkle publish).
#
# Usage:
#   ./NumWorks/Scripts/build-epsilon-update.sh [epsilon-ref]
#   ./NumWorks/Scripts/build-epsilon-update.sh latest
#
# - Resolves / prepares Epsilon
# - Auto-bumps marketing patch + build number
# - Writes release notes via compose-epsilon-notes.sh
# - Builds Release .app (ad-hoc sign OK on CI) and zips it
# - Writes build/releases/release-meta.env for the ship job
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$ROOT/NumWorks.xcodeproj"
SCHEME="NumWorks"
PBXPROJ="$ROOT/NumWorks.xcodeproj/project.pbxproj"
DERIVED="${TMPDIR:-/tmp}/NumWorks-release-derived"
RELEASES="$ROOT/build/releases"
CONFIGURATION="Release"
REF="${1:-latest}"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

cd "$ROOT"
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

if [[ "$REF" == "latest" ]]; then
  REF="$("$ROOT/NumWorks/Scripts/latest-epsilon-tag.sh")"
fi
[[ -n "$REF" ]] || die "could not resolve Epsilon ref"

info "Epsilon ref: $REF"
"$ROOT/NumWorks/Scripts/prepare-epsilon.sh" "$REF"
ARCHS="${ARCHS:-$(uname -m)}" "$ROOT/NumWorks/Scripts/build-epsilon-lib.sh"

mkdir -p "$ROOT/NumWorks/Support"
echo "$REF" > "$ROOT/NumWorks/Support/epsilon-pinned-ref.txt"

# Bump marketing patch + build (NumWorks app target only: COMBINE_HIDPI_IMAGES block)
read -r VERSION BUILD_NUMBER < <(
  python3 - <<'PY' "$PBXPROJ"
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
blocks = re.findall(
    r"buildSettings = \{[^{}]*COMBINE_HIDPI_IMAGES = YES;[^{}]*\};",
    text,
    flags=re.S,
)
if not blocks:
    raise SystemExit("could not find NumWorks app buildSettings")
m_ver = re.search(r"MARKETING_VERSION = ([^;]+);", blocks[0])
m_build = re.search(r"CURRENT_PROJECT_VERSION = (\d+);", blocks[0])
ver = (m_ver.group(1).strip() if m_ver else "1.0.0")
build = int(m_build.group(1) if m_build else "0")
parts = ver.split(".")
while len(parts) < 3:
    parts.append("0")
parts[-1] = str(int(parts[-1]) + 1)
new_ver = ".".join(parts)
new_build = build + 1

def bump(m):
    block = m.group(0)
    block = re.sub(r"CURRENT_PROJECT_VERSION = \d+;", f"CURRENT_PROJECT_VERSION = {new_build};", block)
    block = re.sub(r"MARKETING_VERSION = [^;]+;", f"MARKETING_VERSION = {new_ver};", block)
    return block

new = re.sub(
    r"buildSettings = \{[^{}]*COMBINE_HIDPI_IMAGES = YES;[^{}]*\};",
    bump,
    text,
    flags=re.S,
)
path.write_text(new)
print(new_ver, new_build)
PY
)

info "Version $VERSION (build $BUILD_NUMBER) for Epsilon $REF"

mkdir -p "$RELEASES"
NOTES_OUT="$RELEASES/NumWorks-${VERSION}.md"
"$ROOT/NumWorks/Scripts/compose-epsilon-notes.sh" "$REF" "$NOTES_OUT"

info "Building $SCHEME ($CONFIGURATION)"
rm -rf "$DERIVED"
mkdir -p "$ROOT/build"

# Ad-hoc on CI when no Apple signing secrets; local Release uses project signing.
EXTRA_SIGN=()
if [[ "${CI:-}" == "true" || -n "${GITHUB_ACTIONS:-}" ]]; then
  if [[ -z "${APPLE_CERTIFICATE_BASE64:-}" ]]; then
    info "CI without Apple cert — ad-hoc codesign (fine for your local test download)"
    EXTRA_SIGN=(
      CODE_SIGN_IDENTITY="-"
      CODE_SIGNING_REQUIRED=NO
      CODE_SIGNING_ALLOWED=YES
    )
  fi
fi

set +e
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination "platform=macOS" \
  build \
  "${EXTRA_SIGN[@]}" \
  >"$ROOT/build/xcodebuild.log" 2>&1
BUILD_STATUS=$?
set -e
tail -40 "$ROOT/build/xcodebuild.log" || true
if [[ "$BUILD_STATUS" -ne 0 ]] || ! grep -q '\*\* BUILD SUCCEEDED \*\*' "$ROOT/build/xcodebuild.log"; then
  die "build failed — see $ROOT/build/xcodebuild.log"
fi

APP="$DERIVED/Build/Products/${CONFIGURATION}/NumWorks.app"
[[ -d "$APP" ]] || die "app not found at $APP"

# CI ad-hoc builds leave Sparkle with its original Team ID while the main
# binary is unsigned/ad-hoc → dyld: "different Team IDs". Re-sign the whole
# bundle so the app and embedded frameworks share one signature.
if [[ "${CI:-}" == "true" || -n "${GITHUB_ACTIONS:-}" ]]; then
  if [[ -z "${APPLE_CERTIFICATE_BASE64:-}" ]]; then
    info "Deep ad-hoc re-sign (app + Sparkle) so Team IDs match"
    codesign --force --deep --sign - "$APP"
    codesign --verify --deep --strict "$APP" || die "ad-hoc codesign verify failed"
  fi
fi

got_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
got_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$got_version" == "$VERSION" ]] || die "built marketing version is $got_version, expected $VERSION"
[[ "$got_build" == "$BUILD_NUMBER" ]] || die "built build number is $got_build, expected $BUILD_NUMBER"
info "Built NumWorks $got_version ($got_build)"

ZIP="$RELEASES/NumWorks-${VERSION}.zip"
rm -f "$ZIP"
info "Zipping → $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Ship job needs generate_appcast + meta
SPARKLE_BIN="$(
  find "$DERIVED" -path '*/Sparkle/bin/generate_appcast' -type f 2>/dev/null | head -1
)"
[[ -n "$SPARKLE_BIN" && -x "$SPARKLE_BIN" ]] || die "generate_appcast not found after build"
cp "$SPARKLE_BIN" "$RELEASES/generate_appcast"
chmod +x "$RELEASES/generate_appcast"

cat > "$RELEASES/release-meta.env" <<EOF
VERSION=${VERSION}
BUILD_NUMBER=${BUILD_NUMBER}
EPSILON_REF=${REF}
EOF

info "Ready to test: $ZIP"
info "Notes: $NOTES_OUT"
info "Meta:  $RELEASES/release-meta.env"
