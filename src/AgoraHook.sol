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
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
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

    IPoolManager public immutable poolManager;
    NAVOracle public immutable navOracle;
    Currency public immutable currency0;
    Currency public immutable currency1;

    uint160 public lowerSqrtPriceX96;
    uint160 public upperSqrtPriceX96;
    uint64 public bandNAVUpdatedAt;
    uint24 public baseFee;
    uint24 public edgeFee;
    bool public paused;

    event PriceBandSynced(uint160 lowerSqrtPriceX96, uint160 upperSqrtPriceX96, uint64 navUpdatedAt);
    event FeesUpdated(uint24 baseFee, uint24 edgeFee);
    event PausedSet(bool paused);

    error NotPoolManager();
    error WrongPool();
    error StaleNAV();
    error UnsyncedPriceBand();
    error PriceOutsideBand();
    error SwapsPaused();

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

    function beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (paused) revert SwapsPaused();
        _checkPool(key);
        _checkNAV();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        _checkPrice(sqrtPriceX96);
        return (
            IHooks.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            _feeAt(sqrtPriceX96) | LPFeeLibrary.OVERRIDE_FEE_FLAG
        );
    }

    function afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, int128)
    {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        _checkPrice(sqrtPriceX96);
        return (IHooks.afterSwap.selector, 0);
    }

    function _checkPool(PoolKey calldata key) private view {
        if (
            Currency.unwrap(key.currency0) != Currency.unwrap(currency0)
                || Currency.unwrap(key.currency1) != Currency.unwrap(currency1) || address(key.hooks) != address(this)
        ) revert WrongPool();
    }

    function _checkNAV() private view {
        if (navOracle.isStale()) revert StaleNAV();
        (, uint64 updatedAt) = navOracle.getNAV();
        if (updatedAt != bandNAVUpdatedAt) revert UnsyncedPriceBand();
    }

    function _checkPrice(uint160 sqrtPriceX96) private view {
        if (sqrtPriceX96 < lowerSqrtPriceX96 || sqrtPriceX96 > upperSqrtPriceX96) revert PriceOutsideBand();
    }

    function _feeAt(uint160 price) private view returns (uint24) {
        uint256 midpoint = (uint256(lowerSqrtPriceX96) + upperSqrtPriceX96) / 2;
        uint256 distance = price > midpoint ? price - midpoint : midpoint - price;
        uint256 span = price > midpoint ? upperSqrtPriceX96 - midpoint : midpoint - lowerSqrtPriceX96;
        return baseFee + uint24((uint256(edgeFee - baseFee) * distance) / span);
    }

    function _setFees(uint24 _baseFee, uint24 _edgeFee) private {
        require(_baseFee <= _edgeFee && _edgeFee <= LPFeeLibrary.MAX_LP_FEE, "bad fees");
        baseFee = _baseFee;
        edgeFee = _edgeFee;
        emit FeesUpdated(_baseFee, _edgeFee);
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
