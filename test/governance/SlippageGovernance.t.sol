// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {FlashArbMainnetReady} from "../../src/FlashArbMainnetReady.sol";

/**
 * @title SlippageGovernanceTest
 * @notice Test suite for M-4 remediation: Slippage parameter governance and events
 * @dev Validates slippage setters emit events and enforce 10% upper bound
 * @dev References audit finding M-4: Add governance visibility for slippage parameters
 *
 * Test Coverage:
 * - SlippageUpdated event emitted on maxSlippage changes
 * - MaxSlippageUpdated event emitted on configuration changes
 * - Rejects slippage values > 1000 BPS (10%)
 * - Warning event for high slippage (> 200 BPS / 2%)
 */
contract SlippageGovernanceTest is Test {
    FlashArbMainnetReady public arb;

    address public owner;

    // Events to test (will be added in implementation)
    event MaxSlippageUpdated(uint256 indexed oldBPS, uint256 indexed newBPS, uint256 timestamp);
    event HighSlippageWarning(uint256 indexed slippageBPS, uint256 threshold);

    function setUp() public {
        owner = address(this);

        // Deploy and initialize contract
        arb = new FlashArbMainnetReady();
        arb.initialize();

        // Verify initial slippage (2% = 200 BPS)
        assertEq(arb.maxSlippageBps(), 200, "Initial slippage should be 200 BPS (2%)");
    }

    /**
     * @notice Test MaxSlippageUpdated event emitted when slippage changes
     * @dev M-4 remediation: Event provides governance visibility for parameter changes
     */
    function test_EmitsEventOnMaxSlippageChange() public {
        uint256 oldSlippage = arb.maxSlippageBps();
        uint256 newSlippage = 500; // 5%

        // Expect event with old and new values
        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(oldSlippage, newSlippage, block.timestamp);

        // Act: Change slippage
        arb.setMaxSlippage(newSlippage);

        // Assert: Slippage updated
        assertEq(arb.maxSlippageBps(), newSlippage, "Slippage should be updated");
    }

    /**
     * @notice Test contract reverts on excessive slippage (> 10%)
     * @dev M-4 remediation: Enforce 10% upper bound as recommended by audit
     */
    function test_RevertsOnExcessiveSlippage() public {
        // Act & Assert: 10.01% should revert
        vm.expectRevert(); // Will revert with InvalidSlippage or require message
        arb.setMaxSlippage(1001); // 10.01% = 1001 BPS

        // Act & Assert: 15% should revert
        vm.expectRevert();
        arb.setMaxSlippage(1500);

        // Act & Assert: 100% should revert
        vm.expectRevert();
        arb.setMaxSlippage(10000);

        // Verify slippage unchanged after failed attempts
        assertEq(arb.maxSlippageBps(), 200, "Slippage should remain at initial value");
    }

    /**
     * @notice Test 10% slippage is the maximum allowed value
     * @dev M-4 remediation: Boundary condition - exactly 1000 BPS should succeed
     */
    function test_AllowsMaximumSlippageOf10Percent() public {
        // Act: Set to exactly 10% (1000 BPS)
        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(200, 1000, block.timestamp);
        arb.setMaxSlippage(1000);

        // Assert: Slippage set successfully
        assertEq(arb.maxSlippageBps(), 1000, "Slippage should be set to 10%");
    }

    /**
     * @notice Test HighSlippageWarning event for values > 2%
     * @dev M-4 remediation: Warn governance when slippage exceeds conservative 2% threshold
     */
    function test_WarnsOnHighSlippage() public {
        // Case 1: 2.01% should trigger warning
        uint256 highSlippage = 201; // 2.01%
        vm.expectEmit(true, false, false, true);
        emit HighSlippageWarning(highSlippage, 200); // threshold = 200 BPS (2%)
        arb.setMaxSlippage(highSlippage);

        // Case 2: 5% should trigger warning
        highSlippage = 500;
        vm.expectEmit(true, false, false, true);
        emit HighSlippageWarning(highSlippage, 200);
        arb.setMaxSlippage(highSlippage);

        // Case 3: 10% should trigger warning
        highSlippage = 1000;
        vm.expectEmit(true, false, false, true);
        emit HighSlippageWarning(highSlippage, 200);
        arb.setMaxSlippage(highSlippage);
    }

    /**
     * @notice Test no warning for slippage <= 2%
     * @dev Baseline: Conservative slippage values don't trigger warnings
     */
    function test_NoWarningForConservativeSlippage() public {
        // Case 1: Exactly 2% (200 BPS) - no warning
        // Only expect MaxSlippageUpdated event, NOT HighSlippageWarning
        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(200, 200, block.timestamp);
        arb.setMaxSlippage(200);

        // Case 2: 1% (100 BPS) - no warning
        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(200, 100, block.timestamp);
        arb.setMaxSlippage(100);

        // Case 3: 0.5% (50 BPS) - no warning
        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(100, 50, block.timestamp);
        arb.setMaxSlippage(50);
    }

    /**
     * @notice Test event includes timestamp for audit trail
     * @dev M-4 remediation: Timestamp enables governance to track when changes occurred
     */
    function test_EventIncludesTimestamp() public {
        // Warp to specific time for deterministic testing
        vm.warp(1_700_000_000); // Nov 2023

        uint256 newSlippage = 300;

        // Expect event with current timestamp
        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(200, newSlippage, block.timestamp);
        arb.setMaxSlippage(newSlippage);

        // Warp forward and change again
        vm.warp(1_700_010_000);

        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(newSlippage, 400, block.timestamp);
        arb.setMaxSlippage(400);
    }

    /**
     * @notice Fuzz test: Valid slippage range (0-1000 BPS) all succeed
     * @dev M-4 remediation: Verify all valid values are accepted
     */
    function testFuzz_ValidSlippageRange(uint256 slippageBPS) public {
        // Bound to valid range [0, 1000]
        slippageBPS = bound(slippageBPS, 0, 1000);

        // Act: Set slippage (should succeed for all values in range)
        arb.setMaxSlippage(slippageBPS);

        // Assert: Slippage set correctly
        assertEq(arb.maxSlippageBps(), slippageBPS);
    }

    /**
     * @notice Fuzz test: Invalid slippage values (> 1000 BPS) all revert
     * @dev M-4 remediation: Enforce upper bound for all out-of-range values
     */
    function testFuzz_InvalidSlippageRangeReverts(uint256 slippageBPS) public {
        // Bound to invalid range [1001, type(uint256).max]
        vm.assume(slippageBPS > 1000);
        slippageBPS = bound(slippageBPS, 1001, type(uint128).max); // Cap to avoid overflow

        // Act & Assert: Should revert
        vm.expectRevert();
        arb.setMaxSlippage(slippageBPS);
    }

    /**
     * @notice Test multiple slippage changes emit events in sequence
     * @dev Verify event emission for governance audit trail
     */
    function test_MultipleChangesEmitSequentialEvents() public {
        // Change 1: 200 → 100
        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(200, 100, block.timestamp);
        arb.setMaxSlippage(100);

        // Change 2: 100 → 500 (with warning)
        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(100, 500, block.timestamp);
        vm.expectEmit(true, false, false, true);
        emit HighSlippageWarning(500, 200);
        arb.setMaxSlippage(500);

        // Change 3: 500 → 1000 (with warning)
        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(500, 1000, block.timestamp);
        vm.expectEmit(true, false, false, true);
        emit HighSlippageWarning(1000, 200);
        arb.setMaxSlippage(1000);

        // Change 4: 1000 → 50 (no warning)
        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(1000, 50, block.timestamp);
        arb.setMaxSlippage(50);

        // Verify final state
        assertEq(arb.maxSlippageBps(), 50);
    }

    /**
     * @notice Test boundary conditions around 2% warning threshold
     * @dev Verify warning triggers precisely at > 200 BPS
     */
    function test_WarningThresholdBoundary() public {
        // Exactly 200 BPS (2%) - no warning
        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(200, 200, block.timestamp);
        arb.setMaxSlippage(200);

        // 201 BPS (2.01%) - warning
        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(200, 201, block.timestamp);
        vm.expectEmit(true, false, false, true);
        emit HighSlippageWarning(201, 200);
        arb.setMaxSlippage(201);

        // Back to 199 BPS (1.99%) - no warning
        vm.expectEmit(true, true, false, true);
        emit MaxSlippageUpdated(201, 199, block.timestamp);
        arb.setMaxSlippage(199);
    }
}
