// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library CallAuction {
    struct Order {
        uint256 id;
        address trader;
        uint256 price;
        uint256 qty;
    }

    struct Fill {
        uint256 buyId;
        uint256 sellId;
        uint256 qty;
    }

    struct Result {
        uint256 clearingPrice;
        uint256 matchedQty;
        Fill[] fills;
    }

    uint256 internal constant BPS_DENOMINATOR = 10_000;

    function sortDescending(Order[] memory orders) internal pure {
        for (uint256 i = 1; i < orders.length; i++) {
            Order memory key = orders[i];
            uint256 j = i;
            while (j > 0 && orders[j - 1].price < key.price) {
                orders[j] = orders[j - 1];
                j--;
            }
            orders[j] = key;
        }
    }

    function sortAscending(Order[] memory orders) internal pure {
        for (uint256 i = 1; i < orders.length; i++) {
            Order memory key = orders[i];
            uint256 j = i;
            while (j > 0 && orders[j - 1].price > key.price) {
                orders[j] = orders[j - 1];
                j--;
            }
            orders[j] = key;
        }
    }

    function clear(Order[] memory buys, Order[] memory sells, uint256 navPrice, uint256 navBandBps)
        internal
        pure
        returns (Result memory result)
    {
        Fill[] memory fills = new Fill[](buys.length + sells.length);
        uint256 fillCount;
        uint256 matched;
        uint256 marginalSellPrice;
        uint256 marginalBuyPrice;

        uint256 i;
        uint256 j;
        while (i < buys.length && j < sells.length && buys[i].price >= sells[j].price) {
            uint256 qty = buys[i].qty < sells[j].qty ? buys[i].qty : sells[j].qty;
            if (qty > 0) {
                fills[fillCount++] = Fill({buyId: buys[i].id, sellId: sells[j].id, qty: qty});
                matched += qty;
                buys[i].qty -= qty;
                sells[j].qty -= qty;
                marginalBuyPrice = buys[i].price;
                marginalSellPrice = sells[j].price;
            }
            if (buys[i].qty == 0) i++;
            if (sells[j].qty == 0) j++;
        }

        if (matched == 0) {
            return result;
        }

        uint256 clearingPrice = navPrice;
        if (clearingPrice < marginalSellPrice) clearingPrice = marginalSellPrice;
        if (clearingPrice > marginalBuyPrice) clearingPrice = marginalBuyPrice;

        uint256 bandLow = navPrice - (navPrice * navBandBps) / BPS_DENOMINATOR;
        uint256 bandHigh = navPrice + (navPrice * navBandBps) / BPS_DENOMINATOR;
        if (clearingPrice < bandLow || clearingPrice > bandHigh) {
            return result;
        }

        Fill[] memory trimmedFills = new Fill[](fillCount);
        for (uint256 k = 0; k < fillCount; k++) {
            trimmedFills[k] = fills[k];
        }

        result.clearingPrice = clearingPrice;
        result.matchedQty = matched;
        result.fills = trimmedFills;
    }
}
