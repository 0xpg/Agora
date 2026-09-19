// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PermissionedAssetToken} from "../PermissionedAssetToken.sol";

contract AssetTokenFactory {
    function deploy(string calldata name, string calldata symbol, address initialOwner, address registry)
        external
        returns (address)
    {
        return address(new PermissionedAssetToken(name, symbol, initialOwner, registry));
    }
}
