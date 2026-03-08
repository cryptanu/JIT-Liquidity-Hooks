// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console2} from "forge-std/Script.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {BaseScript} from "script/base/BaseScript.sol";

import {MockNewAssetToken} from "src/MockNewAssetToken.sol";
import {LaunchController} from "src/LaunchController.sol";
import {QuoteInventoryVault} from "src/QuoteInventoryVault.sol";
import {JITLiquidityVault} from "src/JITLiquidityVault.sol";
import {IssuanceModule} from "src/IssuanceModule.sol";
import {JITLaunchHook} from "src/JITLaunchHook.sol";

/// @notice Deploys the core launch stack and mines a deterministic hook address.
contract DeployLaunchStackScript is BaseScript {
    function run() external {
        address broadcaster = _startBroadcast();
        _bootstrapV4();

        (MockNewAssetToken launchToken, MockNewAssetToken quoteToken) = _deployTokens(broadcaster);
        (
            LaunchController controller,
            QuoteInventoryVault quoteVault,
            JITLiquidityVault jitVault,
            IssuanceModule issuance
        ) = _deployModules(launchToken, quoteToken, broadcaster);
        (JITLaunchHook hook, bytes32 salt) = _deployHook(controller, jitVault, issuance, broadcaster);

        _approveForV4(launchToken);
        _approveForV4(quoteToken);

        _stopBroadcast();

        console2.log("Broadcast account", broadcaster);
        console2.log("PoolManager", address(poolManager));
        console2.log("PositionManager", address(positionManager));
        console2.log("SwapRouter", address(swapRouter));

        console2.log("LaunchToken", address(launchToken));
        console2.log("QuoteToken", address(quoteToken));

        console2.log("LaunchController", address(controller));
        console2.log("QuoteInventoryVault", address(quoteVault));
        console2.log("JITLiquidityVault", address(jitVault));
        console2.log("IssuanceModule", address(issuance));
        console2.log("JITLaunchHook", address(hook));
        console2.logBytes32(salt);
    }

    function _deployTokens(address broadcaster)
        internal
        returns (MockNewAssetToken launchToken, MockNewAssetToken quoteToken)
    {
        launchToken = new MockNewAssetToken("Launch Asset", "LCH", broadcaster);
        quoteToken = new MockNewAssetToken("Quote Asset", "QTE", broadcaster);

        launchToken.setMinter(broadcaster, true);
        quoteToken.setMinter(broadcaster, true);

        launchToken.mint(broadcaster, 2_000_000 ether);
        quoteToken.mint(broadcaster, 2_000_000 ether);
    }

    function _deployModules(MockNewAssetToken launchToken, MockNewAssetToken quoteToken, address broadcaster)
        internal
        returns (
            LaunchController controller,
            QuoteInventoryVault quoteVault,
            JITLiquidityVault jitVault,
            IssuanceModule issuance
        )
    {
        controller = new LaunchController(10, 2_000, broadcaster);
        quoteVault = new QuoteInventoryVault(quoteToken, broadcaster);
        jitVault = new JITLiquidityVault(launchToken, quoteVault, controller, broadcaster);
        issuance = new IssuanceModule(launchToken, jitVault, broadcaster);

        launchToken.setMinter(address(issuance), true);
        quoteVault.setReserver(address(jitVault), true);
        jitVault.setIssuanceModule(address(issuance), true);
    }

    function _deployHook(
        LaunchController controller,
        JITLiquidityVault jitVault,
        IssuanceModule issuance,
        address broadcaster
    ) internal returns (JITLaunchHook hook, bytes32 salt) {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(poolManager, controller, jitVault, issuance, broadcaster);

        (address minedHookAddress, bytes32 minedSalt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(JITLaunchHook).creationCode, constructorArgs);

        hook = new JITLaunchHook{salt: minedSalt}(poolManager, controller, jitVault, issuance, broadcaster);
        require(address(hook) == minedHookAddress, "DeployLaunchStack: mined hook mismatch");
        return (hook, minedSalt);
    }
}
