// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BatchAuctionMarket} from "../BatchAuctionMarket.sol";

/// @notice See IdentityRegistryFactory — same reason this is split out of MarketFactory.
/// BatchAuctionMarket is the largest of the four contracts, so this split matters most here.
contract BatchAuctionMarketFactory {
    function deploy(
        address assetToken,
        address settlementToken,
        address identityRegistry,
        address navOracle,
        address issuer,
        uint64 roundDuration,
        uint256 navBandBps
    ) external returns (address) {
        return address(
            new BatchAuctionMarket(
                assetToken, settlementToken, identityRegistry, navOracle, issuer, roundDuration, navBandBps
            )
        );
    }
}
