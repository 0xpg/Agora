// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IdentityRegistry} from "./IdentityRegistry.sol";

contract PermissionedAssetToken is ERC20, Ownable2Step {
    IdentityRegistry public identityRegistry;

    mapping(address => bool) public exemptOperators;

    event IdentityRegistryUpdated(address indexed registry);
    event ExemptOperatorUpdated(address indexed operator, bool exempt);

    constructor(string memory name_, string memory symbol_, address issuer, address registry)
        ERC20(name_, symbol_)
        Ownable(issuer)
    {
        identityRegistry = IdentityRegistry(registry);
    }

    function setIdentityRegistry(address registry) external onlyOwner {
        identityRegistry = IdentityRegistry(registry);
        emit IdentityRegistryUpdated(registry);
    }

    function setExemptOperator(address operator, bool exempt) external onlyOwner {
        exemptOperators[operator] = exempt;
        emit ExemptOperatorUpdated(operator, exempt);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && !exemptOperators[from] && !exemptOperators[to]) {
            require(identityRegistry.isEligible(from), "sender ineligible");
            require(identityRegistry.isEligible(to), "recipient ineligible");
        }
        super._update(from, to, value);
    }
}
