// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {MockNewAssetToken} from "src/MockNewAssetToken.sol";
import {IJITLiquidityVault} from "src/interfaces/IJITLiquidityVault.sol";

/// @notice Optional deterministic issuance stream into JIT launch inventory.
contract IssuanceModule is Ownable {
    struct IssuanceSchedule {
        uint64 startBlock;
        uint64 endBlock;
        uint64 lastMintBlock;
        uint128 maxTotal;
        uint128 mintedTotal;
        uint128 maxPerBlock;
        bool enabled;
    }

    MockNewAssetToken public immutable launchToken;
    IJITLiquidityVault public immutable jitVault;

    mapping(PoolId => IssuanceSchedule) public schedules;

    error InvalidSchedule();

    event ScheduleConfigured(
        PoolId indexed poolId, uint64 startBlock, uint64 endBlock, uint128 maxTotal, uint128 maxPerBlock, bool enabled
    );
    event IssuanceStreamed(PoolId indexed poolId, uint256 amount, uint256 cumulativeMinted);

    constructor(MockNewAssetToken _launchToken, IJITLiquidityVault _jitVault, address initialOwner)
        Ownable(initialOwner)
    {
        launchToken = _launchToken;
        jitVault = _jitVault;
    }

    function configureSchedule(
        PoolId poolId,
        uint64 startBlock,
        uint64 endBlock,
        uint128 maxTotal,
        uint128 maxPerBlock,
        bool enabled
    ) external onlyOwner {
        if (startBlock == 0 || endBlock <= startBlock || maxTotal == 0 || maxPerBlock == 0) {
            revert InvalidSchedule();
        }

        IssuanceSchedule storage schedule = schedules[poolId];

        schedule.startBlock = startBlock;
        schedule.endBlock = endBlock;
        schedule.maxTotal = maxTotal;
        schedule.maxPerBlock = maxPerBlock;
        schedule.enabled = enabled;

        if (schedule.mintedTotal > maxTotal) {
            schedule.mintedTotal = maxTotal;
        }

        emit ScheduleConfigured(poolId, startBlock, endBlock, maxTotal, maxPerBlock, enabled);
    }

    function streamToVault(PoolId poolId) external returns (uint256 amountMinted) {
        amountMinted = availableToMint(poolId);
        if (amountMinted == 0) {
            return 0;
        }

        IssuanceSchedule storage schedule = schedules[poolId];

        schedule.lastMintBlock = uint64(block.number);
        schedule.mintedTotal += uint128(amountMinted);

        launchToken.mint(address(jitVault), amountMinted);
        jitVault.creditIssuedToken0(poolId, amountMinted);

        emit IssuanceStreamed(poolId, amountMinted, schedule.mintedTotal);
    }

    function availableToMint(PoolId poolId) public view returns (uint256) {
        IssuanceSchedule memory schedule = schedules[poolId];
        if (!schedule.enabled) return 0;
        if (block.number < schedule.startBlock) return 0;
        if (schedule.mintedTotal >= schedule.maxTotal) return 0;
        if (schedule.lastMintBlock == block.number) return 0;

        uint256 totalDuration = uint256(schedule.endBlock) - uint256(schedule.startBlock);
        if (totalDuration == 0) return 0;

        uint256 elapsed =
            block.number >= schedule.endBlock ? totalDuration : (block.number - uint256(schedule.startBlock));

        uint256 vested = (uint256(schedule.maxTotal) * elapsed) / totalDuration;
        if (vested <= schedule.mintedTotal) return 0;

        uint256 mintable = vested - schedule.mintedTotal;
        uint256 remaining = uint256(schedule.maxTotal) - schedule.mintedTotal;

        if (mintable > remaining) mintable = remaining;
        if (mintable > schedule.maxPerBlock) mintable = schedule.maxPerBlock;

        return mintable;
    }
}
