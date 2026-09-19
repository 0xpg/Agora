// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Issuer-published reference price for one tokenized asset, scaled 1e18
/// (settlement-token base units per 1e18 asset-token units). A round-based
/// batch auction only needs a price snapshot per round, not a continuous feed,
/// so a simple owner-set value with a staleness bound is sufficient here; swap
/// in a Chainlink/Pyth/RedStone feed behind the same interface for asset classes
/// that have one (e.g. tokenized treasuries).
///
/// Ownable2Step rather than plain Ownable: since NAV directly drives the clearing
/// price, a transfer to an unreachable address would be worse here than on a
/// typical contract — two-step transfer at least rules out that specific failure
/// mode. It does not address the deeper issue that a single compromised owner key
/// can still set an arbitrary NAV; that needs a multisig or timelock in front of
/// this contract, which this scaffold deliberately leaves as a deployment choice
/// rather than baking in a specific governance scheme.
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
