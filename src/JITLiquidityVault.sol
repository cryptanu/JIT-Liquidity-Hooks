// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {ILaunchController} from "src/interfaces/ILaunchController.sol";
import {IQuoteInventoryVault} from "src/interfaces/IQuoteInventoryVault.sol";
import {IJITLiquidityVault} from "src/interfaces/IJITLiquidityVault.sol";

/// @notice Holds launch token inventory and manages deterministic bounded JIT inventory commitments.
contract JITLiquidityVault is Ownable, ReentrancyGuard, IJITLiquidityVault {
    using SafeERC20 for IERC20;

    struct Inventory {
        uint256 freeToken0;
        uint256 reservedToken0;
        uint256 reservedQuote;
        uint128 activeLiquidityUnits;
        int24 lastCenterTick;
        uint64 lastJitBlock;
    }

    IERC20 public immutable token0;
    IQuoteInventoryVault public immutable quoteVault;
    ILaunchController public immutable launchController;

    mapping(PoolId => Inventory) private _inventory;
    mapping(address => bool) public issuanceModules;

    error UnauthorizedHook(PoolId poolId, address caller);
    error UnauthorizedIssuer(address caller);
    error InvalidBandWidth();
    error InvalidBps();
    error InsufficientFreeToken0(PoolId poolId, uint256 requested, uint256 available);

    event IssuanceModuleUpdated(address indexed module, bool allowed);
    event Token0Deposited(PoolId indexed poolId, uint256 amount);
    event Token0Withdrawn(PoolId indexed poolId, address indexed recipient, uint256 amount);
    event IssuanceCredited(PoolId indexed poolId, uint256 amount);
    event JITAdded(
        PoolId indexed poolId,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint256 token0Used,
        uint256 quoteUsed,
        uint128 activeLiquidityUnits
    );
    event JITRemoved(
        PoolId indexed poolId, uint256 token0Released, uint256 quoteReleased, uint128 activeLiquidityUnits
    );

    constructor(
        IERC20 _token0,
        IQuoteInventoryVault _quoteVault,
        ILaunchController _launchController,
        address initialOwner
    ) Ownable(initialOwner) {
        token0 = _token0;
        quoteVault = _quoteVault;
        launchController = _launchController;
    }

    modifier onlyPoolHook(PoolId poolId) {
        if (msg.sender != launchController.hookForPool(poolId)) {
            revert UnauthorizedHook(poolId, msg.sender);
        }
        _;
    }

    modifier onlyIssuer() {
        if (!issuanceModules[msg.sender]) revert UnauthorizedIssuer(msg.sender);
        _;
    }

    function setIssuanceModule(address module, bool allowed) external onlyOwner {
        issuanceModules[module] = allowed;
        emit IssuanceModuleUpdated(module, allowed);
    }

    function depositToken0(PoolId poolId, uint256 amount) external onlyOwner {
        token0.safeTransferFrom(msg.sender, address(this), amount);
        _inventory[poolId].freeToken0 += amount;
        emit Token0Deposited(poolId, amount);
    }

    function withdrawToken0(PoolId poolId, address recipient, uint256 amount) external onlyOwner {
        Inventory storage inv = _inventory[poolId];
        if (amount > inv.freeToken0) {
            revert InsufficientFreeToken0(poolId, amount, inv.freeToken0);
        }

        inv.freeToken0 -= amount;
        token0.safeTransfer(recipient, amount);
        emit Token0Withdrawn(poolId, recipient, amount);
    }

    function creditIssuedToken0(PoolId poolId, uint256 amount) external onlyIssuer {
        _inventory[poolId].freeToken0 += amount;
        emit IssuanceCredited(poolId, amount);
    }

    function quoteAddLiquidityForTick(PoolId poolId, int24 tick, uint16 bandWidth, uint128 maxUsage)
        public
        view
        returns (JITQuote memory quote)
    {
        if (bandWidth == 0) revert InvalidBandWidth();

        Inventory storage inv = _inventory[poolId];

        int24 width = int24(uint24(bandWidth));
        quote.tickLower = tick - width;
        quote.tickUpper = tick + width;

        uint256 freeToken0 = inv.freeToken0;
        uint256 freeQuote = quoteVault.availableQuote(poolId);

        uint256 capped0 = _min(freeToken0, uint256(maxUsage));
        uint256 cappedQuote = _min(freeQuote, uint256(maxUsage));
        uint256 balanced = _min(capped0, cappedQuote);

        quote.token0ToUse = balanced;
        quote.quoteToUse = balanced;
    }

    function executeJITAdd(PoolId poolId, int24 tick, uint16 bandWidth, uint128 maxUsage)
        external
        onlyPoolHook(poolId)
        nonReentrant
        returns (JITQuote memory quote)
    {
        quote = quoteAddLiquidityForTick(poolId, tick, bandWidth, maxUsage);
        if (quote.token0ToUse == 0 || quote.quoteToUse == 0) {
            return quote;
        }

        Inventory storage inv = _inventory[poolId];

        inv.freeToken0 -= quote.token0ToUse;
        inv.reservedToken0 += quote.token0ToUse;

        uint256 quoteReserved = quoteVault.reserveQuote(poolId, quote.quoteToUse);
        if (quoteReserved < quote.quoteToUse) {
            uint256 token0Delta = quote.quoteToUse - quoteReserved;
            inv.freeToken0 += token0Delta;
            inv.reservedToken0 -= token0Delta;

            quote.token0ToUse = quoteReserved;
            quote.quoteToUse = quoteReserved;
        }

        if (quoteReserved == 0) {
            return quote;
        }

        inv.reservedQuote += quote.quoteToUse;

        uint128 addedUnits = uint128(_min(quote.token0ToUse, quote.quoteToUse));
        inv.activeLiquidityUnits += addedUnits;
        inv.lastCenterTick = tick;
        inv.lastJitBlock = uint64(block.number);

        emit JITAdded(
            poolId, quote.tickLower, quote.tickUpper, quote.token0ToUse, quote.quoteToUse, inv.activeLiquidityUnits
        );
    }

    function executeJITRemove(PoolId poolId, uint16 releaseBps)
        external
        onlyPoolHook(poolId)
        nonReentrant
        returns (uint256 token0Released, uint256 quoteReleased)
    {
        if (releaseBps > 10_000) revert InvalidBps();
        if (releaseBps == 0) return (0, 0);

        Inventory storage inv = _inventory[poolId];

        token0Released = (inv.reservedToken0 * releaseBps) / 10_000;
        uint256 quoteTarget = (inv.reservedQuote * releaseBps) / 10_000;

        quoteReleased = quoteVault.releaseQuote(poolId, quoteTarget);

        inv.reservedToken0 -= token0Released;
        inv.freeToken0 += token0Released;

        if (quoteReleased > inv.reservedQuote) {
            quoteReleased = inv.reservedQuote;
        }
        inv.reservedQuote -= quoteReleased;

        uint128 unitsToRemove = uint128((uint256(inv.activeLiquidityUnits) * releaseBps) / 10_000);
        if (unitsToRemove > inv.activeLiquidityUnits) {
            unitsToRemove = inv.activeLiquidityUnits;
        }
        inv.activeLiquidityUnits -= unitsToRemove;
        inv.lastJitBlock = uint64(block.number);

        emit JITRemoved(poolId, token0Released, quoteReleased, inv.activeLiquidityUnits);
    }

    function inventoryState(PoolId poolId)
        external
        view
        returns (
            uint256 freeToken0,
            uint256 reservedToken0,
            uint256 reservedQuote,
            uint128 activeLiquidityUnits,
            int24 lastCenterTick,
            uint64 lastJitBlock
        )
    {
        Inventory memory inv = _inventory[poolId];
        return (
            inv.freeToken0,
            inv.reservedToken0,
            inv.reservedQuote,
            inv.activeLiquidityUnits,
            inv.lastCenterTick,
            inv.lastJitBlock
        );
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
