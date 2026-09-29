// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgoraHook} from "../src/AgoraHook.sol";
import {NAVOracle} from "../src/NAVOracle.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {HookMiner} from "@uniswap/v4-periphery/test/shared/HookMiner.sol";

contract AgoraHookTest is Test {
    uint160 private constant PRICE = 1 << 96;

    MockStateManager private manager;
    NAVOracle private oracle;
    AgoraHook private hook;
    PoolKey private key;

    function setUp() public {
        manager = new MockStateManager(PRICE);
        oracle = new NAVOracle(address(this), 1 days);
        oracle.setNAV(1e18);

        Currency currency0 = Currency.wrap(address(1));
        Currency currency1 = Currency.wrap(address(2));
        bytes memory args = abi.encode(
            IPoolManager(address(manager)), oracle, currency0, currency1, address(this), uint24(500), uint24(5_000)
        );
        uint160 flags = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;
        (address expected, bytes32 salt) = HookMiner.find(address(this), flags, type(AgoraHook).creationCode, args);
        hook = new AgoraHook{salt: salt}(
            IPoolManager(address(manager)), oracle, currency0, currency1, address(this), 500, 5_000
        );
        assertEq(address(hook), expected);

        hook.syncPriceBand(PRICE * 90 / 100, PRICE * 110 / 100);
        hook.setRiskControls(PRICE, 500, 1_000, 500, 1 hours);
        key = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 60, IHooks(address(hook)));
    }

    function test_RiskControlsApplyToExactInputAndOutput() public {
        vm.startPrank(address(manager));
        vm.expectRevert(AgoraHook.SwapTooLarge.selector);
        hook.beforeSwap(address(0), key, _params(true, -1_001), "");
        vm.expectRevert(AgoraHook.SwapTooLarge.selector);
        hook.beforeSwap(address(0), key, _params(false, 1_001), "");
        vm.stopPrank();
    }

    function test_TemporaryPolicyExpires() public {
        hook.setTemporaryPolicy(PRICE * 95 / 100, PRICE * 105 / 100, 1_000, 2_000, uint64(block.timestamp + 1 hours));
        (,,, uint24 activeEdgeFee) = hook.activePolicy();
        assertEq(activeEdgeFee, 2_000);

        vm.warp(block.timestamp + 1 hours);
        (,,, activeEdgeFee) = hook.activePolicy();
        assertEq(activeEdgeFee, 5_000);
    }

    function test_OnlyRebalancingDirectionAllowedOutsideGuard() public {
        manager.setPrice(PRICE * 94 / 100);
        vm.prank(address(manager));
        vm.expectRevert(AgoraHook.RebalanceOnly.selector);
        hook.beforeSwap(address(0), key, _params(true, -100), "");

        vm.prank(address(manager));
        hook.beforeSwap(address(0), key, _params(false, -100), "");
    }

    function test_LargeSwapRequiresFresherNav() public {
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(address(manager));
        vm.expectRevert(AgoraHook.StaleNAV.selector);
        hook.beforeSwap(address(0), key, _params(true, -500), "");
    }

    function _params(bool zeroForOne, int256 amount) private pure returns (SwapParams memory) {
        return SwapParams({zeroForOne: zeroForOne, amountSpecified: amount, sqrtPriceLimitX96: 0});
    }
}

contract MockStateManager {
    bytes32 private slot0;

    constructor(uint160 price) {
        slot0 = bytes32(uint256(price));
    }

    function extsload(bytes32) external view returns (bytes32) {
        return slot0;
    }

    function setPrice(uint160 price) external {
        slot0 = bytes32(uint256(price));
    }
}
