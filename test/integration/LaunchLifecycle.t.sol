// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

import {BaseTest} from "test/utils/BaseTest.sol";
import {EasyPosm} from "test/utils/libraries/EasyPosm.sol";

import {LaunchController} from "src/LaunchController.sol";
import {QuoteInventoryVault} from "src/QuoteInventoryVault.sol";
import {JITLiquidityVault} from "src/JITLiquidityVault.sol";
import {JITLaunchHook} from "src/JITLaunchHook.sol";
import {LaunchConfig} from "src/types/LaunchTypes.sol";
import {IssuanceModule} from "src/IssuanceModule.sol";

contract LaunchLifecycleIntegrationTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    Currency internal currency0;
    Currency internal currency1;

    PoolKey internal baselineKey;
    PoolKey internal jitKey;

    LaunchController internal controller;
    QuoteInventoryVault internal quoteVault;
    JITLiquidityVault internal jitVault;
    JITLaunchHook internal hook;

    function setUp() public {
        deployArtifactsAndLabel();
        (currency0, currency1) = deployCurrencyPair();

        controller = new LaunchController(1, 2_000, address(this));
        quoteVault = new QuoteInventoryVault(IERC20(Currency.unwrap(currency1)), address(this));
        jitVault = new JITLiquidityVault(IERC20(Currency.unwrap(currency0)), quoteVault, controller, address(this));
        quoteVault.setReserver(address(jitVault), true);

        address hookAddress = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0xA1B2 << 144));
        bytes memory constructorArgs =
            abi.encode(poolManager, controller, jitVault, IssuanceModule(address(0)), address(this));
        deployCodeTo("JITLaunchHook.sol:JITLaunchHook", constructorArgs, hookAddress);
        hook = JITLaunchHook(hookAddress);

        baselineKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(0)));
        jitKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));

        LaunchConfig memory config = LaunchConfig({
            startBlock: uint64(block.number),
            preLaunchBlocks: 0,
            launchBlocks: 8,
            allowlistBlocks: 0,
            initialMaxAmountIn: 1 ether,
            steadyMaxAmountIn: 3 ether,
            maxInventoryUsagePerJit: 1 ether,
            initialMaxImpactBps: 10_000,
            steadyMaxImpactBps: 10_000,
            cooldownBlocks: 0,
            maxSwapsPerBlock: 20,
            maxJitActionsPerBlock: 1,
            jitBandWidth: 120,
            preLaunchSwapsEnabled: true,
            allowlistEnabled: false
        });

        controller.registerPool(jitKey.toId(), address(hook), config);
        hook.setPoolRegistration(jitKey, true);

        IERC20(Currency.unwrap(currency0)).approve(address(jitVault), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(quoteVault), type(uint256).max);

        jitVault.depositToken0(jitKey.toId(), 100 ether);
        quoteVault.depositQuote(jitKey.toId(), 100 ether);

        _initPoolAndLiquidity(baselineKey, 50 ether);
        _initPoolAndLiquidity(jitKey, 50 ether);
    }

    function testBaselineVsJITLaunchSequence() public {
        uint256[] memory amounts = new uint256[](6);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.25 ether;
        amounts[2] = 0.5 ether;
        amounts[3] = 0.75 ether;
        amounts[4] = 1.0 ether;
        amounts[5] = 2.0 ether;

        (uint256 baselineAvg, uint256 baselineMaxSlip, uint256 baselineBlocked) =
            _runSequence(baselineKey, amounts, true);
        (uint256 jitAvg, uint256 jitMaxSlip, uint256 jitBlocked) = _runSequence(jitKey, amounts, true);

        assertEq(baselineBlocked, 0);
        assertGt(jitBlocked, baselineBlocked);
        assertLe(jitMaxSlip, baselineMaxSlip);

        // sanity check: both pools execute at least one trade with measurable price
        assertGt(baselineAvg, 0);
        assertGt(jitAvg, 0);
    }

    function _runSequence(PoolKey memory key, uint256[] memory amounts, bool zeroForOne)
        internal
        returns (uint256 avgPriceE18, uint256 maxSlippageBps, uint256 blocked)
    {
        uint256 valid;
        uint256 firstPrice;
        uint256 totalPrice;

        for (uint256 i = 0; i < amounts.length; i++) {
            try swapRouter.swapExactTokensForTokens({
                amountIn: amounts[i],
                amountOutMin: 0,
                zeroForOne: zeroForOne,
                poolKey: key,
                hookData: Constants.ZERO_BYTES,
                receiver: address(this),
                deadline: block.timestamp + 1
            }) returns (
                BalanceDelta delta
            ) {
                uint256 output = zeroForOne ? uint256(int256(delta.amount1())) : uint256(int256(delta.amount0()));
                uint256 price = (amounts[i] * 1e18) / output;

                if (firstPrice == 0) {
                    firstPrice = price;
                }

                uint256 slippageBps = price > firstPrice
                    ? ((price - firstPrice) * 10_000) / firstPrice
                    : ((firstPrice - price) * 10_000) / firstPrice;

                if (slippageBps > maxSlippageBps) {
                    maxSlippageBps = slippageBps;
                }

                totalPrice += price;
                valid += 1;
            } catch {
                blocked += 1;
            }
        }

        if (valid > 0) {
            avgPriceE18 = totalPrice / valid;
        }
    }

    function _initPoolAndLiquidity(PoolKey memory key, uint128 liquidityAmount) internal {
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        int24 tickLower = TickMath.minUsableTick(key.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        positionManager.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }
}
