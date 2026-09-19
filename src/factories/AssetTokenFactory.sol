// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PermissionedAssetToken} from "../PermissionedAssetToken.sol";

/// @notice See IdentityRegistryFactory — same reason this is split out of MarketFactory.
contract AssetTokenFactory {
    function deploy(string calldata name, string calldata symbol, address initialOwner, address registry)
        external
        returns (address)
    {
        return address(new PermissionedAssetToken(name, symbol, initialOwner, registry));
    }
}
