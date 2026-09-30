// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DemoIdentityRegistry} from "../src/DemoIdentityRegistry.sol";
import {PermissionedAssetToken} from "../src/PermissionedAssetToken.sol";

contract EnableDemoAccess is Script {
    address private constant ASSET_TOKEN = 0x4a72a139e65a25723478e5819F03C2789F40C206;

    function run() external returns (DemoIdentityRegistry registry) {
        vm.startBroadcast();
        registry = new DemoIdentityRegistry();
        PermissionedAssetToken(ASSET_TOKEN).setIdentityRegistry(address(registry));
        vm.stopBroadcast();

        console.log("Demo identity registry:", address(registry));
    }
}
