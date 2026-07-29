#!/usr/bin/env bash
# Resolve the newest version-looking tag from numworks/epsilon (e.g. 23.2.3).
set -euo pipefail

EPSILON_REPO="${EPSILON_REPO:-https://github.com/numworks/epsilon.git}"

git ls-remote --tags --refs "$EPSILON_REPO" \
  | awk '{print $2}' \
  | sed 's#refs/tags/##' \
  | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' \
  | sort -t . -k1,1n -k2,2n -k3,3n \
  | tail -1
