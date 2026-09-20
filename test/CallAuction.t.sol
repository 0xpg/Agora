// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CallAuction} from "../src/libraries/CallAuction.sol";

contract CallAuctionTest is Test {
    function _order(uint256 id, uint256 price, uint256 qty) private pure returns (CallAuction.Order memory) {
        return CallAuction.Order({id: id, trader: address(uint160(id)), price: price, qty: qty});
    }

    function test_VoidsRoundWhenNoCrossing() public pure {
        CallAuction.Order[] memory buys = new CallAuction.Order[](1);
        buys[0] = _order(1, 90e18, 5e18);
        CallAuction.Order[] memory sells = new CallAuction.Order[](1);
        sells[0] = _order(2, 100e18, 5e18);

        CallAuction.Result memory r = CallAuction.clear(buys, sells, 95e18, 500);

        assertEq(r.matchedQty, 0);
        assertEq(r.fills.length, 0);
    }

    function test_FallsBackToMarginalPricingWhenOneSideExhausted() public pure {
        CallAuction.Order[] memory buys = new CallAuction.Order[](1);
        buys[0] = _order(1, 110e18, 5e18);
        CallAuction.Order[] memory sells = new CallAuction.Order[](1);
        sells[0] = _order(2, 90e18, 5e18);

        CallAuction.Result memory r = CallAuction.clear(buys, sells, 100e18, 500);

        assertEq(r.buyPrice, 110e18);
        assertEq(r.sellPrice, 90e18);
        assertEq(r.matchedQty, 5e18);
    }

    function test_ClearsAtSinglePriceWhenNextOrdersBracketMarginals() public pure {
        CallAuction.Order[] memory buys = new CallAuction.Order[](3);
        buys[0] = _order(1, 150e18, 3e18);
        buys[1] = _order(2, 130e18, 2e18);
        buys[2] = _order(3, 110e18, 5e18);
        CallAuction.sortDescending(buys);

        CallAuction.Order[] memory sells = new CallAuction.Order[](3);
        sells[0] = _order(4, 100e18, 2e18);
        sells[1] = _order(5, 115e18, 3e18);
        sells[2] = _order(6, 120e18, 6e18);
        CallAuction.sortAscending(sells);

        CallAuction.Result memory r = CallAuction.clear(buys, sells, 115e18, 10_000);

        assertEq(r.buyPrice, 115e18);
        assertEq(r.sellPrice, 115e18);
        assertEq(r.matchedQty, 5e18);
        assertEq(r.fills.length, 3);
    }

    function test_ReducesTradeAndSplitsPriceWhenNextOrdersDontBracket() public pure {
        CallAuction.Order[] memory buys = new CallAuction.Order[](3);
        buys[0] = _order(1, 150e18, 3e18);
        buys[1] = _order(2, 130e18, 4e18);
        buys[2] = _order(3, 110e18, 2e18);
        CallAuction.sortDescending(buys);

        CallAuction.Order[] memory sells = new CallAuction.Order[](3);
        sells[0] = _order(4, 100e18, 2e18);
        sells[1] = _order(5, 115e18, 3e18);
        sells[2] = _order(6, 125e18, 6e18);
        CallAuction.sortAscending(sells);

        CallAuction.Result memory r = CallAuction.clear(buys, sells, 127e18, 10_000);

        assertEq(r.buyPrice, 130e18);
        assertEq(r.sellPrice, 125e18);
        assertEq(r.matchedQty, 5e18);
        assertEq(r.fills.length, 3);
    }

    function test_VoidsRoundWhenSplitPriceMidpointOutsideBand() public pure {
        CallAuction.Order[] memory buys = new CallAuction.Order[](3);
        buys[0] = _order(1, 150e18, 3e18);
        buys[1] = _order(2, 130e18, 4e18);
        buys[2] = _order(3, 110e18, 2e18);
        CallAuction.sortDescending(buys);

        CallAuction.Order[] memory sells = new CallAuction.Order[](3);
        sells[0] = _order(4, 100e18, 2e18);
        sells[1] = _order(5, 115e18, 3e18);
        sells[2] = _order(6, 125e18, 6e18);
        CallAuction.sortAscending(sells);

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

    function test_VoidedRoundLeavesOrderQuantitiesUntouched() public pure {
        CallAuction.Order[] memory buys = new CallAuction.Order[](3);
        buys[0] = _order(1, 150e18, 3e18);
        buys[1] = _order(2, 130e18, 4e18);
        buys[2] = _order(3, 110e18, 2e18);
        CallAuction.sortDescending(buys);

        CallAuction.Order[] memory sells = new CallAuction.Order[](3);
        sells[0] = _order(4, 100e18, 2e18);
        sells[1] = _order(5, 115e18, 3e18);
        sells[2] = _order(6, 125e18, 6e18);
        CallAuction.sortAscending(sells);

        CallAuction.clear(buys, sells, 100e18, 500);

        assertEq(buys[0].qty, 3e18);
        assertEq(buys[1].qty, 4e18);
        assertEq(buys[2].qty, 2e18);
        assertEq(sells[0].qty, 2e18);
        assertEq(sells[1].qty, 3e18);
        assertEq(sells[2].qty, 6e18);
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
        CallAuction.Result memory r = CallAuction.clear(buys, sells, nav, 10_000);

        uint256 maxPossible = buyQty < sellQty ? buyQty : sellQty;
        assertLe(r.matchedQty, maxPossible);
        if (r.matchedQty > 0) {
            assertLe(r.sellPrice, r.buyPrice);
        }
    }

    function testFuzz_SpreadIsNeverNegative(
        uint128 b1,
        uint128 b2,
        uint128 s1,
        uint128 s2,
        uint96 p1,
        uint96 p2,
        uint96 p3,
        uint96 p4
    ) public pure {
        CallAuction.Order[] memory buys = new CallAuction.Order[](2);
        buys[0] = _order(1, bound(p1, 1, 1e24), bound(b1, 1, 1e22));
        buys[1] = _order(2, bound(p2, 1, 1e24), bound(b2, 1, 1e22));
        CallAuction.sortDescending(buys);

        CallAuction.Order[] memory sells = new CallAuction.Order[](2);
        sells[0] = _order(3, bound(p3, 1, 1e24), bound(s1, 1, 1e22));
        sells[1] = _order(4, bound(p4, 1, 1e24), bound(s2, 1, 1e22));
        CallAuction.sortAscending(sells);

        CallAuction.Result memory r = CallAuction.clear(buys, sells, 5e23, 10_000);

        if (r.matchedQty > 0) {
            assertGe(r.buyPrice, r.sellPrice);
        }
    }
}
