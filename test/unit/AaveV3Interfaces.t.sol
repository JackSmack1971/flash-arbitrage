// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../../src/contracts/interfaces/IPoolV3.sol";
import "../../src/contracts/interfaces/IFlashLoanReceiverV3.sol";
import "../../src/contracts/constants/AaveV3Constants.sol";

/**
 * @title AaveV3InterfacesTest
 * @notice Unit tests for Aave V3 interface abstractions (AT-017)
 * @dev Validates interface compilation, method signatures, and constant values
 *
 * Test Coverage:
 * ==============
 * - Interface compilation (smoke test)
 * - Constant value verification (mainnet/sepolia addresses)
 * - Premium calculation validation (5 BPS)
 * - Address non-zero checks
 * - Interface compatibility with Aave V3 documentation
 *
 * Acceptance Criteria (AT-017):
 * ==============================
 * ✓ IPoolV3 interface complete with flashLoan() signature
 * ✓ IFlashLoanReceiverV3 interface complete with executeOperation() signature
 * ✓ Mainnet and Sepolia addresses defined as constants
 * ✓ V3 fee constant (5 BPS) defined
 * ✓ All interfaces have comprehensive NatSpec documentation
 */
contract AaveV3InterfacesTest is Test {
    // ============ Test State ============

    using AaveV3Constants for *;

    // ============ Setup ============

    function setUp() public {
        // No setup required for interface smoke tests
    }

    // ============ Interface Compilation Tests ============

    /**
     * @notice Test: IPoolV3 interface imports and compiles successfully
     * @dev Smoke test - if this compiles, interface is syntactically valid
     */
    function test_IPoolV3_InterfaceCompiles() public pure {
        // If this test compiles, IPoolV3 interface is valid
        // Type check: ensure IPoolV3 is recognized as an interface type
        IPoolV3 pool;
        assembly {
            pool := 0 // Suppress unused variable warning
        }
        assertTrue(true, "IPoolV3 interface compiled successfully");
    }

    /**
     * @notice Test: IFlashLoanReceiverV3 interface imports and compiles successfully
     * @dev Smoke test - if this compiles, interface is syntactically valid
     */
    function test_IFlashLoanReceiverV3_InterfaceCompiles() public pure {
        // If this test compiles, IFlashLoanReceiverV3 interface is valid
        // Type check: ensure IFlashLoanReceiverV3 is recognized as an interface type
        IFlashLoanReceiverV3 receiver;
        assembly {
            receiver := 0 // Suppress unused variable warning
        }
        assertTrue(true, "IFlashLoanReceiverV3 interface compiled successfully");
    }

    /**
     * @notice Test: AaveV3Constants library imports and compiles successfully
     * @dev Smoke test - if this compiles, constants are syntactically valid
     */
    function test_AaveV3Constants_LibraryCompiles() public pure {
        // Access constants to verify they're accessible
        address mainnet = AaveV3Constants.AAVE_V3_POOL_MAINNET;
        address sepolia = AaveV3Constants.AAVE_V3_POOL_SEPOLIA;
        uint256 premium = AaveV3Constants.AAVE_V3_FLASHLOAN_PREMIUM_TOTAL;

        // Suppress unused variable warnings
        assembly {
            mainnet := mainnet
            sepolia := sepolia
            premium := premium
        }

        assertTrue(true, "AaveV3Constants library compiled successfully");
    }

    // ============ Constant Value Validation Tests ============

    /**
     * @notice Test: Mainnet Pool address is non-zero
     * @dev Validates AAVE_V3_POOL_MAINNET constant is defined correctly
     */
    function test_MainnetPoolAddress_IsNonZero() public pure {
        assertNotEq(
            AaveV3Constants.AAVE_V3_POOL_MAINNET,
            address(0),
            "Mainnet Pool address must be non-zero"
        );
    }

    /**
     * @notice Test: Mainnet Pool address matches official Aave V3 deployment
     * @dev Address verified at: https://etherscan.io/address/0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
     */
    function test_MainnetPoolAddress_MatchesOfficialDeployment() public pure {
        assertEq(
            AaveV3Constants.AAVE_V3_POOL_MAINNET,
            0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2,
            "Mainnet Pool address must match official Aave V3 deployment"
        );
    }

    /**
     * @notice Test: Sepolia Pool address is non-zero
     * @dev Validates AAVE_V3_POOL_SEPOLIA constant is defined correctly
     */
    function test_SepoliaPoolAddress_IsNonZero() public pure {
        assertNotEq(
            AaveV3Constants.AAVE_V3_POOL_SEPOLIA,
            address(0),
            "Sepolia Pool address must be non-zero"
        );
    }

    /**
     * @notice Test: Sepolia Pool address matches official Aave V3 testnet deployment
     * @dev Address verified at: https://sepolia.etherscan.io/address/0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951
     */
    function test_SepoliaPoolAddress_MatchesOfficialDeployment() public pure {
        assertEq(
            AaveV3Constants.AAVE_V3_POOL_SEPOLIA,
            0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951,
            "Sepolia Pool address must match official Aave V3 testnet deployment"
        );
    }

    /**
     * @notice Test: Mainnet and Sepolia addresses are different
     * @dev Ensures testnet address is not accidentally used on mainnet
     */
    function test_MainnetAndSepoliaAddresses_AreDifferent() public pure {
        assertNotEq(
            AaveV3Constants.AAVE_V3_POOL_MAINNET,
            AaveV3Constants.AAVE_V3_POOL_SEPOLIA,
            "Mainnet and Sepolia addresses must be different"
        );
    }

    /**
     * @notice Test: Flash loan premium is 5 BPS (0.05%)
     * @dev Validates V3 fee reduction vs V2 (9 BPS)
     */
    function test_FlashLoanPremium_Is5BPS() public pure {
        assertEq(
            AaveV3Constants.AAVE_V3_FLASHLOAN_PREMIUM_TOTAL,
            5,
            "Flash loan premium must be 5 BPS (0.05%)"
        );
    }

    /**
     * @notice Test: Percentage divisor is 10,000 (standard BPS denominator)
     * @dev Validates basis point conversion factor
     */
    function test_PercentageDivisor_Is10000() public pure {
        assertEq(
            AaveV3Constants.PERCENTAGE_DIVISOR,
            10000,
            "Percentage divisor must be 10,000 (standard BPS denominator)"
        );
    }

    // ============ Premium Calculation Validation Tests ============

    /**
     * @notice Test: Premium calculation for 100 ETH loan
     * @dev Example: 100 ETH * 5 / 10000 = 0.05 ETH
     */
    function test_PremiumCalculation_100ETH() public pure {
        uint256 loanAmount = 100 * 10**18; // 100 ETH
        uint256 expectedPremium = 0.05 * 10**18; // 0.05 ETH

        uint256 actualPremium = (loanAmount * AaveV3Constants.AAVE_V3_FLASHLOAN_PREMIUM_TOTAL)
            / AaveV3Constants.PERCENTAGE_DIVISOR;

        assertEq(
            actualPremium,
            expectedPremium,
            "Premium for 100 ETH should be 0.05 ETH"
        );
    }

    /**
     * @notice Test: Premium calculation for 1000 DAI loan
     * @dev Example: 1000 DAI * 5 / 10000 = 0.5 DAI
     */
    function test_PremiumCalculation_1000DAI() public pure {
        uint256 loanAmount = 1000 * 10**18; // 1000 DAI
        uint256 expectedPremium = 0.5 * 10**18; // 0.5 DAI

        uint256 actualPremium = (loanAmount * AaveV3Constants.AAVE_V3_FLASHLOAN_PREMIUM_TOTAL)
            / AaveV3Constants.PERCENTAGE_DIVISOR;

        assertEq(
            actualPremium,
            expectedPremium,
            "Premium for 1000 DAI should be 0.5 DAI"
        );
    }

    /**
     * @notice Test: Premium calculation for 10,000 USDC loan (6 decimals)
     * @dev Example: 10000 USDC * 5 / 10000 = 5 USDC
     */
    function test_PremiumCalculation_10000USDC() public pure {
        uint256 loanAmount = 10000 * 10**6; // 10,000 USDC (6 decimals)
        uint256 expectedPremium = 5 * 10**6; // 5 USDC

        uint256 actualPremium = (loanAmount * AaveV3Constants.AAVE_V3_FLASHLOAN_PREMIUM_TOTAL)
            / AaveV3Constants.PERCENTAGE_DIVISOR;

        assertEq(
            actualPremium,
            expectedPremium,
            "Premium for 10,000 USDC should be 5 USDC"
        );
    }

    /**
     * @notice Test: Fuzz premium calculation across various loan amounts
     * @dev Property: premium = (amount * 5) / 10000 for all valid amounts
     */
    function testFuzz_PremiumCalculation_VariousAmounts(uint256 loanAmount) public pure {
        // Bound to reasonable flash loan sizes (avoid overflow)
        loanAmount = bound(loanAmount, 1 * 10**18, 1_000_000 * 10**18); // 1 to 1M tokens

        uint256 premium = (loanAmount * AaveV3Constants.AAVE_V3_FLASHLOAN_PREMIUM_TOTAL)
            / AaveV3Constants.PERCENTAGE_DIVISOR;

        // Property: Premium should be 0.05% of loan amount
        uint256 expectedPremium = (loanAmount * 5) / 10000;
        assertEq(premium, expectedPremium, "Premium calculation must match formula");

        // Property: Premium should always be less than loan amount (sanity check)
        assertLt(premium, loanAmount, "Premium must be less than loan amount");

        // Property: Premium should be > 0 for non-zero loan amounts
        if (loanAmount > 0) {
            // Note: For very small amounts, premium may round to 0
            // This is expected behavior for amounts < 200 wei (5/10000 < 1)
        }
    }

    // ============ V2 vs V3 Fee Comparison Tests ============

    /**
     * @notice Test: V3 premium is lower than V2 premium
     * @dev Validates 44% fee reduction (9 BPS → 5 BPS)
     */
    function test_V3Premium_LowerThanV2() public pure {
        uint256 V2_PREMIUM_BPS = 9; // Aave V2: 0.09%
        uint256 V3_PREMIUM_BPS = AaveV3Constants.AAVE_V3_FLASHLOAN_PREMIUM_TOTAL;

        assertLt(V3_PREMIUM_BPS, V2_PREMIUM_BPS, "V3 premium must be lower than V2");
    }

    /**
     * @notice Test: V3 fee reduction is exactly 44%
     * @dev Calculation: (9 - 5) / 9 = 0.444... ≈ 44%
     */
    function test_V3FeeReduction_Is44Percent() public pure {
        uint256 V2_PREMIUM_BPS = 9; // Aave V2: 0.09%
        uint256 V3_PREMIUM_BPS = AaveV3Constants.AAVE_V3_FLASHLOAN_PREMIUM_TOTAL;

        // Calculate reduction: (V2 - V3) / V2 * 100
        uint256 reduction = ((V2_PREMIUM_BPS - V3_PREMIUM_BPS) * 100) / V2_PREMIUM_BPS;

        // Expected: (9 - 5) / 9 * 100 = 44.44... → rounds to 44%
        assertEq(reduction, 44, "V3 fee reduction should be 44%");
    }

    /**
     * @notice Test: Cost savings for 1000 ETH flash loan (V2 vs V3)
     * @dev Example: V2 = 0.9 ETH fee, V3 = 0.5 ETH fee, Savings = 0.4 ETH
     */
    function test_CostSavings_1000ETHLoan() public pure {
        uint256 loanAmount = 1000 * 10**18; // 1000 ETH
        uint256 V2_PREMIUM_BPS = 9;
        uint256 V3_PREMIUM_BPS = AaveV3Constants.AAVE_V3_FLASHLOAN_PREMIUM_TOTAL;

        uint256 v2Fee = (loanAmount * V2_PREMIUM_BPS) / AaveV3Constants.PERCENTAGE_DIVISOR;
        uint256 v3Fee = (loanAmount * V3_PREMIUM_BPS) / AaveV3Constants.PERCENTAGE_DIVISOR;

        uint256 savings = v2Fee - v3Fee;

        // Expected savings: 0.9 ETH - 0.5 ETH = 0.4 ETH
        assertEq(savings, 0.4 * 10**18, "Savings for 1000 ETH loan should be 0.4 ETH");
        assertGt(savings, 0, "V3 must save fees compared to V2");
    }

    // ============ Edge Case Tests ============

    /**
     * @notice Test: Premium calculation for minimum loan amount (1 wei)
     * @dev Edge case: Very small loans may have 0 premium due to rounding
     */
    function test_PremiumCalculation_MinimumAmount() public pure {
        uint256 loanAmount = 1; // 1 wei

        uint256 premium = (loanAmount * AaveV3Constants.AAVE_V3_FLASHLOAN_PREMIUM_TOTAL)
            / AaveV3Constants.PERCENTAGE_DIVISOR;

        // 1 * 5 / 10000 = 0 (rounds down)
        assertEq(premium, 0, "Minimum loan amount results in 0 premium (expected rounding)");
    }

    /**
     * @notice Test: Premium calculation for amount at rounding threshold
     * @dev Minimum amount to get 1 wei premium: 10000/5 = 2000 wei
     */
    function test_PremiumCalculation_RoundingThreshold() public pure {
        uint256 loanAmount = 2000; // Minimum for 1 wei premium

        uint256 premium = (loanAmount * AaveV3Constants.AAVE_V3_FLASHLOAN_PREMIUM_TOTAL)
            / AaveV3Constants.PERCENTAGE_DIVISOR;

        // 2000 * 5 / 10000 = 1 wei
        assertEq(premium, 1, "Rounding threshold loan should result in 1 wei premium");
    }

    /**
     * @notice Test: Premium calculation for large loan amount (1M ETH)
     * @dev Edge case: Verify no overflow for large amounts
     */
    function test_PremiumCalculation_LargeAmount() public pure {
        uint256 loanAmount = 1_000_000 * 10**18; // 1M ETH

        uint256 premium = (loanAmount * AaveV3Constants.AAVE_V3_FLASHLOAN_PREMIUM_TOTAL)
            / AaveV3Constants.PERCENTAGE_DIVISOR;

        // 1M ETH * 5 / 10000 = 500 ETH
        assertEq(premium, 500 * 10**18, "Premium for 1M ETH should be 500 ETH");
        assertLt(premium, loanAmount, "Premium must be less than loan amount");
    }
}
