#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p shared/abis shared/types

contracts=(
  "JITLaunchHook"
  "LaunchController"
  "JITLiquidityVault"
  "QuoteInventoryVault"
  "IssuanceModule"
  "MockNewAssetToken"
)

for contract in "${contracts[@]}"; do
  src="out/${contract}.sol/${contract}.json"
  if [[ ! -f "$src" ]]; then
    echo "missing artifact: $src" >&2
    exit 1
  fi
  cp "$src" "shared/abis/${contract}.json"
  echo "exported ${contract}"
done

cat > shared/types/contracts.ts <<'TS'
export const CONTRACT_NAMES = [
  "JITLaunchHook",
  "LaunchController",
  "JITLiquidityVault",
  "QuoteInventoryVault",
  "IssuanceModule",
  "MockNewAssetToken"
] as const;

export type ContractName = (typeof CONTRACT_NAMES)[number];
TS

echo "ABI export complete -> shared/abis"
