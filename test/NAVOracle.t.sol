// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {NAVOracle} from "../src/NAVOracle.sol";

contract NAVOracleTest is Test {
    function test_StagedNAVRespectsDelayAndJumpLimit() public {
        NAVOracle oracle = new NAVOracle(address(this), 1 days);
        oracle.setNAV(100 ether);
        oracle.setUpdatePolicy(1 hours, 500);

        vm.expectRevert("nav jump");
        oracle.scheduleNAV(106 ether);

        oracle.scheduleNAV(104 ether);
        vm.expectRevert("not ready");
        oracle.activateNAV();
        vm.warp(block.timestamp + 1 hours);
        oracle.activateNAV();
        assertEq(oracle.nav(), 104 ether);
    }
}
