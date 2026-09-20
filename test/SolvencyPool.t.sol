// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SolvencyPool} from "../src/SolvencyPool.sol";
import {MockZKVerifier} from "./mocks/MockZKVerifier.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SolvencyPoolTest is Test {
    MockERC20 usdc;
    MockZKVerifier mockVerifier;
    SolvencyPool pool;

    address trader = makeAddr("trader");

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        mockVerifier = new MockZKVerifier();
        pool = new SolvencyPool(address(usdc), address(mockVerifier), 1000e18, 1 days);
    }

    function test_DepositTransfersAssetAndUpdatesRoot() public {
        usdc.mint(address(this), 5000e18);
        usdc.approve(address(pool), 5000e18);
        bytes32 rootBefore = pool.poolRoot();

        uint256 leafIndex = pool.deposit(bytes32(uint256(42)), 5000e18);

        assertEq(leafIndex, 0);
        assertEq(usdc.balanceOf(address(pool)), 5000e18);
        assertTrue(pool.poolRoot() != rootBefore);
    }

    function test_SecondDepositGetsNextLeafIndex() public {
        usdc.mint(address(this), 10_000e18);
        usdc.approve(address(pool), 10_000e18);
        pool.deposit(bytes32(uint256(1)), 5000e18);
        uint256 secondIndex = pool.deposit(bytes32(uint256(2)), 5000e18);

        assertEq(secondIndex, 1);
    }

    function test_ProveEligibilityMarksTraderEligibleForCurrentEpoch() public {
        vm.prank(trader);
        pool.proveEligibility(hex"", trader, bytes32(uint256(1)));

        assertTrue(pool.isEligible(trader));
    }

    function test_ProveEligibilityRevertsForNullifierReuse() public {
        vm.prank(trader);
        pool.proveEligibility(hex"", trader, bytes32(uint256(1)));

        address otherTrader = makeAddr("otherTrader");
        vm.prank(otherTrader);
        vm.expectRevert("nullifier used");
        pool.proveEligibility(hex"", otherTrader, bytes32(uint256(1)));
    }

    function test_ProveEligibilityRevertsWhenCallerIsNotTrader() public {
        vm.expectRevert("not trader");
        pool.proveEligibility(hex"", trader, bytes32(uint256(1)));
    }

    function test_ProveEligibilityRevertsWhenVerifierRejects() public {
        mockVerifier.setResult(false);
        vm.prank(trader);
        vm.expectRevert("invalid proof");
        pool.proveEligibility(hex"", trader, bytes32(uint256(1)));
    }

    function test_EligibilityExpiresNextEpoch() public {
        vm.prank(trader);
        pool.proveEligibility(hex"", trader, bytes32(uint256(1)));
        assertTrue(pool.isEligible(trader));

        vm.warp(block.timestamp + 1 days);
        assertFalse(pool.isEligible(trader));
    }

    function test_ReProvingInNextEpochWithFreshNullifierRestoresEligibility() public {
        vm.prank(trader);
        pool.proveEligibility(hex"", trader, bytes32(uint256(1)));

        vm.warp(block.timestamp + 1 days);
        vm.prank(trader);
        pool.proveEligibility(hex"", trader, bytes32(uint256(2)));

        assertTrue(pool.isEligible(trader));
    }
}
