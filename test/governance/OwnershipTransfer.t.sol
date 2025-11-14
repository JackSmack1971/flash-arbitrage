// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {FlashArbMainnetReady} from "../../src/FlashArbMainnetReady.sol";
import {MockGnosisSafe} from "../mocks/MockGnosisSafe.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title OwnershipTransferTest
 * @notice Test suite for M-1 remediation: Multi-sig ownership migration
 * @dev Validates ownership transfer to Gnosis Safe and post-transfer access control
 * @dev References audit finding M-1: Single-owner EOA risk for TVL >= $100K
 *
 * Test Coverage:
 * - Ownership transfer to multi-sig (Gnosis Safe)
 * - Multi-sig can execute owner-only functions
 * - Previous owner loses access after transfer
 */
contract OwnershipTransferTest is Test {
    FlashArbMainnetReady public arb;
    MockGnosisSafe public gnosisSafe;

    address public originalOwner;
    address public signer1;
    address public signer2;
    address public signer3;
    address public attacker;

    address public constant TEST_ROUTER = address(0x1111);
    address public constant TEST_TOKEN = address(0x2222);

    function setUp() public {
        originalOwner = address(this);
        signer1 = makeAddr("signer1");
        signer2 = makeAddr("signer2");
        signer3 = makeAddr("signer3");
        attacker = makeAddr("attacker");

        // Deploy FlashArbMainnetReady
        arb = new FlashArbMainnetReady();
        arb.initialize();

        // Deploy Gnosis Safe with 2-of-3 multi-sig
        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;
        gnosisSafe = new MockGnosisSafe(signers);

        // Verify original owner
        assertEq(arb.owner(), originalOwner, "Original owner should be this contract");
    }

    /**
     * @notice Test successful ownership transfer to Gnosis Safe
     * @dev M-1 remediation: Verify ownership can be transferred to multi-sig
     */
    function test_TransferOwnershipToMultisig() public {
        // Arrange
        address safeAddress = address(gnosisSafe);

        // Act
        arb.transferOwnership(safeAddress);

        // Assert
        assertEq(arb.owner(), safeAddress, "Owner should be Gnosis Safe");
        assertNotEq(arb.owner(), originalOwner, "Original owner should no longer be owner");
    }

    /**
     * @notice Test multi-sig can execute critical owner functions after transfer
     * @dev M-1 remediation: Verify all privileged operations remain accessible via multi-sig
     * @dev Tests: _authorizeUpgrade, setRouterWhitelist, setTrustedInitiator
     */
    function test_MultisigCanExecuteOwnerFunctions() public {
        // Arrange: Transfer ownership to multi-sig
        arb.transferOwnership(address(gnosisSafe));

        // Act & Assert: Multi-sig can whitelist router
        vm.prank(signer1); // Simulate signer1 initiating transaction
        bytes memory whitelistCalldata = abi.encodeWithSelector(
            FlashArbMainnetReady.setRouterWhitelist.selector,
            TEST_ROUTER,
            true
        );
        bool success = gnosisSafe.execTransaction(
            address(arb),
            0, // no ETH value
            whitelistCalldata,
            0  // CALL operation
        );
        assertTrue(success, "Multi-sig should successfully whitelist router");
        assertTrue(arb.routerWhitelist(TEST_ROUTER), "Router should be whitelisted");

        // Act & Assert: Multi-sig can set trusted initiator
        vm.prank(signer2); // Different signer can also execute
        bytes memory initiatorCalldata = abi.encodeWithSelector(
            FlashArbMainnetReady.setTrustedInitiator.selector,
            signer1,
            true
        );
        success = gnosisSafe.execTransaction(
            address(arb),
            0,
            initiatorCalldata,
            0
        );
        assertTrue(success, "Multi-sig should successfully set trusted initiator");
        assertTrue(arb.trustedInitiators(signer1), "Signer1 should be trusted initiator");

        // Act & Assert: Multi-sig can whitelist token
        vm.prank(signer1);
        bytes memory tokenCalldata = abi.encodeWithSelector(
            FlashArbMainnetReady.setTokenWhitelist.selector,
            TEST_TOKEN,
            true
        );
        success = gnosisSafe.execTransaction(
            address(arb),
            0,
            tokenCalldata,
            0
        );
        assertTrue(success, "Multi-sig should successfully whitelist token");
        assertTrue(arb.tokenWhitelist(TEST_TOKEN), "Token should be whitelisted");
    }

    /**
     * @notice Test previous owner cannot execute owner functions after transfer
     * @dev M-1 remediation: Verify old owner loses all privileges
     * @dev Expected: All owner-only function calls revert with Ownable error
     */
    function test_PreviousOwnerCannotExecuteAfterTransfer() public {
        // Arrange: Transfer ownership to multi-sig
        arb.transferOwnership(address(gnosisSafe));

        // Act & Assert: Previous owner cannot whitelist router
        vm.expectRevert(); // Ownable: caller is not the owner
        arb.setRouterWhitelist(TEST_ROUTER, true);

        // Act & Assert: Previous owner cannot set trusted initiator
        vm.expectRevert();
        arb.setTrustedInitiator(signer1, true);

        // Act & Assert: Previous owner cannot whitelist token
        vm.expectRevert();
        arb.setTokenWhitelist(TEST_TOKEN, true);

        // Act & Assert: Previous owner cannot update slippage
        vm.expectRevert();
        arb.setMaxSlippage(100);
    }

    /**
     * @notice Test attacker cannot execute owner functions before or after transfer
     * @dev Defense in depth: Verify access control enforcement
     */
    function test_AttackerCannotExecuteOwnerFunctions() public {
        // Before transfer
        vm.startPrank(attacker);
        vm.expectRevert();
        arb.setRouterWhitelist(TEST_ROUTER, true);
        vm.stopPrank();

        // After transfer to multi-sig
        arb.transferOwnership(address(gnosisSafe));

        vm.startPrank(attacker);
        vm.expectRevert();
        arb.setRouterWhitelist(TEST_ROUTER, true);
        vm.stopPrank();
    }

    /**
     * @notice Test multi-sig can execute upgrade authorization
     * @dev M-1 remediation: Critical upgrade path remains accessible
     * @dev Note: _authorizeUpgrade is internal, so we test indirectly via upgradeTo
     */
    function test_MultisigCanAuthorizeUpgrade() public {
        // Arrange: Transfer ownership and deploy new implementation
        arb.transferOwnership(address(gnosisSafe));
        FlashArbMainnetReady newImplementation = new FlashArbMainnetReady();

        // Act: Multi-sig executes upgrade
        vm.prank(signer1);
        bytes memory upgradeCalldata = abi.encodeWithSelector(
            FlashArbMainnetReady.upgradeTo.selector,
            address(newImplementation)
        );
        bool success = gnosisSafe.execTransaction(
            address(arb),
            0,
            upgradeCalldata,
            0
        );

        // Assert: Upgrade succeeded
        assertTrue(success, "Multi-sig should successfully authorize upgrade");
    }
}
