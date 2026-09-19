// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal vendored subset of the Ethereum Attestation Service interface
/// (https://github.com/ethereum-attestation-service/eas-contracts), deployed as a
/// predeploy on every OP Stack chain including Base. Only the read path Agora needs.
struct Attestation {
    bytes32 uid;
    bytes32 schema;
    uint64 time;
    uint64 expirationTime;
    uint64 revocationTime;
    bytes32 refUID;
    address recipient;
    address attester;
    bool revocable;
    bytes data;
}

interface IEAS {
    function getAttestation(bytes32 uid) external view returns (Attestation memory);
}
