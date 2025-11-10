// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title IFlashLoanReceiverV3
 * @notice Interface for Aave V3 flash loan receivers
 * @dev Contracts receiving flash loans from Aave V3 Pool must implement this interface
 *      Key Difference from V2: Interface name changed, but signature identical to IFlashLoanReceiver
 */
interface IFlashLoanReceiverV3 {
    /**
     * @notice Executes an operation after receiving the flash-borrowed assets
     * @dev Ensure that the contract can return the debt + premium, e.g., has enough funds to repay
     *      and has approved the Pool to pull the total amount
     * @param assets The addresses of the flash-borrowed assets
     * @param amounts The amounts of the flash-borrowed assets
     * @param premiums The fee of each flash-borrowed asset (amount * 0.05%)
     * @param initiator The address of the flashLoan initiator (msg.sender to Pool.flashLoan())
     * @param params Variadic packed params passed from the initiator
     * @return True if the execution of the operation succeeds, false otherwise
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}
