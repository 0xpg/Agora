// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../../src/IdentityRegistry.sol";
import {NAVOracle} from "../../src/NAVOracle.sol";
import {PermissionedAssetToken} from "../../src/PermissionedAssetToken.sol";
import {BatchAuctionMarket} from "../../src/BatchAuctionMarket.sol";
import {MockEAS} from "../mocks/MockEAS.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {BatchAuctionMarketHandler} from "./BatchAuctionMarketHandler.sol";

contract BatchAuctionMarketInvariantTest is Test {
    bytes32 constant KYC_SCHEMA = keccak256("KYC");

    MockEAS eas;
    IdentityRegistry registry;
    NAVOracle navOracle;
    PermissionedAssetToken token;
    MockERC20 usdc;
    BatchAuctionMarket market;
    BatchAuctionMarketHandler handler;

    address issuer = makeAddr("issuer");
    address kycAttester = makeAddr("kycAttester");

    function setUp() public {
        eas = new MockEAS();

        vm.startPrank(issuer);
        registry = new IdentityRegistry(address(eas), issuer, 365 days);
        bytes32[] memory schemas = new bytes32[](1);
        schemas[0] = KYC_SCHEMA;
        registry.setRequiredSchemas(schemas);
        registry.setTrustedAttester(KYC_SCHEMA, kycAttester, true);

        navOracle = new NAVOracle(issuer, 365 days);
        navOracle.setNAV(100e18);

        token = new PermissionedAssetToken("Agora Test Note", "ATN", issuer, address(registry));
        usdc = new MockERC20("USD Coin", "USDC");

        market = new BatchAuctionMarket(
            address(token), address(usdc), address(registry), address(navOracle), issuer, 1 hours, 5_000
        );
        token.setExemptOperator(address(market), true);
        vm.stopPrank();

        address[] memory actors = new address[](4);
        for (uint256 i = 0; i < actors.length; i++) {
            actors[i] = makeAddr(string.concat("actor", vm.toString(i)));
            bytes32 uid = keccak256(abi.encode("attestation", actors[i]));
            eas.register(uid, KYC_SCHEMA, actors[i], kycAttester, 0, 0);
            bytes32[] memory uids = new bytes32[](1);
            uids[0] = uid;
            registry.refreshEligibility(actors[i], uids);
        }

        handler = new BatchAuctionMarketHandler(market, token, usdc, navOracle, issuer, actors);
        targetContract(address(handler));
    }

    function invariant_AssetTokenBalanceMatchesUnsettledSellEscrow() public view {
        assertEq(token.balanceOf(address(market)), _unsettledEscrow(false));
    }

    function invariant_SettlementTokenBalanceCoversUnsettledBuyEscrow() public view {
        assertGe(usdc.balanceOf(address(market)), _unsettledEscrow(true));
    }

    function invariant_SettlementTokenBalanceMatchesEscrowPlusSpreadWithinDust() public view {
        uint256 expected = _unsettledEscrow(true) + market.accumulatedSpread();
        uint256 actual = usdc.balanceOf(address(market));
        assertLe(actual > expected ? actual - expected : expected - actual, 1e6);
    }

    function invariant_SettledOrdersAlwaysHaveZeroQty() public view {
        uint256 n = market.nextOrderId();
        for (uint256 id = 1; id < n; id++) {
            (,,, uint256 qty,, bool settled) = market.orders(id);
            if (settled) assertEq(qty, 0);
        }
    }

    function _unsettledEscrow(bool isBuy) private view returns (uint256 total) {
        uint256 n = market.nextOrderId();
        for (uint256 id = 1; id < n; id++) {
            (, bool orderIsBuy, uint256 price, uint256 qty,, bool settled) = market.orders(id);
            if (orderIsBuy == isBuy && !settled) {
                total += isBuy ? (price * qty) / 1e18 : qty;
            }
        }
    }
}
