// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {ILaunchController} from "src/interfaces/ILaunchController.sol";
import {LaunchConfig, GuardrailSnapshot, LaunchPhase, PendingConfigUpdate} from "src/types/LaunchTypes.sol";

/// @notice Stores launch configuration and deterministic phase/guardrail logic for a pool.
contract LaunchController is Ownable, ILaunchController {
    uint16 public constant BPS_DENOMINATOR = 10_000;

    uint64 public immutable minUpdateDelayBlocks;
    uint16 public immutable maxAdminStepBps;

    mapping(PoolId => LaunchConfig) private _configs;
    mapping(PoolId => bool) private _configured;
    mapping(PoolId => PendingConfigUpdate) private _pending;

    mapping(PoolId => address) public hookForPool;
    mapping(PoolId => mapping(address => bool)) public allowlisted;

    mapping(PoolId => mapping(address => uint64)) public lastSwapBlockByTrader;

    mapping(PoolId => uint64) public currentSwapCounterBlock;
    mapping(PoolId => uint32) public swapsInBlock;

    mapping(PoolId => uint64) public currentJitCounterBlock;
    mapping(PoolId => uint32) public jitActionsInBlock;

    error PoolNotConfigured(PoolId poolId);
    error PoolAlreadyConfigured(PoolId poolId);
    error UnauthorizedHook(PoolId poolId, address caller);
    error InvalidConfig();
    error PreLaunchSwapsDisabled(PoolId poolId);
    error AllowlistRequired(PoolId poolId, address sender);
    error SwapAmountTooLarge(uint256 amountIn, uint256 maxAmountIn);
    error ImpactTooHigh(uint256 impactBps, uint256 maxImpactBps);
    error CooldownActive(PoolId poolId, address sender, uint256 nextBlock);
    error SwapCapExceeded(PoolId poolId);
    error JitCapExceeded(PoolId poolId);
    error NoPendingUpdate(PoolId poolId);
    error PendingUpdateNotExecutable(uint64 executableAt, uint64 currentBlock);
    error AdminUpdateTooLarge();

    event PoolRegistered(PoolId indexed poolId, address indexed hook, uint64 startBlock);
    event PoolHookUpdated(PoolId indexed poolId, address indexed hook);
    event AllowlistUpdated(PoolId indexed poolId, address indexed user, bool allowed);
    event ConfigUpdateQueued(PoolId indexed poolId, uint64 executableAt);
    event ConfigUpdateExecuted(PoolId indexed poolId);

    constructor(uint64 _minUpdateDelayBlocks, uint16 _maxAdminStepBps, address initialOwner) Ownable(initialOwner) {
        if (_maxAdminStepBps == 0 || _maxAdminStepBps > BPS_DENOMINATOR) revert InvalidConfig();
        minUpdateDelayBlocks = _minUpdateDelayBlocks;
        maxAdminStepBps = _maxAdminStepBps;
    }

    modifier onlyPoolHook(PoolId poolId) {
        if (msg.sender != hookForPool[poolId]) revert UnauthorizedHook(poolId, msg.sender);
        _;
    }

    function registerPool(PoolId poolId, address hook, LaunchConfig calldata config) external onlyOwner {
        if (_configured[poolId]) revert PoolAlreadyConfigured(poolId);
        _validateConfig(config);

        _configs[poolId] = config;
        _configured[poolId] = true;
        hookForPool[poolId] = hook;

        emit PoolRegistered(poolId, hook, config.startBlock);
    }

    function setPoolHook(PoolId poolId, address hook) external onlyOwner {
        _requireConfigured(poolId);
        hookForPool[poolId] = hook;
        emit PoolHookUpdated(poolId, hook);
    }

    function setAllowlist(PoolId poolId, address user, bool allowed) external onlyOwner {
        _requireConfigured(poolId);
        allowlisted[poolId][user] = allowed;
        emit AllowlistUpdated(poolId, user, allowed);
    }

    function queueConfigUpdate(PoolId poolId, LaunchConfig calldata nextConfig) external onlyOwner {
        _requireConfigured(poolId);
        _validateConfig(nextConfig);
        _assertBoundedUpdate(_configs[poolId], nextConfig);

        uint64 executableAt = uint64(block.number) + minUpdateDelayBlocks;
        _pending[poolId] = PendingConfigUpdate({config: nextConfig, executableAt: executableAt, exists: true});

        emit ConfigUpdateQueued(poolId, executableAt);
    }

    function executeConfigUpdate(PoolId poolId) external {
        _requireConfigured(poolId);
        PendingConfigUpdate memory pending = _pending[poolId];
        if (!pending.exists) revert NoPendingUpdate(poolId);
        if (block.number < pending.executableAt) {
            revert PendingUpdateNotExecutable(pending.executableAt, uint64(block.number));
        }

        _configs[poolId] = pending.config;
        delete _pending[poolId];

        emit ConfigUpdateExecuted(poolId);
    }

    function getLaunchConfig(PoolId poolId) external view returns (LaunchConfig memory) {
        _requireConfigured(poolId);
        return _configs[poolId];
    }

    function getGuardrails(PoolId poolId) public view returns (GuardrailSnapshot memory) {
        _requireConfigured(poolId);

        LaunchConfig memory config = _configs[poolId];
        LaunchPhase phase = _phase(config);

        uint128 maxAmountIn;
        uint16 maxImpactBps;

        if (phase == LaunchPhase.PreLaunch) {
            maxAmountIn = config.initialMaxAmountIn;
            maxImpactBps = config.initialMaxImpactBps;
        } else if (phase == LaunchPhase.LaunchDiscovery) {
            uint256 elapsed = block.number - (uint256(config.startBlock) + uint256(config.preLaunchBlocks));
            uint256 progressBps =
                elapsed >= config.launchBlocks ? BPS_DENOMINATOR : (elapsed * BPS_DENOMINATOR) / config.launchBlocks;

            maxAmountIn = uint128(
                uint256(config.initialMaxAmountIn)
                    + ((uint256(config.steadyMaxAmountIn) - uint256(config.initialMaxAmountIn)) * progressBps)
                    / BPS_DENOMINATOR
            );

            maxImpactBps = uint16(
                uint256(config.initialMaxImpactBps)
                    + ((uint256(config.steadyMaxImpactBps) - uint256(config.initialMaxImpactBps)) * progressBps)
                    / BPS_DENOMINATOR
            );
        } else {
            maxAmountIn = config.steadyMaxAmountIn;
            maxImpactBps = config.steadyMaxImpactBps;
        }

        bool allowlistActive =
            config.allowlistEnabled && (block.number < uint256(config.startBlock) + uint256(config.allowlistBlocks));

        return GuardrailSnapshot({
            phase: phase,
            maxAmountIn: maxAmountIn,
            maxImpactBps: maxImpactBps,
            cooldownBlocks: config.cooldownBlocks,
            maxSwapsPerBlock: config.maxSwapsPerBlock,
            maxJitActionsPerBlock: config.maxJitActionsPerBlock,
            jitBandWidth: config.jitBandWidth,
            maxInventoryUsagePerJit: config.maxInventoryUsagePerJit,
            allowlistActive: allowlistActive
        });
    }

    function getPhase(PoolId poolId) external view returns (LaunchPhase) {
        _requireConfigured(poolId);
        return _phase(_configs[poolId]);
    }

    function enforceSwapGuardrails(PoolId poolId, address sender, uint256 amountIn, uint256 impactBps)
        external
        onlyPoolHook(poolId)
        returns (GuardrailSnapshot memory snapshot)
    {
        snapshot = getGuardrails(poolId);

        if (snapshot.phase == LaunchPhase.PreLaunch && !_configs[poolId].preLaunchSwapsEnabled) {
            revert PreLaunchSwapsDisabled(poolId);
        }

        if (snapshot.allowlistActive && !allowlisted[poolId][sender]) {
            revert AllowlistRequired(poolId, sender);
        }

        if (amountIn > snapshot.maxAmountIn) {
            revert SwapAmountTooLarge(amountIn, snapshot.maxAmountIn);
        }

        if (impactBps > snapshot.maxImpactBps) {
            revert ImpactTooHigh(impactBps, snapshot.maxImpactBps);
        }

        uint64 lastSwapBlock = lastSwapBlockByTrader[poolId][sender];
        if (
            snapshot.cooldownBlocks > 0 && lastSwapBlock != 0
                && block.number < uint256(lastSwapBlock) + uint256(snapshot.cooldownBlocks)
        ) {
            revert CooldownActive(poolId, sender, uint256(lastSwapBlock) + uint256(snapshot.cooldownBlocks));
        }

        if (currentSwapCounterBlock[poolId] != block.number) {
            currentSwapCounterBlock[poolId] = uint64(block.number);
            swapsInBlock[poolId] = 0;
        }

        unchecked {
            swapsInBlock[poolId] += 1;
        }

        if (swapsInBlock[poolId] > snapshot.maxSwapsPerBlock) {
            revert SwapCapExceeded(poolId);
        }

        lastSwapBlockByTrader[poolId][sender] = uint64(block.number);
    }

    function consumeJitAction(PoolId poolId) external onlyPoolHook(poolId) returns (bool) {
        GuardrailSnapshot memory snapshot = getGuardrails(poolId);

        if (snapshot.phase == LaunchPhase.PreLaunch) {
            return false;
        }

        if (currentJitCounterBlock[poolId] != block.number) {
            currentJitCounterBlock[poolId] = uint64(block.number);
            jitActionsInBlock[poolId] = 0;
        }

        unchecked {
            jitActionsInBlock[poolId] += 1;
        }

        if (jitActionsInBlock[poolId] > snapshot.maxJitActionsPerBlock) {
            revert JitCapExceeded(poolId);
        }

        return true;
    }

    function _requireConfigured(PoolId poolId) internal view {
        if (!_configured[poolId]) revert PoolNotConfigured(poolId);
    }

    function _phase(LaunchConfig memory config) internal view returns (LaunchPhase) {
        if (block.number < config.startBlock) {
            return LaunchPhase.PreLaunch;
        }

        uint256 launchStart = uint256(config.startBlock) + uint256(config.preLaunchBlocks);
        if (block.number < launchStart) {
            return LaunchPhase.PreLaunch;
        }

        uint256 steadyStart = launchStart + uint256(config.launchBlocks);
        if (block.number < steadyStart) {
            return LaunchPhase.LaunchDiscovery;
        }

        return LaunchPhase.SteadyState;
    }

    function _validateConfig(LaunchConfig calldata config) internal pure {
        if (config.startBlock == 0) revert InvalidConfig();
        if (config.launchBlocks == 0) revert InvalidConfig();
        if (config.initialMaxAmountIn == 0 || config.steadyMaxAmountIn == 0) revert InvalidConfig();
        if (config.initialMaxImpactBps == 0 || config.steadyMaxImpactBps == 0) revert InvalidConfig();
        if (config.initialMaxAmountIn > config.steadyMaxAmountIn) revert InvalidConfig();
        if (config.initialMaxImpactBps > config.steadyMaxImpactBps) revert InvalidConfig();
        if (config.maxSwapsPerBlock == 0 || config.maxJitActionsPerBlock == 0) revert InvalidConfig();
        if (config.jitBandWidth == 0 || config.maxInventoryUsagePerJit == 0) revert InvalidConfig();
    }

    function _assertBoundedUpdate(LaunchConfig memory current, LaunchConfig calldata nextConfig) internal view {
        if (!_isBpsBounded(current.initialMaxAmountIn, nextConfig.initialMaxAmountIn, maxAdminStepBps)) {
            revert AdminUpdateTooLarge();
        }
        if (!_isBpsBounded(current.steadyMaxAmountIn, nextConfig.steadyMaxAmountIn, maxAdminStepBps)) {
            revert AdminUpdateTooLarge();
        }
        if (!_isBpsBounded(current.maxInventoryUsagePerJit, nextConfig.maxInventoryUsagePerJit, maxAdminStepBps)) {
            revert AdminUpdateTooLarge();
        }
        if (!_isBpsBounded(current.initialMaxImpactBps, nextConfig.initialMaxImpactBps, maxAdminStepBps)) {
            revert AdminUpdateTooLarge();
        }
        if (!_isBpsBounded(current.steadyMaxImpactBps, nextConfig.steadyMaxImpactBps, maxAdminStepBps)) {
            revert AdminUpdateTooLarge();
        }
        if (!_isBpsBounded(current.cooldownBlocks, nextConfig.cooldownBlocks, maxAdminStepBps)) {
            revert AdminUpdateTooLarge();
        }
        if (!_isBpsBounded(current.maxSwapsPerBlock, nextConfig.maxSwapsPerBlock, maxAdminStepBps)) {
            revert AdminUpdateTooLarge();
        }
        if (!_isBpsBounded(current.maxJitActionsPerBlock, nextConfig.maxJitActionsPerBlock, maxAdminStepBps)) {
            revert AdminUpdateTooLarge();
        }
        if (!_isBpsBounded(current.jitBandWidth, nextConfig.jitBandWidth, maxAdminStepBps)) {
            revert AdminUpdateTooLarge();
        }
    }

    function _isBpsBounded(uint256 oldValue, uint256 newValue, uint256 limitBps) internal pure returns (bool) {
        if (oldValue == 0) {
            return newValue == 0;
        }

        if (oldValue == newValue) {
            return true;
        }

        uint256 diff = oldValue > newValue ? oldValue - newValue : newValue - oldValue;
        uint256 maxAllowed = (oldValue * limitBps) / BPS_DENOMINATOR;

        if (maxAllowed == 0) {
            maxAllowed = 1;
        }

        return diff <= maxAllowed;
    }
}
