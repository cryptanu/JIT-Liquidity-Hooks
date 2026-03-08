// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console2} from "forge-std/Script.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {BaseScript} from "script/base/BaseScript.sol";

import {MockNewAssetToken} from "src/MockNewAssetToken.sol";
import {LaunchController} from "src/LaunchController.sol";
import {QuoteInventoryVault} from "src/QuoteInventoryVault.sol";
import {JITLiquidityVault} from "src/JITLiquidityVault.sol";
import {IssuanceModule} from "src/IssuanceModule.sol";
import {JITLaunchHook} from "src/JITLaunchHook.sol";
import {GuardrailSnapshot, LaunchConfig, LaunchPhase} from "src/types/LaunchTypes.sol";

/// @notice Runs launch-demand swap comparison against already deployed stack loaded from `.env`.
/// No fresh contract deployments are performed in this script.
contract DemoCompareExistingScript is BaseScript {
    using PoolIdLibrary for PoolKey;

    struct SwapStats {
        uint256 totalPriceE18;
        uint256 maxSlippageBps;
        uint256 firstPriceE18;
        uint256 successfulSwaps;
        uint256 blockedSwaps;
    }

    address internal broadcaster;
    address internal receiver;

    MockNewAssetToken internal token0;
    MockNewAssetToken internal token1;

    LaunchController internal controller;
    QuoteInventoryVault internal quoteVault;
    JITLiquidityVault internal jitVault;
    IssuanceModule internal issuance;
    JITLaunchHook internal hook;

    PoolKey internal baselineKey;
    PoolKey internal jitKey;

    function run() external {
        console2.log("=== Existing-Stack JIT Demo (No Deploy) ===");
        console2.log("Chain ID", block.chainid);
        console2.log("Start block", block.number);

        broadcaster = _startBroadcast();
        receiver = broadcaster;

        _bootstrapV4();
        _logV4Infra();
        _loadFromEnv();
        _configurePoolKeys();
        _logLoadedContracts();
        _approveForV4(token0);
        _approveForV4(token1);

        _logGuardrailState("current guardrails", jitKey);
        _logInventoryState("pre-swap inventory snapshot");

        uint256[] memory launchDemand = _demandSchedule();
        SwapStats memory baseline = _runSequence("BASELINE_EXISTING", baselineKey, launchDemand, true);
        SwapStats memory jit = _runSequence("JIT_EXISTING", jitKey, launchDemand, true);

        _logInventoryState("post-swap inventory snapshot");
        _stopBroadcast();
        _printSummary(baseline, jit);
    }

    function _loadFromEnv() internal {
        address launchTokenAddress = vm.envAddress("LAUNCH_TOKEN_ADDRESS");
        address quoteTokenAddress = vm.envAddress("QUOTE_TOKEN_ADDRESS");

        controller = LaunchController(vm.envAddress("LAUNCH_CONTROLLER_ADDRESS"));
        quoteVault = QuoteInventoryVault(vm.envAddress("QUOTE_INVENTORY_VAULT_ADDRESS"));
        jitVault = JITLiquidityVault(vm.envAddress("JIT_LIQUIDITY_VAULT_ADDRESS"));
        issuance = IssuanceModule(vm.envAddress("ISSUANCE_MODULE_ADDRESS"));
        hook = JITLaunchHook(vm.envAddress("JIT_LAUNCH_HOOK_ADDRESS"));

        address vaultToken0 = address(jitVault.token0());
        address vaultQuote = address(quoteVault.quoteAsset());

        // Require env to point to a coherent stack.
        require(
            (vaultToken0 == launchTokenAddress || vaultToken0 == quoteTokenAddress)
                && (vaultQuote == launchTokenAddress || vaultQuote == quoteTokenAddress),
            "DemoExisting: env stack mismatch"
        );
        require(vaultToken0 != vaultQuote, "DemoExisting: invalid token pair");
        require(vaultToken0 < vaultQuote, "DemoExisting: token order mismatch; use sorted token0/token1 stack");

        token0 = MockNewAssetToken(vaultToken0);
        token1 = MockNewAssetToken(vaultQuote);
    }

    function _configurePoolKeys() internal {
        Currency currency0 = Currency.wrap(address(token0));
        Currency currency1 = Currency.wrap(address(token1));

        baselineKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(0)));
        jitKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));
    }

    function _demandSchedule() internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](6);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.25 ether;
        amounts[2] = 0.5 ether;
        amounts[3] = 0.75 ether;
        amounts[4] = 1.0 ether;
        amounts[5] = 2.0 ether;
    }

    function _runSequence(string memory label, PoolKey memory key, uint256[] memory amounts, bool zeroForOne)
        internal
        returns (SwapStats memory stats)
    {
        for (uint256 i = 0; i < amounts.length; i++) {
            (bool blocked, string memory reason, GuardrailSnapshot memory guardrail) = _predictSwapResult(key, amounts[i]);

            console2.log("----");
            console2.log("pool", label);
            console2.log("swap index", i);
            console2.log("block", block.number);
            console2.log("amountIn", amounts[i]);

            if (address(key.hooks) == address(hook)) {
                console2.log("phase", _phaseName(guardrail.phase));
                console2.log("maxAmountIn", uint256(guardrail.maxAmountIn));
                console2.log("maxImpactBps", uint256(guardrail.maxImpactBps));
            }

            if (blocked) {
                console2.log("status", "BLOCKED");
                console2.log("reason", reason);
                stats.blockedSwaps += 1;
                continue;
            }

            (bool ok, uint256 priceE18) = _swapPrice(key, amounts[i], zeroForOne);
            if (!ok) {
                console2.log("status", "FAILED");
                console2.log("reason", "swap call failed");
                stats.blockedSwaps += 1;
                continue;
            }

            if (stats.firstPriceE18 == 0) {
                stats.firstPriceE18 = priceE18;
            }

            uint256 slippageBps = priceE18 > stats.firstPriceE18
                ? ((priceE18 - stats.firstPriceE18) * 10_000) / stats.firstPriceE18
                : ((stats.firstPriceE18 - priceE18) * 10_000) / stats.firstPriceE18;

            if (slippageBps > stats.maxSlippageBps) {
                stats.maxSlippageBps = slippageBps;
            }

            stats.totalPriceE18 += priceE18;
            stats.successfulSwaps += 1;

            console2.log("status", "EXECUTED");
            console2.log("executionPriceE18", priceE18);
            console2.log("slippageBpsFromFirst", slippageBps);
        }
    }

    function _swapPrice(PoolKey memory key, uint256 amountIn, bool zeroForOne)
        internal
        returns (bool ok, uint256 priceE18)
    {
        try swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: key,
            hookData: Constants.ZERO_BYTES,
            receiver: receiver,
            deadline: type(uint256).max
        }) returns (
            BalanceDelta delta
        ) {
            uint256 output = zeroForOne ? uint256(int256(delta.amount1())) : uint256(int256(delta.amount0()));
            if (output == 0) {
                return (false, 0);
            }
            return (true, (amountIn * 1e18) / output);
        } catch {
            return (false, 0);
        }
    }

    function _predictSwapResult(PoolKey memory key, uint256 amountIn)
        internal
        view
        returns (bool blocked, string memory reason, GuardrailSnapshot memory guardrail)
    {
        if (address(key.hooks) != address(hook)) {
            return (false, "no launch hook", guardrail);
        }

        guardrail = controller.getGuardrails(key.toId());
        LaunchConfig memory cfg = controller.getLaunchConfig(key.toId());

        if (guardrail.phase == LaunchPhase.PreLaunch && !cfg.preLaunchSwapsEnabled) {
            return (true, "pre-launch swaps disabled", guardrail);
        }

        if (guardrail.allowlistActive && !controller.allowlisted(key.toId(), receiver)) {
            return (true, "allowlist required", guardrail);
        }

        if (amountIn > guardrail.maxAmountIn) {
            return (true, "amount exceeds maxAmountIn", guardrail);
        }

        return (false, "guardrails passed", guardrail);
    }

    function _avgPrice(SwapStats memory stats) internal pure returns (uint256) {
        if (stats.successfulSwaps == 0) {
            return 0;
        }
        return stats.totalPriceE18 / stats.successfulSwaps;
    }

    function _phaseName(LaunchPhase phase) internal pure returns (string memory) {
        if (phase == LaunchPhase.PreLaunch) return "PreLaunch";
        if (phase == LaunchPhase.LaunchDiscovery) return "LaunchDiscovery";
        return "SteadyState";
    }

    function _logV4Infra() internal view {
        console2.log("Infra / Permit2", address(permit2));
        console2.log("Infra / PoolManager", address(poolManager));
        console2.log("Infra / PositionManager", address(positionManager));
        console2.log("Infra / SwapRouter", address(swapRouter));
    }

    function _logLoadedContracts() internal view {
        console2.log("Loaded token0", address(token0));
        console2.log("Loaded token1", address(token1));
        console2.log("Loaded LaunchController", address(controller));
        console2.log("Loaded QuoteInventoryVault", address(quoteVault));
        console2.log("Loaded JITLiquidityVault", address(jitVault));
        console2.log("Loaded IssuanceModule", address(issuance));
        console2.log("Loaded JITLaunchHook", address(hook));
        console2.logBytes32(PoolId.unwrap(jitKey.toId()));
    }

    function _logGuardrailState(string memory label, PoolKey memory key) internal view {
        GuardrailSnapshot memory g = controller.getGuardrails(key.toId());
        console2.log(label);
        console2.log("phase", _phaseName(g.phase));
        console2.log("maxAmountIn", uint256(g.maxAmountIn));
        console2.log("maxImpactBps", uint256(g.maxImpactBps));
        console2.log("maxSwapsPerBlock", uint256(g.maxSwapsPerBlock));
        console2.log("maxJitActionsPerBlock", uint256(g.maxJitActionsPerBlock));
        console2.log("jitBandWidth", uint256(g.jitBandWidth));
    }

    function _logInventoryState(string memory label) internal view {
        PoolId poolId = jitKey.toId();
        (
            uint256 freeToken0,
            uint256 reservedToken0,
            uint256 reservedQuote,
            uint128 activeUnits,
            int24 lastCenterTick,
            uint64 lastJitBlock
        ) = jitVault.inventoryState(poolId);
        uint256 freeQuote = quoteVault.availableQuote(poolId);

        console2.log(label);
        console2.log("vault freeToken0", freeToken0);
        console2.log("vault reservedToken0", reservedToken0);
        console2.log("vault reservedQuote", reservedQuote);
        console2.log("vault activeUnits", uint256(activeUnits));
        console2.log("vault lastCenterTick", lastCenterTick);
        console2.log("vault lastJitBlock", uint256(lastJitBlock));
        console2.log("quote freeQuote", freeQuote);
    }

    function _printSummary(SwapStats memory baseline, SwapStats memory jit) internal view {
        console2.log("=== Existing-Stack Demo Summary ===");
        console2.log("Broadcaster", broadcaster);
        console2.log("PoolManager", address(poolManager));
        console2.log("BaselinePoolId");
        console2.logBytes32(PoolId.unwrap(baselineKey.toId()));
        console2.log("JITPoolId");
        console2.logBytes32(PoolId.unwrap(jitKey.toId()));
        console2.log("Hook", address(hook));

        console2.log("Baseline avg execution price (1e18)", _avgPrice(baseline));
        console2.log("JIT avg execution price (1e18)", _avgPrice(jit));
        console2.log("Baseline max slippage bps", baseline.maxSlippageBps);
        console2.log("JIT max slippage bps", jit.maxSlippageBps);
        console2.log("Baseline blocked swaps", baseline.blockedSwaps);
        console2.log("JIT blocked swaps", jit.blockedSwaps);
    }
}
