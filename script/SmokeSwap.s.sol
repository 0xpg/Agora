// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PermissionedAssetToken} from "../src/PermissionedAssetToken.sol";
import {DemoIdentityRegistry} from "../src/DemoIdentityRegistry.sol";
import {NAVOracle} from "../src/NAVOracle.sol";
import {AgoraHook} from "../src/AgoraHook.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

contract SmokeSwap is Script {
    PermissionedAssetToken private constant TOKEN = PermissionedAssetToken(0x4a72a139e65a25723478e5819F03C2789F40C206);
    DemoIdentityRegistry private constant REGISTRY = DemoIdentityRegistry(0xcaDF49580A6FF18A10E5fC089E4a1C78DA0151D6);
    NAVOracle private constant ORACLE = NAVOracle(0xfB8A8746C4f44173b0812cfA1815b8Eb17108B08);
    AgoraHook private constant HOOK = AgoraHook(0xB410db440051eC321Cae11edC322DB6f5AD2a0C0);
    PoolSwapTest private constant ROUTER = PoolSwapTest(0x150f6e746aD2d86D7c6869B29992bfec857bF54D);
    address private constant SETTLEMENT = 0xEb9EaC3f9Ec57632CDFDE23D55716c2EA2Fa3a99;
    uint160 private constant PRICE = 1 << 96;

    function run() external {
        vm.startBroadcast();

        ORACLE.setNAV(1 ether);
        HOOK.syncPriceBand(PRICE * 95 / 100, PRICE * 105 / 100);
        if (!REGISTRY.registered(msg.sender)) REGISTRY.register();
        TOKEN.approve(address(ROUTER), 1 ether);

        PoolKey memory key = PoolKey(
            Currency.wrap(address(TOKEN)),
            Currency.wrap(SETTLEMENT),
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            60,
            IHooks(address(HOOK))
        );
        ROUTER.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        vm.stopBroadcast();
    }
}
