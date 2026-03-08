# Overview

JIT Liquidity & Issuance Hook is a launch-market primitive for newly listed or thinly liquid assets on Uniswap v4.

The system adds deterministic launch controls:
- phase-gated swapping (pre-launch, discovery, steady)
- per-swap and per-block anti-sniping guardrails
- bounded just-in-time inventory activation around the active tick
- optional bounded issuance streamed into launch inventory

No keepers are required for correctness. Swap flow itself triggers deterministic checks and bounded JIT actions.

Core contracts:
- `JITLaunchHook`
- `LaunchController`
- `JITLiquidityVault`
- `QuoteInventoryVault`
- `IssuanceModule` (optional)
- `MockNewAssetToken` (demo)
