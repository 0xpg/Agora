// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEAS, Attestation} from "../../src/interfaces/IEAS.sol";

contract MockEAS is IEAS {
    mapping(bytes32 => Attestation) private _attestations;

    function register(
        bytes32 uid,
        bytes32 schema,
        address recipient,
        address attester,
        uint64 expirationTime,
        uint64 revocationTime
    ) external {
        _attestations[uid] = Attestation({
            uid: uid,
            schema: schema,
            time: uint64(block.timestamp),
            expirationTime: expirationTime,
            revocationTime: revocationTime,
            refUID: bytes32(0),
            recipient: recipient,
            attester: attester,
            revocable: true,
            data: ""
        });
    }

    function revoke(bytes32 uid) external {
        _attestations[uid].revocationTime = uint64(block.timestamp);
    }

    function getAttestation(bytes32 uid) external view returns (Attestation memory) {
        return _attestations[uid];
    }
}
