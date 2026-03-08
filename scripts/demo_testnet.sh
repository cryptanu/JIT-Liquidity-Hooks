#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RPC_URL="${RPC_URL:-${BASE_SEPOLIA_RPC_URL:-}}"
PRIVATE_KEY="${PRIVATE_KEY:-}"
CHAIN_ID="${CHAIN_ID:-84532}"

if [[ -z "$RPC_URL" || -z "$PRIVATE_KEY" ]]; then
  echo "RPC_URL (or BASE_SEPOLIA_RPC_URL) and PRIVATE_KEY are required" >&2
  exit 1
fi

forge script script/01_DemoCompare.s.sol:DemoCompareScript \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --non-interactive

./scripts/print_broadcast.sh script/01_DemoCompare.s.sol "$CHAIN_ID"
