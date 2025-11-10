// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title FuzzBounds
 * @notice Centralized fuzzing bounds for consistent test constraints
 * @dev Used across all fuzz tests to ensure realistic and safe input ranges
 */
library FuzzBounds {
    // ============ BPS (Basis Points) Bounds ============

    /// @notice Maximum basis points (100%)
    uint256 internal constant MAX_BPS = 10_000;

    /// @notice Maximum slippage tolerance (5%)
    uint256 internal constant MAX_SLIPPAGE_BPS = 500;

    /// @notice Flash loan fee in BPS for Aave V2 (0.09%)
    /// @dev Aave V2 charges 9 BPS premium (governance-controlled, may change)
    uint256 internal constant FLASH_LOAN_FEE_BPS_V2 = 9;

    /// @notice Flash loan fee in BPS for Aave V3 (0.05%)
    /// @dev Aave V3 charges 5 BPS premium (44% savings vs V2, governance-controlled)
    uint256 internal constant FLASH_LOAN_FEE_BPS_V3 = 5;

    /// @notice Default flash loan fee (using V2 for backward compatibility)
    uint256 internal constant FLASH_LOAN_FEE_BPS = FLASH_LOAN_FEE_BPS_V2;

    // ============ Token Amount Bounds ============

    /// @notice Minimum trade amount (1 token with 18 decimals)
    uint256 internal constant MIN_TRADE = 1e18;

    /// @notice Maximum trade amount (1 billion tokens with 18 decimals)
    /// @dev Capped to prevent overflow in exchange rate calculations
    uint256 internal constant MAX_TRADE = 1e27;

    /// @notice Maximum pool liquidity (used in tests)
    uint256 internal constant MAX_POOL_LIQUIDITY = 1e30;

    /// @notice Safe maximum for flash loans (90% of pool to leave headroom)
    uint256 internal constant MAX_FLASH_LOAN = 9e29;

    // ============ Exchange Rate Bounds ============

    /// @notice Minimum exchange rate (0.01x with 18 decimals)
    uint256 internal constant MIN_EXCHANGE_RATE = 1e16;

    /// @notice Maximum exchange rate (100x with 18 decimals)
    uint256 internal constant MAX_EXCHANGE_RATE = 100e18;

    // ============ Deadline Bounds ============

    /// @notice Minimum deadline offset (1 second from now)
    uint256 internal constant MIN_DEADLINE_OFFSET = 1;

    /// @notice Maximum deadline offset per protocol (30 seconds)
    uint256 internal constant MAX_DEADLINE_OFFSET = 30;

    // ============ Path Bounds ============

    /// @notice Minimum path length (direct swap)
    uint256 internal constant MIN_PATH_LENGTH = 2;

    /// @notice Maximum path length (multi-hop)
    uint256 internal constant MAX_PATH_LENGTH = 5;
}
