// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Faucet-style settlement token for the Base Sepolia demo only.
contract DemoSettlementToken is ERC20 {
    constructor() ERC20("Demo USD", "dUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
