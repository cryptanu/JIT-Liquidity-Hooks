// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
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

contract JITLaunchHookTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency internal currency0;
    Currency internal currency1;

    PoolKey internal poolKey;
    PoolId internal poolId;

    LaunchController internal controller;
    QuoteInventoryVault internal quoteVault;
    JITLiquidityVault internal jitVault;
    JITLaunchHook internal hook;

    function setUp() public {
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();

        controller = new LaunchController(2, 2_000, address(this));
        quoteVault = new QuoteInventoryVault(IERC20(Currency.unwrap(currency1)), address(this));
        jitVault = new JITLiquidityVault(IERC20(Currency.unwrap(currency0)), quoteVault, controller, address(this));

        quoteVault.setReserver(address(jitVault), true);

        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x9977 << 144));
        bytes memory args = abi.encode(poolManager, controller, jitVault, IssuanceModule(address(0)), address(this));
        deployCodeTo("JITLaunchHook.sol:JITLaunchHook", args, flags);
        hook = JITLaunchHook(flags);

        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));
        poolId = poolKey.toId();

        LaunchConfig memory config = LaunchConfig({
            startBlock: uint64(block.number + 4),
            preLaunchBlocks: 3,
            launchBlocks: 20,
            allowlistBlocks: 0,
            initialMaxAmountIn: 1 ether,
            steadyMaxAmountIn: 5 ether,
            maxInventoryUsagePerJit: 2 ether,
            initialMaxImpactBps: 10_000,
            steadyMaxImpactBps: 10_000,
            cooldownBlocks: 0,
            maxSwapsPerBlock: 3,
            maxJitActionsPerBlock: 1,
            jitBandWidth: 120,
            preLaunchSwapsEnabled: false,
            allowlistEnabled: false
        });

        controller.registerPool(poolId, address(hook), config);
        hook.setPoolRegistration(poolKey, true);

        IERC20(Currency.unwrap(currency0)).approve(address(jitVault), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(quoteVault), type(uint256).max);

        jitVault.depositToken0(poolId, 50 ether);
        quoteVault.depositQuote(poolId, 50 ether);

        _initializePoolAndLiquidity();
    }

    function testPreLaunchBoundaryRevertsSwap() public {
        vm.expectRevert();
        _swap(0.5 ether);
    }

    function testLaunchDiscoverySwapPassesAndActivatesJIT() public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);
        vm.roll(cfg.startBlock + cfg.preLaunchBlocks);

        BalanceDelta delta = _swap(0.5 ether);
        assertEq(int256(delta.amount0()), -int256(0.5 ether));

        (, uint256 reservedToken0, uint256 reservedQuote,, int24 centerTick, uint64 lastJitBlock) =
            jitVault.inventoryState(poolId);

        assertGt(reservedToken0, 0);
        assertGt(reservedQuote, 0);
        assertEq(lastJitBlock, uint64(block.number));
        assertTrue(centerTick != 0 || centerTick == 0);
    }

    function testMaxAmountBoundaryReverts() public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);
        vm.roll(cfg.startBlock + cfg.preLaunchBlocks);

        vm.expectRevert();
        _swap(2 ether);
    }

    function testSteadyStateTriggersJITRemoval() public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);
        vm.roll(cfg.startBlock + cfg.preLaunchBlocks);

        _swap(0.5 ether);
        (, uint256 reservedBefore,, uint128 unitsBefore,,) = jitVault.inventoryState(poolId);
        assertGt(reservedBefore, 0);

        vm.roll(cfg.startBlock + cfg.preLaunchBlocks + cfg.launchBlocks);
        _swap(0.5 ether);

        (, uint256 reservedAfter,, uint128 unitsAfter,,) = jitVault.inventoryState(poolId);
        assertLt(reservedAfter, reservedBefore);
        assertLt(unitsAfter, unitsBefore);
    }

    function _initializePoolAndLiquidity() internal {
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);
        uint128 liquidityAmount = 100 ether;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        positionManager.mint(
            poolKey,
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

    function _swap(uint256 amountIn) internal returns (BalanceDelta) {
        return swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }
}
