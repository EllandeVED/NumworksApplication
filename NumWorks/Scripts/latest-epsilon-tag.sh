#!/usr/bin/env bash
# Highest version-N branch on numworks/epsilon.
set -euo pipefail

EPSILON_REPO="${EPSILON_REPO:-https://github.com/numworks/epsilon.git}"

git ls-remote --heads "$EPSILON_REPO" \
  | awk '{print $2}' \
  | sed 's#refs/heads/##' \
  | grep -E '^version-[0-9]+$' \
  | sort -t - -k2,2n \
  | tail -1
