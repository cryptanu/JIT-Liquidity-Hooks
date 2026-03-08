#!/usr/bin/env bash
set -euo pipefail

EXPECTED_COUNT=300
EXPECTED_AUTHOR="najnomics"
EXPECTED_EMAIL="jesuorobonosakhare873@gmail.com"

COUNT="$(git rev-list --count HEAD)"
if [[ "$COUNT" -ne "$EXPECTED_COUNT" ]]; then
  echo "commit count mismatch: expected ${EXPECTED_COUNT}, got ${COUNT}" >&2
  exit 1
fi

BAD="$(git log --pretty='%an|%ae' | awk -F'|' -v a="$EXPECTED_AUTHOR" -v e="$EXPECTED_EMAIL" '$1 != a || $2 != e {print $0; exit 0}')"
if [[ -n "$BAD" ]]; then
  echo "author mismatch found: ${BAD}" >&2
  exit 1
fi

echo "commit policy satisfied (${EXPECTED_COUNT} commits, author ${EXPECTED_AUTHOR} <${EXPECTED_EMAIL}>)"
