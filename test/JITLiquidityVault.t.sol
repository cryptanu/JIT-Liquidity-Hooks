// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {LaunchController} from "src/LaunchController.sol";
import {JITLiquidityVault} from "src/JITLiquidityVault.sol";
import {QuoteInventoryVault} from "src/QuoteInventoryVault.sol";
import {MockNewAssetToken} from "src/MockNewAssetToken.sol";
import {IJITLiquidityVault} from "src/interfaces/IJITLiquidityVault.sol";
import {LaunchConfig} from "src/types/LaunchTypes.sol";

contract JITLiquidityVaultTest is Test {
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

        poolId = PoolId.wrap(keccak256("VAULT_POOL"));
        controller.registerPool(poolId, hook, _config());

        token0.mint(address(this), 1_000 ether);
        quote.mint(address(this), 1_000 ether);

        token0.approve(address(vault), type(uint256).max);
        quote.approve(address(quoteVault), type(uint256).max);

        vault.depositToken0(poolId, 100 ether);
        quoteVault.depositQuote(poolId, 100 ether);
    }

    function testQuoteAddLiquidityBounded() public view {
        IJITLiquidityVault.JITQuote memory quoteData = vault.quoteAddLiquidityForTick(poolId, 100, 120, 20 ether);
        assertEq(quoteData.token0ToUse, 20 ether);
        assertEq(quoteData.quoteToUse, 20 ether);
    }

    function testExecuteAddAndRemoveAccounting() public {
        vm.prank(hook);
        vault.executeJITAdd(poolId, 150, 120, 30 ether);

        (uint256 freeToken0, uint256 reservedToken0, uint256 reservedQuote, uint128 activeLiquidityUnits,,) =
            vault.inventoryState(poolId);

        assertEq(freeToken0, 70 ether);
        assertEq(reservedToken0, 30 ether);
        assertEq(reservedQuote, 30 ether);
        assertEq(activeLiquidityUnits, 30 ether);

        vm.prank(hook);
        (uint256 token0Released, uint256 quoteReleased) = vault.executeJITRemove(poolId, 5_000);

        assertEq(token0Released, 15 ether);
        assertEq(quoteReleased, 15 ether);

        (freeToken0, reservedToken0, reservedQuote, activeLiquidityUnits,,) = vault.inventoryState(poolId);

        assertEq(freeToken0, 85 ether);
        assertEq(reservedToken0, 15 ether);
        assertEq(reservedQuote, 15 ether);
        assertEq(activeLiquidityUnits, 15 ether);
    }

    function testUnauthorizedHookReverts() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        vault.executeJITAdd(poolId, 120, 120, 10 ether);
    }

    function testCreditIssuedToken0OnlyIssuer() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        vault.creditIssuedToken0(poolId, 1 ether);

        vault.setIssuanceModule(address(this), true);
        vault.creditIssuedToken0(poolId, 2 ether);

        (uint256 freeToken0,,,,,) = vault.inventoryState(poolId);
        assertEq(freeToken0, 102 ether);
    }

    function testZeroInventoryDoesNotOverdraw() public {
        PoolId emptyPool = PoolId.wrap(keccak256("EMPTY"));
        controller.registerPool(emptyPool, hook, _config());

        vm.prank(hook);
        vault.executeJITAdd(emptyPool, 100, 120, 10 ether);

        (uint256 freeToken0, uint256 reservedToken0, uint256 reservedQuote,,,) = vault.inventoryState(emptyPool);
        assertEq(freeToken0, 0);
        assertEq(reservedToken0, 0);
        assertEq(reservedQuote, 0);
    }

    function _config() internal view returns (LaunchConfig memory cfg) {
        cfg = LaunchConfig({
            startBlock: uint64(block.number + 1),
            preLaunchBlocks: 1,
            launchBlocks: 20,
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
