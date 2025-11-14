// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {FlashArbMainnetReady} from "../../src/FlashArbMainnetReady.sol";

/**
 * @title PathLengthValidationTest
 * @notice Test suite for L-1 remediation: maxPathLength validation and governance
 * @dev Validates setMaxPathLength enforces >= 2 requirement and emits events
 * @dev References audit finding L-1: Document minimum path length requirement
 *
 * Test Coverage:
 * - Reverts when maxPathLength < 2 (prevents arbitrage brick)
 * - Accepts valid path lengths (2-10)
 * - Emits MaxPathLengthUpdated event with old/new values
 */
contract PathLengthValidationTest is Test {
    FlashArbMainnetReady public arb;

    address public owner;

    // Event to test (will be validated in implementation)
    event MaxPathLengthUpdated(uint8 indexed oldLength, uint8 indexed newLength);

    function setUp() public {
        owner = address(this);

        // Deploy and initialize contract
        arb = new FlashArbMainnetReady();
        arb.initialize();

        // Verify initial max path length (5)
        assertEq(arb.maxPathLength(), 5, "Initial maxPathLength should be 5");
    }

    /**
     * @notice Test contract reverts when maxPathLength < 2
     * @dev L-1 remediation: Minimum 2-leg path required for arbitrage (tokenA → tokenB → tokenA)
     */
    function test_RevertsOnPathLengthBelowTwo() public {
        // Act & Assert: pathLength = 0 should revert
        vm.expectRevert(); // Will revert with InvalidPathLength or custom error
        arb.setMaxPathLength(0);

        // Act & Assert: pathLength = 1 should revert
        vm.expectRevert();
        arb.setMaxPathLength(1);

        // Verify maxPathLength unchanged after failed attempts
        assertEq(arb.maxPathLength(), 5, "MaxPathLength should remain at initial value");
    }

    /**
     * @notice Test contract accepts valid path lengths (>= 2)
     * @dev L-1 remediation: Verify 2-10 range is accepted
     */
    function test_AcceptsValidPathLengths() public {
        // Case 1: Minimum valid path length (2)
        vm.expectEmit(true, true, false, false);
        emit MaxPathLengthUpdated(5, 2);
        arb.setMaxPathLength(2);
        assertEq(arb.maxPathLength(), 2, "Should accept pathLength = 2");

        // Case 2: Standard path length (3)
        vm.expectEmit(true, true, false, false);
        emit MaxPathLengthUpdated(2, 3);
        arb.setMaxPathLength(3);
        assertEq(arb.maxPathLength(), 3, "Should accept pathLength = 3");

        // Case 3: Longer path length (7)
        vm.expectEmit(true, true, false, false);
        emit MaxPathLengthUpdated(3, 7);
        arb.setMaxPathLength(7);
        assertEq(arb.maxPathLength(), 7, "Should accept pathLength = 7");

        // Case 4: Maximum path length (10)
        vm.expectEmit(true, true, false, false);
        emit MaxPathLengthUpdated(7, 10);
        arb.setMaxPathLength(10);
        assertEq(arb.maxPathLength(), 10, "Should accept pathLength = 10");
    }

    /**
     * @notice Test MaxPathLengthUpdated event emission
     * @dev L-1 remediation: Event provides governance visibility
     */
    function test_EmitsEventOnPathLengthChange() public {
        uint8 oldLength = arb.maxPathLength(); // 5
        uint8 newLength = 3;

        // Expect event with old and new values
        vm.expectEmit(true, true, false, false);
        emit MaxPathLengthUpdated(oldLength, newLength);

        // Act: Change path length
        arb.setMaxPathLength(newLength);

        // Assert: Path length updated
        assertEq(arb.maxPathLength(), newLength, "Path length should be updated");
    }

    /**
     * @notice Test boundary condition: exactly 2 is minimum allowed
     * @dev L-1 remediation: 2-leg arbitrage is minimum viable strategy
     */
    function test_BoundaryCondition_ExactlyTwoAllowed() public {
        // Act: Set to exactly 2
        vm.expectEmit(true, true, false, false);
        emit MaxPathLengthUpdated(5, 2);
        arb.setMaxPathLength(2);

        // Assert: Successfully set to 2
        assertEq(arb.maxPathLength(), 2, "Should accept exactly 2");
    }

    /**
     * @notice Test multiple path length changes emit sequential events
     * @dev Verify governance audit trail
     */
    function test_MultipleChangesEmitSequentialEvents() public {
        // Change 1: 5 → 2
        vm.expectEmit(true, true, false, false);
        emit MaxPathLengthUpdated(5, 2);
        arb.setMaxPathLength(2);

        // Change 2: 2 → 10
        vm.expectEmit(true, true, false, false);
        emit MaxPathLengthUpdated(2, 10);
        arb.setMaxPathLength(10);

        // Change 3: 10 → 4
        vm.expectEmit(true, true, false, false);
        emit MaxPathLengthUpdated(10, 4);
        arb.setMaxPathLength(4);

        // Verify final state
        assertEq(arb.maxPathLength(), 4);
    }

    /**
     * @notice Test idempotent path length setting
     * @dev Setting to same value should succeed (with event)
     */
    function test_IdempotentPathLengthSetting() public {
        uint8 currentLength = arb.maxPathLength(); // 5

        // Set to same value (should succeed and emit event)
        vm.expectEmit(true, true, false, false);
        emit MaxPathLengthUpdated(currentLength, currentLength);
        arb.setMaxPathLength(currentLength);

        // Verify unchanged
        assertEq(arb.maxPathLength(), currentLength);
    }

    /**
     * @notice Fuzz test: Valid path length range (2-10) all succeed
     * @dev L-1 remediation: Verify all valid values accepted
     */
    function testFuzz_ValidPathLengthRange(uint8 pathLength) public {
        // Bound to valid range [2, 10]
        pathLength = uint8(bound(pathLength, 2, 10));

        // Act: Set path length (should succeed)
        arb.setMaxPathLength(pathLength);

        // Assert: Path length set correctly
        assertEq(arb.maxPathLength(), pathLength);
    }

    /**
     * @notice Fuzz test: Invalid path lengths (0-1) all revert
     * @dev L-1 remediation: Enforce minimum bound
     */
    function testFuzz_InvalidPathLengthReverts(uint8 pathLength) public {
        // Bound to invalid range [0, 1]
        pathLength = uint8(bound(pathLength, 0, 1));

        // Act & Assert: Should revert
        vm.expectRevert();
        arb.setMaxPathLength(pathLength);
    }

    /**
     * @notice Test error message clarity for path length = 0
     * @dev Verify helpful error message for governance/operators
     */
    function test_ClearErrorMessageForZeroPathLength() public {
        // Note: Actual error message will be implemented in AT-010
        vm.expectRevert(); // InvalidPathLength(0) or similar
        arb.setMaxPathLength(0);
    }

    /**
     * @notice Test error message clarity for path length = 1
     * @dev Verify helpful error message explaining minimum requirement
     */
    function test_ClearErrorMessageForOnePathLength() public {
        vm.expectRevert(); // InvalidPathLength(1) or similar
        arb.setMaxPathLength(1);
    }
}
