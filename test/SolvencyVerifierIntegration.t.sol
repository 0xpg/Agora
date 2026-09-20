// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SolvencyPool} from "../src/SolvencyPool.sol";
import {HonkVerifier} from "../src/SolvencyVerifier.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SolvencyVerifierIntegrationTest is Test {
    bytes32 constant LEAF = 0x20367e304fa6cb0f31b09ea9df45e619af70dcd356c44ccde060f35547ddc1ca;
    bytes32 constant EXPECTED_ROOT = 0x2e31ca3780f6eb5e809f44f8a7d2f96c42427fe0bd3efc868b9a0799dbb61f21;
    bytes32 constant NULLIFIER = 0x194999f114264e45ecf18ed62bd27f9a00c8dfc6dea8bd85013a97c0d7b58dfd;
    address constant TRADER = address(0x1111);

    function test_RealDepositAndRealProofGrantEligibility() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC");
        HonkVerifier verifier = new HonkVerifier();
        SolvencyPool pool = new SolvencyPool(address(usdc), address(verifier), 1000, 1 days);

        usdc.mint(address(this), 5000);
        usdc.approve(address(pool), 5000);
        pool.deposit(LEAF, 5000);

        assertEq(pool.poolRoot(), EXPECTED_ROOT);

        vm.warp(7 days);
        assertEq(pool.currentEpoch(), 7);

        bytes memory proof = vm.parseBytes(vm.readLine("test/fixtures/solvency/proof.hex"));

        vm.prank(TRADER);
        pool.proveEligibility(proof, TRADER, NULLIFIER);

        assertTrue(pool.isEligible(TRADER));
    }
}
