// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title IPoolV3
 * @notice Minimal interface for Aave V3 Pool flash loan functionality
 * @dev Official Aave V3 Pool address (Ethereum Mainnet): 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
 *      Key Differences from V2:
 *      - Direct Pool interaction (no AddressesProvider lookup needed)
 *      - Lower flash loan fee: 0.05% (5 BPS) vs V2's 0.09% (9 BPS) = 44% savings
 *      - `interestRateModes` replaces `modes` parameter (same values for flash loans: 0)
 *      - Callback interface renamed from IFlashLoanReceiver to IFlashLoanReceiverV3
 */
interface IPoolV3 {
    /**
     * @notice Allows smartcontracts to access the liquidity of the pool within one transaction,
     * as long as the amount taken plus a fee is returned.
     * @param receiverAddress The address of the contract receiving the funds, implementing IFlashLoanReceiverV3
     * @param assets The addresses of the assets being flash-borrowed
     * @param amounts The amounts of the assets being flash-borrowed
     * @param interestRateModes Types of debt to open if the flash loan is not returned:
     *        0 -> Don't open any debt, just revert if funds can't be transferred back
     *        1 -> Open debt at stable rate for the value of the amount flash-borrowed to the `onBehalfOf` address
     *        2 -> Open debt at variable rate for the value of the amount flash-borrowed to the `onBehalfOf` address
     * @param onBehalfOf The address that will receive the debt in case the flash loan is not returned
     * @param params Variadic packed params to pass to the receiver as extra information
     * @param referralCode The code used to register the integrator originating the operation (0 if no referral)
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

    /**
     * @notice Returns the total fee on flash loans (in basis points)
     * @return The flash loan fee (0.05% = 5 BPS)
     */
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);
}
