// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {LaunchController} from "src/LaunchController.sol";
import {JITLiquidityVault} from "src/JITLiquidityVault.sol";
import {QuoteInventoryVault} from "src/QuoteInventoryVault.sol";
import {MockNewAssetToken} from "src/MockNewAssetToken.sol";
import {LaunchConfig, GuardrailSnapshot} from "src/types/LaunchTypes.sol";

contract JITFuzzTest is Test {
    LaunchController internal controller;
    JITLiquidityVault internal vault;
    QuoteInventoryVault internal quoteVault;
    MockNewAssetToken internal token0;
    MockNewAssetToken internal quote;

    PoolId internal poolId;
    address internal hook = address(0xBEEF);

    function setUp() public {
        token0 = new MockNewAssetToken("Launch", "LCH", address(this));
        quote = new MockNewAssetToken("Quote", "QTE", address(this));
        token0.setMinter(address(this), true);
        quote.setMinter(address(this), true);

        controller = new LaunchController(1, 2_000, address(this));
        quoteVault = new QuoteInventoryVault(quote, address(this));
        vault = new JITLiquidityVault(token0, quoteVault, controller, address(this));
        quoteVault.setReserver(address(vault), true);

        poolId = PoolId.wrap(keccak256("FUZZ_POOL"));
        controller.registerPool(poolId, hook, _config());

        token0.mint(address(this), 10_000 ether);
        quote.mint(address(this), 10_000 ether);

        token0.approve(address(vault), type(uint256).max);
        quote.approve(address(quoteVault), type(uint256).max);
    }

    function testFuzz_JITAddsAndRemovesStayWithinCaps(
        uint96 deposit0,
        uint96 depositQ,
        uint96 maxUsage,
        uint16 releaseBps,
        int24 tick
    ) public {
        deposit0 = uint96(bound(uint256(deposit0), 1, 1_000 ether));
        depositQ = uint96(bound(uint256(depositQ), 1, 1_000 ether));
        maxUsage = uint96(bound(uint256(maxUsage), 1, 1_000 ether));
        releaseBps = uint16(bound(uint256(releaseBps), 0, 10_000));
        if (tick < type(int24).min + 120) tick = type(int24).min + 120;
        if (tick > type(int24).max - 120) tick = type(int24).max - 120;

        vault.depositToken0(poolId, deposit0);
        quoteVault.depositQuote(poolId, depositQ);

        vm.prank(hook);
        vault.executeJITAdd(poolId, tick, 120, maxUsage);

        (uint256 free0, uint256 reserved0, uint256 reservedQuote,,,) = vault.inventoryState(poolId);

        assertLe(reserved0, maxUsage);
        assertLe(reservedQuote, maxUsage);
        assertEq(free0 + reserved0, deposit0);

        vm.prank(hook);
        vault.executeJITRemove(poolId, releaseBps);

        (free0, reserved0, reservedQuote,,,) = vault.inventoryState(poolId);
        assertEq(free0 + reserved0, deposit0);

        uint256 freeQuote = quoteVault.availableQuote(poolId);
        assertEq(freeQuote + reservedQuote, depositQ);
    }

    function testFuzz_GuardrailsMonotonicInDiscovery(uint32 a, uint32 b) public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);

        uint256 launchStart = uint256(cfg.startBlock) + uint256(cfg.preLaunchBlocks);

        uint256 e1 = bound(uint256(a), 0, cfg.launchBlocks - 1);
        uint256 e2 = bound(uint256(b), 0, cfg.launchBlocks - 1);

        if (e1 > e2) {
            (e1, e2) = (e2, e1);
        }

        vm.roll(launchStart + e1);
        GuardrailSnapshot memory g1 = controller.getGuardrails(poolId);

        vm.roll(launchStart + e2);
        GuardrailSnapshot memory g2 = controller.getGuardrails(poolId);

        assertLe(g1.maxAmountIn, g2.maxAmountIn);
        assertLe(g1.maxImpactBps, g2.maxImpactBps);
    }

    function testFuzz_PhaseDeterministicForSameBlock(uint64 offset) public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);
        uint64 target = cfg.startBlock + (offset % (cfg.preLaunchBlocks + cfg.launchBlocks + 20));

        vm.roll(target);
        uint256 p1 = uint256(controller.getPhase(poolId));
        uint256 p2 = uint256(controller.getPhase(poolId));

        assertEq(p1, p2);
    }

    function _config() internal view returns (LaunchConfig memory cfg) {
        cfg = LaunchConfig({
            startBlock: uint64(block.number + 10),
            preLaunchBlocks: 4,
            launchBlocks: 40,
            allowlistBlocks: 0,
            initialMaxAmountIn: 10 ether,
            steadyMaxAmountIn: 100 ether,
            maxInventoryUsagePerJit: 5 ether,
            initialMaxImpactBps: 100,
            steadyMaxImpactBps: 1_000,
            cooldownBlocks: 0,
            maxSwapsPerBlock: 10,
            maxJitActionsPerBlock: 1,
            jitBandWidth: 120,
            preLaunchSwapsEnabled: true,
            allowlistEnabled: false
        });
    }
}
