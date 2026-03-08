// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {ILaunchController} from "src/interfaces/ILaunchController.sol";
import {IJITLiquidityVault} from "src/interfaces/IJITLiquidityVault.sol";
import {LaunchPhase, GuardrailSnapshot} from "src/types/LaunchTypes.sol";
import {IssuanceModule} from "src/IssuanceModule.sol";

/// @notice Launch-phase swap hook with deterministic guardrails and bounded JIT inventory activation.
contract JITLaunchHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    ILaunchController public immutable launchController;
    IJITLiquidityVault public immutable jitVault;

    IssuanceModule public issuanceModule;

    mapping(PoolId => bool) public registeredPools;

    error PoolNotRegistered(PoolId poolId);

    event PoolRegistrationSet(PoolId indexed poolId, bool enabled);
    event IssuanceModuleSet(address indexed module);
    event GuardrailCheck(
        PoolId indexed poolId,
        address indexed sender,
        LaunchPhase phase,
        uint256 amountIn,
        uint256 impactBps,
        uint256 maxAmountIn,
        uint256 maxImpactBps
    );

    constructor(
        IPoolManager _poolManager,
        ILaunchController _launchController,
        IJITLiquidityVault _jitVault,
        IssuanceModule _issuanceModule,
        address initialOwner
    ) BaseHook(_poolManager) Ownable(initialOwner) {
        launchController = _launchController;
        jitVault = _jitVault;
        issuanceModule = _issuanceModule;
    }

    function setPoolRegistration(PoolKey calldata key, bool enabled) external onlyOwner {
        PoolId poolId = key.toId();
        registeredPools[poolId] = enabled;
        emit PoolRegistrationSet(poolId, enabled);
    }

    function setIssuanceModule(IssuanceModule module) external onlyOwner {
        issuanceModule = module;
        emit IssuanceModuleSet(address(module));
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        if (!registeredPools[poolId]) revert PoolNotRegistered(poolId);

        uint256 amountIn = _abs(params.amountSpecified);
        uint256 impactBps = _estimateImpactBps(poolId, params.sqrtPriceLimitX96);

        GuardrailSnapshot memory guardrails =
            launchController.enforceSwapGuardrails(poolId, sender, amountIn, impactBps);

        emit GuardrailCheck(
            poolId, sender, guardrails.phase, amountIn, impactBps, guardrails.maxAmountIn, guardrails.maxImpactBps
        );

        if (guardrails.phase == LaunchPhase.LaunchDiscovery) {
            if (launchController.consumeJitAction(poolId)) {
                IssuanceModule module = issuanceModule;
                if (address(module) != address(0)) {
                    module.streamToVault(poolId);
                }

                (, int24 tick,,) = poolManager.getSlot0(poolId);
                jitVault.executeJITAdd(poolId, tick, guardrails.jitBandWidth, guardrails.maxInventoryUsagePerJit);
            }
        } else if (guardrails.phase == LaunchPhase.SteadyState) {
            if (launchController.consumeJitAction(poolId)) {
                jitVault.executeJITRemove(poolId, 2_500);
            }
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        pure
        override
        returns (bytes4, int128)
    {
        return (BaseHook.afterSwap.selector, 0);
    }

    function _estimateImpactBps(PoolId poolId, uint160 sqrtPriceLimitX96) internal view returns (uint256 impactBps) {
        if (sqrtPriceLimitX96 == 0) {
            return 0;
        }

        (uint160 currentSqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        if (currentSqrtPriceX96 == 0) {
            return 0;
        }

        uint256 high = currentSqrtPriceX96 > sqrtPriceLimitX96 ? currentSqrtPriceX96 : sqrtPriceLimitX96;
        uint256 low = currentSqrtPriceX96 > sqrtPriceLimitX96 ? sqrtPriceLimitX96 : currentSqrtPriceX96;

        impactBps = ((high - low) * 10_000) / currentSqrtPriceX96;
    }

    function _abs(int256 value) private pure returns (uint256) {
        return value >= 0 ? uint256(value) : uint256(-value);
    }
}
