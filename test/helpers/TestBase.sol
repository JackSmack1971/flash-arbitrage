// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

/**
 * @title TestBase
 * @notice Base contract for all tests with common helpers
 * @dev Provides deadline helpers and time management for consistent test behavior
 */
abstract contract TestBase is Test {
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
