// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {PermissionedAssetToken} from "../src/PermissionedAssetToken.sol";
import {BatchAuctionMarket} from "../src/BatchAuctionMarket.sol";
import {IdentityRegistryFactory} from "../src/factories/IdentityRegistryFactory.sol";
import {NAVOracleFactory} from "../src/factories/NAVOracleFactory.sol";
import {AssetTokenFactory} from "../src/factories/AssetTokenFactory.sol";
import {BatchAuctionMarketFactory} from "../src/factories/BatchAuctionMarketFactory.sol";
import {MockEAS} from "./mocks/MockEAS.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract MarketFactoryTest is Test {
    function test_DeployMarketWiresExemptionAndHandsOwnershipToIssuer() public {
        MockEAS eas = new MockEAS();
        MockERC20 usdc = new MockERC20("USD Coin", "USDC");
        MarketFactory factory = new MarketFactory(
            address(eas),
            address(usdc),
            address(new IdentityRegistryFactory()),
            address(new NAVOracleFactory()),
            address(new AssetTokenFactory()),
            address(new BatchAuctionMarketFactory())
        );

        address issuer = makeAddr("issuer");
        vm.prank(issuer);
        (address token, address market,,) = factory.deployMarket("Agora Note", "AGN", 1 days, 1 hours, 500, 30 days);

        assertEq(PermissionedAssetToken(token).owner(), issuer);
        assertTrue(PermissionedAssetToken(token).exemptOperators(market));
        assertEq(BatchAuctionMarket(market).owner(), issuer);
    }
}
