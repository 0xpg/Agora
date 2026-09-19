// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IdentityRegistry} from "../IdentityRegistry.sol";

/// @notice Deploys one IdentityRegistry per call. Split out of MarketFactory so
/// IdentityRegistry's creation bytecode isn't embedded in MarketFactory itself —
/// deploying four full contracts via `new` from one contract blows past EIP-170's
/// 24,576-byte runtime size limit (MarketFactory alone hit ~35KB before this split).
contract IdentityRegistryFactory {
    function deploy(address eas, address issuer, uint64 maxCacheAge) external returns (address) {
        return address(new IdentityRegistry(eas, issuer, maxCacheAge));
    }
}
