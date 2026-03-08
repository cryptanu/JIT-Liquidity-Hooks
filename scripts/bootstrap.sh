#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

V4_PERIPHERY_PIN="3779387e5d296f39df543d23524b050f89a62917"
V4_CORE_PIN="59d3ecf53afa9264a16bba0e38f4c5d2231f80bc"

echo "[bootstrap] syncing submodules"
git submodule sync --recursive
git submodule update --init --recursive

echo "[bootstrap] pinning Uniswap v4-periphery -> ${V4_PERIPHERY_PIN}"
git -C lib/uniswap-hooks/lib/v4-periphery fetch --all --tags --prune
git -C lib/uniswap-hooks/lib/v4-periphery checkout "$V4_PERIPHERY_PIN"

echo "[bootstrap] pinning Uniswap v4-core -> ${V4_CORE_PIN}"
git -C lib/uniswap-hooks/lib/v4-core fetch --all --tags --prune
git -C lib/uniswap-hooks/lib/v4-core checkout "$V4_CORE_PIN"

git -C lib/uniswap-hooks/lib/v4-periphery/lib/v4-core fetch --all --tags --prune
git -C lib/uniswap-hooks/lib/v4-periphery/lib/v4-core checkout "$V4_CORE_PIN"

ACTUAL_PERIPHERY="$(git -C lib/uniswap-hooks/lib/v4-periphery rev-parse HEAD)"
ACTUAL_CORE_TOP="$(git -C lib/uniswap-hooks/lib/v4-core rev-parse HEAD)"
ACTUAL_CORE_PERIPHERY="$(git -C lib/uniswap-hooks/lib/v4-periphery/lib/v4-core rev-parse HEAD)"

[[ "$ACTUAL_PERIPHERY" == "$V4_PERIPHERY_PIN" ]] || {
  echo "[bootstrap] periphery pin mismatch: $ACTUAL_PERIPHERY" >&2
  exit 1
}

[[ "$ACTUAL_CORE_TOP" == "$V4_CORE_PIN" ]] || {
  echo "[bootstrap] core pin mismatch (top): $ACTUAL_CORE_TOP" >&2
  exit 1
}

[[ "$ACTUAL_CORE_PERIPHERY" == "$V4_CORE_PIN" ]] || {
  echo "[bootstrap] core pin mismatch (nested): $ACTUAL_CORE_PERIPHERY" >&2
  exit 1
}

echo "[bootstrap] pins verified"

forge --version
forge build -q

./scripts/export_abis.sh

echo "[bootstrap] done"
