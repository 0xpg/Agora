// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IdentityRegistry} from "./IdentityRegistry.sol";

/// @notice ERC-20 representing a tokenized security. Transfers are blocked unless
/// both parties currently pass the IdentityRegistry eligibility check — the
/// token-level enforcement gate (mirrors ERC-3643); BatchAuctionMarket adds a
/// second, pool-level gate by re-checking eligibility again at settlement.
///
/// Ownable2Step: see NAVOracle's NatSpec. Note MarketFactory relies on the
/// two-step handoff being real — it deploys this contract owned by itself, wires
/// the market's escrow exemption, calls transferOwnership(issuer), and the issuer
/// only becomes owner once they call acceptOwnership() themselves.
contract PermissionedAssetToken is ERC20, Ownable2Step {
    IdentityRegistry public identityRegistry;

    /// @notice Contracts (e.g. a BatchAuctionMarket) trusted to enforce eligibility
    /// in their own logic before moving tokens. Any transfer touching an exempt
    /// operator skips the token-level check on BOTH sides, not just the operator's:
    /// an operator only ever (a) receives escrow from a sender it already checked,
    /// (b) delivers matched proceeds to a recipient it already checked, or (c)
    /// refunds an investor's own prior escrow — which must succeed even if that
    /// investor has since become ineligible for *new* allocations (a status change
    /// must not trap already-owned, already-escrowed funds).
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

    /// @notice Primary issuance/redemption, controlled by the issuer. Secondary
    /// trading happens exclusively through BatchAuctionMarket.
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
