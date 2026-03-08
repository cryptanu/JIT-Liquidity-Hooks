export const CONTRACT_NAMES = [
  "JITLaunchHook",
  "LaunchController",
  "JITLiquidityVault",
  "QuoteInventoryVault",
  "IssuanceModule",
  "MockNewAssetToken"
] as const;

export type ContractName = (typeof CONTRACT_NAMES)[number];
