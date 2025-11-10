// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title IPoolV3
 * @notice Minimal interface for Aave V3 Pool flash loan functionality
 * @dev Official Aave V3 Pool interface: https://github.com/aave/aave-v3-core/blob/master/contracts/interfaces/IPool.sol
 *
 * Key Differences from Aave V2:
 * =============================
 * 1. **Flash Loan Fee Structure**: V3 uses 0.05% (5 BPS) vs V2's 0.09% (9 BPS) - 44% fee reduction
 * 2. **Contract Naming**: "Pool" instead of "LendingPool" (V2)
 * 3. **Interest Rate Modes**: V3 uses same parameter naming but different internal architecture
 * 4. **Callback Interface**: executeOperation signature identical but receiver interface renamed
 * 5. **Gas Efficiency**: V3 implementation is more gas-efficient (~5% savings on flash loan initiation)
 * 6. **Return Value**: V3 flashLoan() returns void (no return value) vs V2's void
 *
 * Security Considerations:
 * ========================
 * - Flash loan callback MUST repay loan + premium (0.05%) in same transaction
 * - Receiver contract MUST implement IFlashLoanReceiverV3.executeOperation()
 * - Flash loan mode 0 (no debt) is the only mode used in this protocol
 * - Premium is calculated per-asset: (amount * 5) / 10000
 *
 * @custom:security-contact security@aave.com
 */
interface IPoolV3 {
    /**
     * @notice Initiates a flash loan from Aave V3 Pool
     * @dev Allows borrowing assets without collateral with mandatory repayment in same transaction
     *
     * Execution Flow:
     * ===============
     * 1. Pool validates flash loan parameters (assets exist, amounts > 0)
     * 2. Pool transfers requested assets to receiverAddress
     * 3. Pool calls receiverAddress.executeOperation() with loan details
     * 4. executeOperation() MUST approve Pool to pull back assets + premium
     * 5. Pool pulls repayment (assets + premium) from receiverAddress
     * 6. Transaction reverts if repayment insufficient
     *
     * Premium Calculation:
     * ====================
     * For each asset: premium = (amount * 5) / 10000 = 0.05% of loan amount
     * Example: 1000 USDC loan → 0.5 USDC fee (1000 * 5 / 10000)
     *
     * @param receiverAddress Address of contract implementing IFlashLoanReceiverV3 (typically address(this))
     * @param assets Array of asset addresses to borrow (e.g., [WETH, DAI])
     * @param amounts Array of amounts to borrow (same order as assets)
     * @param interestRateModes Array of interest rate modes:
     *                          - 0: No debt (flash loan, used in this protocol)
     *                          - 1: Stable debt (not used in arbitrage)
     *                          - 2: Variable debt (not used in arbitrage)
     * @param onBehalfOf Address receiving the debt (use address(this) for flash loans)
     * @param params Arbitrary bytes passed to executeOperation (arbitrage parameters)
     * @param referralCode Aave referral code (use 0 if no referral)
     *
     * @custom:security Requirements:
     * - receiverAddress MUST be a contract implementing IFlashLoanReceiverV3
     * - receiverAddress MUST approve Pool to spend (amount + premium) for each asset
     * - executeOperation() MUST NOT revert (or entire transaction reverts)
     * - Premium MUST be repaid in addition to principal
     *
     * @custom:gas-cost ~150k gas for single-asset flash loan (excluding callback execution)
     */
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata interestRateModes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}
