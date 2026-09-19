// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {NAVOracle} from "../src/NAVOracle.sol";
import {PermissionedAssetToken} from "../src/PermissionedAssetToken.sol";
import {BatchAuctionMarket} from "../src/BatchAuctionMarket.sol";
import {MockEAS} from "./mocks/MockEAS.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract BatchAuctionMarketTest is Test {
    bytes32 constant KYC_SCHEMA = keccak256("KYC");

    MockEAS eas;
    IdentityRegistry registry;
    NAVOracle navOracle;
    PermissionedAssetToken assetToken;
    MockERC20 usdc;
    BatchAuctionMarket market;

    address issuer = makeAddr("issuer");
    address kycAttester = makeAddr("kycAttester");
    address buyer = makeAddr("buyer");
    address seller = makeAddr("seller");
    address notWhitelisted = makeAddr("notWhitelisted");

    function setUp() public {
        eas = new MockEAS();

        vm.startPrank(issuer);
        registry = new IdentityRegistry(address(eas), issuer, 30 days);
        bytes32[] memory schemas = new bytes32[](1);
        schemas[0] = KYC_SCHEMA;
        registry.setRequiredSchemas(schemas);
        registry.setTrustedAttester(KYC_SCHEMA, kycAttester, true);

        navOracle = new NAVOracle(issuer, 1 days);
        navOracle.setNAV(100e18);

        assetToken = new PermissionedAssetToken("Agora Test Note", "ATN", issuer, address(registry));
        usdc = new MockERC20("USD Coin", "USDC");

        market = new BatchAuctionMarket(
            address(assetToken), address(usdc), address(registry), address(navOracle), issuer, 1 hours, 500
        );
        assetToken.setExemptOperator(address(market), true);
        vm.stopPrank();

        _whitelist(buyer);
        _whitelist(seller);

        vm.prank(issuer);
        assetToken.mint(seller, 10e18);
        usdc.mint(buyer, 10_000e18);

        vm.prank(seller);
        assetToken.approve(address(market), type(uint256).max);
        vm.prank(buyer);
        usdc.approve(address(market), type(uint256).max);
    }

    function _whitelist(address investor) private {
        bytes32 uid = keccak256(abi.encode("attestation", investor));
        eas.register(uid, KYC_SCHEMA, investor, kycAttester, 0, 0);
        bytes32[] memory uids = new bytes32[](1);
        uids[0] = uid;
        registry.refreshEligibility(investor, uids);
    }

    function test_FullRoundMatchesAndSettles() public {
        market.startRound();

        vm.prank(buyer);
        market.submitOrder(true, 110e18, 5e18);
        vm.prank(seller);
        market.submitOrder(false, 90e18, 5e18);

        vm.warp(block.timestamp + 1 hours);
        market.settleRound();

        assertEq(assetToken.balanceOf(buyer), 5e18);
        assertEq(assetToken.balanceOf(seller), 5e18);
        // clearing price clamps to NAV=100 (inside the [90,110] crossing interval)
        assertEq(usdc.balanceOf(seller), 500e18);
        // buyer escrowed 110*5=550, paid 100*5=500, refunded 50
        assertEq(usdc.balanceOf(buyer), 10_000e18 - 500e18);
    }

    function test_IneligibleTraderAtSubmitTimeIsRejected() public {
        market.startRound();
        usdc.mint(notWhitelisted, 1_000e18);
        vm.prank(notWhitelisted);
        usdc.approve(address(market), type(uint256).max);

        vm.expectRevert("ineligible");
        vm.prank(notWhitelisted);
        market.submitOrder(true, 100e18, 1e18);
    }

    function test_RevokedAttestationRefreshedBeforeSettlementIsExcludedAndRefunded() public {
        // isEligible() reads a cache populated by refreshEligibility(), not a live
        // EAS lookup on every call (that would be an external call per transfer —
        // too expensive). So revoking an attestation alone doesn't retroactively
        // flip a cached record; what closes the mid-round gap is that *anyone* —
        // the trader, the issuer, an automated compliance bot — can permissionlessly
        // call refreshEligibility() to pull the revocation into the cache before
        // settlement runs, and settleRound() always reads the live cache, not a
        // snapshot taken at order-submission time.
        bytes32 sellerUID = keccak256(abi.encode("attestation", seller));

        market.startRound();

        vm.prank(buyer);
        market.submitOrder(true, 110e18, 5e18);
        vm.prank(seller);
        market.submitOrder(false, 90e18, 5e18);

        // issuer's KYC vendor revokes the seller's attestation after submission...
        eas.revoke(sellerUID);
        // ...and a refresh (callable by anyone) pulls the revocation into the cache
        // before the round settles.
        bytes32[] memory uids = new bytes32[](1);
        uids[0] = sellerUID;
        registry.refreshEligibility(seller, uids);

        uint256 sellerAssetBefore = assetToken.balanceOf(seller);
        vm.warp(block.timestamp + 1 hours);
        market.settleRound();

        // no match: seller was excluded at settlement-time eligibility re-check
        assertEq(assetToken.balanceOf(buyer), 0);
        assertEq(assetToken.balanceOf(seller), sellerAssetBefore + 5e18); // full refund
        assertEq(usdc.balanceOf(buyer), 10_000e18); // full refund
    }

    /// @notice Documents the actual boundary of the eligibility guarantee: revoking
    /// an attestation alone does NOT retroactively invalidate an already-cached
    /// eligibility record. The cache is only as fresh as the last refreshEligibility()
    /// call, bounded by maxCacheAge / the attestation's own expirationTime. This is a
    /// deliberate gas/trust tradeoff, not a bug — but it means "closes the mid-round
    /// gap" depends on someone actually calling refresh before settlement, and
    /// production deployments should set maxCacheAge no longer than the round
    /// duration if instant-ish revocation matters for a given asset.
    function test_RevocationWithoutRefreshDoesNotRetroactivelyExcludeCachedEligibility() public {
        market.startRound();

        vm.prank(buyer);
        market.submitOrder(true, 110e18, 5e18);
        vm.prank(seller);
        market.submitOrder(false, 90e18, 5e18);

        eas.revoke(keccak256(abi.encode("attestation", seller))); // no refresh call after this

        vm.warp(block.timestamp + 1 hours);
        market.settleRound();

        // trade still matched: the cache was never refreshed, so isEligible(seller)
        // still reflects its pre-revocation state.
        assertEq(assetToken.balanceOf(buyer), 5e18);
        assertEq(usdc.balanceOf(seller), 500e18);
    }

    function test_CancelOrderRefundsEscrow() public {
        market.startRound();
        vm.startPrank(buyer);
        uint256 orderId = market.submitOrder(true, 100e18, 2e18);
        uint256 balanceAfterSubmit = usdc.balanceOf(buyer);
        market.cancelOrder(orderId);
        vm.stopPrank();

        assertEq(usdc.balanceOf(buyer), balanceAfterSubmit + 200e18);
    }
}
