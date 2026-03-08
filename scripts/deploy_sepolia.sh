#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

RPC_URL="${RPC_URL:-${SEPOLIA_RPC_URL:-${BASE_SEPOLIA_RPC_URL:-}}}"
PRIVATE_KEY="${PRIVATE_KEY:-${SEPOLIA_PRIVATE_KEY:-}}"
CHAIN_ID="${CHAIN_ID:-${SEPOLIA_CHAIN_ID:-1301}}"
EXPLORER_TX_BASE_URL="${EXPLORER_TX_BASE_URL:-https://unichain-sepolia.blockscout.com/tx/}"

if [[ -z "$RPC_URL" || -z "$PRIVATE_KEY" ]]; then
  echo "RPC_URL (or SEPOLIA_RPC_URL/BASE_SEPOLIA_RPC_URL) and PRIVATE_KEY (or SEPOLIA_PRIVATE_KEY) are required" >&2
  exit 1
fi

forge script script/00_DeployLaunchStack.s.sol:DeployLaunchStackScript \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --non-interactive \
  --slow \
  --skip-simulation

EXPLORER_TX_BASE_URL="$EXPLORER_TX_BASE_URL" ./scripts/print_broadcast.sh script/00_DeployLaunchStack.s.sol "$CHAIN_ID"
