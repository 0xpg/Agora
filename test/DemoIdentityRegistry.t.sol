// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DemoIdentityRegistry} from "../src/DemoIdentityRegistry.sol";

contract DemoIdentityRegistryTest is Test {
    function test_AnyoneCanRegisterThemself() public {
        DemoIdentityRegistry registry = new DemoIdentityRegistry();
        address investor = makeAddr("investor");

        vm.prank(investor);
        registry.register();

        assertTrue(registry.isEligible(investor));
        assertEq(registry.tierOf(investor), 1);
    }
}
