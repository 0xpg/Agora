// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IdentityRegistry} from "../IdentityRegistry.sol";

contract IdentityRegistryFactory {
    function deploy(address issuer) external returns (address) {
        return address(new IdentityRegistry(issuer));
    }
}
