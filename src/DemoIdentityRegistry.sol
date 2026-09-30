// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEligibilityOracle} from "./interfaces/IEligibilityOracle.sol";

/// @notice Open self-registration for the Base Sepolia hackathon demo only.
contract DemoIdentityRegistry is IEligibilityOracle {
    mapping(address investor => bool) public registered;

    event Registered(address indexed investor);

    function register() external {
        registered[msg.sender] = true;
        emit Registered(msg.sender);
    }

    function isEligible(address investor) external view returns (bool) {
        return registered[investor];
    }

    function tierOf(address investor) external view returns (uint8) {
        return registered[investor] ? 1 : 0;
    }
}
