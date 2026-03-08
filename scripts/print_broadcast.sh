#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <script-path> <chain-id>" >&2
  exit 1
fi

SCRIPT_PATH="$1"
CHAIN_ID="$2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BROADCAST_FILE="broadcast/${SCRIPT_PATH}/${CHAIN_ID}/run-latest.json"
if [[ ! -f "$BROADCAST_FILE" ]]; then
  ALT_FILE="broadcast/$(basename "$SCRIPT_PATH")/${CHAIN_ID}/run-latest.json"
  if [[ -f "$ALT_FILE" ]]; then
    BROADCAST_FILE="$ALT_FILE"
  else
    echo "broadcast file not found: $BROADCAST_FILE" >&2
    echo "broadcast file not found: $ALT_FILE" >&2
    exit 1
  fi
fi

explorer_base() {
  case "$1" in
    1301) echo "https://unichain-sepolia.blockscout.com/tx/" ;;
    84532) echo "https://sepolia.basescan.org/tx/" ;;
    11155111) echo "https://sepolia.etherscan.io/tx/" ;;
    31337) echo "TBD" ;;
    *) echo "TBD" ;;
  esac
}

BASE_URL="${EXPLORER_TX_BASE_URL:-$(explorer_base "$CHAIN_ID")}"

echo "=== Broadcast Transactions (${CHAIN_ID}) ==="
jq -r '.transactions[] | [.hash, .transactionType, (.contractName // ""), (.contractAddress // "")] | @tsv' "$BROADCAST_FILE" |
while IFS=$'\t' read -r hash txType contractName contractAddress; do
  if [[ "$BASE_URL" == "TBD" ]]; then
    echo "tx: ${hash} | type: ${txType} | contract: ${contractName:-n/a} ${contractAddress:+| address: $contractAddress} | explorer: TBD"
  else
    echo "tx: ${hash} | type: ${txType} | contract: ${contractName:-n/a} ${contractAddress:+| address: $contractAddress} | explorer: ${BASE_URL}${hash}"
  fi
done
