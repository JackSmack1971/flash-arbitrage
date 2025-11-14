// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MockGnosisSafe
 * @notice Minimal Gnosis Safe implementation for testing multi-sig ownership transfer
 * @dev Simulates 2-of-3 multi-sig with simplified execTransaction pattern
 * @dev Used to verify FlashArbMainnetReady.sol M-1 remediation: ownership transfer to multi-sig
 */
contract MockGnosisSafe {
    address[] public owners;
    uint256 public threshold;
    mapping(address => bool) public isOwner;

    event ExecutionSuccess(bytes32 indexed txHash);
    event ExecutionFailure(bytes32 indexed txHash);

    /**
     * @notice Initialize mock Gnosis Safe with 2-of-3 threshold
     * @param _owners Array of 3 owner addresses
     */
    constructor(address[] memory _owners) {
        require(_owners.length == 3, "MockGnosisSafe: requires exactly 3 owners");
        owners = _owners;
        threshold = 2; // 2-of-3 multi-sig

        for (uint256 i = 0; i < _owners.length; i++) {
            isOwner[_owners[i]] = true;
        }
    }

    /**
     * @notice Execute a transaction with multi-sig approval
     * @dev Simplified version - in production, would validate signatures
     * @dev For testing, we assume caller has collected 2+ signatures
     * @param to Destination contract address
     * @param value ETH value to send
     * @param data Transaction calldata
     * @param operation 0 = CALL, 1 = DELEGATECALL
     * @return success Whether the transaction succeeded
     */
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation
    ) external payable returns (bool success) {
        require(isOwner[msg.sender], "MockGnosisSafe: caller not owner");
        require(operation == 0, "MockGnosisSafe: only CALL operations supported in mock");

        bytes32 txHash = keccak256(abi.encode(to, value, data, operation, block.timestamp));

        // Execute transaction (in production, would verify threshold signatures)
        (success, ) = to.call{value: value}(data);

        if (success) {
            emit ExecutionSuccess(txHash);
        } else {
            emit ExecutionFailure(txHash);
        }

        return success;
    }

    /**
     * @notice Get all owner addresses
     * @return Array of owner addresses
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /**
     * @notice Get threshold requirement
     * @return Number of required signatures (2 for 2-of-3)
     */
    function getThreshold() external view returns (uint256) {
        return threshold;
    }

    // Allow receiving ETH
    receive() external payable {}
}
