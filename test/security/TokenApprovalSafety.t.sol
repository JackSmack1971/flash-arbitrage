// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {MockNonStandardToken} from "../mocks/MockNonStandardToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TokenApprovalSafetyTest
 * @notice Test suite for M-3 remediation: SafeERC20.forceApprove pattern for non-standard tokens
 * @dev Validates approval pattern handles USDT-like tokens that revert on non-zero allowance changes
 * @dev References audit finding M-3: Use SafeERC20.forceApprove for token compatibility
 *
 * Test Coverage:
 * - forceApprove handles non-standard tokens (USDT behavior)
 * - forceApprove is idempotent (can be called repeatedly)
 * - Direct approve fails for non-standard tokens without zero-reset
 */
contract TokenApprovalSafetyTest is Test {
    using SafeERC20 for IERC20;

    MockNonStandardToken public token;
    address public spender;
    address public user;

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10**18;
    uint256 constant APPROVAL_AMOUNT = 100_000 * 10**18;

    function setUp() public {
        user = address(this);
        spender = makeAddr("spender");

        // Deploy non-standard token (USDT-like behavior)
        token = new MockNonStandardToken(INITIAL_SUPPLY);
    }

    /**
     * @notice Test SafeERC20.forceApprove handles non-standard tokens correctly
     * @dev M-3 remediation: forceApprove automatically resets to 0 then sets new value
     * @dev This pattern works with USDT and other non-standard tokens
     */
    function test_SafeApprovalForNonStandardTokens() public {
        // Arrange: Set initial approval
        IERC20(address(token)).forceApprove(spender, APPROVAL_AMOUNT);
        assertEq(token.allowance(user, spender), APPROVAL_AMOUNT, "Initial approval should be set");

        // Act: Change approval to different amount using forceApprove
        // This should succeed even with non-standard token behavior
        uint256 newAmount = APPROVAL_AMOUNT * 2;
        IERC20(address(token)).forceApprove(spender, newAmount);

        // Assert: Approval changed successfully
        assertEq(token.allowance(user, spender), newAmount, "Approval should be updated");
    }

    /**
     * @notice Test forceApprove is idempotent (can be called multiple times)
     * @dev M-3 remediation: Repeated approvals don't cause issues
     */
    function test_SafeApprovalIdempotent() public {
        // First approval
        IERC20(address(token)).forceApprove(spender, APPROVAL_AMOUNT);
        assertEq(token.allowance(user, spender), APPROVAL_AMOUNT);

        // Second approval with same amount (should succeed)
        IERC20(address(token)).forceApprove(spender, APPROVAL_AMOUNT);
        assertEq(token.allowance(user, spender), APPROVAL_AMOUNT);

        // Third approval with different amount (should succeed)
        uint256 newAmount = APPROVAL_AMOUNT / 2;
        IERC20(address(token)).forceApprove(spender, newAmount);
        assertEq(token.allowance(user, spender), newAmount);

        // Fourth approval back to original (should succeed)
        IERC20(address(token)).forceApprove(spender, APPROVAL_AMOUNT);
        assertEq(token.allowance(user, spender), APPROVAL_AMOUNT);
    }

    /**
     * @notice Test direct approve fails with non-standard tokens when changing non-zero allowance
     * @dev M-3 finding: Without forceApprove, non-standard tokens cause reverts
     * @dev This demonstrates why forceApprove is necessary
     */
    function test_FailsWithUnsafeApproval() public {
        // Arrange: Set initial approval using standard approve (works for first approval)
        token.approve(spender, APPROVAL_AMOUNT);
        assertEq(token.allowance(user, spender), APPROVAL_AMOUNT);

        // Act & Assert: Directly changing non-zero allowance FAILS with non-standard token
        vm.expectRevert("MockNonStandardToken: approve from non-zero to non-zero not allowed");
        token.approve(spender, APPROVAL_AMOUNT * 2);

        // Verify allowance unchanged after failed attempt
        assertEq(token.allowance(user, spender), APPROVAL_AMOUNT, "Allowance should remain unchanged");
    }

    /**
     * @notice Test forceApprove can reset approval to zero
     * @dev M-3 remediation: Verify forceApprove handles zero-approval case
     */
    function test_ForceApproveCanResetToZero() public {
        // Arrange: Set initial approval
        IERC20(address(token)).forceApprove(spender, APPROVAL_AMOUNT);
        assertEq(token.allowance(user, spender), APPROVAL_AMOUNT);

        // Act: Reset to zero using forceApprove
        IERC20(address(token)).forceApprove(spender, 0);

        // Assert: Approval reset to zero
        assertEq(token.allowance(user, spender), 0, "Approval should be reset to zero");
    }

    /**
     * @notice Test forceApprove from zero to non-zero always works
     * @dev Baseline test: Even non-standard tokens allow 0 → X approvals
     */
    function test_ForceApproveFromZeroToNonZero() public {
        // Arrange: Ensure starting at zero
        assertEq(token.allowance(user, spender), 0);

        // Act: Approve from zero to non-zero
        IERC20(address(token)).forceApprove(spender, APPROVAL_AMOUNT);

        // Assert: Approval set successfully
        assertEq(token.allowance(user, spender), APPROVAL_AMOUNT);
    }

    /**
     * @notice Fuzz test: forceApprove works with arbitrary amounts
     * @dev M-3 remediation: Verify robustness across value range
     */
    function testFuzz_ForceApproveWithArbitraryAmounts(uint128 amount1, uint128 amount2) public {
        // Act: Set first approval
        IERC20(address(token)).forceApprove(spender, amount1);
        assertEq(token.allowance(user, spender), amount1);

        // Act: Change to second approval (different value)
        IERC20(address(token)).forceApprove(spender, amount2);
        assertEq(token.allowance(user, spender), amount2);

        // Act: Change back to first approval
        IERC20(address(token)).forceApprove(spender, amount1);
        assertEq(token.allowance(user, spender), amount1);
    }

    /**
     * @notice Test multiple spenders with forceApprove
     * @dev Verify forceApprove works independently for different spenders
     */
    function test_ForceApproveMultipleSpenders() public {
        address spender2 = makeAddr("spender2");
        address spender3 = makeAddr("spender3");

        // Approve different amounts for different spenders
        IERC20(address(token)).forceApprove(spender, APPROVAL_AMOUNT);
        IERC20(address(token)).forceApprove(spender2, APPROVAL_AMOUNT * 2);
        IERC20(address(token)).forceApprove(spender3, APPROVAL_AMOUNT * 3);

        // Verify all approvals set correctly
        assertEq(token.allowance(user, spender), APPROVAL_AMOUNT);
        assertEq(token.allowance(user, spender2), APPROVAL_AMOUNT * 2);
        assertEq(token.allowance(user, spender3), APPROVAL_AMOUNT * 3);

        // Change first spender approval
        IERC20(address(token)).forceApprove(spender, APPROVAL_AMOUNT / 2);

        // Verify only first spender changed
        assertEq(token.allowance(user, spender), APPROVAL_AMOUNT / 2);
        assertEq(token.allowance(user, spender2), APPROVAL_AMOUNT * 2);
        assertEq(token.allowance(user, spender3), APPROVAL_AMOUNT * 3);
    }
}
