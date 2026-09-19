// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {IdentityRegistryFactory} from "../src/factories/IdentityRegistryFactory.sol";
import {NAVOracleFactory} from "../src/factories/NAVOracleFactory.sol";
import {AssetTokenFactory} from "../src/factories/AssetTokenFactory.sol";
import {BatchAuctionMarketFactory} from "../src/factories/BatchAuctionMarketFactory.sol";

/// @notice Deploys the four per-contract sub-factories, then MarketFactory wired to
/// their addresses (see MarketFactory's NatSpec for why the sub-factories must be
/// deployed independently rather than from MarketFactory's own constructor) and
/// pointed at the chain's EAS predeploy and a settlement token. Fill in EAS_ADDRESS
/// / SETTLEMENT_TOKEN in .env before running — see .env.example. On Base/Base
/// Sepolia, look up the current addresses at docs.base.org (EAS) and Circle's docs
/// (native USDC) rather than trusting a hardcoded value here.
contract Deploy is Script {
    function run() external returns (MarketFactory factory) {
        address easAddress = vm.envAddress("EAS_ADDRESS");
        address settlementToken = vm.envAddress("SETTLEMENT_TOKEN");

        vm.startBroadcast();
        address identityRegistryFactory = address(new IdentityRegistryFactory());
        address navOracleFactory = address(new NAVOracleFactory());
        address assetTokenFactory = address(new AssetTokenFactory());
        address batchAuctionMarketFactory = address(new BatchAuctionMarketFactory());

        factory = new MarketFactory(
            easAddress,
            settlementToken,
            identityRegistryFactory,
            navOracleFactory,
            assetTokenFactory,
            batchAuctionMarketFactory
        );
        vm.stopBroadcast();

        console.log("MarketFactory deployed at:", address(factory));
    }
}
