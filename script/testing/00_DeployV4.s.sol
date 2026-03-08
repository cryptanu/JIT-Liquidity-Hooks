// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console2} from "forge-std/Script.sol";
import {BaseScript} from "../base/BaseScript.sol";

contract DeployLocalV4 is BaseScript {
    function run() public {
        require(block.chainid == 31337, "Local deployment only");
        /**
         * Important:
         *
         * This script deploys the Uniswap V4 artifacts to local Anvil network.
         * That said, scripts in this repo will NOT automatically use these deployments,
         * unless you also change the addresses in the `Deployers.sol` file.
         *
         * You can override or modify the following functions with your own deployments:
         * - deployPoolManager()
         * - deployPositionManager()
         * - deployRouter()
         *
         * Permit2 is always on the same address.
         */

        _startBroadcast();
        _bootstrapV4();
        _stopBroadcast();

        console2.log("Deployed Permit2 at:", address(permit2));
        console2.log("Deployed V4PoolManager at:", address(poolManager));
        console2.log("Deployed V4PositionManager at:", address(positionManager));
        console2.log("Deployed V4SwapRouter at:", address(swapRouter));
    }
}
