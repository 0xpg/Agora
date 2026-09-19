// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CallAuction} from "./libraries/CallAuction.sol";
import {IEligibilityOracle} from "./interfaces/IEligibilityOracle.sol";
import {NAVOracle} from "./NAVOracle.sol";

contract BatchAuctionMarket is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    struct StoredOrder {
        address trader;
        bool isBuy;
        uint256 price;
        uint256 qty;
        uint256 roundId;
        bool settled;
    }

    struct MakerProgram {
        address maker;
        uint256 maxSpreadBps;
        uint256 rebatePerRound;
        uint256 minOrganicOrdersPerSide;
        uint256 graduationRounds;
        uint256 consecutiveOrganicRounds;
        bool active;
    }

    IERC20 public immutable assetToken;
    IERC20 public immutable settlementToken;
    IEligibilityOracle public identityRegistry;
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
    event RoundSettled(uint256 indexed roundId, uint256 buyPrice, uint256 sellPrice, uint256 matchedQty);
    event BuyOrderSettled(uint256 indexed orderId, uint256 assetFilled, uint256 settlementRefunded);
    event SellOrderSettled(uint256 indexed orderId, uint256 settlementProceeds, uint256 assetRefunded);
    event OrderExcludedIneligible(uint256 indexed orderId, address indexed trader);
    event IdentityRegistryUpdated(address indexed registry);
    event NAVOracleUpdated(address indexed oracle);
    event RoundDurationUpdated(uint64 roundDuration);
    event NAVBandUpdated(uint256 navBandBps);
    event SpreadWithdrawn(address indexed to, uint256 amount);
    event MakerProgramSet(
        address indexed maker,
        uint256 maxSpreadBps,
        uint256 rebatePerRound,
        uint256 minOrganicOrdersPerSide,
        uint256 graduationRounds
    );
    event MakerProgramGraduated(uint256 indexed roundId);
    event MakerRebatePaid(uint256 indexed roundId, address indexed maker, uint256 amount);

    uint256 private constant PRICE_SCALE = 1e18;
    uint256 public accumulatedSpread;
    MakerProgram public makerProgram;

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
        identityRegistry = IEligibilityOracle(_identityRegistry);
        navOracle = NAVOracle(_navOracle);
        roundDuration = _roundDuration;
        navBandBps = _navBandBps;
    }

    function setIdentityRegistry(address registry) external onlyOwner {
        identityRegistry = IEligibilityOracle(registry);
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

    function withdrawSpread(address to, uint256 amount) external onlyOwner nonReentrant {
        accumulatedSpread -= amount;
        settlementToken.safeTransfer(to, amount);
        emit SpreadWithdrawn(to, amount);
    }

    function setMakerProgram(
        address maker,
        uint256 maxSpreadBps,
        uint256 rebatePerRound,
        uint256 minOrganicOrdersPerSide,
        uint256 graduationRounds
    ) external onlyOwner {
        if (maker != address(0)) {
            require(maxSpreadBps > 0 && maxSpreadBps <= CallAuction.BPS_DENOMINATOR, "spread bps");
            require(graduationRounds > 0, "graduationRounds=0");
        }
        makerProgram = MakerProgram({
            maker: maker,
            maxSpreadBps: maxSpreadBps,
            rebatePerRound: rebatePerRound,
            minOrganicOrdersPerSide: minOrganicOrdersPerSide,
            graduationRounds: graduationRounds,
            consecutiveOrganicRounds: 0,
            active: maker != address(0)
        });
        emit MakerProgramSet(maker, maxSpreadBps, rebatePerRound, minOrganicOrdersPerSide, graduationRounds);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

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

        uint256 collected = _settleBuys(buys, result.buyPrice);
        uint256 paid = _settleSells(sells, result.sellPrice);
        if (collected >= paid) {
            accumulatedSpread += collected - paid;
        } else {
            uint256 shortfall = paid - collected;
            accumulatedSpread = accumulatedSpread > shortfall ? accumulatedSpread - shortfall : 0;
        }

        _settleMakerProgram(roundId);

        emit RoundSettled(roundId, result.buyPrice, result.sellPrice, result.matchedQty);
    }

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

    function _settleBuys(CallAuction.Order[] memory postClear, uint256 buyPrice) private returns (uint256 collected) {
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
            uint256 retained = (filled * buyPrice) / PRICE_SCALE;
            collected += retained;
            uint256 originalEscrow = (stored.price * originalQty) / PRICE_SCALE;
            uint256 refund = originalEscrow - retained;
            if (refund > 0) {
                settlementToken.safeTransfer(o.trader, refund);
            }
            emit BuyOrderSettled(o.id, filled, refund);
        }
    }

    function _settleSells(CallAuction.Order[] memory postClear, uint256 sellPrice) private returns (uint256 paid) {
        for (uint256 i = 0; i < postClear.length; i++) {
            CallAuction.Order memory o = postClear[i];
            StoredOrder storage stored = orders[o.id];
            uint256 filled = stored.qty - o.qty;
            stored.qty = 0;
            stored.settled = true;

            uint256 proceeds = (filled * sellPrice) / PRICE_SCALE;
            paid += proceeds;
            if (proceeds > 0) {
                settlementToken.safeTransfer(o.trader, proceeds);
            }
            if (o.qty > 0) {
                assetToken.safeTransfer(o.trader, o.qty);
            }
            emit SellOrderSettled(o.id, proceeds, o.qty);
        }
    }

    function _settleMakerProgram(uint256 roundId) private {
        if (!makerProgram.active) return;

        (bool hasBuy, uint256 bestBuy, uint256 nonMakerBuys) = _makerSide(buyOrderIds[roundId], true);
        (bool hasSell, uint256 bestSell, uint256 nonMakerSells) = _makerSide(sellOrderIds[roundId], false);

        bool organic = nonMakerBuys >= makerProgram.minOrganicOrdersPerSide
            && nonMakerSells >= makerProgram.minOrganicOrdersPerSide;
        makerProgram.consecutiveOrganicRounds = organic ? makerProgram.consecutiveOrganicRounds + 1 : 0;

        if (hasBuy && hasSell && _makerQuoteQualifies(bestBuy, bestSell)) {
            _payMakerRebate(roundId);
        }

        if (makerProgram.consecutiveOrganicRounds >= makerProgram.graduationRounds) {
            makerProgram.active = false;
            emit MakerProgramGraduated(roundId);
        }
    }

    function _makerSide(uint256[] storage ids, bool isBuy)
        private
        view
        returns (bool has, uint256 best, uint256 nonMakerCount)
    {
        best = isBuy ? 0 : type(uint256).max;
        for (uint256 i = 0; i < ids.length; i++) {
            StoredOrder storage o = orders[ids[i]];
            if (o.trader == makerProgram.maker) {
                has = true;
                if (isBuy ? o.price > best : o.price < best) {
                    best = o.price;
                }
            } else {
                nonMakerCount++;
            }
        }
    }

    function _makerQuoteQualifies(uint256 bestBuy, uint256 bestSell) private view returns (bool) {
        if (bestSell < bestBuy) return false;
        uint256 mid = (bestBuy + bestSell) / 2;
        (uint256 nav,) = navOracle.getNAV();
        uint256 bandLow = nav - (nav * navBandBps) / CallAuction.BPS_DENOMINATOR;
        uint256 bandHigh = nav + (nav * navBandBps) / CallAuction.BPS_DENOMINATOR;
        if (mid < bandLow || mid > bandHigh) return false;
        uint256 spreadBps = ((bestSell - bestBuy) * CallAuction.BPS_DENOMINATOR) / mid;
        return spreadBps <= makerProgram.maxSpreadBps;
    }

    function _payMakerRebate(uint256 roundId) private {
        uint256 rebate =
            accumulatedSpread < makerProgram.rebatePerRound ? accumulatedSpread : makerProgram.rebatePerRound;
        if (rebate == 0) return;
        accumulatedSpread -= rebate;
        settlementToken.safeTransfer(makerProgram.maker, rebate);
        emit MakerRebatePaid(roundId, makerProgram.maker, rebate);
    }
}
