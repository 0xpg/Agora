// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library SolvencyMerkleTree {
    uint256 internal constant DEPTH = 8;
    uint256 internal constant FIELD_MODULUS =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    struct Tree {
        bytes32 root;
        uint256 nextIndex;
        bytes32[DEPTH] filledSubtrees;
    }

    function hash2(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encodePacked(a, b))) % FIELD_MODULUS);
    }

    function zero(uint256 level) internal pure returns (bytes32 z) {
        for (uint256 i = 0; i < level; i++) {
            z = hash2(z, z);
        }
    }

    function insert(Tree storage self, bytes32 leaf) internal returns (uint256 index, bytes32 newRoot) {
        require(self.nextIndex < (1 << DEPTH), "tree full");

        index = self.nextIndex;
        uint256 currentIndex = index;
        bytes32 currentHash = leaf;

        for (uint256 i = 0; i < DEPTH; i++) {
            if (currentIndex % 2 == 0) {
                self.filledSubtrees[i] = currentHash;
                currentHash = hash2(currentHash, zero(i));
            } else {
                currentHash = hash2(self.filledSubtrees[i], currentHash);
            }
            currentIndex /= 2;
        }

        self.root = currentHash;
        self.nextIndex = index + 1;
        newRoot = currentHash;
    }
}
