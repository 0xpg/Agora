// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NAVOracle} from "../NAVOracle.sol";

contract NAVOracleFactory {
    function deploy(address issuer, uint64 maxStaleness) external returns (address) {
        return address(new NAVOracle(issuer, maxStaleness));
    }
}
