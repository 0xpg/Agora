// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BatchAuctionMarket} from "../../src/BatchAuctionMarket.sol";
import {PermissionedAssetToken} from "../../src/PermissionedAssetToken.sol";
import {NAVOracle} from "../../src/NAVOracle.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Randomly drives BatchAuctionMarket through submit/cancel/settle/NAV/time
/// sequences for invariant testing. Every action is bounded to a valid range and
/// wrapped in try/catch so a rejected action (submitting to a closed round, an
/// actor cancelling someone else's order, ...) is simply skipped rather than
/// counted as a fuzz failure — the property under test is fund conservation, not
/// "every call succeeds."
contract BatchAuctionMarketHandler is Test {
    BatchAuctionMarket public market;
    PermissionedAssetToken public token;
    MockERC20 public usdc;
    NAVOracle public navOracle;
    address public issuer;
    address[] public actors;

    constructor(
        BatchAuctionMarket _market,
        PermissionedAssetToken _token,
        MockERC20 _usdc,
        NAVOracle _navOracle,
        address _issuer,
        address[] memory _actors
    ) {
        market = _market;
        token = _token;
        usdc = _usdc;
        navOracle = _navOracle;
        issuer = _issuer;
        actors = _actors;
    }

    function submitOrder(uint256 actorSeed, bool isBuy, uint256 price, uint256 qty) external {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        price = bound(price, 1e16, 1_000e18);
        qty = bound(qty, 1e16, 100e18);

        if (market.currentRoundSettled()) {
            try market.startRound() {}
            catch {
                return;
            }
        }
        if (block.timestamp >= market.roundCloseAt()) return;

        vm.startPrank(issuer);
        if (isBuy) {
            usdc.mint(actor, (price * qty) / 1e18);
        } else {
            token.mint(actor, qty);
        }
        vm.stopPrank();

        vm.startPrank(actor);
        if (isBuy) {
            usdc.approve(address(market), type(uint256).max);
        } else {
            token.approve(address(market), type(uint256).max);
        }
        try market.submitOrder(isBuy, price, qty) {} catch {}
        vm.stopPrank();
    }

    function cancelOrder(uint256 orderIdSeed) external {
        uint256 nextId = market.nextOrderId();
        if (nextId <= 1) return;
        uint256 orderId = bound(orderIdSeed, 1, nextId - 1);
        (address trader,,,,,) = market.orders(orderId);
        if (trader == address(0)) return;

        vm.prank(trader);
        try market.cancelOrder(orderId) {} catch {}
    }

    function settleRound() external {
        if (market.currentRoundSettled()) return;
        if (block.timestamp < market.roundCloseAt()) {
            vm.warp(market.roundCloseAt());
        }
        try market.settleRound() {} catch {}
    }

    function updateNAV(uint256 seed) external {
        uint256 newNav = bound(seed, 50e18, 200e18);
        vm.prank(issuer);
        navOracle.setNAV(newNav);
    }

    function warpForward(uint256 seed) external {
        vm.warp(block.timestamp + bound(seed, 1 minutes, 2 hours));
    }
}
