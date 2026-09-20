// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IZKVerifier} from "../../src/interfaces/IZKVerifier.sol";

contract MockZKVerifier is IZKVerifier {
    bool public result = true;

    function setResult(bool _result) external {
        result = _result;
    }

    function verify(bytes calldata, bytes32[] calldata) external view returns (bool) {
        return result;
    }
}
