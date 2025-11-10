// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title IFlashLoanReceiverV3
 * @notice Interface for Aave V3 flash loan receiver contracts
 * @dev Official Aave V3 receiver interface: https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/interfaces/IFlashLoanReceiver.sol
 *
 * Implementation Requirements:
 * =============================
 * 1. Contract MUST implement executeOperation() with exact signature below
 * 2. executeOperation() MUST approve Pool to spend (amounts[i] + premiums[i]) for each asset
 * 3. executeOperation() MUST return true on success (false causes transaction revert)
 * 4. Contract MUST have sufficient balance of each asset to cover repayment before returning
 *
 * Callback Execution Context:
 * ============================
 * - msg.sender: Aave V3 Pool contract address (validates caller identity)
 * - initiator: Address that initiated the flash loan (validates authorized caller)
 * - Assets transferred: Contract balance increased by amounts[] before callback
 * - Repayment: Pool pulls amounts[] + premiums[] after callback returns
 *
 * V3 vs V2 Differences:
 * =====================
 * - Interface name: IFlashLoanReceiverV3 vs IFlashLoanReceiver (V2)
 * - Signature: Identical to V2 (no parameter changes)
 * - Premium: Lower (5 BPS in V3 vs 9 BPS in V2)
 * - Gas efficiency: V3 callback has ~2% lower overhead
 *
 * Security Invariants:
 * ====================
 * - Only callable by Aave V3 Pool contract (validate msg.sender)
 * - initiator MUST be trusted address (prevent unauthorized flash loans)
 * - Total repayment = sum(amounts[i] + premiums[i])
 * - Contract balance MUST cover repayment before returning
 *
 * @custom:security-contact security@aave.com
 */
interface IFlashLoanReceiverV3 {
    /**
     * @notice Executes an operation after receiving flash loan
     * @dev Called by Aave V3 Pool after transferring flash loan assets to this contract
     *
     * Execution Responsibilities:
     * ============================
     * 1. Perform arbitrage logic (swap on DEX, liquidations, etc.)
     * 2. Calculate total debt: totalDebt[i] = amounts[i] + premiums[i]
     * 3. Approve Pool to spend totalDebt for each asset:
     *    IERC20(assets[i]).approve(msg.sender, totalDebt[i])
     * 4. Ensure contract has sufficient balance to cover repayment
     * 5. Return true to signal success
     *
     * Premium Calculation Example:
     * =============================
     * Asset: WETH
     * Amount: 100 WETH (100 * 10^18)
     * Premium: 100 * 5 / 10000 = 0.05 WETH (0.05 * 10^18)
     * Total Debt: 100.05 WETH
     *
     * @param assets Array of asset addresses borrowed (same order as flashLoan call)
     * @param amounts Array of amounts borrowed (same order as flashLoan call)
     * @param premiums Array of flash loan fees (calculated as: amount * 5 / 10000)
     * @param initiator Address that initiated the flash loan (NOT msg.sender)
     * @param params Arbitrary bytes passed from flashLoan() call (arbitrage parameters)
     * @return success Boolean indicating successful execution (MUST return true or tx reverts)
     *
     * @custom:security Validations REQUIRED in implementation:
     * - require(msg.sender == AAVE_V3_POOL, "only-pool");
     * - require(trustedInitiators[initiator], "untrusted-initiator");
     * - require(finalBalance >= totalDebt, "insufficient-to-repay");
     * - IERC20(asset).approve(msg.sender, totalDebt) for each asset
     *
     * @custom:reentrancy MUST be protected with nonReentrant modifier
     * @custom:gas-cost Variable (depends on arbitrage logic complexity)
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}
