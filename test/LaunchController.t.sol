// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {LaunchController} from "src/LaunchController.sol";
import {LaunchConfig, GuardrailSnapshot, LaunchPhase} from "src/types/LaunchTypes.sol";

contract LaunchControllerTest is Test {
    LaunchController internal controller;

    PoolId internal poolId;
    address internal hook = address(0xBEEF);

    function setUp() public {
        controller = new LaunchController(5, 2_000, address(this));
        poolId = PoolId.wrap(keccak256("POOL_A"));

        controller.registerPool(poolId, hook, _baseConfig());
    }

    function testPhaseBoundariesAreDeterministic() public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);

        vm.roll(cfg.startBlock - 1);
        assertEq(uint256(controller.getPhase(poolId)), uint256(LaunchPhase.PreLaunch));

        vm.roll(cfg.startBlock + cfg.preLaunchBlocks - 1);
        assertEq(uint256(controller.getPhase(poolId)), uint256(LaunchPhase.PreLaunch));

        vm.roll(cfg.startBlock + cfg.preLaunchBlocks);
        assertEq(uint256(controller.getPhase(poolId)), uint256(LaunchPhase.LaunchDiscovery));

        vm.roll(cfg.startBlock + cfg.preLaunchBlocks + cfg.launchBlocks);
        assertEq(uint256(controller.getPhase(poolId)), uint256(LaunchPhase.SteadyState));
    }

    function testExactMaxAmountInBoundaryPasses() public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);
        vm.roll(cfg.startBlock);

        vm.prank(hook);
        controller.enforceSwapGuardrails(poolId, address(0x1), cfg.initialMaxAmountIn, cfg.initialMaxImpactBps);
    }

    function testAmountAboveBoundaryReverts() public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);
        vm.roll(cfg.startBlock);

        vm.prank(hook);
        vm.expectRevert();
        controller.enforceSwapGuardrails(
            poolId, address(0x1), uint256(cfg.initialMaxAmountIn) + 1, cfg.initialMaxImpactBps
        );
    }

    function testImpactBoundaryReverts() public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);
        vm.roll(cfg.startBlock);

        vm.prank(hook);
        vm.expectRevert();
        controller.enforceSwapGuardrails(
            poolId, address(0x1), cfg.initialMaxAmountIn, uint256(cfg.initialMaxImpactBps) + 1
        );
    }

    function testCooldownBoundary() public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);
        vm.roll(cfg.startBlock);

        address trader = address(0x1234);

        vm.prank(hook);
        controller.enforceSwapGuardrails(poolId, trader, 1 ether, 10);

        vm.prank(hook);
        vm.expectRevert();
        controller.enforceSwapGuardrails(poolId, trader, 1 ether, 10);

        vm.roll(block.number + cfg.cooldownBlocks);
        vm.prank(hook);
        controller.enforceSwapGuardrails(poolId, trader, 1 ether, 10);
    }

    function testSwapCapPerBlockBoundary() public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);
        vm.roll(cfg.startBlock);

        vm.prank(hook);
        controller.enforceSwapGuardrails(poolId, address(0x1), 1 ether, 10);

        vm.prank(hook);
        controller.enforceSwapGuardrails(poolId, address(0x2), 1 ether, 10);

        vm.prank(hook);
        vm.expectRevert();
        controller.enforceSwapGuardrails(poolId, address(0x3), 1 ether, 10);
    }

    function testAllowlistBoundary() public {
        PoolId allowlistPool = PoolId.wrap(keccak256("POOL_ALLOW"));
        LaunchConfig memory cfg = _baseConfig();
        cfg.allowlistEnabled = true;
        cfg.allowlistBlocks = 10;

        controller.registerPool(allowlistPool, hook, cfg);
        vm.roll(cfg.startBlock);

        vm.prank(hook);
        vm.expectRevert();
        controller.enforceSwapGuardrails(allowlistPool, address(0x222), 1 ether, 10);

        controller.setAllowlist(allowlistPool, address(0x222), true);

        vm.prank(hook);
        controller.enforceSwapGuardrails(allowlistPool, address(0x222), 1 ether, 10);
    }

    function testRepeatedJitCallsSameBlockBlocked() public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);
        vm.roll(cfg.startBlock + cfg.preLaunchBlocks);

        vm.prank(hook);
        bool first = controller.consumeJitAction(poolId);
        assertTrue(first);

        vm.prank(hook);
        vm.expectRevert();
        controller.consumeJitAction(poolId);
    }

    function testUnauthorizedUpdateAndHookCallsRevert() public {
        vm.prank(address(0xCAFE));
        vm.expectRevert();
        controller.setPoolHook(poolId, address(0x9999));

        vm.prank(address(0xCAFE));
        vm.expectRevert();
        controller.enforceSwapGuardrails(poolId, address(0x1), 1 ether, 1);
    }

    function testConfigUpdateDelayAndCaps() public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);
        LaunchConfig memory next = cfg;
        next.steadyMaxAmountIn = uint128((uint256(cfg.steadyMaxAmountIn) * 11) / 10);

        controller.queueConfigUpdate(poolId, next);

        vm.expectRevert();
        controller.executeConfigUpdate(poolId);

        vm.roll(block.number + 5);
        controller.executeConfigUpdate(poolId);

        LaunchConfig memory updated = controller.getLaunchConfig(poolId);
        assertEq(updated.steadyMaxAmountIn, next.steadyMaxAmountIn);
    }

    function testConfigUpdateTooLargeReverts() public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);
        LaunchConfig memory next = cfg;
        next.steadyMaxAmountIn = cfg.steadyMaxAmountIn * 3;

        vm.expectRevert();
        controller.queueConfigUpdate(poolId, next);
    }

    function testFuzzPhaseDeterminism(uint64 offset) public {
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);
        uint64 target = cfg.startBlock + (offset % (cfg.preLaunchBlocks + cfg.launchBlocks + 50));
        vm.roll(target);

        LaunchPhase p1 = controller.getPhase(poolId);
        LaunchPhase p2 = controller.getPhase(poolId);

        assertEq(uint256(p1), uint256(p2));
    }

    function _baseConfig() internal view returns (LaunchConfig memory cfg) {
        cfg = LaunchConfig({
            startBlock: uint64(block.number + 10),
            preLaunchBlocks: 5,
            launchBlocks: 20,
            allowlistBlocks: 0,
            initialMaxAmountIn: 10 ether,
            steadyMaxAmountIn: 100 ether,
            maxInventoryUsagePerJit: 5 ether,
            initialMaxImpactBps: 100,
            steadyMaxImpactBps: 1_000,
            cooldownBlocks: 2,
            maxSwapsPerBlock: 2,
            maxJitActionsPerBlock: 1,
            jitBandWidth: 120,
            preLaunchSwapsEnabled: true,
            allowlistEnabled: false
        });
    }
}
