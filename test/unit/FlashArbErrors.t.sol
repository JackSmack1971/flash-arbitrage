// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../../src/errors/FlashArbErrors.sol";

/**
 * @title FlashArbErrorsTest
 * @notice Smoke test for custom error type compilation and importability
 * @dev AT-015 acceptance criteria: verify each custom error can be imported and used in test contexts
 *      No revert expectations yet - this is purely a compilation validation test
 */
contract FlashArbErrorsTest is Test {
    /**
     * @notice Test that AdapterNotApproved error compiles and has correct signature
     * @dev Validates error can be encoded with address parameter
     */
    function test_AdapterNotApproved_Compilation() public pure {
        address testAdapter = address(0x1);
        bytes memory encodedError = abi.encodeWithSelector(
            AdapterNotApproved.selector,
            testAdapter
        );

        // Verify selector is 4 bytes (standard error selector length)
        assertEq(encodedError.length, 36); // 4 bytes selector + 32 bytes address
    }

    /**
     * @notice Test that RouterNotWhitelisted error compiles and has correct signature
     * @dev Validates error can be encoded with address parameter
     */
    function test_RouterNotWhitelisted_Compilation() public pure {
        address testRouter = address(0x2);
        bytes memory encodedError = abi.encodeWithSelector(
            RouterNotWhitelisted.selector,
            testRouter
        );

        assertEq(encodedError.length, 36); // 4 bytes selector + 32 bytes address
    }

    /**
     * @notice Test that TokenNotWhitelisted error compiles and has correct signature
     * @dev Validates error can be encoded with address parameter
     */
    function test_TokenNotWhitelisted_Compilation() public pure {
        address testToken = address(0x3);
        bytes memory encodedError = abi.encodeWithSelector(
            TokenNotWhitelisted.selector,
            testToken
        );

        assertEq(encodedError.length, 36); // 4 bytes selector + 32 bytes address
    }

    /**
     * @notice Test that InvalidDeadline error compiles and has correct signature
     * @dev Validates error can be encoded with three uint256 parameters
     */
    function test_InvalidDeadline_Compilation() public pure {
        uint256 provided = 1000;
        uint256 min = 900;
        uint256 max = 1100;
        bytes memory encodedError = abi.encodeWithSelector(
            InvalidDeadline.selector,
            provided,
            min,
            max
        );

        // 4 bytes selector + 32 bytes * 3 parameters
        assertEq(encodedError.length, 100);
    }

    /**
     * @notice Test that InsufficientProfit error compiles and has correct signature
     * @dev Validates error can be encoded with two uint256 parameters
     */
    function test_InsufficientProfit_Compilation() public pure {
        uint256 profit = 100;
        uint256 debt = 200;
        bytes memory encodedError = abi.encodeWithSelector(
            InsufficientProfit.selector,
            profit,
            debt
        );

        // 4 bytes selector + 32 bytes * 2 parameters
        assertEq(encodedError.length, 68);
    }

    /**
     * @notice Test that InvalidPathLength error compiles and has correct signature
     * @dev Validates error can be encoded with uint256 parameter
     */
    function test_InvalidPathLength_Compilation() public pure {
        uint256 length = 15;
        bytes memory encodedError = abi.encodeWithSelector(
            InvalidPathLength.selector,
            length
        );

        // 4 bytes selector + 32 bytes parameter
        assertEq(encodedError.length, 36);
    }

    /**
     * @notice Test that InvalidSlippage error compiles and has correct signature
     * @dev Validates error can be encoded with uint256 parameter
     */
    function test_InvalidSlippage_Compilation() public pure {
        uint256 bps = 1500;
        bytes memory encodedError = abi.encodeWithSelector(
            InvalidSlippage.selector,
            bps
        );

        // 4 bytes selector + 32 bytes parameter
        assertEq(encodedError.length, 36);
    }

    /**
     * @notice Test that ZeroAddress error compiles and has correct signature
     * @dev Validates error can be encoded with no parameters
     */
    function test_ZeroAddress_Compilation() public pure {
        bytes memory encodedError = abi.encodeWithSelector(
            ZeroAddress.selector
        );

        // Only 4 bytes selector, no parameters
        assertEq(encodedError.length, 4);
    }

    /**
     * @notice Test that ZeroAmount error compiles and has correct signature
     * @dev Validates error can be encoded with no parameters
     */
    function test_ZeroAmount_Compilation() public pure {
        bytes memory encodedError = abi.encodeWithSelector(
            ZeroAmount.selector
        );

        // Only 4 bytes selector, no parameters
        assertEq(encodedError.length, 4);
    }

    /**
     * @notice Test all error selectors are unique
     * @dev Verifies no selector collisions between different errors
     */
    function test_ErrorSelectorsUnique() public pure {
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = AdapterNotApproved.selector;
        selectors[1] = RouterNotWhitelisted.selector;
        selectors[2] = TokenNotWhitelisted.selector;
        selectors[3] = InvalidDeadline.selector;
        selectors[4] = InsufficientProfit.selector;
        selectors[5] = InvalidPathLength.selector;
        selectors[6] = InvalidSlippage.selector;
        selectors[7] = ZeroAddress.selector;
        selectors[8] = ZeroAmount.selector;

        // Verify all selectors are unique (no collisions)
        for (uint256 i = 0; i < selectors.length; i++) {
            for (uint256 j = i + 1; j < selectors.length; j++) {
                assertTrue(
                    selectors[i] != selectors[j],
                    "Error selector collision detected"
                );
            }
        }
    }
}
