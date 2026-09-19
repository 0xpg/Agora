// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CallAuction} from "./libraries/CallAuction.sol";
import {IdentityRegistry} from "./IdentityRegistry.sol";
import {NAVOracle} from "./NAVOracle.sol";

/// @notice Compliant secondary market for one tokenized asset, structured as a
/// periodic uniform-price call auction instead of a continuous AMM. Orders escrow
/// on submission; a round closes on a timer; anyone can trigger settlement, which
/// re-checks eligibility (not just at submit time — closes the "de-whitelisted
/// mid-round" gap), matches via CallAuction, and pays out/refunds in one pass.
///
/// Ownable2Step: see NAVOracle's NatSpec for the same reasoning and its limits.
///
/// Pausable gates new trading activity — starting a round and submitting orders —
/// for issuer-controlled halts around distributions or corporate actions, the
/// real-world reason Theorem's own product has a pause switch. cancelOrder and
/// settleRound are deliberately NOT gated by it: a pause must never be able to
/// trap funds already escrowed in an open round, whether the investor wants it
/// back individually (cancelOrder) or the round runs its course (settleRound).
contract BatchAuctionMarket is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    struct StoredOrder {
        address trader;
        bool isBuy;
        uint256 price;
        uint256 qty; // remaining unfilled quantity; 0 once fully settled
        uint256 roundId;
        bool settled;
    }

    IERC20 public immutable assetToken;
    IERC20 public immutable settlementToken;
    IdentityRegistry public identityRegistry;
    NAVOracle public navOracle;

    uint64 public roundDuration;
    uint256 public navBandBps;

    uint256 public currentRoundId;
    uint64 public roundOpenAt;
    uint64 public roundCloseAt;
    bool public currentRoundSettled = true;

    uint256 public nextOrderId = 1;
    mapping(uint256 orderId => StoredOrder) public orders;
    mapping(uint256 roundId => uint256[]) public buyOrderIds;
    mapping(uint256 roundId => uint256[]) public sellOrderIds;

    event RoundStarted(uint256 indexed roundId, uint64 openAt, uint64 closeAt);
    event OrderSubmitted(
        uint256 indexed orderId, uint256 indexed roundId, address indexed trader, bool isBuy, uint256 price, uint256 qty
    );
    event OrderCancelled(uint256 indexed orderId);
    event RoundSettled(uint256 indexed roundId, uint256 clearingPrice, uint256 matchedQty);
    /// @dev Per-order settlement detail an indexer would otherwise have to
    /// reconstruct by correlating ERC20 Transfer events back to orders by hand.
    event BuyOrderSettled(uint256 indexed orderId, uint256 assetFilled, uint256 settlementRefunded);
    event SellOrderSettled(uint256 indexed orderId, uint256 settlementProceeds, uint256 assetRefunded);
    event OrderExcludedIneligible(uint256 indexed orderId, address indexed trader);
    event IdentityRegistryUpdated(address indexed registry);
    event NAVOracleUpdated(address indexed oracle);
    event RoundDurationUpdated(uint64 roundDuration);
    event NAVBandUpdated(uint256 navBandBps);

    uint256 private constant PRICE_SCALE = 1e18;

    constructor(
        address _assetToken,
        address _settlementToken,
        address _identityRegistry,
        address _navOracle,
        address issuer,
        uint64 _roundDuration,
        uint256 _navBandBps
    ) Ownable(issuer) {
        assetToken = IERC20(_assetToken);
        settlementToken = IERC20(_settlementToken);
        identityRegistry = IdentityRegistry(_identityRegistry);
        navOracle = NAVOracle(_navOracle);
        roundDuration = _roundDuration;
        navBandBps = _navBandBps;
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    function setIdentityRegistry(address registry) external onlyOwner {
        identityRegistry = IdentityRegistry(registry);
        emit IdentityRegistryUpdated(registry);
    }

    function setNAVOracle(address oracle) external onlyOwner {
        navOracle = NAVOracle(oracle);
        emit NAVOracleUpdated(oracle);
    }

    function setRoundDuration(uint64 _roundDuration) external onlyOwner {
        require(_roundDuration > 0, "roundDuration=0");
        roundDuration = _roundDuration;
        emit RoundDurationUpdated(_roundDuration);
    }

    function setNAVBandBps(uint256 _navBandBps) external onlyOwner {
        require(_navBandBps <= CallAuction.BPS_DENOMINATOR, "band>100%");
        navBandBps = _navBandBps;
        emit NAVBandUpdated(_navBandBps);
    }

    /// @notice Halts new trading activity (see contract NatSpec). Existing orders
    /// remain cancellable throughout — a pause stops new activity, never withdrawals.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ---------------------------------------------------------------------
    // Round lifecycle
    // ---------------------------------------------------------------------

    /// @notice Permissionless: anyone can open the next round once the previous one
    /// is settled and NAV is fresh, so market continuity never depends on the issuer.
    function startRound() external whenNotPaused {
        require(currentRoundSettled, "previous round not settled");
        require(!navOracle.isStale(), "stale NAV");

        currentRoundId++;
        roundOpenAt = uint64(block.timestamp);
        roundCloseAt = roundOpenAt + roundDuration;
        currentRoundSettled = false;

        emit RoundStarted(currentRoundId, roundOpenAt, roundCloseAt);
    }

    function submitOrder(bool isBuy, uint256 price, uint256 qty)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 orderId)
    {
        require(!currentRoundSettled, "no open round");
        require(block.timestamp < roundCloseAt, "round closed");
        require(price > 0 && qty > 0, "price/qty=0");
        require(identityRegistry.isEligible(msg.sender), "ineligible");

        orderId = nextOrderId++;
        orders[orderId] = StoredOrder({
            trader: msg.sender, isBuy: isBuy, price: price, qty: qty, roundId: currentRoundId, settled: false
        });

        if (isBuy) {
            buyOrderIds[currentRoundId].push(orderId);
            settlementToken.safeTransferFrom(msg.sender, address(this), (price * qty) / PRICE_SCALE);
        } else {
            sellOrderIds[currentRoundId].push(orderId);
            assetToken.safeTransferFrom(msg.sender, address(this), qty);
        }

        emit OrderSubmitted(orderId, currentRoundId, msg.sender, isBuy, price, qty);
    }

    /// @notice Cancel and fully refund an order before its round closes.
    function cancelOrder(uint256 orderId) external nonReentrant {
        StoredOrder storage o = orders[orderId];
        require(o.trader == msg.sender, "not your order");
        require(!o.settled, "already settled");
        require(o.roundId == currentRoundId && block.timestamp < roundCloseAt, "round closed");

        uint256 qty = o.qty;
        o.qty = 0;
        o.settled = true;

        if (o.isBuy) {
            settlementToken.safeTransfer(msg.sender, (o.price * qty) / PRICE_SCALE);
        } else {
            assetToken.safeTransfer(msg.sender, qty);
        }

        emit OrderCancelled(orderId);
    }

    /// @notice Permissionless settlement: matches the round via CallAuction, then
    /// pays out/refunds every order in one pass from the (mutated in place) arrays.
    function settleRound() external nonReentrant {
        require(!currentRoundSettled, "no open round");
        require(block.timestamp >= roundCloseAt, "round still open");
        require(!navOracle.isStale(), "stale NAV");

        uint256 roundId = currentRoundId;
        currentRoundSettled = true;

        CallAuction.Order[] memory buys = _loadEligibleAndRefundRest(buyOrderIds[roundId], true);
        CallAuction.Order[] memory sells = _loadEligibleAndRefundRest(sellOrderIds[roundId], false);

        CallAuction.sortDescending(buys);
        CallAuction.sortAscending(sells);

        (uint256 nav,) = navOracle.getNAV();
        CallAuction.Result memory result = CallAuction.clear(buys, sells, nav, navBandBps);

        uint256 sellerPool = _settleBuys(buys, result.clearingPrice);
        _settleSells(sells, result.clearingPrice, sellerPool);

        emit RoundSettled(roundId, result.clearingPrice, result.matchedQty);
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    /// @dev Single O(n) pass: orders whose trader is currently eligible are
    /// returned for matching; every other non-empty order is refunded immediately
    /// and excluded. An earlier version filtered to the eligible subset first and
    /// then re-scanned it per order to refund the rest — an O(n*m) nested search
    /// that could make settleRound() exceed the block gas limit, permanently
    /// stuck, on a round with enough orders. Classifying each order exactly once
    /// removes that DoS surface entirely.
    function _loadEligibleAndRefundRest(uint256[] storage ids, bool isBuy)
        private
        returns (CallAuction.Order[] memory loaded)
    {
        uint256 n = ids.length;
        CallAuction.Order[] memory tmp = new CallAuction.Order[](n);
        uint256 count;

        for (uint256 i = 0; i < n; i++) {
            uint256 id = ids[i];
            StoredOrder storage o = orders[id];
            if (o.qty == 0) continue;

            if (identityRegistry.isEligible(o.trader)) {
                tmp[count++] = CallAuction.Order({id: id, trader: o.trader, price: o.price, qty: o.qty});
                continue;
            }

            uint256 qty = o.qty;
            o.qty = 0;
            o.settled = true;
            if (isBuy) {
                settlementToken.safeTransfer(o.trader, (o.price * qty) / PRICE_SCALE);
            } else {
                assetToken.safeTransfer(o.trader, qty);
            }
            emit OrderExcludedIneligible(id, o.trader);
        }

        loaded = new CallAuction.Order[](count);
        for (uint256 i = 0; i < count; i++) {
            loaded[i] = tmp[i];
        }
    }

    /// @dev Settles every buy order: delivers the filled asset-token amount, refunds
    /// the rest of the escrow, and returns the total settlement token retained (not
    /// refunded) across all of them — the exact pot sellers must be paid from.
    /// Refund is escrow minus the retained portion, by subtraction, so each buy
    /// order is exactly self-consistent (its own escrow, filled, and refund always
    /// sum correctly) regardless of how price*qty/1e18 happens to round.
    function _settleBuys(CallAuction.Order[] memory postClear, uint256 clearingPrice)
        private
        returns (uint256 sellerPool)
    {
        for (uint256 i = 0; i < postClear.length; i++) {
            CallAuction.Order memory o = postClear[i];
            StoredOrder storage stored = orders[o.id];
            uint256 originalQty = stored.qty;
            uint256 filled = originalQty - o.qty;
            stored.qty = 0;
            stored.settled = true;

            if (filled > 0) {
                assetToken.safeTransfer(o.trader, filled);
            }
            uint256 originalEscrow = (stored.price * originalQty) / PRICE_SCALE;
            uint256 retained = (filled * clearingPrice) / PRICE_SCALE;
            sellerPool += retained;
            uint256 refund = originalEscrow - retained;
            if (refund > 0) {
                settlementToken.safeTransfer(o.trader, refund);
            }
            emit BuyOrderSettled(o.id, filled, refund);
        }
    }

    /// @dev Settles every sell order: delivers proceeds for the filled portion and
    /// refunds the unmatched remainder. Every filled order except the last one is
    /// paid via the standard per-order formula (floor(filled*clearingPrice/1e18)),
    /// which can individually round down by a fraction of a unit; the last filled
    /// order is instead paid exactly `sellerPool` minus what's already been paid
    /// out, absorbing the accumulated rounding remainder so the sum paid to sellers
    /// always equals `sellerPool` exactly — not just in expectation. Distributing
    /// each seller's own formula-computed share independently, with no such
    /// reconciliation, can under-total sellerPool by up to (order count - 1) units
    /// even though every individual order's math looks correct in isolation; that
    /// gap would silently and permanently strand settlement token in the contract.
    function _settleSells(CallAuction.Order[] memory postClear, uint256 clearingPrice, uint256 sellerPool) private {
        uint256 lastFilledIndex = type(uint256).max;
        for (uint256 i = 0; i < postClear.length; i++) {
            if (orders[postClear[i].id].qty > postClear[i].qty) lastFilledIndex = i;
        }

        uint256 distributed;
        for (uint256 i = 0; i < postClear.length; i++) {
            CallAuction.Order memory o = postClear[i];
            StoredOrder storage stored = orders[o.id];
            uint256 filled = stored.qty - o.qty;
            stored.qty = 0;
            stored.settled = true;

            uint256 proceeds;
            if (filled > 0) {
                proceeds = i == lastFilledIndex ? sellerPool - distributed : (filled * clearingPrice) / PRICE_SCALE;
                distributed += proceeds;
                if (proceeds > 0) {
                    settlementToken.safeTransfer(o.trader, proceeds);
                }
            }
            if (o.qty > 0) {
                assetToken.safeTransfer(o.trader, o.qty);
            }
            emit SellOrderSettled(o.id, proceeds, o.qty);
        }
    }
}
