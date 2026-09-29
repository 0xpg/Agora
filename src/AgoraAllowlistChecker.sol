// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseAllowlistChecker} from "@uniswap/v4-periphery/src/hooks/permissionedPools/BaseAllowListChecker.sol";
import {
    PermissionFlag,
    PermissionFlags
} from "@uniswap/v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";
import {IEligibilityOracle} from "./interfaces/IEligibilityOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Exposes Agora eligibility to Uniswap v4's permissioned router and position manager.
contract AgoraAllowlistChecker is BaseAllowlistChecker, Ownable {
    address public immutable assetToken;
    IEligibilityOracle public immutable eligibilityOracle;
    mapping(uint8 tier => PermissionFlag permissions) public tierPermissions;

    event TierPermissionsUpdated(uint8 indexed tier, PermissionFlag permissions);

    constructor(address _assetToken, IEligibilityOracle _eligibilityOracle, address issuer) Ownable(issuer) {
        require(_assetToken != address(0) && address(_eligibilityOracle) != address(0), "zero address");
        assetToken = _assetToken;
        eligibilityOracle = _eligibilityOracle;
        tierPermissions[1] = PermissionFlags.ALL_ALLOWED;
    }

    function setTierPermissions(uint8 tier, PermissionFlag permissions) external onlyOwner {
        tierPermissions[tier] = permissions;
        emit TierPermissionsUpdated(tier, permissions);
    }

    function checkAllowlist(address account, address tokenAddress) public view override returns (PermissionFlag) {
        if (tokenAddress != assetToken || !eligibilityOracle.isEligible(account)) return PermissionFlags.NONE;
        return tierPermissions[eligibilityOracle.tierOf(account)];
    }
}
