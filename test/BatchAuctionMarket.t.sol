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
    address buyer2 = makeAddr("buyer2");
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

    /// @notice Regression test for a real bug an invariant test found: summing each
    /// buy order's own floor(price*qty/1e18) contribution and separately summing
    /// each sell order's own floor(filled*clearingPrice/1e18) proceeds can disagree
    /// by a few units even though both sides matched the same total quantity —
    /// different order-size partitions of the same total round differently. With
    /// two buy orders of qty 0.7e18 and 1.3e18 against one seller for 2e18 at this
    /// clearing price, the naive per-order formulas would retain 2469135780246913577
    /// from buyers but the naive seller-proceeds formula would try to pay out
    /// 2469135780246913578 — one unit more than was ever collected. The fix pays the
    /// last filled seller `sellerPool - alreadyDistributed` instead of its own
    /// formula, so the round always settles exactly, with nothing left stranded.
    function test_RoundingRemainderAcrossOrderPartitionsSettlesExactlyWithNoStrandedFunds() public {
        uint256 clearingPrice = 1234567890123456789;
        vm.prank(issuer);
        navOracle.setNAV(clearingPrice);
        _whitelist(buyer2);
        usdc.mint(buyer2, 10_000e18);
        vm.prank(buyer2);
        usdc.approve(address(market), type(uint256).max);

        market.startRound();
        vm.prank(buyer);
        market.submitOrder(true, clearingPrice, 7e17);
        vm.prank(buyer2);
        market.submitOrder(true, clearingPrice, 13e17);
        vm.prank(seller);
        market.submitOrder(false, clearingPrice, 2e18);

        vm.warp(block.timestamp + 1 hours);
        market.settleRound();

        // The seller can only ever receive what was actually retained from buyers'
        // independently-floored escrow (sellerPool) — not floor(totalQty*price/1e18),
        // which is 1 wei more here than the buy side ever collected. Paying that
        // would mean creating a wei that was never escrowed.
        uint256 expectedSellerProceeds = (7e17 * clearingPrice) / 1e18 + (13e17 * clearingPrice) / 1e18;
        assertEq(expectedSellerProceeds, (2e18 * clearingPrice) / 1e18 - 1, "test fixture must exercise the gap");
        assertEq(usdc.balanceOf(seller), expectedSellerProceeds);
        assertEq(assetToken.balanceOf(buyer), 7e17);
        assertEq(assetToken.balanceOf(buyer2), 13e17);
        assertEq(usdc.balanceOf(address(market)), 0);
        assertEq(assetToken.balanceOf(address(market)), 0);
    }

    function test_PauseBlocksStartRound() public {
        vm.prank(issuer);
        market.pause();

        vm.expectRevert();
        market.startRound();
    }

    function test_PauseBlocksNewOrdersButNotCancelOrSettle() public {
        market.startRound();
        vm.prank(buyer);
        uint256 buyOrderId = market.submitOrder(true, 110e18, 5e18);
        vm.prank(seller);
        market.submitOrder(false, 90e18, 5e18);

        vm.prank(issuer);
        market.pause();

        vm.prank(buyer);
        vm.expectRevert();
        market.submitOrder(true, 100e18, 1e18);

        // an investor can still get their own escrowed funds back while paused
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        vm.prank(buyer);
        market.cancelOrder(buyOrderId);
        assertEq(usdc.balanceOf(buyer), buyerBalanceBefore + 550e18);

        // an already-open round can still be settled while paused
        vm.warp(block.timestamp + 1 hours);
        market.settleRound();
        assertEq(assetToken.balanceOf(seller), 10e18); // seller's order refunded (no counterparty left)
    }

    function test_UnpauseRestoresNewActivity() public {
        vm.startPrank(issuer);
        market.pause();
        market.unpause();
        vm.stopPrank();

        market.startRound();
        vm.prank(buyer);
        market.submitOrder(true, 100e18, 1e18);
    }

    function test_SecondRoundDoesNotSeeFirstRoundsOrdersOrIds() public {
        market.startRound();
        vm.prank(buyer);
        uint256 round1OrderId = market.submitOrder(true, 110e18, 5e18);
        vm.prank(seller);
        market.submitOrder(false, 90e18, 5e18);

        vm.warp(block.timestamp + 1 hours);
        market.settleRound();
        assertEq(market.currentRoundId(), 1);
        assertEq(assetToken.balanceOf(buyer), 5e18);

        vm.prank(issuer);
        assetToken.mint(seller, 3e18);
        vm.prank(seller);
        assetToken.approve(address(market), type(uint256).max);

        market.startRound();
        assertEq(market.currentRoundId(), 2);

        // a fresh order in round 2 gets a fresh id, distinct from round 1's
        vm.prank(seller);
        uint256 round2OrderId = market.submitOrder(false, 90e18, 3e18);
        assertTrue(round2OrderId != round1OrderId);

        // round 1's already-settled order is untouched by round 2 settling
        (,,,,, bool round1Settled) = market.orders(round1OrderId);
        assertTrue(round1Settled);

        // round 2 has no matching buy order, so it must fully refund, not match
        // against anything left over from round 1
        uint256 sellerBalanceBeforeSettle = assetToken.balanceOf(seller);
        vm.warp(block.timestamp + 1 hours);
        market.settleRound();
        assertEq(assetToken.balanceOf(seller), sellerBalanceBeforeSettle + 3e18); // refunded in full
    }
}
