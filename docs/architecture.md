# Architecture

## Components
- `JITLaunchHook`: Uniswap v4 hook callbacks, guardrail enforcement entrypoint.
- `LaunchController`: per-pool config, phase machine, decaying constraints, per-block counters.
- `JITLiquidityVault`: deterministic inventory reservation/release model for JIT bands.
- `QuoteInventoryVault`: quote-side custody and reservation accounting.
- `IssuanceModule`: optional deterministic mint stream with hard caps.

## System Diagram
```mermaid
flowchart LR
    Frontend[Frontend Launch Console] --> Hook[JITLaunchHook]
    Hook --> Controller[LaunchController]
    Hook --> Vault[JITLiquidityVault]
    Vault --> QuoteVault[QuoteInventoryVault]
    Hook --> PoolManager[Uniswap v4 PoolManager]
    Issuance[IssuanceModule] --> Vault
    Issuance --> Token[MockNewAssetToken]
```

## Interaction Notes
- Hook entrypoints are `onlyPoolManager` via `BaseHook`.
- `LaunchController.enforceSwapGuardrails` executes first and can revert.
- JIT actions are bounded by `maxJitActionsPerBlock` and `maxInventoryUsagePerJit`.
- Steady-state swaps can trigger deterministic JIT unwind.
