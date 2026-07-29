#!/usr/bin/env bash
# Publish a pre-built NumWorks zip to Sparkle (appcast + gh-pages).
#
# Usage:
#   ./NumWorks/Scripts/publish-sparkle.sh \
#     --version 2.0.6 --zip ./NumWorks-2.0.6.zip --notes ./NumWorks-2.0.6.md \
#     [--generate-appcast /path/to/generate_appcast]
#
# Sparkle signing:
#   Local (default): Keychain EdDSA key (may prompt Allow)
#   CI: set SPARKLE_ED_KEY to the base64 private key (from `generate_keys` export)
#       and it is passed via --ed-key-file -
#
# Env:
#   SKIP_PUBLISH=1  — write appcast locally only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Appcast feed stays on Pages; new zip enclosures point at GitHub Releases so
# download_count (and the Widgy stats widget) includes Sparkle updates.
FEED_PREFIX="https://ellandeved.github.io/NumworksApplication/"
GITHUB_REPO="${GITHUB_REPO:-EllandeVED/NumworksApplication}"
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"
RELEASES="$ROOT/build/releases"
SKIP_PUBLISH="${SKIP_PUBLISH:-0}"

VERSION=""
ZIP=""
NOTES=""
SPARKLE_BIN=""

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:?}"; shift 2 ;;
    --zip) ZIP="${2:?}"; shift 2 ;;
    --notes) NOTES="${2:?}"; shift 2 ;;
    --generate-appcast) SPARKLE_BIN="${2:?}"; shift 2 ;;
    --skip-publish) SKIP_PUBLISH=1; shift ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "$VERSION" ]] || die "--version required"
[[ -f "$ZIP" ]] || die "zip not found: $ZIP"
[[ -f "$NOTES" ]] || die "notes not found: $NOTES"

mkdir -p "$RELEASES"
STAGE="$(mktemp -d -t numworks-sparkle)"
cp "$ZIP" "$STAGE/NumWorks-${VERSION}.zip"
cp "$NOTES" "$STAGE/NumWorks-${VERSION}.md"

if [[ -z "$SPARKLE_BIN" ]]; then
  SPARKLE_BIN="$(
    find "${TMPDIR:-/tmp}/NumWorks-release-derived" \
      "$ROOT/build" \
      "$HOME/Library/Developer/Xcode/DerivedData" \
      -path '*/Sparkle/bin/generate_appcast' \
      -type f 2>/dev/null | head -1
  )"
fi
[[ -n "$SPARKLE_BIN" && -x "$SPARKLE_BIN" ]] || die "generate_appcast not found (pass --generate-appcast)"

if curl -fsSL "${FEED_PREFIX}appcast.xml" -o "$STAGE/appcast.xml" 2>/dev/null; then
  info "Merged with existing live appcast"
else
  info "No existing appcast online — creating a new one"
fi

info "Signing update + writing appcast"
# Enclosure URL: GitHub Releases CDN (counted) — filename is appended by Sparkle.
DOWNLOAD_PREFIX="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/"
if [[ -n "${SPARKLE_ED_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_ED_KEY" | "$SPARKLE_BIN" \
    --ed-key-file - \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    --embed-release-notes \
    "$STAGE"
else
  "$SPARKLE_BIN" \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    --embed-release-notes \
    "$STAGE"
fi

[[ -f "$STAGE/appcast.xml" ]] || die "appcast.xml was not generated"
cp "$STAGE/appcast.xml" "$RELEASES/appcast.xml"
cp "$STAGE/NumWorks-${VERSION}.zip" "$RELEASES/NumWorks-${VERSION}.zip"
cp "$NOTES" "$RELEASES/NumWorks-${VERSION}.md"
info "Appcast ready at $RELEASES/appcast.xml"

if [[ "$SKIP_PUBLISH" -eq 1 ]]; then
  info "Skipping publish"
  rm -rf "$STAGE"
  exit 0
fi

WORKDIR="$(mktemp -d -t numworks-gh-pages)"
info "Cloning $GITHUB_REPO ($PAGES_BRANCH)"
# Prefer token when present (CI)
clone_url="https://github.com/${GITHUB_REPO}.git"
if [[ -n "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ]]; then
  token="${GITHUB_TOKEN:-$GH_TOKEN}"
  clone_url="https://x-access-token:${token}@github.com/${GITHUB_REPO}.git"
fi
git clone --branch "$PAGES_BRANCH" --single-branch "$clone_url" "$WORKDIR"

cp "$RELEASES/appcast.xml" "$WORKDIR/appcast.xml"
cp "$RELEASES/NumWorks-${VERSION}.zip" "$WORKDIR/NumWorks-${VERSION}.zip"
cp "$RELEASES/NumWorks-${VERSION}.md" "$WORKDIR/NumWorks-${VERSION}.md"

cd "$WORKDIR"
git add appcast.xml "NumWorks-${VERSION}.zip" "NumWorks-${VERSION}.md"
if git diff --cached --quiet; then
  info "Nothing new to publish"
else
  git config user.name "${GIT_AUTHOR_NAME:-github-actions[bot]}"
  git config user.email "${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
  git commit -m "Release NumWorks ${VERSION}"
  info "Pushing to origin/$PAGES_BRANCH"
  git push origin "$PAGES_BRANCH"
fi

rm -rf "$STAGE" "$WORKDIR"
info "Published ${FEED_PREFIX}appcast.xml"
