# Anti-Sniping

Guardrails implemented on-chain:
- `maxAmountIn` per swap
- `maxImpactBps` per swap (hook input-bound check)
- `maxSwapsPerBlock` per pool
- optional allowlist window (`allowlistBlocks`)
- per-trader cooldown (`cooldownBlocks`)
- `maxJitActionsPerBlock` to reduce oscillation abuse

Tradeoff:
- stricter launch controls improve fairness and reduce early manipulation,
- but can temporarily reduce throughput for legitimate large traders.
