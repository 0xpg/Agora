// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DemoIdentityRegistry} from "../src/DemoIdentityRegistry.sol";
import {PermissionedAssetToken} from "../src/PermissionedAssetToken.sol";
import {AgoraAllowlistChecker} from "../src/AgoraAllowlistChecker.sol";

contract EnableDemoAccess is Script {
    address private constant ASSET_TOKEN = 0x6985ae688BcCeB88D00aaf07e3bFB49e6BFfa1e6;

    function run() external returns (DemoIdentityRegistry registry) {
        vm.startBroadcast();
        registry = new DemoIdentityRegistry();
        PermissionedAssetToken(ASSET_TOKEN).setIdentityRegistry(address(registry));
        AgoraAllowlistChecker allowlist = new AgoraAllowlistChecker(ASSET_TOKEN, registry, msg.sender);
        vm.stopBroadcast();

        console.log("Demo identity registry:", address(registry));
        console.log("Demo allowlist checker:", address(allowlist));
    }
}
