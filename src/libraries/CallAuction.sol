// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Uniform-price call auction matching for one round of one market.
///
/// Why a call auction instead of an AMM: an AMM anchored to an external reference
/// price (like an issuer NAV) suffers Loss-Versus-Rebalancing (Milionis, Moallemi,
/// Roughgarden & Zhang, arXiv:2208.06046) — whoever sees a NAV update first trades
/// against the pool before it reprices, extracting the gap from LPs. A call auction
/// removes the stale-price window entirely: every order in the round clears at one
/// price, computed only after the round closes, using the NAV known at that moment.
///
/// Standard call-auction result: for sorted order books, cumulative demand is
/// non-increasing in price and cumulative supply is non-decreasing in price, so the
/// set of prices maximizing matched volume is a closed interval [marginalSellPrice,
/// marginalBuyPrice] bounded by the last (marginal) orders that cross. Agora picks
/// the point in that interval closest to the issuer's NAV, then voids the round if
/// even that point falls outside the configured NAV band — keeping every clearing
/// price anchored without needing a continuous rebalancer.
library CallAuction {
    struct Order {
        uint256 id;
        address trader;
        uint256 price; // settlement-token base units per 1e18 asset-token units
        uint256 qty; // asset-token units, 1e18 scale; mutated in place to the unmatched remainder
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

    /// @dev Insertion sort, descending by price. O(n^2) — fine for the small,
    /// per-round order counts a round-based RWA market sees; revisit if volume grows.
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

    /// @dev Insertion sort, ascending by price.
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

    /// @param buys Buy orders, must already be sorted descending by price (see sortDescending).
    /// @param sells Sell orders, must already be sorted ascending by price (see sortAscending).
    /// @param navPrice Issuer NAV at round close, same scale as order prices.
    /// @param navBandBps Max allowed deviation of the clearing price from navPrice, in basis points.
    /// Mutates `buys` and `sells` in place: each order's `qty` is left holding its
    /// unmatched remainder (0 if fully filled), so the caller can settle payouts and
    /// refunds directly from the same arrays without re-deriving fill state.
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
            // Volume-maximizing crossing exists, but only outside the issuer's NAV
            // band. Void the round rather than clear off-band; a future version can
            // re-run the match trimmed to the band instead of an all-or-nothing void.
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
