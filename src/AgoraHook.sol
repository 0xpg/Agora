// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {NAVOracle} from "./NAVOracle.sol";

/// @notice NAV guard and dynamic fee policy for one permissioned Uniswap v4 pool.
/// @dev Trader/LP eligibility is enforced by Uniswap's PermissionsAdapter, permissioned router,
///      and PermissionedPositionManager. Deploy this contract at an address carrying the
///      BEFORE_INITIALIZE, BEFORE_SWAP, and AFTER_SWAP hook flags.
contract AgoraHook is IHooks, Ownable2Step {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using BalanceDeltaLibrary for BalanceDelta;

    IPoolManager public immutable poolManager;
    NAVOracle public immutable navOracle;
    Currency public immutable currency0;
    Currency public immutable currency1;

    uint160 public lowerSqrtPriceX96;
    uint160 public upperSqrtPriceX96;
    uint64 public bandNAVUpdatedAt;
    uint24 public baseFee;
    uint24 public edgeFee;
    uint160 public targetSqrtPriceX96;
    uint16 public directionalGuardBps;
    uint256 public maxSwapAmount;
    uint256 public largeSwapAmount;
    uint64 public largeSwapMaxStaleness;
    bool public paused;

    struct FlowRisk {
        uint64 epochDuration;
        uint64 epochStart;
        uint128 grossLimit;
        uint128 netLimit;
        uint128 grossFlow;
        int128 netAssetFlow;
        uint24 inventoryFeeMax;
        uint24 volatilityFeeMax;
        uint16 inventoryDeadBandBps;
        bool assetIsCurrency0;
        uint160 lastSqrtPriceX96;
    }

    FlowRisk public flowRisk;

    struct TemporaryPolicy {
        uint160 lowerSqrtPriceX96;
        uint160 upperSqrtPriceX96;
        uint24 baseFee;
        uint24 edgeFee;
        uint64 expiresAt;
    }

    TemporaryPolicy public temporaryPolicy;

    event PriceBandSynced(uint160 lowerSqrtPriceX96, uint160 upperSqrtPriceX96, uint64 navUpdatedAt);
    event FeesUpdated(uint24 baseFee, uint24 edgeFee);
    event PausedSet(bool paused);
    event RiskControlsUpdated(
        uint160 targetSqrtPriceX96,
        uint16 directionalGuardBps,
        uint256 maxSwapAmount,
        uint256 largeSwapAmount,
        uint64 largeSwapMaxStaleness
    );
    event TemporaryPolicyUpdated(uint160 lower, uint160 upper, uint24 baseFee, uint24 edgeFee, uint64 expiresAt);
    event FlowRiskUpdated(
        uint64 epochDuration,
        uint128 grossLimit,
        uint128 netLimit,
        uint24 inventoryFeeMax,
        uint24 volatilityFeeMax,
        uint16 inventoryDeadBandBps,
        bool assetIsCurrency0
    );
    event SwapRiskEvaluated(
        bool indexed zeroForOne,
        int256 amountSpecified,
        uint24 navFee,
        uint24 inventoryFee,
        uint24 volatilityFee,
        uint24 totalFee,
        uint128 epochGrossFlow,
        int128 epochNetAssetFlow,
        uint64 navUpdatedAt
    );
    event FlowRecorded(uint128 assetAmount, int128 netAssetFlow, uint128 grossFlow, uint64 epochStart);

    error NotPoolManager();
    error WrongPool();
    error StaleNAV();
    error UnsyncedPriceBand();
    error PriceOutsideBand();
    error SwapsPaused();
    error SwapTooLarge();
    error RebalanceOnly();
    error EpochGrossLimitExceeded();
    error EpochNetLimitExceeded();

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(
        IPoolManager _poolManager,
        NAVOracle _navOracle,
        Currency _currency0,
        Currency _currency1,
        address issuer,
        uint24 _baseFee,
        uint24 _edgeFee
    ) Ownable(issuer) {
        require(address(_poolManager) != address(0) && address(_navOracle) != address(0), "zero address");
        require(Currency.unwrap(_currency0) < Currency.unwrap(_currency1), "currency order");
        poolManager = _poolManager;
        navOracle = _navOracle;
        currency0 = _currency0;
        currency1 = _currency1;
        _setFees(_baseFee, _edgeFee);

        Hooks.validateHookPermissions(
            IHooks(address(this)),
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            })
        );
    }

    /// @notice Sync bounds whenever the issuer publishes a new NAV.
    /// @dev Bounds are sqrt(token1/token0) Q64.96 values, including token decimal scaling.
    function syncPriceBand(uint160 lower, uint160 upper) external onlyOwner {
        if (navOracle.isStale()) revert StaleNAV();
        require(lower > 0 && uint256(upper) - lower > 1, "bad band");
        (, uint64 updatedAt) = navOracle.getNAV();
        lowerSqrtPriceX96 = lower;
        upperSqrtPriceX96 = upper;
        if (targetSqrtPriceX96 == 0) targetSqrtPriceX96 = uint160((uint256(lower) + upper) / 2);
        bandNAVUpdatedAt = updatedAt;
        emit PriceBandSynced(lower, upper, updatedAt);
    }

    function setFees(uint24 _baseFee, uint24 _edgeFee) external onlyOwner {
        _setFees(_baseFee, _edgeFee);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PausedSet(_paused);
    }

    function setRiskControls(
        uint160 target,
        uint16 guardBps,
        uint256 _maxSwapAmount,
        uint256 _largeSwapAmount,
        uint64 _largeSwapMaxStaleness
    ) external onlyOwner {
        require(target > lowerSqrtPriceX96 && target < upperSqrtPriceX96 && guardBps <= 10_000, "bad risk controls");
        require(_largeSwapAmount == 0 || _largeSwapAmount <= _maxSwapAmount, "bad large swap");
        targetSqrtPriceX96 = target;
        directionalGuardBps = guardBps;
        maxSwapAmount = _maxSwapAmount;
        largeSwapAmount = _largeSwapAmount;
        largeSwapMaxStaleness = _largeSwapMaxStaleness;
        emit RiskControlsUpdated(target, guardBps, _maxSwapAmount, _largeSwapAmount, _largeSwapMaxStaleness);
    }

    function setTemporaryPolicy(uint160 lower, uint160 upper, uint24 _baseFee, uint24 _edgeFee, uint64 expiresAt)
        external
        onlyOwner
    {
        require(
            lower > 0 && upper > lower && targetSqrtPriceX96 > lower && targetSqrtPriceX96 < upper
                && expiresAt > block.timestamp,
            "bad temporary policy"
        );
        require(
            _baseFee <= _edgeFee
                && uint256(_edgeFee) + flowRisk.inventoryFeeMax + flowRisk.volatilityFeeMax <= LPFeeLibrary.MAX_LP_FEE,
            "bad fees"
        );
        temporaryPolicy = TemporaryPolicy(lower, upper, _baseFee, _edgeFee, expiresAt);
        emit TemporaryPolicyUpdated(lower, upper, _baseFee, _edgeFee, expiresAt);
    }

    function setFlowRisk(
        uint64 epochDuration,
        uint128 grossLimit,
        uint128 netLimit,
        uint24 inventoryFeeMax,
        uint24 volatilityFeeMax,
        uint16 inventoryDeadBandBps,
        bool assetIsCurrency0
    ) external onlyOwner {
        require(epochDuration != 0 && netLimit <= grossLimit, "bad flow limits");
        require(inventoryDeadBandBps <= 10_000, "bad dead band");
        require(uint256(edgeFee) + inventoryFeeMax + volatilityFeeMax <= LPFeeLibrary.MAX_LP_FEE, "fee overflow");
        flowRisk.epochDuration = epochDuration;
        flowRisk.epochStart = uint64(block.timestamp - (block.timestamp % epochDuration));
        flowRisk.grossLimit = grossLimit;
        flowRisk.netLimit = netLimit;
        flowRisk.grossFlow = 0;
        flowRisk.netAssetFlow = 0;
        flowRisk.inventoryFeeMax = inventoryFeeMax;
        flowRisk.volatilityFeeMax = volatilityFeeMax;
        flowRisk.inventoryDeadBandBps = inventoryDeadBandBps;
        flowRisk.assetIsCurrency0 = assetIsCurrency0;
        emit FlowRiskUpdated(
            epochDuration,
            grossLimit,
            netLimit,
            inventoryFeeMax,
            volatilityFeeMax,
            inventoryDeadBandBps,
            assetIsCurrency0
        );
    }

    function beforeInitialize(address, PoolKey calldata key, uint160 sqrtPriceX96)
        external
        onlyPoolManager
        returns (bytes4)
    {
        _checkPool(key);
        require(key.fee == LPFeeLibrary.DYNAMIC_FEE_FLAG, "dynamic fee required");
        _checkNAV();
        _checkPrice(sqrtPriceX96);
        return IHooks.beforeInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (paused) revert SwapsPaused();
        _checkPool(key);
        uint256 amount = _absolute(params.amountSpecified);
        if (maxSwapAmount != 0 && amount > maxSwapAmount) revert SwapTooLarge();
        _checkNAV(amount);
        _rollEpoch();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        _checkPrice(sqrtPriceX96);
        _checkDirection(sqrtPriceX96, params.zeroForOne);
        (uint24 navFee, uint24 inventoryFee, uint24 volatilityFee, uint24 totalFee) =
            feeBreakdown(sqrtPriceX96, params.zeroForOne);
        (, uint64 navUpdatedAt) = navOracle.getNAV();
        emit SwapRiskEvaluated(
            params.zeroForOne,
            params.amountSpecified,
            navFee,
            inventoryFee,
            volatilityFee,
            totalFee,
            flowRisk.grossFlow,
            flowRisk.netAssetFlow,
            navUpdatedAt
        );
        return
            (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, totalFee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta delta, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, int128)
    {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        _checkPrice(sqrtPriceX96);
        _recordFlow(delta, sqrtPriceX96);
        return (IHooks.afterSwap.selector, 0);
    }

    function _checkPool(PoolKey calldata key) private view {
        if (
            Currency.unwrap(key.currency0) != Currency.unwrap(currency0)
                || Currency.unwrap(key.currency1) != Currency.unwrap(currency1) || address(key.hooks) != address(this)
        ) revert WrongPool();
    }

    function _checkNAV() private view {
        _checkNAV(0);
    }

    function _checkNAV(uint256 amount) private view {
        if (navOracle.isStale()) revert StaleNAV();
        (, uint64 updatedAt) = navOracle.getNAV();
        if (updatedAt != bandNAVUpdatedAt) revert UnsyncedPriceBand();
        if (
            largeSwapAmount != 0 && amount >= largeSwapAmount
                && block.timestamp > uint256(updatedAt) + largeSwapMaxStaleness
        ) revert StaleNAV();
    }

    function _checkPrice(uint160 sqrtPriceX96) private view {
        (uint160 lower, uint160 upper,,) = activePolicy();
        if (sqrtPriceX96 < lower || sqrtPriceX96 > upper) revert PriceOutsideBand();
    }

    function feeBreakdown(uint160 price, bool zeroForOne)
        public
        view
        returns (uint24 navFee, uint24 inventoryFee, uint24 volatilityFee, uint24 totalFee)
    {
        navFee = _navFee(price);
        inventoryFee = _inventoryFee(zeroForOne);
        volatilityFee = _volatilityFee(price);
        totalFee = navFee + inventoryFee + volatilityFee;
    }

    function _navFee(uint160 price) private view returns (uint24) {
        (uint160 lower, uint160 upper, uint24 activeBaseFee, uint24 activeEdgeFee) = activePolicy();
        uint256 midpoint = targetSqrtPriceX96 == 0 ? (uint256(lower) + upper) / 2 : targetSqrtPriceX96;
        uint256 distance = price > midpoint ? price - midpoint : midpoint - price;
        uint256 span = price > midpoint ? upper - midpoint : midpoint - lower;
        if (distance > span) distance = span;
        return activeBaseFee + uint24((uint256(activeEdgeFee - activeBaseFee) * distance) / span);
    }

    function _inventoryFee(bool zeroForOne) private view returns (uint24) {
        FlowRisk memory risk = flowRisk;
        bool addsAsset = risk.assetIsCurrency0 == zeroForOne;
        bool worsensImbalance = (risk.netAssetFlow > 0 && addsAsset) || (risk.netAssetFlow < 0 && !addsAsset);
        uint256 absNet = risk.netAssetFlow < 0
            ? uint256(uint128(-(risk.netAssetFlow + 1))) + 1
            : uint256(uint128(risk.netAssetFlow));
        uint256 deadBand = uint256(risk.netLimit) * risk.inventoryDeadBandBps / 10_000;
        if (worsensImbalance && risk.netLimit != 0 && absNet > deadBand) {
            uint256 chargeable = absNet - deadBand;
            uint256 range = uint256(risk.netLimit) - deadBand;
            if (chargeable > range) chargeable = range;
            return uint24(uint256(risk.inventoryFeeMax) * chargeable / range);
        }
        return 0;
    }

    function _volatilityFee(uint160 price) private view returns (uint24) {
        FlowRisk memory risk = flowRisk;
        if (risk.lastSqrtPriceX96 != 0 && risk.volatilityFeeMax != 0) {
            uint256 move = price > risk.lastSqrtPriceX96 ? price - risk.lastSqrtPriceX96 : risk.lastSqrtPriceX96 - price;
            uint256 moveBps = move * 10_000 / risk.lastSqrtPriceX96;
            if (moveBps > 10_000) moveBps = 10_000;
            return uint24(uint256(risk.volatilityFeeMax) * moveBps / 10_000);
        }
        return 0;
    }

    function activePolicy()
        public
        view
        returns (uint160 lower, uint160 upper, uint24 activeBaseFee, uint24 activeEdgeFee)
    {
        TemporaryPolicy memory policy = temporaryPolicy;
        if (policy.expiresAt > block.timestamp) {
            return (policy.lowerSqrtPriceX96, policy.upperSqrtPriceX96, policy.baseFee, policy.edgeFee);
        }
        return (lowerSqrtPriceX96, upperSqrtPriceX96, baseFee, edgeFee);
    }

    function _checkDirection(uint160 price, bool zeroForOne) private view {
        if (directionalGuardBps == 0 || targetSqrtPriceX96 == 0) return;
        uint256 lowerTrigger = uint256(targetSqrtPriceX96) * (10_000 - directionalGuardBps) / 10_000;
        uint256 upperTrigger = uint256(targetSqrtPriceX96) * (10_000 + directionalGuardBps) / 10_000;
        if ((price <= lowerTrigger && zeroForOne) || (price >= upperTrigger && !zeroForOne)) revert RebalanceOnly();
    }

    function _absolute(int256 amount) private pure returns (uint256) {
        return amount < 0 ? uint256(-(amount + 1)) + 1 : uint256(amount);
    }

    function _setFees(uint24 _baseFee, uint24 _edgeFee) private {
        require(
            _baseFee <= _edgeFee
                && uint256(_edgeFee) + flowRisk.inventoryFeeMax + flowRisk.volatilityFeeMax <= LPFeeLibrary.MAX_LP_FEE,
            "bad fees"
        );
        baseFee = _baseFee;
        edgeFee = _edgeFee;
        emit FeesUpdated(_baseFee, _edgeFee);
    }

    function _rollEpoch() private {
        FlowRisk storage risk = flowRisk;
        if (risk.epochDuration == 0) return;
        uint64 start = uint64(block.timestamp - (block.timestamp % risk.epochDuration));
        if (start != risk.epochStart) {
            risk.epochStart = start;
            risk.grossFlow = 0;
            risk.netAssetFlow = 0;
        }
    }

    function _recordFlow(BalanceDelta delta, uint160 price) private {
        FlowRisk storage risk = flowRisk;
        risk.lastSqrtPriceX96 = price;
        if (risk.epochDuration == 0) return;
        int128 callerAssetDelta = risk.assetIsCurrency0 ? delta.amount0() : delta.amount1();
        int256 poolAssetDelta = -int256(callerAssetDelta);
        uint256 amount = poolAssetDelta < 0 ? uint256(-poolAssetDelta) : uint256(poolAssetDelta);
        uint256 gross = uint256(risk.grossFlow) + amount;
        int256 net = int256(risk.netAssetFlow) + poolAssetDelta;
        if (risk.grossLimit != 0 && gross > risk.grossLimit) revert EpochGrossLimitExceeded();
        if (risk.netLimit != 0 && (net > int256(uint256(risk.netLimit)) || net < -int256(uint256(risk.netLimit)))) {
            revert EpochNetLimitExceeded();
        }
        require(gross <= type(uint128).max && net <= type(int128).max && net >= type(int128).min, "flow overflow");
        risk.grossFlow = uint128(gross);
        risk.netAssetFlow = int128(net);
        emit FlowRecorded(uint128(amount), risk.netAssetFlow, risk.grossFlow, risk.epochStart);
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        revert();
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        revert();
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        revert();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        revert();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        revert();
    }
}
