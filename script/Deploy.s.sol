// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {IdentityRegistryFactory} from "../src/factories/IdentityRegistryFactory.sol";
import {NAVOracleFactory} from "../src/factories/NAVOracleFactory.sol";
import {AssetTokenFactory} from "../src/factories/AssetTokenFactory.sol";

contract Deploy is Script {
    function run() external returns (MarketFactory factory) {
        address easAddress = vm.envAddress("EAS_ADDRESS");
        vm.startBroadcast();
        address identityRegistryFactory = address(new IdentityRegistryFactory());
        address navOracleFactory = address(new NAVOracleFactory());
        address assetTokenFactory = address(new AssetTokenFactory());

        factory = new MarketFactory(easAddress, identityRegistryFactory, navOracleFactory, assetTokenFactory);
        vm.stopBroadcast();

        console.log("MarketFactory deployed at:", address(factory));
    }
}
