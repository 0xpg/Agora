// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CallAuction} from "./libraries/CallAuction.sol";
import {IdentityRegistry} from "./IdentityRegistry.sol";
import {NAVOracle} from "./NAVOracle.sol";

/// @notice Compliant secondary market for one tokenized asset, structured as a
/// periodic uniform-price call auction instead of a continuous AMM. Orders escrow
/// on submission; a round closes on a timer; anyone can trigger settlement, which
/// re-checks eligibility (not just at submit time — closes the "de-whitelisted
/// mid-round" gap), matches via CallAuction, and pays out/refunds in one pass.
contract BatchAuctionMarket is Ownable, ReentrancyGuard {
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

    // ---------------------------------------------------------------------
    // Round lifecycle
    // ---------------------------------------------------------------------

    /// @notice Permissionless: anyone can open the next round once the previous one
    /// is settled and NAV is fresh, so market continuity never depends on the issuer.
    function startRound() external {
        require(currentRoundSettled, "previous round not settled");
        require(!navOracle.isStale(), "stale NAV");

        currentRoundId++;
        roundOpenAt = uint64(block.timestamp);
        roundCloseAt = roundOpenAt + roundDuration;
        currentRoundSettled = false;

        emit RoundStarted(currentRoundId, roundOpenAt, roundCloseAt);
    }

    function submitOrder(bool isBuy, uint256 price, uint256 qty) external nonReentrant returns (uint256 orderId) {
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

        (CallAuction.Order[] memory buys, uint256[] memory eligibleBuyIds) = _loadEligibleOrders(buyOrderIds[roundId]);
        (CallAuction.Order[] memory sells, uint256[] memory eligibleSellIds) =
            _loadEligibleOrders(sellOrderIds[roundId]);
        _refundIneligible(buyOrderIds[roundId], eligibleBuyIds, true);
        _refundIneligible(sellOrderIds[roundId], eligibleSellIds, false);

        CallAuction.sortDescending(buys);
        CallAuction.sortAscending(sells);

        (uint256 nav,) = navOracle.getNAV();
        CallAuction.Result memory result = CallAuction.clear(buys, sells, nav, navBandBps);

        _settleSide(buys, true, result.clearingPrice);
        _settleSide(sells, false, result.clearingPrice);

        emit RoundSettled(roundId, result.clearingPrice, result.matchedQty);
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _loadEligibleOrders(uint256[] storage ids)
        private
        view
        returns (CallAuction.Order[] memory loaded, uint256[] memory eligibleIds)
    {
        uint256 n = ids.length;
        CallAuction.Order[] memory tmp = new CallAuction.Order[](n);
        uint256[] memory tmpIds = new uint256[](n);
        uint256 count;

        for (uint256 i = 0; i < n; i++) {
            uint256 id = ids[i];
            StoredOrder storage o = orders[id];
            if (o.qty > 0 && identityRegistry.isEligible(o.trader)) {
                tmp[count] = CallAuction.Order({id: id, trader: o.trader, price: o.price, qty: o.qty});
                tmpIds[count] = id;
                count++;
            }
        }

        loaded = new CallAuction.Order[](count);
        eligibleIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            loaded[i] = tmp[i];
            eligibleIds[i] = tmpIds[i];
        }
    }

    /// @dev Full refund for any order excluded from matching because its trader
    /// failed the eligibility re-check at settlement time.
    function _refundIneligible(uint256[] storage ids, uint256[] memory eligibleIds, bool isBuy) private {
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            StoredOrder storage o = orders[id];
            if (o.qty == 0) continue;

            bool eligible;
            for (uint256 j = 0; j < eligibleIds.length; j++) {
                if (eligibleIds[j] == id) {
                    eligible = true;
                    break;
                }
            }
            if (eligible) continue;

            uint256 qty = o.qty;
            o.qty = 0;
            o.settled = true;
            if (isBuy) {
                settlementToken.safeTransfer(o.trader, (o.price * qty) / PRICE_SCALE);
            } else {
                assetToken.safeTransfer(o.trader, qty);
            }
        }
    }

    /// @dev Pays out the filled portion and refunds the unmatched remainder for
    /// every order in `postClear`, whose `.qty` CallAuction.clear left holding the
    /// unfilled remainder (0 if fully matched).
    function _settleSide(CallAuction.Order[] memory postClear, bool isBuy, uint256 clearingPrice) private {
        for (uint256 i = 0; i < postClear.length; i++) {
            CallAuction.Order memory o = postClear[i];
            StoredOrder storage stored = orders[o.id];
            uint256 filled = stored.qty - o.qty;
            stored.qty = 0;
            stored.settled = true;

            if (isBuy) {
                if (filled > 0) {
                    assetToken.safeTransfer(o.trader, filled);
                }
                uint256 refund =
                    (filled * (stored.price - clearingPrice)) / PRICE_SCALE + (o.qty * stored.price) / PRICE_SCALE;
                if (refund > 0) {
                    settlementToken.safeTransfer(o.trader, refund);
                }
            } else {
                if (filled > 0) {
                    settlementToken.safeTransfer(o.trader, (filled * clearingPrice) / PRICE_SCALE);
                }
                if (o.qty > 0) {
                    assetToken.safeTransfer(o.trader, o.qty);
                }
            }
        }
    }
}
