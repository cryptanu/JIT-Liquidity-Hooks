#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
CHAIN_ID="${CHAIN_ID:-31337}"

forge script script/00_DeployLaunchStack.s.sol:DeployLaunchStackScript \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --non-interactive \
  --skip-simulation

./scripts/print_broadcast.sh script/00_DeployLaunchStack.s.sol "$CHAIN_ID"
