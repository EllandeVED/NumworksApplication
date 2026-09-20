#!/usr/bin/env bash
# Resolve the latest Epsilon version line from numworks/epsilon.
# Tags stopped at 23.2.3; the highest version-N branch is the real latest
# (e.g. version-25), and currently matches master.
set -euo pipefail

EPSILON_REPO="${EPSILON_REPO:-https://github.com/numworks/epsilon.git}"

git ls-remote --heads "$EPSILON_REPO" \
  | awk '{print $2}' \
  | sed 's#refs/heads/##' \
  | grep -E '^version-[0-9]+$' \
  | sort -t - -k2,2n \
  | tail -1
