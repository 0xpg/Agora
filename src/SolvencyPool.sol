// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IEligibilityOracle} from "./interfaces/IEligibilityOracle.sol";
import {IZKVerifier} from "./interfaces/IZKVerifier.sol";
import {SolvencyMerkleTree} from "./libraries/SolvencyMerkleTree.sol";

contract SolvencyPool is IEligibilityOracle, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SolvencyMerkleTree for SolvencyMerkleTree.Tree;

    IERC20 public immutable asset;
    IZKVerifier public immutable verifier;
    uint256 public immutable thresholdValue;
    uint256 public immutable epochLength;

    SolvencyMerkleTree.Tree private tree;

    mapping(bytes32 nullifier => bool used) public nullifierUsed;
    mapping(address trader => uint256 epoch) public provenUntilEpoch;

    event Deposited(uint256 indexed leafIndex, bytes32 leaf, uint256 amount, bytes32 newRoot);
    event EligibilityProven(address indexed trader, uint256 indexed epoch, bytes32 nullifier);

    constructor(address _asset, address _verifier, uint256 _thresholdValue, uint256 _epochLength) {
        require(_thresholdValue > 0, "threshold=0");
        require(_epochLength > 0, "epochLength=0");
        asset = IERC20(_asset);
        verifier = IZKVerifier(_verifier);
        thresholdValue = _thresholdValue;
        epochLength = _epochLength;
    }

    function currentEpoch() public view returns (uint256) {
        return block.timestamp / epochLength;
    }

    function poolRoot() external view returns (bytes32) {
        return tree.root;
    }

    function deposit(bytes32 leaf, uint256 amount) external nonReentrant returns (uint256 leafIndex) {
        require(amount > 0, "amount=0");
        asset.safeTransferFrom(msg.sender, address(this), amount);
        (leafIndex,) = tree.insert(leaf);
        emit Deposited(leafIndex, leaf, amount, tree.root);
    }

    function proveEligibility(bytes calldata proof, address trader, bytes32 nullifier) external {
        require(msg.sender == trader, "not trader");
        require(!nullifierUsed[nullifier], "nullifier used");

        uint256 epoch = currentEpoch();

        bytes32[] memory publicInputs = new bytes32[](5);
        publicInputs[0] = tree.root;
        publicInputs[1] = bytes32(uint256(uint160(trader)));
        publicInputs[2] = bytes32(epoch);
        publicInputs[3] = bytes32(thresholdValue);
        publicInputs[4] = nullifier;

        require(verifier.verify(proof, publicInputs), "invalid proof");

        nullifierUsed[nullifier] = true;
        provenUntilEpoch[trader] = epoch;
        emit EligibilityProven(trader, epoch, nullifier);
    }

    function isEligible(address trader) external view returns (bool) {
        return provenUntilEpoch[trader] == currentEpoch();
    }
}
