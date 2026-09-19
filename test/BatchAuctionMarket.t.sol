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
        assertEq(usdc.balanceOf(seller), 450e18);
        assertEq(usdc.balanceOf(buyer), 10_000e18 - 550e18);
        assertEq(market.accumulatedSpread(), 100e18);
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
        bytes32 sellerUID = keccak256(abi.encode("attestation", seller));

        market.startRound();

        vm.prank(buyer);
        market.submitOrder(true, 110e18, 5e18);
        vm.prank(seller);
        market.submitOrder(false, 90e18, 5e18);

        eas.revoke(sellerUID);
        bytes32[] memory uids = new bytes32[](1);
        uids[0] = sellerUID;
        registry.refreshEligibility(seller, uids);

        uint256 sellerAssetBefore = assetToken.balanceOf(seller);
        vm.warp(block.timestamp + 1 hours);
        market.settleRound();

        assertEq(assetToken.balanceOf(buyer), 0);
        assertEq(assetToken.balanceOf(seller), sellerAssetBefore + 5e18);
        assertEq(usdc.balanceOf(buyer), 10_000e18);
    }

    function test_RevocationWithoutRefreshDoesNotRetroactivelyExcludeCachedEligibility() public {
        market.startRound();

        vm.prank(buyer);
        market.submitOrder(true, 110e18, 5e18);
        vm.prank(seller);
        market.submitOrder(false, 90e18, 5e18);

        eas.revoke(keccak256(abi.encode("attestation", seller)));

        vm.warp(block.timestamp + 1 hours);
        market.settleRound();

        assertEq(assetToken.balanceOf(buyer), 5e18);
        assertEq(usdc.balanceOf(seller), 450e18);
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

    function test_AccumulatedSpreadIsWithdrawableByIssuer() public {
        market.startRound();
        vm.prank(buyer);
        market.submitOrder(true, 110e18, 5e18);
        vm.prank(seller);
        market.submitOrder(false, 90e18, 5e18);

        vm.warp(block.timestamp + 1 hours);
        market.settleRound();

        assertEq(market.accumulatedSpread(), 100e18);
        assertEq(usdc.balanceOf(address(market)), 100e18);

        address treasury = makeAddr("treasury");
        vm.prank(issuer);
        market.withdrawSpread(treasury, 100e18);

        assertEq(usdc.balanceOf(treasury), 100e18);
        assertEq(market.accumulatedSpread(), 0);
        assertEq(usdc.balanceOf(address(market)), 0);
    }

    function test_WithdrawSpreadRevertsPastAccumulated() public {
        market.startRound();
        vm.prank(buyer);
        market.submitOrder(true, 110e18, 5e18);
        vm.prank(seller);
        market.submitOrder(false, 90e18, 5e18);
        vm.warp(block.timestamp + 1 hours);
        market.settleRound();

        vm.prank(issuer);
        vm.expectRevert();
        market.withdrawSpread(makeAddr("treasury"), 100e18 + 1);
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

        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        vm.prank(buyer);
        market.cancelOrder(buyOrderId);
        assertEq(usdc.balanceOf(buyer), buyerBalanceBefore + 550e18);

        vm.warp(block.timestamp + 1 hours);
        market.settleRound();
        assertEq(assetToken.balanceOf(seller), 10e18);
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

        vm.prank(seller);
        uint256 round2OrderId = market.submitOrder(false, 90e18, 3e18);
        assertTrue(round2OrderId != round1OrderId);

        (,,,,, bool round1Settled) = market.orders(round1OrderId);
        assertTrue(round1Settled);

        uint256 sellerBalanceBeforeSettle = assetToken.balanceOf(seller);
        vm.warp(block.timestamp + 1 hours);
        market.settleRound();
        assertEq(assetToken.balanceOf(seller), sellerBalanceBeforeSettle + 3e18);
    }
}
