# Security Policy

## Scope
Contracts in `src/` are in scope:
- `JITLaunchHook`
- `LaunchController`
- `JITLiquidityVault`
- `QuoteInventoryVault`
- `IssuanceModule`
- `MockNewAssetToken` (demo-only)

## Reporting
Please report vulnerabilities privately to:
- email: `cryptanu@users.noreply.github.com` (or open a private security advisory on GitHub)

Include:
- affected contract/function
- reproducible scenario and calldata
- impact and preconditions

## Security Model
- Hook entrypoints are `onlyPoolManager`.
- Per-pool hook authorization gates guardrail/JIT paths.
- Inventory math is bounded and no unbounded loops are used.
- Issuance is optional, block-capped, and total-capped.

## Residual Risks
- Misconfigured launch parameters can cause temporary DoS-like strictness.
- Governance/admin key risk exists without multisig/timelock hardening.
- Hook-level impact checks are conservative and not a full oracle guarantee.

## Recommended Hardening Before Mainnet
1. Move ownership to multisig.
2. Increase config update delays.
3. External audit + invariant review.
4. Dry-run launch parameter simulation with realistic orderflow.
