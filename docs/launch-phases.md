# Launch Phases

`LaunchController` derives phase from block numbers.

Definitions:
- `startBlock`: phase schedule anchor
- `preLaunchBlocks`: pre-launch duration
- `launchBlocks`: discovery duration

Phase function:
- `PreLaunch` if `block < startBlock + preLaunchBlocks`
- `LaunchDiscovery` if in `[startBlock + preLaunchBlocks, startBlock + preLaunchBlocks + launchBlocks)`
- `SteadyState` afterwards

Guardrail decay in discovery is linear:
- `maxAmountIn` interpolates from initial to steady
- `maxImpactBps` interpolates from initial to steady

This guarantees deterministic transitions for identical inputs.
