# Security

## Trust Model
- Owner can register pools and queue bounded config updates.
- Config updates are delayed by `minUpdateDelayBlocks`.
- Step-change caps (`maxAdminStepBps`) limit abrupt parameter shifts.

## Primary Threats and Mitigations
- Launch sniping: bounded max-in and optional allowlist.
- Burst MEV/JIT oscillation: per-block swap and JIT action caps.
- Inventory overdraw: strict free/reserved accounting and bounded usage.
- Reentrancy in inventory paths: `ReentrancyGuard` on vault state mutators.
- Unauthorized hook callbacks: `onlyPoolManager` and hook authorization checks.

## Residual Risks
- Poorly chosen launch parameters can still degrade UX.
- Hook-level impact estimates are conservative and not a full execution-proof slippage oracle.
- Admin key risk remains unless migrated to multisig + timelock governance.
