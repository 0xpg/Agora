// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEligibilityOracle} from "./interfaces/IEligibilityOracle.sol";

/// @notice Demo access list managed by the market issuer.
contract IdentityRegistry is Ownable2Step, IEligibilityOracle {
    mapping(address investor => uint8 tier) public tiers;

    event EligibilityUpdated(address indexed investor, uint8 tier);

    constructor(address issuer) Ownable(issuer) {}

    function setEligibility(address investor, uint8 tier) external onlyOwner {
        require(investor != address(0), "zero investor");
        tiers[investor] = tier;
        emit EligibilityUpdated(investor, tier);
    }

    function isEligible(address investor) public view override returns (bool) {
        return tiers[investor] != 0;
    }

    function tierOf(address investor) external view override returns (uint8) {
        return tiers[investor];
    }
}
