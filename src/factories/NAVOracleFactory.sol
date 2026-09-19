// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NAVOracle} from "../NAVOracle.sol";

/// @notice See IdentityRegistryFactory — same reason this is split out of MarketFactory.
contract NAVOracleFactory {
    function deploy(address issuer, uint64 maxStaleness) external returns (address) {
        return address(new NAVOracle(issuer, maxStaleness));
    }
}
