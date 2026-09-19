// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IdentityRegistry} from "../IdentityRegistry.sol";

contract IdentityRegistryFactory {
    function deploy(address eas, address issuer, uint64 maxCacheAge) external returns (address) {
        return address(new IdentityRegistry(eas, issuer, maxCacheAge));
    }
}
