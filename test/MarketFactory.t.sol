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
import {MockEAS} from "./mocks/MockEAS.sol";

contract MarketFactoryTest is Test {
    function test_DeployMarketWiresAllowlistAndHandsOwnershipToIssuer() public {
        MockEAS eas = new MockEAS();
        MarketFactory factory = new MarketFactory(
            address(eas),
            address(new IdentityRegistryFactory()),
            address(new NAVOracleFactory()),
            address(new AssetTokenFactory())
        );

        address issuer = makeAddr("issuer");
        vm.prank(issuer);
        (address token,,, address checker) = factory.deployMarket("Agora Note", "AGN", 1 days, 30 days);

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

    function test_AttestedTierControlsSwapAndLiquidityPermissions() public {
        MockEAS eas = new MockEAS();
        address issuer = makeAddr("issuer");
        address investor = makeAddr("investor");
        bytes32 schema = keccak256("investor-tier");
        bytes32 uid = keccak256("attestation");

        IdentityRegistry registry = new IdentityRegistry(address(eas), issuer, 30 days);
        AgoraAllowlistChecker checker = new AgoraAllowlistChecker(address(1), registry, issuer);

        bytes32[] memory schemas = new bytes32[](1);
        schemas[0] = schema;
        vm.startPrank(issuer);
        registry.setRequiredSchemas(schemas);
        registry.setTrustedAttester(schema, issuer, true);
        checker.setTierPermissions(2, PermissionFlags.SWAP_ALLOWED);
        vm.stopPrank();

        eas.registerWithData(uid, schema, investor, issuer, 0, 0, abi.encode(uint8(2)));
        bytes32[] memory uids = new bytes32[](1);
        uids[0] = uid;
        registry.refreshEligibility(investor, uids);

        assertEq(registry.tierOf(investor), 2);
        assertEq(
            PermissionFlag.unwrap(checker.checkAllowlist(investor, address(1))),
            PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED)
        );
    }
}
