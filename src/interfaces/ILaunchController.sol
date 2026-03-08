// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {LaunchConfig, GuardrailSnapshot, LaunchPhase} from "src/types/LaunchTypes.sol";

interface ILaunchController {
    function hookForPool(PoolId poolId) external view returns (address);

    function registerPool(PoolId poolId, address hook, LaunchConfig calldata config) external;

    function setPoolHook(PoolId poolId, address hook) external;

    function setAllowlist(PoolId poolId, address user, bool allowed) external;

    function queueConfigUpdate(PoolId poolId, LaunchConfig calldata nextConfig) external;

    function executeConfigUpdate(PoolId poolId) external;

    function getLaunchConfig(PoolId poolId) external view returns (LaunchConfig memory);

    function getGuardrails(PoolId poolId) external view returns (GuardrailSnapshot memory);

    function getPhase(PoolId poolId) external view returns (LaunchPhase);

    function enforceSwapGuardrails(PoolId poolId, address sender, uint256 amountIn, uint256 impactBps)
        external
        returns (GuardrailSnapshot memory);

    function consumeJitAction(PoolId poolId) external returns (bool);
}
