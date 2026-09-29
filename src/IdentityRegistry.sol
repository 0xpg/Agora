// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEAS, Attestation} from "./interfaces/IEAS.sol";
import {IEligibilityOracle} from "./interfaces/IEligibilityOracle.sol";

contract IdentityRegistry is Ownable2Step, IEligibilityOracle {
    struct EligibilityRecord {
        bool eligible;
        uint64 validUntil;
        uint8 tier;
    }

    IEAS public immutable eas;
    bytes32[] public requiredSchemas;
    uint64 public maxCacheAge;

    mapping(bytes32 schema => mapping(address attester => bool trusted)) public trustedAttesters;
    mapping(address investor => EligibilityRecord) public eligibility;

    event RequiredSchemasUpdated(bytes32[] schemas);
    event TrustedAttesterUpdated(bytes32 indexed schema, address indexed attester, bool trusted);
    event MaxCacheAgeUpdated(uint64 maxCacheAge);
    event EligibilityRefreshed(address indexed investor, bool eligible, uint64 validUntil);

    constructor(address _eas, address issuer, uint64 _maxCacheAge) Ownable(issuer) {
        eas = IEAS(_eas);
        maxCacheAge = _maxCacheAge;
    }

    function setRequiredSchemas(bytes32[] calldata schemas) external onlyOwner {
        requiredSchemas = schemas;
        emit RequiredSchemasUpdated(schemas);
    }

    function setTrustedAttester(bytes32 schema, address attester, bool trusted) external onlyOwner {
        trustedAttesters[schema][attester] = trusted;
        emit TrustedAttesterUpdated(schema, attester, trusted);
    }

    function setMaxCacheAge(uint64 _maxCacheAge) external onlyOwner {
        maxCacheAge = _maxCacheAge;
        emit MaxCacheAgeUpdated(_maxCacheAge);
    }

    function requiredSchemasLength() external view returns (uint256) {
        return requiredSchemas.length;
    }

    function refreshEligibility(address investor, bytes32[] calldata attestationUIDs) external {
        uint256 n = requiredSchemas.length;
        require(n > 0, "no required schemas configured");
        require(attestationUIDs.length == n, "uid count mismatch");

        uint64 earliestExpiry = type(uint64).max;
        bool allValid = true;

        for (uint256 i = 0; i < n; i++) {
            Attestation memory att = eas.getAttestation(attestationUIDs[i]);
            bool ok = att.schema == requiredSchemas[i] && att.recipient == investor
                && trustedAttesters[requiredSchemas[i]][att.attester] && att.revocationTime == 0
                && (att.expirationTime == 0 || att.expirationTime > block.timestamp);
            if (!ok) {
                allValid = false;
                break;
            }
            if (att.expirationTime != 0 && att.expirationTime < earliestExpiry) {
                earliestExpiry = att.expirationTime;
            }
        }

        uint64 cacheBound = uint64(block.timestamp) + maxCacheAge;
        uint64 validUntil = allValid ? (earliestExpiry < cacheBound ? earliestExpiry : cacheBound) : 0;

        uint8 tier = allValid && attestationUIDs.length > 0 ? _tier(eas.getAttestation(attestationUIDs[0]).data) : 0;
        eligibility[investor] = EligibilityRecord({eligible: allValid, validUntil: validUntil, tier: tier});
        emit EligibilityRefreshed(investor, allValid, validUntil);
    }

    function isEligible(address investor) public view override returns (bool) {
        EligibilityRecord memory r = eligibility[investor];
        return r.eligible && block.timestamp <= r.validUntil;
    }

    function tierOf(address investor) external view override returns (uint8) {
        return isEligible(investor) ? eligibility[investor].tier : 0;
    }

    function _tier(bytes memory data) private pure returns (uint8) {
        return data.length == 32 ? abi.decode(data, (uint8)) : 1;
    }
}
