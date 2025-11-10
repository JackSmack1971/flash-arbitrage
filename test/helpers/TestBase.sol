// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {FuzzBounds} from "./FuzzBounds.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title FlashArbTestBase
 * @notice Base contract for all FlashArb tests with common helpers
 * @dev Provides deadline helpers and time management for consistent test behavior
 */
abstract contract FlashArbTestBase is Test {
    // ============ Math Helpers ============

    /**
     * @notice Calculate flash loan fee with ceiling division (Aave V2 default)
     * @dev Uses ceiling division to avoid rounding down: (amount * fee + divisor - 1) / divisor
     * @dev WARNING: This uses hardcoded V2 fee. For accurate tests, use _flashLoanFeeV2() or _flashLoanFeeV3()
     * @param amount The loan amount
     * @return fee The flash loan fee (rounded up)
     */
    function _flashLoanFee(uint256 amount) internal pure returns (uint256) {
        return (amount * FuzzBounds.FLASH_LOAN_FEE_BPS + FuzzBounds.MAX_BPS - 1) / FuzzBounds.MAX_BPS;
    }

    /**
     * @notice Calculate flash loan fee for Aave V2 (9 BPS)
     * @param amount The loan amount
     * @return fee The flash loan fee for V2 (rounded up)
     */
    function _flashLoanFeeV2(uint256 amount) internal pure returns (uint256) {
        return (amount * FuzzBounds.FLASH_LOAN_FEE_BPS_V2 + FuzzBounds.MAX_BPS - 1) / FuzzBounds.MAX_BPS;
    }

    /**
     * @notice Calculate flash loan fee for Aave V3 (5 BPS)
     * @param amount The loan amount
     * @return fee The flash loan fee for V3 (rounded up)
     */
    function _flashLoanFeeV3(uint256 amount) internal pure returns (uint256) {
        return (amount * FuzzBounds.FLASH_LOAN_FEE_BPS_V3 + FuzzBounds.MAX_BPS - 1) / FuzzBounds.MAX_BPS;
    }

    /**
     * @notice Calculate flash loan fee with custom BPS
     * @dev Use this when testing with MockLendingPool's configurable premium
     * @param amount The loan amount
     * @param feeBps Custom fee in basis points
     * @return fee The flash loan fee (rounded up)
     */
    function _flashLoanFeeCustom(uint256 amount, uint256 feeBps) internal pure returns (uint256) {
        return (amount * feeBps + FuzzBounds.MAX_BPS - 1) / FuzzBounds.MAX_BPS;
    }

    /**
     * @notice Calculate minimum output after slippage
     * @dev SEC-104: Uses Math.mulDiv to prevent overflow in extreme fuzz scenarios
     * @dev Applies slippage tolerance: quote * (10000 - slippageBps) / 10000
     * @param quote The quoted output amount
     * @param slippageBps Slippage in basis points
     * @return minOut Minimum acceptable output after slippage
     */
    function _minOutAfterSlippage(uint256 quote, uint256 slippageBps) internal pure returns (uint256) {
        require(slippageBps <= FuzzBounds.MAX_SLIPPAGE_BPS, "Slippage too high");
        // Use Math.mulDiv for overflow-safe calculation
        return Math.mulDiv(quote, FuzzBounds.MAX_BPS - slippageBps, FuzzBounds.MAX_BPS);
    }

    /**
     * @notice Bound trade amount to safe range
     * @param amount Fuzzed amount
     * @return Bounded amount within [MIN_TRADE, MAX_TRADE]
     */
    function _boundTrade(uint256 amount) internal pure returns (uint256) {
        return bound(amount, FuzzBounds.MIN_TRADE, FuzzBounds.MAX_TRADE);
    }

    /**
     * @notice Bound flash loan amount to safe range with fee headroom
     * @param amount Fuzzed amount
     * @return Bounded amount within [MIN_TRADE, MAX_FLASH_LOAN]
     */
    function _boundFlashLoan(uint256 amount) internal pure returns (uint256) {
        return bound(amount, FuzzBounds.MIN_TRADE, FuzzBounds.MAX_FLASH_LOAN);
    }

    /**
     * @notice Bound slippage to reasonable range
     * @param bps Fuzzed slippage in basis points
     * @return Bounded slippage within [0, MAX_SLIPPAGE_BPS]
     */
    function _boundSlippage(uint256 bps) internal pure returns (uint256) {
        return bound(bps, 0, FuzzBounds.MAX_SLIPPAGE_BPS);
    }

    /**
     * @notice Bound exchange rate to realistic range
     * @param rate Fuzzed exchange rate
     * @return Bounded rate within [MIN_EXCHANGE_RATE, MAX_EXCHANGE_RATE]
     */
    function _boundExchangeRate(uint256 rate) internal pure returns (uint256) {
        return bound(rate, FuzzBounds.MIN_EXCHANGE_RATE, FuzzBounds.MAX_EXCHANGE_RATE);
    }

    // ============ Deadline Helpers ============
    /**
     * @notice Generate a valid future deadline from a fuzzed input
     * @dev Bounds deadline to [block.timestamp + 1, type(uint256).max - 1 hours]
     *      This ensures:
     *      - Deadline is always in the future (> block.timestamp)
     *      - Safe headroom to avoid overflow in arithmetic operations
     * @param fuzzed Raw fuzzed value from test input
     * @return Valid future deadline
     */
    function _futureDeadline(uint256 fuzzed) internal view returns (uint256) {
        return bound(
            fuzzed,
            block.timestamp + 1,              // Strictly in the future
            type(uint256).max - 1 hours       // Safety headroom for additions
        );
    }

    /**
     * @notice Set a stable block timestamp for deterministic testing
     * @dev Call this in setUp() to fix the testing "now" to a known value
     *      Default: 1700000000 (Nov 2023)
     */
    function _setStableTime() internal {
        vm.warp(1_700_000_000);
    }

    /**
     * @notice Generate a deadline N seconds from now
     * @param secondsFromNow Number of seconds in the future
     * @return Deadline timestamp
     */
    function _deadlineFromNow(uint256 secondsFromNow) internal view returns (uint256) {
        return block.timestamp + secondsFromNow;
    }
}
