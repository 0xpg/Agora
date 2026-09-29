// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PermissionedAssetToken} from "./PermissionedAssetToken.sol";
import {AgoraAllowlistChecker} from "./AgoraAllowlistChecker.sol";
import {IEligibilityOracle} from "./interfaces/IEligibilityOracle.sol";
import {IdentityRegistryFactory} from "./factories/IdentityRegistryFactory.sol";
import {NAVOracleFactory} from "./factories/NAVOracleFactory.sol";
import {AssetTokenFactory} from "./factories/AssetTokenFactory.sol";

contract MarketFactory {
    address public immutable eas;

    IdentityRegistryFactory public immutable identityRegistryFactory;
    NAVOracleFactory public immutable navOracleFactory;
    AssetTokenFactory public immutable assetTokenFactory;

    event MarketAssetsDeployed(
        address indexed issuer, address token, address navOracle, address identityRegistry, address allowlistChecker
    );

    constructor(address _eas, address _identityRegistryFactory, address _navOracleFactory, address _assetTokenFactory) {
        eas = _eas;
        identityRegistryFactory = IdentityRegistryFactory(_identityRegistryFactory);
        navOracleFactory = NAVOracleFactory(_navOracleFactory);
        assetTokenFactory = AssetTokenFactory(_assetTokenFactory);
    }

    function deployMarket(
        string calldata name,
        string calldata symbol,
        uint64 navMaxStaleness,
        uint64 identityMaxCacheAge
    ) external returns (address token, address navOracle, address identityRegistry, address allowlistChecker) {
        identityRegistry = identityRegistryFactory.deploy(eas, msg.sender, identityMaxCacheAge);
        navOracle = navOracleFactory.deploy(msg.sender, navMaxStaleness);

        token = assetTokenFactory.deploy(name, symbol, address(this), identityRegistry);
        allowlistChecker = address(new AgoraAllowlistChecker(token, IEligibilityOracle(identityRegistry)));

        PermissionedAssetToken deployedToken = PermissionedAssetToken(token);
        deployedToken.transferOwnership(msg.sender);

        emit MarketAssetsDeployed(msg.sender, token, navOracle, identityRegistry, allowlistChecker);
    }
}
