// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Launch lifecycle phases for a pool.
enum LaunchPhase {
    PreLaunch,
    LaunchDiscovery,
    SteadyState
}

/// @notice Static launch configuration, stored per pool.
struct LaunchConfig {
    uint64 startBlock;
    uint32 preLaunchBlocks;
    uint32 launchBlocks;
    uint32 allowlistBlocks;
    uint128 initialMaxAmountIn;
    uint128 steadyMaxAmountIn;
    uint128 maxInventoryUsagePerJit;
    uint16 initialMaxImpactBps;
    uint16 steadyMaxImpactBps;
    uint16 cooldownBlocks;
    uint16 maxSwapsPerBlock;
    uint16 maxJitActionsPerBlock;
    uint16 jitBandWidth;
    bool preLaunchSwapsEnabled;
    bool allowlistEnabled;
}

/// @notice Runtime guardrails derived from the active phase and decay schedule.
struct GuardrailSnapshot {
    LaunchPhase phase;
    uint128 maxAmountIn;
    uint16 maxImpactBps;
    uint16 cooldownBlocks;
    uint16 maxSwapsPerBlock;
    uint16 maxJitActionsPerBlock;
    uint16 jitBandWidth;
    uint128 maxInventoryUsagePerJit;
    bool allowlistActive;
}

/// @notice Queued admin config update with execution delay.
struct PendingConfigUpdate {
    LaunchConfig config;
    uint64 executableAt;
    bool exists;
}
