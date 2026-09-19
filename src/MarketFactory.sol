// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PermissionedAssetToken} from "./PermissionedAssetToken.sol";
import {IdentityRegistryFactory} from "./factories/IdentityRegistryFactory.sol";
import {NAVOracleFactory} from "./factories/NAVOracleFactory.sol";
import {AssetTokenFactory} from "./factories/AssetTokenFactory.sol";
import {BatchAuctionMarketFactory} from "./factories/BatchAuctionMarketFactory.sol";

/// @notice Self-serve deployment of a full (token + registry + oracle + market) set
/// for one issuer — "infrastructure you own" rather than a single shared venue.
/// Orchestrates four small per-contract sub-factories, deployed separately (see
/// Deploy.s.sol) and referenced here only by address, rather than deploying them
/// via `new` directly: embedding all four contracts' creation bytecode in one
/// contract blows past EIP-170's 24,576-byte runtime size limit (this contract
/// alone hit ~35KB before the split). Calling a pre-deployed sub-factory's
/// deploy() function only needs its ABI, not its bytecode, so this contract stays
/// small no matter how large the things it deploys are — critically, `new X()`
/// inside a constructor embeds X's bytecode into the caller regardless of how many
/// indirection layers deep, so the sub-factories must be deployed independently,
/// not from within this constructor, or the same limit reappears one level up.
/// Deploys plain instances rather than minimal proxies for scaffold clarity; swap
/// in OpenZeppelin Clones (with an initializer pattern) once the gas cost of
/// repeated full deploys actually matters.
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

        // Token is temporarily owned by this contract so it can wire the market's
        // escrow exemption atomically, then starts handing ownership to the issuer
        // below. PermissionedAssetToken is Ownable2Step, so transferOwnership only
        // proposes the issuer as pendingOwner here — the issuer must call
        // acceptOwnership() themselves afterward to actually take ownership. Until
        // then this contract remains the token's owner (registry/oracle/market
        // ownership isn't affected: they're deployed already owned by msg.sender
        // directly, with no handoff to accept).
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
