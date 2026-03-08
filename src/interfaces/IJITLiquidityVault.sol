// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

interface IJITLiquidityVault {
    struct JITQuote {
        int24 tickLower;
        int24 tickUpper;
        uint256 token0ToUse;
        uint256 quoteToUse;
    }

    function quoteAddLiquidityForTick(PoolId poolId, int24 tick, uint16 bandWidth, uint128 maxUsage)
        external
        view
        returns (JITQuote memory);

    function executeJITAdd(PoolId poolId, int24 tick, uint16 bandWidth, uint128 maxUsage)
        external
        returns (JITQuote memory);

    function executeJITRemove(PoolId poolId, uint16 releaseBps)
        external
        returns (uint256 token0Released, uint256 quoteReleased);

    function creditIssuedToken0(PoolId poolId, uint256 amount) external;

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
        );
}
