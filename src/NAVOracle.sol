// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract NAVOracle is Ownable2Step {
    uint256 public nav;
    uint64 public updatedAt;
    uint64 public maxStaleness;
    uint256 public pendingNAV;
    uint64 public pendingActivation;
    uint64 public minUpdateDelay;
    uint16 public maxUpdateBps;

    event NAVUpdated(uint256 nav, uint64 updatedAt);
    event NAVScheduled(uint256 nav, uint64 activatesAt);
    event NAVScheduleCancelled();
    event MaxStalenessUpdated(uint64 maxStaleness);
    event NAVUpdatePolicyUpdated(uint64 minUpdateDelay, uint16 maxUpdateBps);

    constructor(address issuer, uint64 _maxStaleness) Ownable(issuer) {
        maxStaleness = _maxStaleness;
    }

    function setNAV(uint256 _nav) external onlyOwner {
        require(_nav > 0, "nav=0");
        require(nav == 0, "use scheduleNAV");
        _setNAV(_nav);
    }

    function scheduleNAV(uint256 _nav) external onlyOwner {
        require(_nav > 0 && nav > 0, "bad nav");
        if (maxUpdateBps != 0) {
            uint256 change = _nav > nav ? _nav - nav : nav - _nav;
            require(change * 10_000 <= nav * maxUpdateBps, "nav jump");
        }
        pendingNAV = _nav;
        pendingActivation = uint64(block.timestamp) + minUpdateDelay;
        emit NAVScheduled(_nav, pendingActivation);
    }

    function activateNAV() external {
        require(pendingNAV != 0 && block.timestamp >= pendingActivation, "not ready");
        uint256 nextNAV = pendingNAV;
        pendingNAV = 0;
        pendingActivation = 0;
        _setNAV(nextNAV);
    }

    function cancelPendingNAV() external onlyOwner {
        pendingNAV = 0;
        pendingActivation = 0;
        emit NAVScheduleCancelled();
    }

    function setUpdatePolicy(uint64 _minUpdateDelay, uint16 _maxUpdateBps) external onlyOwner {
        require(_maxUpdateBps <= 10_000, "bad update limit");
        minUpdateDelay = _minUpdateDelay;
        maxUpdateBps = _maxUpdateBps;
        emit NAVUpdatePolicyUpdated(_minUpdateDelay, _maxUpdateBps);
    }

    function _setNAV(uint256 _nav) private {
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
