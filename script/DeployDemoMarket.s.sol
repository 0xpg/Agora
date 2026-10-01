// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PermissionedAssetToken} from "../src/PermissionedAssetToken.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {NAVOracle} from "../src/NAVOracle.sol";
import {AgoraHook} from "../src/AgoraHook.sol";
import {AgoraAllowlistChecker} from "../src/AgoraAllowlistChecker.sol";
import {DemoSettlementToken} from "../src/DemoSettlementToken.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {HookMiner} from "@uniswap/v4-periphery/test/shared/HookMiner.sol";

contract DeployDemoMarket is Script {
    address private constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    uint160 private constant PRICE = 1 << 96;

    function run() external {
        address issuer = msg.sender;
        vm.startBroadcast();

        DemoSettlementToken settlement = new DemoSettlementToken();
        IdentityRegistry registry = new IdentityRegistry(issuer);
        NAVOracle oracle = new NAVOracle(issuer, 1 days);
        PermissionedAssetToken token = new PermissionedAssetToken("Agora Demo Note", "ADN", issuer, address(registry));
        AgoraAllowlistChecker allowlist = new AgoraAllowlistChecker(address(token), registry, issuer);
        registry.setEligibility(issuer, 1);
        oracle.setNAV(1 ether);
        oracle.setUpdatePolicy(15 minutes, 500);

        _deployPool(issuer, token, settlement, oracle);

        vm.stopBroadcast();

        console.log("Asset token:", address(token));
        console.log("Settlement token:", address(settlement));
        console.log("Identity registry:", address(registry));
        console.log("NAV oracle:", address(oracle));
        console.log("Allowlist checker:", address(allowlist));
    }

    function _deployPool(address issuer, PermissionedAssetToken token, DemoSettlementToken settlement, NAVOracle oracle)
        private
    {
        PoolManager manager = new PoolManager(issuer);
        token.setExemptOperator(address(manager), true);

        Currency assetCurrency = Currency.wrap(address(token));
        Currency settlementCurrency = Currency.wrap(address(settlement));
        (Currency currency0, Currency currency1) = Currency.unwrap(assetCurrency) < Currency.unwrap(settlementCurrency)
            ? (assetCurrency, settlementCurrency)
            : (settlementCurrency, assetCurrency);

        AgoraHook hook = _deployHook(manager, oracle, currency0, currency1, issuer);

        hook.syncPriceBand(PRICE * 95 / 100, PRICE * 105 / 100);
        hook.setRiskControls(PRICE, 250, 10_000 ether, 5_000 ether, 1 hours);
        hook.setFlowRisk(
            1 hours,
            20_000 ether,
            10_000 ether,
            2_500,
            1_000,
            1_000,
            Currency.unwrap(assetCurrency) == Currency.unwrap(currency0)
        );

        PoolKey memory key = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 60, IHooks(address(hook)));
        manager.initialize(key, PRICE);

        PoolModifyLiquidityTest liquidityRouter = new PoolModifyLiquidityTest(manager);
        PoolSwapTest swapRouter = new PoolSwapTest(manager);
        token.mint(issuer, 100_000 ether);
        settlement.mint(issuer, 100_000 ether);
        token.approve(address(liquidityRouter), type(uint256).max);
        settlement.approve(address(liquidityRouter), type(uint256).max);
        liquidityRouter.modifyLiquidity(
            key, ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 100_000 ether, salt: 0}), ""
        );

        console.log("Pool manager:", address(manager));
        console.log("Hook:", address(hook));
        console.log("Liquidity router:", address(liquidityRouter));
        console.log("Swap router:", address(swapRouter));
    }

    function _deployHook(PoolManager manager, NAVOracle oracle, Currency currency0, Currency currency1, address issuer)
        private
        returns (AgoraHook hook)
    {
        bytes memory args = abi.encode(
            IPoolManager(address(manager)), oracle, currency0, currency1, issuer, uint24(500), uint24(5_000)
        );
        uint160 flags = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;
        (address expectedHook, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(AgoraHook).creationCode, args);
        hook = new AgoraHook{salt: salt}(manager, oracle, currency0, currency1, issuer, 500, 5_000);
        require(address(hook) == expectedHook, "hook address mismatch");
    }
}
