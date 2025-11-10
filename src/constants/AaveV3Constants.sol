// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title AaveV3Constants
 * @notice Aave V3 deployment addresses and protocol constants
 * @dev Verified addresses from Aave V3 official deployments:
 *      Mainnet: https://docs.aave.com/developers/deployed-contracts/v3-mainnet
 *      Sepolia: https://docs.aave.com/developers/deployed-contracts/v3-testnet-addresses
 */

/**
 * @dev Aave V3 Pool address on Ethereum Mainnet
 *      Verified at: https://etherscan.io/address/0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
 *      No AddressesProvider needed for V3 (direct Pool interaction)
 */
address constant AAVE_V3_POOL_MAINNET = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

/**
 * @dev Aave V3 Pool address on Sepolia Testnet
 *      Verified at: https://sepolia.etherscan.io/address/0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951
 */
address constant AAVE_V3_POOL_SEPOLIA = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;

/**
 * @dev Aave V3 flash loan premium in basis points
 *      0.05% = 5 BPS (vs Aave V2's 0.09% = 9 BPS)
 *      Savings: 44% reduction in flash loan fees
 */
uint256 constant AAVE_V3_FLASHLOAN_PREMIUM_TOTAL = 5; // 0.05%

/**
 * @dev Interest rate mode for flash loans (no debt opened)
 *      0 = No debt, revert if flash loan not repaid
 *      1 = Stable rate debt
 *      2 = Variable rate debt
 */
uint256 constant AAVE_V3_INTEREST_RATE_MODE_NONE = 0;
