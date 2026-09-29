// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseAllowlistChecker} from "@uniswap/v4-periphery/src/hooks/permissionedPools/BaseAllowListChecker.sol";
import {
    PermissionFlag,
    PermissionFlags
} from "@uniswap/v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";
import {IEligibilityOracle} from "./interfaces/IEligibilityOracle.sol";

/// @notice Exposes Agora eligibility to Uniswap v4's permissioned router and position manager.
contract AgoraAllowlistChecker is BaseAllowlistChecker {
    address public immutable assetToken;
    IEligibilityOracle public immutable eligibilityOracle;

    constructor(address _assetToken, IEligibilityOracle _eligibilityOracle) {
        require(_assetToken != address(0) && address(_eligibilityOracle) != address(0), "zero address");
        assetToken = _assetToken;
        eligibilityOracle = _eligibilityOracle;
    }

    function checkAllowlist(address account, address tokenAddress) public view override returns (PermissionFlag) {
        return tokenAddress == assetToken && eligibilityOracle.isEligible(account)
            ? PermissionFlags.ALL_ALLOWED
            : PermissionFlags.NONE;
    }
}
