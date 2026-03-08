// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

interface IQuoteInventoryVault {
    function reserveQuote(PoolId poolId, uint256 amount) external returns (uint256 reserved);

    function releaseQuote(PoolId poolId, uint256 amount) external returns (uint256 released);

    function availableQuote(PoolId poolId) external view returns (uint256);

    function reservedQuote(PoolId poolId) external view returns (uint256);
}
