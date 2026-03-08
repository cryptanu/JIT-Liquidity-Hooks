# Demo Flow

## Targets
- `make demo-launch`: deploy launch stack only.
- `make demo-compare`: run deterministic comparison test locally.
- `make demo-local`: broadcast on local node and print tx hashes.
- `make deploy-sepolia`: deploy launch stack on Unichain Sepolia from `.env`.
- `make demo-sepolia`: broadcast on Unichain Sepolia from `.env` and print tx URLs.
- `make demo-testnet`: broadcast on configured testnet and print explorer links.
- `make demo-all`: launch + compare.

## Scenario
The scripted comparison creates two pools:
- Baseline: no hook
- JIT: `JITLaunchHook`

Both are initialized with equal liquidity, then the same demand sequence is replayed.
Output summary includes:
- average execution price
- max observed slippage
- blocked swap count
- phase transition behavior
