// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {IQuoteInventoryVault} from "src/interfaces/IQuoteInventoryVault.sol";

/// @notice Custodies the quote-side inventory used by deterministic JIT activation.
contract QuoteInventoryVault is Ownable, IQuoteInventoryVault {
    using SafeERC20 for IERC20;

    IERC20 public immutable quoteAsset;

    mapping(PoolId => uint256) private _freeQuote;
    mapping(PoolId => uint256) private _reservedQuote;
    mapping(address => bool) public reservers;

    error UnauthorizedReserver(address caller);
    error InsufficientFreeQuote(PoolId poolId, uint256 requested, uint256 available);

    event ReserverUpdated(address indexed reserver, bool allowed);
    event QuoteDeposited(PoolId indexed poolId, uint256 amount);
    event QuoteWithdrawn(PoolId indexed poolId, address indexed recipient, uint256 amount);
    event QuoteReserved(PoolId indexed poolId, uint256 amount);
    event QuoteReleased(PoolId indexed poolId, uint256 amount);

    constructor(IERC20 _quoteAsset, address initialOwner) Ownable(initialOwner) {
        quoteAsset = _quoteAsset;
    }

    modifier onlyReserver() {
        if (!reservers[msg.sender]) revert UnauthorizedReserver(msg.sender);
        _;
    }

    function setReserver(address reserver, bool allowed) external onlyOwner {
        reservers[reserver] = allowed;
        emit ReserverUpdated(reserver, allowed);
    }

    function depositQuote(PoolId poolId, uint256 amount) external onlyOwner {
        quoteAsset.safeTransferFrom(msg.sender, address(this), amount);
        _freeQuote[poolId] += amount;
        emit QuoteDeposited(poolId, amount);
    }

    function withdrawQuote(PoolId poolId, address recipient, uint256 amount) external onlyOwner {
        uint256 free = _freeQuote[poolId];
        if (amount > free) revert InsufficientFreeQuote(poolId, amount, free);

        _freeQuote[poolId] = free - amount;
        quoteAsset.safeTransfer(recipient, amount);
        emit QuoteWithdrawn(poolId, recipient, amount);
    }

    function reserveQuote(PoolId poolId, uint256 amount) external onlyReserver returns (uint256 reserved) {
        uint256 free = _freeQuote[poolId];
        reserved = amount > free ? free : amount;

        if (reserved == 0) return 0;

        _freeQuote[poolId] = free - reserved;
        _reservedQuote[poolId] += reserved;

        emit QuoteReserved(poolId, reserved);
    }

    function releaseQuote(PoolId poolId, uint256 amount) external onlyReserver returns (uint256 released) {
        uint256 reserved = _reservedQuote[poolId];
        released = amount > reserved ? reserved : amount;

        if (released == 0) return 0;

        _reservedQuote[poolId] = reserved - released;
        _freeQuote[poolId] += released;

        emit QuoteReleased(poolId, released);
    }

    function availableQuote(PoolId poolId) external view returns (uint256) {
        return _freeQuote[poolId];
    }

    function reservedQuote(PoolId poolId) external view returns (uint256) {
        return _reservedQuote[poolId];
    }
}
