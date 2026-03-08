// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {LaunchController} from "src/LaunchController.sol";
import {JITLiquidityVault} from "src/JITLiquidityVault.sol";
import {QuoteInventoryVault} from "src/QuoteInventoryVault.sol";
import {MockNewAssetToken} from "src/MockNewAssetToken.sol";
import {LaunchConfig, GuardrailSnapshot} from "src/types/LaunchTypes.sol";

contract JITInvariantHandler is Test {
    LaunchController public immutable controller;
    JITLiquidityVault public immutable vault;
    QuoteInventoryVault public immutable quoteVault;

    PoolId public immutable poolId;

    address internal immutable traderA;
    address internal immutable traderB;

    constructor(
        LaunchController _controller,
        JITLiquidityVault _vault,
        QuoteInventoryVault _quoteVault,
        PoolId _poolId
    ) {
        controller = _controller;
        vault = _vault;
        quoteVault = _quoteVault;
        poolId = _poolId;

        traderA = address(0xA1);
        traderB = address(0xB2);
    }

    function stepAdd(uint96 maxUsage, int24 tick) external {
        uint128 boundedUsage = uint128(bound(uint256(maxUsage), 0, 50 ether));

        try vault.executeJITAdd(poolId, tick, 120, boundedUsage) {} catch {}
    }

    function stepRemove(uint16 releaseBps) external {
        uint16 bps = uint16(bound(uint256(releaseBps), 0, 10_000));

        try vault.executeJITRemove(poolId, bps) {} catch {}
    }

    function stepSwapGuardrails(uint128 amountIn, uint16 impactBps, bool useTraderA) external {
        uint256 amount = bound(uint256(amountIn), 0, 20 ether);
        uint256 impact = bound(uint256(impactBps), 0, 2_000);
        address trader = useTraderA ? traderA : traderB;

        try controller.enforceSwapGuardrails(poolId, trader, amount, impact) {} catch {}
    }

    function stepConsumeJit() external {
        try controller.consumeJitAction(poolId) {} catch {}
    }

    function stepRoll(uint8 blocksForward) external {
        vm.roll(block.number + (uint256(blocksForward) % 3));
    }
}

contract JITInvariantTest is StdInvariant, Test {
    uint256 internal constant INITIAL_TOKEN0 = 500 ether;
    uint256 internal constant INITIAL_QUOTE = 500 ether;

    LaunchController internal controller;
    JITLiquidityVault internal vault;
    QuoteInventoryVault internal quoteVault;
    MockNewAssetToken internal token0;
    MockNewAssetToken internal quote;

    PoolId internal poolId;

    JITInvariantHandler internal handler;

    function setUp() public {
        token0 = new MockNewAssetToken("Launch", "LCH", address(this));
        quote = new MockNewAssetToken("Quote", "QTE", address(this));

        token0.setMinter(address(this), true);
        quote.setMinter(address(this), true);

        controller = new LaunchController(1, 2_000, address(this));
        quoteVault = new QuoteInventoryVault(quote, address(this));
        vault = new JITLiquidityVault(token0, quoteVault, controller, address(this));

        quoteVault.setReserver(address(vault), true);

        poolId = PoolId.wrap(keccak256("INVARIANT_POOL"));

        handler = new JITInvariantHandler(controller, vault, quoteVault, poolId);

        controller.registerPool(poolId, address(handler), _config());

        token0.mint(address(this), INITIAL_TOKEN0);
        quote.mint(address(this), INITIAL_QUOTE);

        token0.approve(address(vault), type(uint256).max);
        quote.approve(address(quoteVault), type(uint256).max);

        vault.depositToken0(poolId, INITIAL_TOKEN0);
        quoteVault.depositQuote(poolId, INITIAL_QUOTE);

        targetContract(address(handler));
    }

    function invariant_vaultInventoryNeverUnderflows() public view {
        (uint256 freeToken0, uint256 reservedToken0,, uint128 activeLiquidityUnits,,) = vault.inventoryState(poolId);

        assertEq(freeToken0 + reservedToken0, INITIAL_TOKEN0);
        assertLe(reservedToken0, INITIAL_TOKEN0);
        assertLe(activeLiquidityUnits, uint128(INITIAL_TOKEN0));
    }

    function invariant_quoteInventoryNeverUnderflows() public view {
        uint256 freeQuote = quoteVault.availableQuote(poolId);
        uint256 reservedQuote = quoteVault.reservedQuote(poolId);

        assertEq(freeQuote + reservedQuote, INITIAL_QUOTE);
        assertLe(reservedQuote, INITIAL_QUOTE);
    }

    function invariant_phaseAndGuardrailsDeterministic() public view {
        uint256 p1 = uint256(controller.getPhase(poolId));
        uint256 p2 = uint256(controller.getPhase(poolId));
        assertEq(p1, p2);

        GuardrailSnapshot memory g = controller.getGuardrails(poolId);
        LaunchConfig memory cfg = controller.getLaunchConfig(poolId);

        assertGe(g.maxAmountIn, cfg.initialMaxAmountIn);
        assertLe(g.maxAmountIn, cfg.steadyMaxAmountIn);
        assertGe(g.maxImpactBps, cfg.initialMaxImpactBps);
        assertLe(g.maxImpactBps, cfg.steadyMaxImpactBps);
    }

    function _config() internal view returns (LaunchConfig memory cfg) {
        cfg = LaunchConfig({
            startBlock: uint64(block.number),
            preLaunchBlocks: 0,
            launchBlocks: 20,
            allowlistBlocks: 0,
            initialMaxAmountIn: 1 ether,
            steadyMaxAmountIn: 10 ether,
            maxInventoryUsagePerJit: 5 ether,
            initialMaxImpactBps: 100,
            steadyMaxImpactBps: 1_000,
            cooldownBlocks: 0,
            maxSwapsPerBlock: 20,
            maxJitActionsPerBlock: 1,
            jitBandWidth: 120,
            preLaunchSwapsEnabled: true,
            allowlistEnabled: false
        });
    }
}
