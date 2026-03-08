// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Deployers} from "test/utils/Deployers.sol";

/// @notice Shared script utilities for local and public-network launch demos.
abstract contract BaseScript is Script, Deployers {
    function _etch(address target, bytes memory bytecode) internal override {
        if (block.chainid == 31337) {
            // Keep Forge simulation state and Anvil RPC state aligned for script execution.
            vm.etch(target, bytecode);
            vm.rpc("anvil_setCode", string.concat('["', vm.toString(target), '",', '"', vm.toString(bytecode), '"]'));
        } else {
            revert("BaseScript: unsupported etch");
        }
    }

    function _startBroadcast() internal returns (address broadcaster) {
        uint256 privateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (privateKey == 0) {
            vm.startBroadcast();
            return msg.sender;
        }

        broadcaster = vm.addr(privateKey);
        vm.startBroadcast(privateKey);
    }

    function _stopBroadcast() internal {
        vm.stopBroadcast();
    }

    function _bootstrapV4() internal {
        deployArtifacts();
    }

    function _approveForV4(IERC20 token) internal {
        token.approve(address(permit2), type(uint256).max);
        token.approve(address(swapRouter), type(uint256).max);

        if (address(permit2).code.length > 0) {
            permit2.approve(address(token), address(positionManager), type(uint160).max, type(uint48).max);
            permit2.approve(address(token), address(poolManager), type(uint160).max, type(uint48).max);
        }
    }
}
