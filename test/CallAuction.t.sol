// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CallAuction} from "../src/libraries/CallAuction.sol";

contract CallAuctionTest is Test {
    function _order(uint256 id, uint256 price, uint256 qty) private pure returns (CallAuction.Order memory) {
        return CallAuction.Order({id: id, trader: address(uint160(id)), price: price, qty: qty});
    }

    function test_ClearsAtNAVWhenInsideCrossingInterval() public pure {
        CallAuction.Order[] memory buys = new CallAuction.Order[](1);
        buys[0] = _order(1, 110e18, 5e18);
        CallAuction.Order[] memory sells = new CallAuction.Order[](1);
        sells[0] = _order(2, 90e18, 5e18);

        CallAuction.Result memory r = CallAuction.clear(buys, sells, 100e18, 500);

        assertEq(r.clearingPrice, 100e18);
        assertEq(r.matchedQty, 5e18);
        assertEq(r.fills.length, 1);
    }

    function test_ClampsToMarginalPriceWhenNAVOutsideCrossingInterval() public pure {
        CallAuction.Order[] memory buys = new CallAuction.Order[](1);
        buys[0] = _order(1, 105e18, 5e18);
        CallAuction.Order[] memory sells = new CallAuction.Order[](1);
        sells[0] = _order(2, 100e18, 5e18);

        // NAV of 80 is far below the crossing interval [100, 105]; with a band wide
        // enough to still reach the interval, the price should clamp to 100, not 80.
        CallAuction.Result memory r = CallAuction.clear(buys, sells, 80e18, 3000);

        assertEq(r.clearingPrice, 100e18);
        assertEq(r.matchedQty, 5e18);
    }

    function test_VoidsRoundWhenNoCrossing() public pure {
        CallAuction.Order[] memory buys = new CallAuction.Order[](1);
        buys[0] = _order(1, 90e18, 5e18);
        CallAuction.Order[] memory sells = new CallAuction.Order[](1);
        sells[0] = _order(2, 100e18, 5e18);

        CallAuction.Result memory r = CallAuction.clear(buys, sells, 95e18, 500);

        assertEq(r.clearingPrice, 0);
        assertEq(r.matchedQty, 0);
        assertEq(r.fills.length, 0);
    }

    function test_VoidsRoundWhenCrossingOutsideBand() public pure {
        CallAuction.Order[] memory buys = new CallAuction.Order[](1);
        buys[0] = _order(1, 150e18, 5e18);
        CallAuction.Order[] memory sells = new CallAuction.Order[](1);
        sells[0] = _order(2, 140e18, 5e18);

        // Crossing interval [140, 150] is far from NAV=100 even with a 5% band.
        CallAuction.Result memory r = CallAuction.clear(buys, sells, 100e18, 500);

        assertEq(r.matchedQty, 0);
    }

    function test_PartialFillLeavesRemainderOnLargerSide() public pure {
        CallAuction.Order[] memory buys = new CallAuction.Order[](1);
        buys[0] = _order(1, 110e18, 3e18);
        CallAuction.Order[] memory sells = new CallAuction.Order[](1);
        sells[0] = _order(2, 90e18, 5e18);

        CallAuction.Result memory r = CallAuction.clear(buys, sells, 100e18, 500);

        assertEq(r.matchedQty, 3e18);
        assertEq(buys[0].qty, 0);
        assertEq(sells[0].qty, 2e18);
    }

    function test_MultipleOrdersMatchInPriceTimePriority() public pure {
        CallAuction.Order[] memory buys = new CallAuction.Order[](2);
        buys[0] = _order(1, 100e18, 2e18);
        buys[1] = _order(2, 105e18, 2e18);
        CallAuction.sortDescending(buys);
        assertEq(buys[0].id, 2); // higher price sorts first

        CallAuction.Order[] memory sells = new CallAuction.Order[](2);
        sells[0] = _order(3, 100e18, 2e18);
        sells[1] = _order(4, 95e18, 2e18);
        CallAuction.sortAscending(sells);
        assertEq(sells[0].id, 4); // lower price sorts first

        CallAuction.Result memory r = CallAuction.clear(buys, sells, 100e18, 500);
        assertEq(r.matchedQty, 4e18);
    }

    function testFuzz_MatchedVolumeNeverExceedsEitherSideTotal(
        uint128 buyQty,
        uint128 sellQty,
        uint96 buyPrice,
        uint96 sellPrice
    ) public pure {
        buyQty = uint128(bound(buyQty, 1, 1e24));
        sellQty = uint128(bound(sellQty, 1, 1e24));
        buyPrice = uint96(bound(buyPrice, 1, 1e24));
        sellPrice = uint96(bound(sellPrice, 1, 1e24));

        CallAuction.Order[] memory buys = new CallAuction.Order[](1);
        buys[0] = _order(1, buyPrice, buyQty);
        CallAuction.Order[] memory sells = new CallAuction.Order[](1);
        sells[0] = _order(2, sellPrice, sellQty);

        uint256 nav = (uint256(buyPrice) + sellPrice) / 2;
        CallAuction.Result memory r = CallAuction.clear(buys, sells, nav, 10_000); // 100% band, isolates the volume invariant

        uint256 maxPossible = buyQty < sellQty ? buyQty : sellQty;
        assertLe(r.matchedQty, maxPossible);
    }
}
