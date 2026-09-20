// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BatchAuctionMarket} from "../BatchAuctionMarket.sol";

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
