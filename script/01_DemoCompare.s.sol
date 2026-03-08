// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console2} from "forge-std/Script.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {BaseScript} from "script/base/BaseScript.sol";
import {LiquidityHelpers} from "script/base/LiquidityHelpers.sol";

import {MockNewAssetToken} from "src/MockNewAssetToken.sol";
import {LaunchController} from "src/LaunchController.sol";
import {QuoteInventoryVault} from "src/QuoteInventoryVault.sol";
import {JITLiquidityVault} from "src/JITLiquidityVault.sol";
import {IssuanceModule} from "src/IssuanceModule.sol";
import {JITLaunchHook} from "src/JITLaunchHook.sol";
import {GuardrailSnapshot, LaunchConfig, LaunchPhase} from "src/types/LaunchTypes.sol";

/// @notice End-to-end local/testnet demo: baseline pool vs JIT launch pool.
contract DemoCompareScript is BaseScript {
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

    MockNewAssetToken internal tokenA;
    MockNewAssetToken internal tokenB;
    MockNewAssetToken internal token0;
    MockNewAssetToken internal token1;

    LaunchController internal controller;
    QuoteInventoryVault internal quoteVault;
    JITLiquidityVault internal jitVault;
    IssuanceModule internal issuance;
    JITLaunchHook internal hook;

    PoolKey internal baselineKey;
    PoolKey internal jitKey;
    LaunchConfig internal config;

    function run() external {
        console2.log("=== JIT Launch Detailed Demo ===");
        console2.log("Chain ID", block.chainid);
        console2.log("Start block", block.number);

        broadcaster = _startBroadcast();
        receiver = broadcaster;
        _bootstrapV4();
        _logV4Infra();

        _deployContracts();
        _logDeployedContracts();
        _configurePools();
        _logPoolConfiguration();
        _seedInventoryAndLiquidity();
        _logInventoryState("after-seed");

        uint256[] memory launchDemand = _demandSchedule();

        (bool preLaunchBlocked, string memory preLaunchReason,) = _predictSwapResult(jitKey, launchDemand[0]);
        console2.log("[pre-launch probe] blocked", preLaunchBlocked);
        console2.log("[pre-launch probe] reason", preLaunchReason);

        vm.roll(config.startBlock + config.preLaunchBlocks);
        console2.log("Rolled to launch-discovery block", block.number);
        _logGuardrailState("launch-discovery guardrails", jitKey);

        SwapStats memory baseline = _runSequence("BASELINE", baselineKey, launchDemand, true);
        SwapStats memory jit = _runSequence("JIT", jitKey, launchDemand, true);

        vm.roll(config.startBlock + config.preLaunchBlocks + config.launchBlocks);
        console2.log("Rolled to steady-state block", block.number);
        _logGuardrailState("steady-state guardrails", jitKey);
        bool steadySwapOk = _attemptSwap(jitKey, 0.5 ether, true);
        console2.log("[steady-state check] 0.5 ether swap executed", steadySwapOk);

        (, uint256 reservedToken0,, uint128 activeUnits,,) = jitVault.inventoryState(jitKey.toId());
        _logInventoryState("post-steady-check");

        _stopBroadcast();

        _printSummary(preLaunchBlocked, baseline, jit, reservedToken0, activeUnits, steadySwapOk);
    }

    function _deployContracts() internal {
        tokenA = new MockNewAssetToken("Demo Asset", "DEMO", broadcaster);
        tokenB = new MockNewAssetToken("Quote Asset", "QTE", broadcaster);

        tokenA.setMinter(broadcaster, true);
        tokenB.setMinter(broadcaster, true);
        tokenA.mint(broadcaster, 2_000_000 ether);
        tokenB.mint(broadcaster, 2_000_000 ether);

        token0 = address(tokenA) < address(tokenB) ? tokenA : tokenB;
        token1 = address(tokenA) < address(tokenB) ? tokenB : tokenA;

        controller = new LaunchController(2, 2_000, broadcaster);
        quoteVault = new QuoteInventoryVault(token1, broadcaster);
        jitVault = new JITLiquidityVault(token0, quoteVault, controller, broadcaster);
        issuance = new IssuanceModule(token0, jitVault, broadcaster);

        token0.setMinter(address(issuance), true);
        quoteVault.setReserver(address(jitVault), true);
        jitVault.setIssuanceModule(address(issuance), true);

        (address hookAddress, bytes32 salt) = _mineHookAddress();
        hook = new JITLaunchHook{salt: salt}(poolManager, controller, jitVault, issuance, broadcaster);
        require(address(hook) == hookAddress, "DemoCompare: hook mismatch");
    }

    function _mineHookAddress() internal view returns (address hookAddress, bytes32 salt) {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(poolManager, controller, jitVault, issuance, broadcaster);
        return HookMiner.find(CREATE2_FACTORY, flags, type(JITLaunchHook).creationCode, constructorArgs);
    }

    function _configurePools() internal {
        Currency currency0 = Currency.wrap(address(token0));
        Currency currency1 = Currency.wrap(address(token1));

        baselineKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(0)));
        jitKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));

        config = LaunchConfig({
            startBlock: uint64(block.number + 2),
            preLaunchBlocks: 3,
            launchBlocks: 12,
            allowlistBlocks: 0,
            initialMaxAmountIn: 1 ether,
            steadyMaxAmountIn: 3 ether,
            maxInventoryUsagePerJit: 1 ether,
            initialMaxImpactBps: 10_000,
            steadyMaxImpactBps: 10_000,
            cooldownBlocks: 0,
            maxSwapsPerBlock: 50,
            maxJitActionsPerBlock: 10,
            jitBandWidth: 120,
            preLaunchSwapsEnabled: false,
            allowlistEnabled: false
        });

        controller.registerPool(jitKey.toId(), address(hook), config);
        hook.setPoolRegistration(jitKey, true);

        issuance.configureSchedule(
            jitKey.toId(), uint64(block.number + 2), uint64(block.number + 40), 200 ether, 10 ether, true
        );
    }

    function _seedInventoryAndLiquidity() internal {
        _approveForV4(token0);
        _approveForV4(token1);

        token0.approve(address(jitVault), type(uint256).max);
        token1.approve(address(quoteVault), type(uint256).max);

        jitVault.depositToken0(jitKey.toId(), 100 ether);
        quoteVault.depositQuote(jitKey.toId(), 100 ether);

        _initPoolAndLiquidity(baselineKey, 80 ether, broadcaster);
        _initPoolAndLiquidity(jitKey, 80 ether, broadcaster);
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

    function _attemptSwap(PoolKey memory key, uint256 amountIn, bool zeroForOne) internal returns (bool ok) {
        try swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: key,
            hookData: Constants.ZERO_BYTES,
            receiver: receiver,
            deadline: type(uint256).max
        }) {
            return true;
        } catch {
            return false;
        }
    }

    function _initPoolAndLiquidity(PoolKey memory key, uint128 liquidityAmount, address recipient) internal {
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        int24 tickLower = TickMath.minUsableTick(key.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (bytes memory actions, bytes[] memory mintParams) = LiquidityHelpers.mintLiquidityParams(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            recipient,
            Constants.ZERO_BYTES
        );

        positionManager.modifyLiquidities(abi.encode(actions, mintParams), type(uint256).max);
    }

    function _avgPrice(SwapStats memory stats) internal pure returns (uint256) {
        if (stats.successfulSwaps == 0) {
            return 0;
        }
        return stats.totalPriceE18 / stats.successfulSwaps;
    }

    function _wouldSwapBeBlocked(PoolKey memory key, uint256 amountIn) internal view returns (bool) {
        (bool blocked,,) = _predictSwapResult(key, amountIn);
        return blocked;
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
        if (guardrail.phase == LaunchPhase.PreLaunch && !config.preLaunchSwapsEnabled) {
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

    function _logDeployedContracts() internal view {
        console2.log("Launch token0", address(token0));
        console2.log("Quote token1", address(token1));
        console2.log("LaunchController", address(controller));
        console2.log("QuoteInventoryVault", address(quoteVault));
        console2.log("JITLiquidityVault", address(jitVault));
        console2.log("IssuanceModule", address(issuance));
        console2.log("JITLaunchHook", address(hook));
    }

    function _logPoolConfiguration() internal view {
        console2.log("BaselinePoolId");
        console2.logBytes32(PoolId.unwrap(baselineKey.toId()));
        console2.log("JITPoolId");
        console2.logBytes32(PoolId.unwrap(jitKey.toId()));
        console2.log("startBlock", config.startBlock);
        console2.log("preLaunchBlocks", config.preLaunchBlocks);
        console2.log("launchBlocks", config.launchBlocks);
        console2.log("initialMaxAmountIn", uint256(config.initialMaxAmountIn));
        console2.log("steadyMaxAmountIn", uint256(config.steadyMaxAmountIn));
        console2.log("maxInventoryUsagePerJit", uint256(config.maxInventoryUsagePerJit));
        console2.log("jitBandWidth", uint256(config.jitBandWidth));
    }

    function _logGuardrailState(string memory label, PoolKey memory key) internal view {
        if (address(key.hooks) != address(hook)) return;
        GuardrailSnapshot memory guardrail = controller.getGuardrails(key.toId());
        console2.log(label);
        console2.log("phase", _phaseName(guardrail.phase));
        console2.log("maxAmountIn", uint256(guardrail.maxAmountIn));
        console2.log("maxImpactBps", uint256(guardrail.maxImpactBps));
        console2.log("maxSwapsPerBlock", uint256(guardrail.maxSwapsPerBlock));
        console2.log("maxJitActionsPerBlock", uint256(guardrail.maxJitActionsPerBlock));
    }

    function _logInventoryState(string memory label) internal view {
        (uint256 freeToken0, uint256 reservedToken0, uint256 reservedQuote, uint128 activeUnits, int24 centerTick, uint64 lastJitBlock) =
            jitVault.inventoryState(jitKey.toId());
        console2.log(label);
        console2.log("vault freeToken0", freeToken0);
        console2.log("vault reservedToken0", reservedToken0);
        console2.log("vault reservedQuote", reservedQuote);
        console2.log("vault activeUnits", uint256(activeUnits));
        console2.log("vault lastCenterTick", centerTick);
        console2.log("vault lastJitBlock", lastJitBlock);
        console2.log("quote freeQuote", quoteVault.availableQuote(jitKey.toId()));
        console2.log("quote reservedQuote", quoteVault.reservedQuote(jitKey.toId()));
    }

    function _printSummary(
        bool preLaunchBlocked,
        SwapStats memory baseline,
        SwapStats memory jit,
        uint256 reservedToken0,
        uint128 activeUnits,
        bool steadySwapOk
    ) internal view {
        console2.log("=== Demo Summary ===");
        console2.log("Broadcaster", broadcaster);
        console2.log("PoolManager", address(poolManager));
        console2.log("BaselinePoolId");
        console2.logBytes32(PoolId.unwrap(baselineKey.toId()));
        console2.log("JITPoolId");
        console2.logBytes32(PoolId.unwrap(jitKey.toId()));
        console2.log("Hook", address(hook));

        console2.log("Prelaunch swap blocked (JIT)", preLaunchBlocked);

        console2.log("Baseline avg execution price (1e18)", _avgPrice(baseline));
        console2.log("JIT avg execution price (1e18)", _avgPrice(jit));
        console2.log("Baseline max slippage bps", baseline.maxSlippageBps);
        console2.log("JIT max slippage bps", jit.maxSlippageBps);

        console2.log("Baseline blocked swaps", baseline.blockedSwaps);
        console2.log("JIT blocked swaps", jit.blockedSwaps);
        console2.log("Steady-state test swap executed", steadySwapOk);

        console2.log("Steady-state reserved token0 after decay", reservedToken0);
        console2.log("Steady-state active units", activeUnits);
    }
}
