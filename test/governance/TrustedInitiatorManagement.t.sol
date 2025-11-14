// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {FlashArbMainnetReady} from "../../src/FlashArbMainnetReady.sol";

/**
 * @title TrustedInitiatorManagementTest
 * @notice Test suite for M-2 remediation: Prevent owner self-removal as trusted initiator
 * @dev Validates setTrustedInitiator prevents owner from removing themselves
 * @dev References audit finding M-2: Risk of bricking contract execution if owner removed
 *
 * Test Coverage:
 * - Owner cannot remove themselves as trusted initiator
 * - Owner is always a trusted initiator regardless of explicit setting
 * - Owner can remove other initiators without issue
 */
contract TrustedInitiatorManagementTest is Test {
    FlashArbMainnetReady public arb;

    address public owner;
    address public bot1;
    address public bot2;

    event TrustedInitiatorChanged(address indexed initiator, bool trusted);

    function setUp() public {
        owner = address(this);
        bot1 = makeAddr("bot1");
        bot2 = makeAddr("bot2");

        // Deploy and initialize contract
        arb = new FlashArbMainnetReady();
        arb.initialize();

        // Verify owner is automatically trusted in initialize()
        assertTrue(arb.trustedInitiators(owner), "Owner should be trusted initiator after initialize");
    }

    /**
     * @notice Test owner cannot remove themselves as trusted initiator
     * @dev M-2 remediation: Prevent accidental self-removal that would brick contract
     * @dev Expected: Transaction reverts when owner tries to set themselves as untrusted
     */
    function test_CannotRemoveSelfAsTrustedInitiator() public {
        // Act & Assert: Owner cannot remove themselves
        vm.expectRevert(); // Should revert with custom error or require message
        arb.setTrustedInitiator(owner, false);

        // Verify owner remains trusted after failed attempt
        assertTrue(arb.trustedInitiators(owner), "Owner should still be trusted after failed removal");
    }

    /**
     * @notice Test owner is always trusted initiator regardless of explicit setting
     * @dev M-2 remediation: Owner privilege is implicit and cannot be revoked
     */
    function test_OwnerAlwaysTrustedInitiator() public {
        // Arrange: Add other initiators
        arb.setTrustedInitiator(bot1, true);

        // Assert: Owner remains trusted even without explicit set call
        assertTrue(arb.trustedInitiators(owner), "Owner should be trusted");
        assertTrue(arb.trustedInitiators(bot1), "Bot1 should be trusted");

        // Act: Try to remove owner (should revert)
        vm.expectRevert();
        arb.setTrustedInitiator(owner, false);

        // Assert: Owner still trusted
        assertTrue(arb.trustedInitiators(owner), "Owner should remain trusted");
    }

    /**
     * @notice Test owner can successfully remove other initiators
     * @dev M-2 remediation: Only self-removal is prevented; other initiator management works normally
     */
    function test_CanRemoveOtherInitiators() public {
        // Arrange: Add two bots as trusted initiators
        arb.setTrustedInitiator(bot1, true);
        arb.setTrustedInitiator(bot2, true);
        assertTrue(arb.trustedInitiators(bot1), "Bot1 should be trusted");
        assertTrue(arb.trustedInitiators(bot2), "Bot2 should be trusted");

        // Act: Remove bot1
        vm.expectEmit(true, false, false, true);
        emit TrustedInitiatorChanged(bot1, false);
        arb.setTrustedInitiator(bot1, false);

        // Assert: Bot1 removed, bot2 and owner still trusted
        assertFalse(arb.trustedInitiators(bot1), "Bot1 should no longer be trusted");
        assertTrue(arb.trustedInitiators(bot2), "Bot2 should still be trusted");
        assertTrue(arb.trustedInitiators(owner), "Owner should still be trusted");

        // Act: Remove bot2
        arb.setTrustedInitiator(bot2, false);

        // Assert: Only owner remains trusted
        assertFalse(arb.trustedInitiators(bot2), "Bot2 should no longer be trusted");
        assertTrue(arb.trustedInitiators(owner), "Owner should still be trusted");
    }

    /**
     * @notice Test owner can add and re-add initiators
     * @dev Verify normal initiator management functionality
     */
    function test_CanAddAndReAddInitiators() public {
        // Add bot1
        arb.setTrustedInitiator(bot1, true);
        assertTrue(arb.trustedInitiators(bot1), "Bot1 should be trusted");

        // Remove bot1
        arb.setTrustedInitiator(bot1, false);
        assertFalse(arb.trustedInitiators(bot1), "Bot1 should not be trusted");

        // Re-add bot1
        arb.setTrustedInitiator(bot1, true);
        assertTrue(arb.trustedInitiators(bot1), "Bot1 should be trusted again");
    }

    /**
     * @notice Test multiple attempts to remove owner all fail
     * @dev Defense in depth: Verify protection is consistent
     */
    function test_MultipleAttemptsToRemoveOwnerFail() public {
        // First attempt
        vm.expectRevert();
        arb.setTrustedInitiator(owner, false);
        assertTrue(arb.trustedInitiators(owner), "Owner should remain trusted");

        // Second attempt
        vm.expectRevert();
        arb.setTrustedInitiator(owner, false);
        assertTrue(arb.trustedInitiators(owner), "Owner should still remain trusted");

        // Third attempt after adding other initiators
        arb.setTrustedInitiator(bot1, true);
        vm.expectRevert();
        arb.setTrustedInitiator(owner, false);
        assertTrue(arb.trustedInitiators(owner), "Owner should still remain trusted");
    }

    /**
     * @notice Test owner can set themselves as trusted (idempotent operation)
     * @dev Verify setting owner to true is allowed (even though they're already trusted)
     */
    function test_OwnerCanSetSelfAsTrue() public {
        // Act: Owner explicitly sets themselves as trusted (should succeed)
        vm.expectEmit(true, false, false, true);
        emit TrustedInitiatorChanged(owner, true);
        arb.setTrustedInitiator(owner, true);

        // Assert: Owner remains trusted
        assertTrue(arb.trustedInitiators(owner), "Owner should be trusted");
    }
}
