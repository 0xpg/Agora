// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract NAVOracle is Ownable2Step {
    uint256 public nav;
    uint64 public updatedAt;
    uint64 public maxStaleness;

    event NAVUpdated(uint256 nav, uint64 updatedAt);
    event MaxStalenessUpdated(uint64 maxStaleness);

    constructor(address issuer, uint64 _maxStaleness) Ownable(issuer) {
        maxStaleness = _maxStaleness;
    }

    function setNAV(uint256 _nav) external onlyOwner {
        require(_nav > 0, "nav=0");
        nav = _nav;
        updatedAt = uint64(block.timestamp);
        emit NAVUpdated(_nav, updatedAt);
    }

    function setMaxStaleness(uint64 _maxStaleness) external onlyOwner {
        maxStaleness = _maxStaleness;
        emit MaxStalenessUpdated(_maxStaleness);
    }

    function isStale() public view returns (bool) {
        return updatedAt == 0 || block.timestamp > updatedAt + maxStaleness;
    }

    function getNAV() external view returns (uint256, uint64) {
        return (nav, updatedAt);
    }
}
