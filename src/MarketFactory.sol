// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PermissionedAssetToken} from "./PermissionedAssetToken.sol";
import {IdentityRegistryFactory} from "./factories/IdentityRegistryFactory.sol";
import {NAVOracleFactory} from "./factories/NAVOracleFactory.sol";
import {AssetTokenFactory} from "./factories/AssetTokenFactory.sol";
import {BatchAuctionMarketFactory} from "./factories/BatchAuctionMarketFactory.sol";

contract MarketFactory {
    address public immutable eas;
    address public immutable settlementToken;

    IdentityRegistryFactory public immutable identityRegistryFactory;
    NAVOracleFactory public immutable navOracleFactory;
    AssetTokenFactory public immutable assetTokenFactory;
    BatchAuctionMarketFactory public immutable marketFactory;

    event MarketDeployed(
        address indexed issuer, address token, address market, address navOracle, address identityRegistry
    );

    constructor(
        address _eas,
        address _settlementToken,
        address _identityRegistryFactory,
        address _navOracleFactory,
        address _assetTokenFactory,
        address _batchAuctionMarketFactory
    ) {
        eas = _eas;
        settlementToken = _settlementToken;

        identityRegistryFactory = IdentityRegistryFactory(_identityRegistryFactory);
        navOracleFactory = NAVOracleFactory(_navOracleFactory);
        assetTokenFactory = AssetTokenFactory(_assetTokenFactory);
        marketFactory = BatchAuctionMarketFactory(_batchAuctionMarketFactory);
    }

    function deployMarket(
        string calldata name,
        string calldata symbol,
        uint64 navMaxStaleness,
        uint64 roundDuration,
        uint256 navBandBps,
        uint64 identityMaxCacheAge
    ) external returns (address token, address market, address navOracle, address identityRegistry) {
        identityRegistry = identityRegistryFactory.deploy(eas, msg.sender, identityMaxCacheAge);
        navOracle = navOracleFactory.deploy(msg.sender, navMaxStaleness);

        token = assetTokenFactory.deploy(name, symbol, address(this), identityRegistry);
        market = marketFactory.deploy(
            token, settlementToken, identityRegistry, navOracle, msg.sender, roundDuration, navBandBps
        );

        PermissionedAssetToken deployedToken = PermissionedAssetToken(token);
        deployedToken.setExemptOperator(market, true);
        deployedToken.transferOwnership(msg.sender);

        emit MarketDeployed(msg.sender, token, market, navOracle, identityRegistry);
    }
}
