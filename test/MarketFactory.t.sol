// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {PermissionedAssetToken} from "../src/PermissionedAssetToken.sol";
import {AgoraAllowlistChecker} from "../src/AgoraAllowlistChecker.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {
    PermissionFlag,
    PermissionFlags
} from "@uniswap/v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";
import {IdentityRegistryFactory} from "../src/factories/IdentityRegistryFactory.sol";
import {NAVOracleFactory} from "../src/factories/NAVOracleFactory.sol";
import {AssetTokenFactory} from "../src/factories/AssetTokenFactory.sol";

contract MarketFactoryTest is Test {
    function test_DeployMarketWiresAllowlistAndHandsOwnershipToIssuer() public {
        MarketFactory factory = new MarketFactory(
            address(new IdentityRegistryFactory()), address(new NAVOracleFactory()), address(new AssetTokenFactory())
        );

        address issuer = makeAddr("issuer");
        vm.prank(issuer);
        (address token,,, address checker) = factory.deployMarket("Agora Note", "AGN", 1 days);

        assertEq(AgoraAllowlistChecker(checker).assetToken(), token);
        assertEq(
            PermissionFlag.unwrap(AgoraAllowlistChecker(checker).checkAllowlist(issuer, token)),
            PermissionFlag.unwrap(PermissionFlags.NONE)
        );

        assertEq(PermissionedAssetToken(token).owner(), address(factory));
        assertEq(PermissionedAssetToken(token).pendingOwner(), issuer);

        vm.prank(issuer);
        PermissionedAssetToken(token).acceptOwnership();
        assertEq(PermissionedAssetToken(token).owner(), issuer);
    }

    function test_IssuerManagedTierControlsSwapAndLiquidityPermissions() public {
        address issuer = makeAddr("issuer");
        address investor = makeAddr("investor");
        IdentityRegistry registry = new IdentityRegistry(issuer);
        AgoraAllowlistChecker checker = new AgoraAllowlistChecker(address(1), registry, issuer);

        vm.startPrank(issuer);
        registry.setEligibility(investor, 2);
        checker.setTierPermissions(2, PermissionFlags.SWAP_ALLOWED);
        vm.stopPrank();

        assertEq(registry.tierOf(investor), 2);
        assertEq(
            PermissionFlag.unwrap(checker.checkAllowlist(investor, address(1))),
            PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED)
        );
    }
}
