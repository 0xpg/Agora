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
        uint256 buyPrice;
        uint256 sellPrice;
        uint256 matchedQty;
        Fill[] fills;
    }

    struct Walk {
        Fill[] fills;
        uint256 fillCount;
        uint256 matched;
        uint256 marginalBuyPrice;
        uint256 marginalSellPrice;
        uint256 lastFillQty;
        uint256 lastBuyIdx;
        uint256 lastSellIdx;
        uint256 nextBuyIdx;
        uint256 nextSellIdx;
        bool hasNextBuy;
        bool hasNextSell;
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
        uint256[] memory buyRem = new uint256[](buys.length);
        uint256[] memory sellRem = new uint256[](sells.length);
        for (uint256 x = 0; x < buys.length; x++) {
            buyRem[x] = buys[x].qty;
        }
        for (uint256 y = 0; y < sells.length; y++) {
            sellRem[y] = sells[y].qty;
        }

        Walk memory w = _walk(buys, sells, buyRem, sellRem);
        if (w.matched == 0) {
            return result;
        }

        (uint256 buyPrice, uint256 sellPrice, uint256 tradedQty) = _price(buys, sells, w, buyRem, sellRem);
        if (tradedQty == 0 || !_withinBand(buyPrice, sellPrice, navPrice, navBandBps)) {
            return result;
        }

        for (uint256 x = 0; x < buys.length; x++) {
            buys[x].qty = buyRem[x];
        }
        for (uint256 y = 0; y < sells.length; y++) {
            sells[y].qty = sellRem[y];
        }

        Fill[] memory trimmedFills = new Fill[](w.fillCount);
        for (uint256 k = 0; k < w.fillCount; k++) {
            trimmedFills[k] = w.fills[k];
        }

        result.buyPrice = buyPrice;
        result.sellPrice = sellPrice;
        result.matchedQty = tradedQty;
        result.fills = trimmedFills;
    }

    function _walk(Order[] memory buys, Order[] memory sells, uint256[] memory buyRem, uint256[] memory sellRem)
        private
        pure
        returns (Walk memory w)
    {
        w.fills = new Fill[](buys.length + sells.length);
        uint256 i;
        uint256 j;
        while (i < buys.length && j < sells.length && buys[i].price >= sells[j].price) {
            uint256 qty = buyRem[i] < sellRem[j] ? buyRem[i] : sellRem[j];
            if (qty > 0) {
                w.fills[w.fillCount] = Fill({buyId: buys[i].id, sellId: sells[j].id, qty: qty});
                w.fillCount++;
                w.matched += qty;
                buyRem[i] -= qty;
                sellRem[j] -= qty;
                w.marginalBuyPrice = buys[i].price;
                w.marginalSellPrice = sells[j].price;
                w.lastFillQty = qty;
                w.lastBuyIdx = i;
                w.lastSellIdx = j;
            }
            if (buyRem[i] == 0) i++;
            if (sellRem[j] == 0) j++;
        }
        w.hasNextBuy = i < buys.length;
        w.hasNextSell = j < sells.length;
        w.nextBuyIdx = i;
        w.nextSellIdx = j;
    }

    function _price(
        Order[] memory buys,
        Order[] memory sells,
        Walk memory w,
        uint256[] memory buyRem,
        uint256[] memory sellRem
    ) private pure returns (uint256 buyPrice, uint256 sellPrice, uint256 tradedQty) {
        tradedQty = w.matched;
        if (w.hasNextBuy && w.hasNextSell) {
            uint256 p0 = (buys[w.nextBuyIdx].price + sells[w.nextSellIdx].price) / 2;
            if (p0 <= w.marginalBuyPrice && p0 >= w.marginalSellPrice) {
                buyPrice = p0;
                sellPrice = p0;
            } else {
                buyPrice = w.marginalBuyPrice;
                sellPrice = w.marginalSellPrice;
                tradedQty = w.matched - w.lastFillQty;
                buyRem[w.lastBuyIdx] += w.lastFillQty;
                sellRem[w.lastSellIdx] += w.lastFillQty;
                w.fillCount--;
            }
        } else {
            buyPrice = w.marginalBuyPrice;
            sellPrice = w.marginalSellPrice;
        }
    }

    function _withinBand(uint256 buyPrice, uint256 sellPrice, uint256 navPrice, uint256 navBandBps)
        private
        pure
        returns (bool)
    {
        uint256 mid = (buyPrice + sellPrice) / 2;
        uint256 bandLow = navPrice - (navPrice * navBandBps) / BPS_DENOMINATOR;
        uint256 bandHigh = navPrice + (navPrice * navBandBps) / BPS_DENOMINATOR;
        return mid >= bandLow && mid <= bandHigh;
    }
}
