# CLAUDE.md: AI Collaboration Guide

This document provides essential context for AI models interacting with the Flash Arbitrage project. Adhering to these guidelines will ensure consistency, maintain code quality, and optimize security in this DeFi protocol.

## 1. Project Overview & Purpose

*   **Primary Goal:** Production-ready flash arbitrage executor leveraging Aave V2 flash loans to execute profitable arbitrage opportunities across multiple DEXes (Uniswap V2, Sushiswap) on Ethereum mainnet. This is a high-value DeFi protocol designed to extract MEV opportunities while maintaining strict security controls.
*   **Business Domain:** Decentralized Finance (DeFi), Flash Loans, MEV (Maximal Extractable Value), Arbitrage Trading, Ethereum Smart Contracts
*   **Key Features:**
    *   UUPS upgradeable architecture for future enhancements without redeployment
    *   Modular DEX adapter pattern supporting Uniswap V2/V3 and future integrations
    *   Multi-layer security: trusted initiator validation, router/token whitelisting, adapter code hash verification
    *   MEV protection via deadline constraints (max 30-second execution window)
    *   Comprehensive reentrancy protection on all privileged operations
    *   Real-time profit tracking with optional ETH unwrapping
    *   Gas-optimized operations with infinite approvals for common routers

## 2. Core Technologies & Stack

*   **Languages:** Solidity ^0.8.21 (latest 0.8.x with native overflow checks)
*   **Frameworks & Runtimes:** Foundry/Forge (blazing-fast Ethereum development toolkit written in Rust)
*   **Key Libraries/Dependencies:**
    *   **OpenZeppelin Contracts v5.5.0**: Upgradeable patterns (UUPSUpgradeable, Initializable), Security (Ownable, ReentrancyGuard, Pausable), Token standards (IERC20, SafeERC20)
    *   **Forge-Std v1.9.0**: Testing utilities, VM cheatcodes, console logging, assertion helpers
    *   **Aave V2 Protocol**: ILendingPool, ILendingPoolAddressesProvider for flash loan integration
    *   **Uniswap V2**: IUniswapV2Router02 interface for DEX interactions
*   **Package Manager:** Forge (built into Foundry) with remappings for dependency management
*   **Platforms:** Ethereum Mainnet (production target), Local Anvil node (development), Forked Mainnet (testing)
*   **Smart Contract Standards:** ERC-20, ERC-3156 (Flash Loans), EIP-1822 (UUPS Proxies)

## 3. Architectural Patterns & Structure

*   **Overall Architecture:** Production-grade upgradeable flash arbitrage system following the UUPS proxy pattern. The contract acts as both a flash loan receiver (implementing Aave's IFlashLoanReceiver) and an arbitrage executor with modular DEX adapters. Architecture enforces separation of concerns: owner-controlled configuration, flash loan orchestration, swap execution via adapters, and profit accounting.
    
*   **Directory Structure Philosophy:**
    *   `/src`: Core smart contract implementations
        *   `FlashArbMainnetReady.sol`: Primary production contract (1000+ lines) with full security hardening
        *   `IDexAdapter.sol`: Interface for modular DEX integrations
    *   `/test`: Comprehensive test suite with multiple testing methodologies
        *   `FlashArbTest.t.sol`: Unit tests for all contract functions
        *   `FlashArbInvariantTest.t.sol`: Foundry invariant tests for property validation
        *   `FlashArbEchidnaTest.sol`: Echidna property-based fuzzing tests
        *   `mocks/`: Test doubles for external dependencies (MockRouter, MockToken, MockLendingPool)
    *   `/lib`: External dependencies managed via Forge
        *   `forge-std/`: Foundry standard library
        *   `openzeppelin-contracts/`: OpenZeppelin security and upgrade primitives
        *   `openzeppelin-contracts-upgradeable/`: Upgradeable versions of OZ contracts
    *   `/script`: Deployment and upgrade scripts (Foundry scripts)
    *   `/docs/security`: Security documentation including 2025 toolchain extensions
    *   `/out`: Compiled artifacts (excluded from version control)
    *   `/broadcast`: Deployment transaction logs (excluded from version control)

*   **Module Organization:** 
    *   **FlashArbMainnetReady**: Monolithic main contract with clear functional sections:
        *   Constants and state variables (Aave addresses, DEX addresses, whitelists, profit tracking)
        *   Initialization and upgrade logic (UUPS pattern)
        *   Owner-controlled configuration functions (whitelisting, adapter management)
        *   Flash loan orchestration (startFlashLoan → executeOperation)
        *   Swap execution with adapter validation
        *   Profit withdrawal mechanisms
    *   **Test Contracts**: Organized by testing methodology (unit, invariant, fuzzing)
    *   **Mock Contracts**: Minimal implementations for deterministic testing

*   **Common Patterns & Idioms:**
    *   **Upgradeable Pattern**: UUPS (Universal Upgradeable Proxy Standard) via OpenZeppelin, with `_disableInitializers()` in constructor
    *   **Security Patterns**: 
        *   Check-Effects-Interactions pattern throughout
        *   Reentrancy guards (`nonReentrant`) on all owner functions
        *   Two-step adapter validation (address + bytecode hash)
        *   Strict whitelist-based access control
    *   **Gas Optimization**:
        *   Infinite approvals for trusted routers (eliminates redundant approval transactions)
        *   Native Solidity 0.8.x arithmetic (no SafeMath overhead)
        *   Single-storage-slot state updates where possible
    *   **Error Handling**: String-based custom errors with descriptive messages (e.g., "adapter-not-approved", "deadline-invalid", "profit-less-than-min")
    *   **Modularity**: IDexAdapter interface enables pluggable swap execution logic without core contract changes

## 4. Coding Conventions & Style Guide

*   **Formatting:** 
    *   **Indentation**: 4 spaces (Foundry default)
    *   **Line Length**: 120 characters maximum (configured in `lib/forge-std/foundry.toml`)
    *   **Bracket Spacing**: `false` (no spaces inside brackets)
    *   **Quote Style**: Double quotes for strings
    *   **Formatter**: Use `forge fmt` before every commit
    
*   **Naming Conventions:**
    *   **Functions**: `camelCase` (e.g., `startFlashLoan`, `setRouterWhitelist`, `executeOperation`)
    *   **State Variables**: `camelCase` (e.g., `lendingPool`, `maxSlippageBps`, `trustedInitiators`)
    *   **Constants**: `SCREAMING_SNAKE_CASE` (e.g., `AAVE_PROVIDER`, `UNISWAP_V2_ROUTER`, `MAX_DEADLINE`)
    *   **Interfaces**: `IPascalCase` (e.g., `ILendingPool`, `IDexAdapter`, `IUniswapV2Router02`)
    *   **Events**: `PascalCase` (e.g., `FlashLoanExecuted`, `RouterWhitelisted`, `AdapterApproved`)
    *   **Test Functions**: `test` prefix for standard tests, `testFuzz_` for fuzz tests, `testFail_` for expected-failure tests, `invariant_` for invariant tests, `echidna_` for Echidna properties

*   **API Design Principles:**
    *   **Explicit Security**: All privileged functions use `onlyOwner` modifier; flash loan execution validates caller identity
    *   **Defense in Depth**: Multiple validation layers (whitelist → adapter approval → runtime verification)
    *   **MEV Resistance**: Strict deadline enforcement (30-second maximum) prevents stale transaction execution
    *   **Fail-Fast**: Use `require()` with descriptive error messages; never silently ignore validation failures
    *   **Event Emission**: Emit events for all state changes to enable off-chain monitoring and indexing

*   **Documentation Style:**
    *   Use NatSpec comments (`/// @notice`, `/// @dev`, `/// @param`, `/// @return`) for all public/external functions
    *   Include security notes in `@dev` tags (e.g., "Protected with nonReentrant to prevent malicious adapter reentrancy attacks")
    *   Document system invariants in contract-level comments
    *   Maintain inline comments for complex arithmetic or security-critical logic

*   **Error Handling:**
    *   Use descriptive string-based errors (e.g., `require(condition, "error-code")`)
    *   Error codes follow hyphenated lowercase convention: `"adapter-not-approved"`, `"deadline-invalid"`, `"insufficient-to-repay"`
    *   Never use `assert()` for user-input validation; reserve for invariant checking
    *   Always provide actionable error messages

*   **Forbidden Patterns:**
    *   **NEVER** use `selfdestruct` (deprecated and dangerous)
    *   **NEVER** use `delegatecall` to untrusted contracts
    *   **NEVER** perform external calls before state updates (Check-Effects-Interactions)
    *   **NEVER** use `tx.origin` for authentication (use `msg.sender`)
    *   **NEVER** hardcode addresses (use configurable state variables or constants)
    *   **NEVER** skip validation checks for gas optimization without explicit security review

## 5. Development & Testing Workflow

**Testing Philosophy**: This project follows **test-driven security development**. Every feature begins with comprehensive tests across multiple methodologies (unit, fuzz, invariant, fork) before implementation. Testing is not optional—it's the primary defense mechanism for immutable smart contracts.

### 5.1 Local Development Setup

1. **Install Foundry (Latest Stable):**
```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   forge --version  # Verify installation
```

2. **Clone and Install Dependencies:**
```bash
   git clone <repository>
   cd flash-arbitrage
   forge install  # Installs from foundry.toml remappings
   forge build    # Verify compilation succeeds
```

3. **Environment Configuration:**
```bash
   cp .env.example .env
   # Configure: MAINNET_RPC_URL, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY, PRIVATE_KEY
   # NEVER commit .env to version control
```

4. **Verify Test Infrastructure:**
```bash
   forge test        # All tests should pass on fresh install
   forge test -vvv   # Verbose mode to verify test execution
```

---

### 5.2 Foundry/Forge Testing Framework - Comprehensive Ruleset

**CRITICAL**: This project uses Foundry's battle-tested framework. The following conventions are **mandatory** for all test code.

#### 5.2.1 Test File Organization & Structure

**File Naming Convention:**
```
test/
├── FlashArbTest.t.sol                    # Unit tests (standard)
├── FlashArbInvariantTest.t.sol           # Invariant tests (property-based)
├── FlashArbEchidnaTest.sol               # Echidna fuzzing tests
├── FlashArbForkTest.t.sol                # Fork tests (mainnet state)
├── mocks/
│   ├── MockRouter.sol                    # Test doubles
│   ├── MockToken.sol
│   └── MockLendingPool.sol
└── helpers/
    └── TestHelpers.sol                   # Shared test utilities
```

**Mandatory File Suffix**: 
- `.t.sol` for Foundry tests (enables auto-discovery)
- No suffix for Echidna tests (`.sol` only)

**Test Contract Structure Pattern:**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../src/FlashArbMainnetReady.sol";
import "./mocks/MockRouter.sol";

/**
 * @title FlashArbTest
 * @notice Comprehensive unit test suite for FlashArbMainnetReady contract
 * @dev Covers all public/external functions with positive and negative cases
 */
contract FlashArbTest is Test {
    // ============ State Variables ============
    FlashArbMainnetReady public arb;
    MockRouter public router1;
    MockRouter public router2;
    MockToken public tokenA;
    MockToken public tokenB;
    MockLendingPool public lendingPool;
    
    address public owner = address(this);
    address public attacker = address(0xBEEF);
    
    // ============ Constants ============
    uint256 constant INITIAL_BALANCE = 10_000 * 10**18;
    uint256 constant LOAN_AMOUNT = 1_000 * 10**18;
    
    // ============ Setup ============
    
    function setUp() public {
        // Deploy mocks (deterministic order)
        tokenA = new MockToken("Token A", "TKA", 18);
        tokenB = new MockToken("Token B", "TKB", 18);
        router1 = new MockRouter();
        router2 = new MockRouter();
        lendingPool = new MockLendingPool();
        
        // Deploy contract under test
        arb = new FlashArbMainnetReady();
        arb.initialize();
        
        // Setup initial state
        _setupInitialBalances();
        _setupRouterRates();
        _whitelistAssets();
    }
    
    // ============ Helper Functions ============
    
    function _setupInitialBalances() internal {
        deal(address(tokenA), address(lendingPool), INITIAL_BALANCE);
        deal(address(tokenB), address(router1), INITIAL_BALANCE);
    }
    
    function _setupRouterRates() internal {
        router1.setExchangeRate(1 * 10**18, 95 * 10**17);  // 1 A -> 0.95 B
        router2.setExchangeRate(1 * 10**18, 105 * 10**17); // 1 B -> 1.05 A
    }
    
    function _whitelistAssets() internal {
        arb.setRouterWhitelist(address(router1), true);
        arb.setRouterWhitelist(address(router2), true);
        arb.setTokenWhitelist(address(tokenA), true);
        arb.setTokenWhitelist(address(tokenB), true);
    }
    
    // ============ Unit Tests ============
    
    function test_SuccessfulArbitrage() public {
        // Arrange: Setup profitable opportunity
        uint256 loanAmount = LOAN_AMOUNT;
        bytes memory params = _createValidParams(loanAmount);
        
        // Act: Execute flash loan arbitrage
        vm.prank(owner);
        arb.startFlashLoan(address(tokenA), loanAmount, params);
        
        // Assert: Profit recorded
        assertGt(arb.profits(address(tokenA)), 0, "Profit should be positive");
        assertEq(tokenA.balanceOf(address(arb)), arb.profits(address(tokenA)), 
                 "Contract balance should equal recorded profit");
    }
    
    function testFail_UnauthorizedExecutor() public {
        // Should revert when non-owner attempts flash loan
        bytes memory params = _createValidParams(LOAN_AMOUNT);
        vm.prank(attacker);
        arb.startFlashLoan(address(tokenA), LOAN_AMOUNT, params);
    }
    
    // ... additional tests
}
```

#### 5.2.2 Test Naming Conventions (STRICTLY ENFORCED)

**Standard Tests (Success Cases):**
```solidity
function test_<FunctionName>_<Scenario>() public {
    // Test passes if no revert
}

// Examples:
function test_StartFlashLoan_WithProfitableOpportunity() public { }
function test_Withdraw_TransfersTokensToOwner() public { }
function test_SetRouterWhitelist_UpdatesMapping() public { }
```

**Failure Tests (Expected Reverts):**
```solidity
function testFail_<FunctionName>_<FailureReason>() public {
    // Test passes if function reverts (any reason)
}

// Examples:
function testFail_StartFlashLoan_UnauthorizedCaller() public { }
function testFail_ExecuteOperation_ExpiredDeadline() public { }
function testFail_Withdraw_InsufficientBalance() public { }
```

**Fuzz Tests (Property-Based):**
```solidity
function testFuzz_<FunctionName>_<Property>(uint256 input) public {
    vm.assume(input > 0 && input < type(uint128).max);
    // Test property holds for all valid inputs
}

// Examples:
function testFuzz_ExecuteOperation_AlwaysRepaysLoan(uint256 loanAmount) public { }
function testFuzz_SetMaxSlippage_RejectsAboveTenPercent(uint256 bps) public { }
function testFuzz_StartFlashLoan_ValidatesDeadlineBounds(uint256 deadline) public { }
```

**Invariant Tests (State Properties):**
```solidity
function invariant_<PropertyName>() external {
    // Property that must ALWAYS hold true
}

// Examples:
function invariant_FlashLoanAlwaysRepaid() external { }
function invariant_ProfitNeverNegative() external { }
function invariant_ContractBalanceMatchesAccountedProfits() external { }
function invariant_OnlyOwnerCanExecutePrivilegedFunctions() external { }
```

**Fork Tests (Mainnet State):**
```solidity
function testFork_<Scenario>_<ExpectedOutcome>() public {
    // Test against real mainnet state
}

// Examples:
function testFork_ArbitrageUniswapSushiswap_RealMainnetPrices() public { }
function testFork_FlashLoanAaveV2_RealLendingPool() public { }
```

---

#### 5.2.3 Test Structure Best Practices

**Arrange-Act-Assert Pattern (MANDATORY):**
```solidity
function test_Example() public {
    // ============ ARRANGE ============
    // Setup test preconditions, create test data
    uint256 loanAmount = 1000 * 10**18;
    router1.setExchangeRate(1 * 10**18, 95 * 10**17);
    bytes memory params = _createValidParams(loanAmount);
    
    // ============ ACT ============
    // Execute the function under test (single action)
    vm.prank(owner);
    arb.startFlashLoan(address(tokenA), loanAmount, params);
    
    // ============ ASSERT ============
    // Verify expected outcomes (multiple assertions allowed)
    assertGt(arb.profits(address(tokenA)), 0);
    assertEq(tokenA.balanceOf(address(arb)), arb.profits(address(tokenA)));
}
```

**Test Isolation (CRITICAL):**
- Each test MUST be independent (no shared state between tests)
- Use `setUp()` to reset state before EVERY test
- NEVER rely on test execution order
- NEVER use global mutable state across tests

**Helper Function Patterns:**
```solidity
// Private helpers (internal test utilities)
function _createValidParams(uint256 amount) private view returns (bytes memory) {
    address[] memory path1 = new address[](2);
    path1[0] = address(tokenA);
    path1[1] = address(tokenB);
    // ... construct params
    return abi.encode(/* params */);
}

// Setup helpers (reusable state initialization)
function _setupProfitableArbitrage() internal {
    router1.setExchangeRate(1 * 10**18, 95 * 10**17);
    router2.setExchangeRate(1 * 10**18, 105 * 10**17);
}

// Assertion helpers (complex validation logic)
function _assertProfitRecorded(address token, uint256 expectedMin) internal {
    uint256 profit = arb.profits(token);
    assertGe(profit, expectedMin, "Profit below minimum threshold");
    assertEq(IERC20(token).balanceOf(address(arb)), profit, 
             "Balance mismatch with recorded profit");
}
```

---

#### 5.2.4 Foundry Cheatcodes (Essential Usage Patterns)

**Address Manipulation:**
```solidity
// Prank: Execute next call as specified address
vm.prank(attacker);
arb.startFlashLoan(/* params */);  // msg.sender = attacker

// Start prank: Execute all calls as specified address until stopPrank
vm.startPrank(owner);
arb.setRouterWhitelist(address(router1), true);
arb.setTokenWhitelist(address(tokenA), true);
vm.stopPrank();

// Deal: Set ERC20 balance directly
deal(address(tokenA), address(lendingPool), 10_000 * 10**18);

// Hoax: Combined prank + deal (set caller + give ETH)
hoax(attacker, 100 ether);
arb.somePayableFunction{value: 1 ether}();
```

**Time Manipulation:**
```solidity
// Warp: Set block.timestamp
vm.warp(block.timestamp + 3600);  // Fast-forward 1 hour

// Roll: Set block.number
vm.roll(block.number + 100);  // Advance 100 blocks
```

**Expectation Assertions:**
```solidity
// Expect specific revert message
vm.expectRevert("deadline-invalid");
arb.startFlashLoan(/* params with expired deadline */);

// Expect any revert (no message check)
vm.expectRevert();
arb.unauthorizedFunction();

// Expect specific error selector (custom errors)
vm.expectRevert(
    abi.encodeWithSelector(FlashArbMainnetReady.UnauthorizedCaller.selector)
);
arb.restrictedFunction();

// Expect event emission
vm.expectEmit(true, true, false, true);
emit FlashLoanExecuted(owner, address(tokenA), 1000e18, 9e17, 50e18);
arb.startFlashLoan(/* params */);
```

**Storage Manipulation:**
```solidity
// Store: Write directly to storage slot
vm.store(address(arb), bytes32(uint256(5)), bytes32(uint256(100)));

// Load: Read storage slot
bytes32 value = vm.load(address(arb), bytes32(uint256(5)));

// Record: Start recording storage reads/writes
vm.record();
arb.someFunction();
(bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(arb));
```

**Mock External Calls:**
```solidity
// Mock call: Return specific data for external call
vm.mockCall(
    address(router1),
    abi.encodeWithSelector(IUniswapV2Router02.swapExactTokensForTokens.selector),
    abi.encode(new uint256[](2))  // Mock return value
);

// Expect call: Verify external call is made
vm.expectCall(
    address(tokenA),
    abi.encodeWithSelector(IERC20.approve.selector, address(router1), 1000e18)
);
arb.startFlashLoan(/* params */);
```

---

#### 5.2.5 Fuzz Testing Best Practices

**Foundry Fuzzing Configuration** (`foundry.toml`):
```toml
[fuzz]
runs = 10000                  # Number of fuzz runs per test
max_test_rejects = 1000000    # Maximum rejections before failing
seed = '0x3e8'                # Deterministic seed (optional)
dictionary_weight = 40        # Use dictionary-based inputs (0-100)
include_storage = true        # Include storage values in fuzzing
include_push_bytes = true     # Include push bytes in fuzzing
```

**Fuzz Test Pattern:**
```solidity
function testFuzz_ExecuteOperation_RepaysLoan(
    uint256 loanAmount,
    uint256 exchangeRate1,
    uint256 exchangeRate2
) public {
    // ============ BOUND INPUTS ============
    // Constrain inputs to valid ranges (CRITICAL)
    loanAmount = bound(loanAmount, 1 * 10**18, 10_000 * 10**18);
    exchangeRate1 = bound(exchangeRate1, 90 * 10**16, 100 * 10**16);  // 0.90 - 1.00
    exchangeRate2 = bound(exchangeRate2, 100 * 10**16, 110 * 10**16); // 1.00 - 1.10
    
    // Alternative: Use vm.assume (but can waste runs if too restrictive)
    // vm.assume(loanAmount > 0 && loanAmount < 10_000 * 10**18);
    
    // ============ SETUP ============
    deal(address(tokenA), address(lendingPool), loanAmount);
    router1.setExchangeRate(1 * 10**18, exchangeRate1);
    router2.setExchangeRate(1 * 10**18, exchangeRate2);
    
    bytes memory params = _createValidParams(loanAmount);
    
    // ============ ACT ============
    vm.prank(owner);
    arb.startFlashLoan(address(tokenA), loanAmount, params);
    
    // ============ ASSERT ============
    // Invariant: Flash loan MUST be repaid (contract balance >= 0)
    assertGe(tokenA.balanceOf(address(arb)), 0, "Flash loan not repaid");
}
```

**Fuzz Testing Guidelines:**

1. **Use `bound()` instead of `vm.assume()`** for numeric constraints
   - `bound()` maps input to valid range (no wasted runs)
   - `vm.assume()` rejects inputs (can waste runs if range is small)

2. **Constrain inputs to realistic ranges**
```solidity
   // ❌ Bad: Too permissive (tests unrealistic scenarios)
   function testFuzz_Bad(uint256 amount) public { }
   
   // ✅ Good: Bounded to practical limits
   function testFuzz_Good(uint256 amount) public {
       amount = bound(amount, 1e18, 1_000_000e18);  // 1 to 1M tokens
   }
```

3. **Test ONE property per fuzz test**
   - Focus on specific invariant or property
   - Don't mix multiple unrelated assertions

4. **Use fuzz seed for reproducibility**
```bash
   # Reproduce failing fuzz case
   forge test --fuzz-seed 0x1234567890abcdef
```

5. **Analyze fuzz failures systematically**
```bash
   # Run with maximum verbosity to see failing input
   forge test --match-test testFuzz_ExecuteOperation -vvvv
```

---

#### 5.2.6 Invariant Testing Framework

**Invariant Test Configuration** (`foundry.toml`):
```toml
[invariant]
runs = 1000                   # Number of invariant runs
depth = 100                   # Max function calls per run
fail_on_revert = false        # Continue on reverts (useful for finding edge cases)
call_override = false         # Don't override function selectors
dictionary_weight = 80        # Heavy dictionary use for invariants
include_storage = true
include_push_bytes = true
```

**Invariant Test Structure:**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../src/FlashArbMainnetReady.sol";

/**
 * @title FlashArbInvariantTest
 * @notice Stateful fuzz testing for system-wide invariants
 * @dev Tests properties that MUST hold after any sequence of function calls
 */
contract FlashArbInvariantTest is Test {
    FlashArbMainnetReady public arb;
    Handler public handler;  // Actor contract for targeted invariant testing
    
    function setUp() public {
        arb = new FlashArbMainnetReady();
        arb.initialize();
        
        // Create handler for targeted function calls
        handler = new Handler(arb);
        
        // Target handler for invariant testing (not main contract directly)
        targetContract(address(handler));
    }
    
    // ============ Invariant: Flash Loan Always Repaid ============
    
    function invariant_FlashLoanAlwaysRepaid() external {
        // Property: After any flash loan execution, contract must have
        // sufficient balance to cover debt (balance >= 0)
        
        // This invariant validates SC05 (Reentrancy) and SC03 (Logic Errors)
        assertTrue(
            handler.loansExecuted() == 0 || 
            handler.allLoansRepaid(),
            "Flash loan not repaid in at least one execution"
        );
    }
    
    // ============ Invariant: Profit Accuracy ============
    
    function invariant_ProfitMatchesBalance() external {
        // Property: Recorded profits MUST match actual token balances
        
        address[] memory tokens = handler.getTrackedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 recordedProfit = arb.profits(tokens[i]);
            uint256 actualBalance = IERC20(tokens[i]).balanceOf(address(arb));
            
            assertEq(
                actualBalance,
                recordedProfit,
                string.concat("Profit mismatch for token ", vm.toString(tokens[i]))
            );
        }
    }
    
    // ============ Invariant: Access Control ============
    
    function invariant_OnlyOwnerExecutesPrivilegedFunctions() external {
        // Property: Non-owner CANNOT execute owner-only functions
        
        assertTrue(
            handler.unauthorizedCallsReverted() == handler.unauthorizedCallsAttempted(),
            "Unauthorized call succeeded when it should have reverted"
        );
    }
}

/**
 * @title Handler
 * @notice Actor contract for targeted invariant testing
 * @dev Wraps main contract calls with tracking and validation
 */
contract Handler is Test {
    FlashArbMainnetReady public arb;
    
    uint256 public loansExecuted;
    uint256 public loansRepaid;
    uint256 public unauthorizedCallsAttempted;
    uint256 public unauthorizedCallsReverted;
    
    address[] public trackedTokens;
    
    constructor(FlashArbMainnetReady _arb) {
        arb = _arb;
    }
    
    function executeFlashLoan(uint256 loanAmount, uint256 seed) external {
        // Bounded inputs
        loanAmount = bound(loanAmount, 1e18, 1000e18);
        
        // Track execution
        loansExecuted++;
        
        // Execute (may revert, which is acceptable)
        try arb.startFlashLoan(/* params */) {
            loansRepaid++;  // If succeeded, loan was repaid
        } catch {
            // Revert is acceptable (unprofitable, invalid params, etc.)
        }
    }
    
    function attemptUnauthorizedCall() external {
        unauthorizedCallsAttempted++;
        
        address attacker = address(0xBEEF);
        vm.prank(attacker);
        
        try arb.setRouterWhitelist(address(0x1), true) {
            // Should NEVER succeed
        } catch {
            unauthorizedCallsReverted++;  // Expected
        }
    }
    
    function allLoansRepaid() external view returns (bool) {
        return loansRepaid == loansExecuted;
    }
    
    function getTrackedTokens() external view returns (address[] memory) {
        return trackedTokens;
    }
}
```

**Invariant Testing Best Practices:**

1. **Use Handler Pattern** for targeted testing (don't fuzz main contract directly)
2. **Track state changes** in handler for invariant validation
3. **Test system-wide properties**, not individual function outputs
4. **Accept reverts** (`fail_on_revert = false`) to explore edge cases
5. **Run overnight** for deep invariant campaigns (1000+ runs, depth 500+)

---

#### 5.2.7 Fork Testing (Mainnet State)

**Fork Testing Configuration:**
```bash
# Set mainnet RPC URL
export MAINNET_RPC_URL="https://eth-mainnet.alchemyapi.io/v2/YOUR_KEY"

# Run fork tests
forge test --fork-url $MAINNET_RPC_URL --match-test testFork_
```

**Fork Test Pattern:**
```solidity
function testFork_RealUniswapArbitrage() public {
    // ============ SETUP FORK ============
    uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 18_000_000);
    vm.selectFork(forkId);
    
    // Verify we're on mainnet fork
    assertEq(block.chainid, 1, "Not on mainnet fork");
    
    // ============ DEPLOY ON FORK ============
    FlashArbMainnetReady arbFork = new FlashArbMainnetReady();
    arbFork.initialize();
    
    // ============ USE REAL MAINNET CONTRACTS ============
    address REAL_UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address REAL_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address REAL_DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    
    // ============ EXECUTE REAL ARBITRAGE ============
    // ... test with actual mainnet liquidity and prices
    
    // ============ ASSERT REALISTIC OUTCOMES ============
    // Verify gas costs, slippage, profit margins match expectations
}
```

**Fork Testing Best Practices:**

1. **Pin fork to specific block** for reproducibility
```bash
   forge test --fork-url $URL --fork-block-number 18000000
```

2. **Cache RPC responses** (Foundry caches automatically after first run)
   - First run is slow (fetches state from RPC)
   - Subsequent runs are fast (uses local cache)

3. **Test realistic scenarios** that can't be mocked
   - Real DEX liquidity and pricing
   - Actual Aave flash loan fees
   - Mainnet gas costs

4. **Verify contract interactions** with real protocols
   - Ensure ABI compatibility
   - Test against actual deployed contracts (not mocks)

5. **Use for pre-deployment validation**
```bash
   # Final check before mainnet deploy
   forge test --fork-url $MAINNET_RPC_URL --gas-report
```

---

#### 5.2.8 Gas Profiling & Optimization Testing

**Gas Reporting:**
```bash
# Generate gas report for all tests
forge test --gas-report

# Gas report with detailed breakdown
forge test --gas-report | tee gas-report.txt

# Gas snapshot (track changes over time)
forge snapshot
forge snapshot --diff  # Compare with previous snapshot
```

**Gas Optimization Test Pattern:**
```solidity
function test_GasOptimization_InfiniteApprovals() public {
    // ============ SETUP ============
    uint256 initialGas;
    uint256 gasUsed;
    
    // ============ TEST: First execution (approval needed) ============
    initialGas = gasleft();
    arb.startFlashLoan(/* params */);
    gasUsed = initialGas - gasleft();
    
    uint256 firstExecutionGas = gasUsed;
    console.log("First execution gas:", firstExecutionGas);
    
    // ============ TEST: Second execution (infinite approval cached) ============
    initialGas = gasleft();
    arb.startFlashLoan(/* params */);
    gasUsed = initialGas - gasleft();
    
    uint256 secondExecutionGas = gasUsed;
    console.log("Second execution gas:", secondExecutionGas);
    
    // ============ ASSERT ============
    // Second execution should be cheaper (no approval transaction)
    assertLt(
        secondExecutionGas,
        firstExecutionGas,
        "Infinite approvals not working (gas should decrease)"
    );
    
    // Verify gas savings are significant (>20k gas saved)
    assertGt(
        firstExecutionGas - secondExecutionGas,
        20_000,
        "Gas savings below threshold"
    );
}

function test_GasLimit_AllFunctionsUnderBlockLimit() public {
    // ============ ASSERT ============
    // No single function should use >5M gas (well under 30M block limit)
    
    uint256 initialGas = gasleft();
    arb.startFlashLoan(/* params */);
    uint256 gasUsed = initialGas - gasleft();
    
    assertLt(gasUsed, 5_000_000, "Function exceeds gas safety threshold");
}
```

**Gas Profiling Best Practices:**

1. **Track gas usage in CI/CD** (fail build if gas increases unexpectedly)
2. **Set gas thresholds** for critical functions (alert on regression)
3. **Use `forge snapshot`** to track gas changes over time
4. **Optimize hot paths** (functions called frequently in production)
5. **Document trade-offs** (security vs. gas optimization decisions)

---

#### 5.2.9 Test Coverage Requirements

**Coverage Configuration** (`foundry.toml`):
```toml
# Coverage settings (not a standard section, but tracked via lcov)
# Use forge coverage to generate reports
```

**Coverage Commands:**
```bash
# Generate coverage report (terminal output)
forge coverage

# Generate LCOV format (for tools like Codecov)
forge coverage --report lcov

# Generate detailed HTML report
genhtml lcov.info -o coverage-report
open coverage-report/index.html  # View in browser
```

**Coverage Requirements (MANDATORY):**

- **≥95% line coverage** for `src/FlashArbMainnetReady.sol`
- **100% coverage** for all security-critical functions:
  - `executeOperation()`
  - `setDexAdapter()`
  - `approveAdapter()`
  - `withdraw()`
  - `_authorizeUpgrade()`
- **≥90% branch coverage** (all conditional paths tested)
- **100% function coverage** (every public/external function has ≥1 test)

**Coverage Verification (Pre-PR Checklist):**
```bash
# Run coverage and verify thresholds
forge coverage | grep "src/FlashArbMainnetReady.sol"

# Expected output:
# | src/FlashArbMainnetReady.sol | 95.2% | 98.1% | 96.7% | 100.0% |
#                                  ^^^^    ^^^^    ^^^^    ^^^^^
#                                  Line    Branch  Func    Statement
```

**Coverage Anti-Patterns (AVOID):**
- ❌ Writing tests just to increase coverage percentage
- ❌ Testing getters/setters without meaningful assertions
- ❌ Skipping negative test cases (only testing happy path)
- ✅ Focus on **meaningful coverage** (test actual behavior, not just lines)

---

#### 5.2.10 Continuous Integration (CI/CD) Pipeline

**GitHub Actions Workflow** (`.github/workflows/test.yml`):
```yaml
name: Foundry Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
        with:
          submodules: recursive
      
      - name: Install Foundry
        uses: foundry-rs/foundry-toolchain@v1
        with:
          version: nightly
      
      - name: Check formatting
        run: forge fmt --check
      
      - name: Build contracts
        run: forge build --sizes
      
      - name: Run unit tests
        run: forge test -vvv
      
      - name: Run fuzz tests
        run: forge test --match-test testFuzz_ --fuzz-runs 10000
      
      - name: Run invariant tests
        run: forge test --match-contract Invariant
      
      - name: Generate coverage report
        run: forge coverage --report lcov
      
      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          files: ./lcov.info
      
      - name: Generate gas report
        run: forge test --gas-report > gas-report.txt
      
      - name: Run Slither static analysis
        uses: crytic/slither-action@v0.3.0
        with:
          fail-on: high
      
      - name: Check contract size
        run: |
          forge build --sizes | tee contract-sizes.txt
          # Fail if any contract >24KB (mainnet limit)
          if grep -q "24\.[0-9]" contract-sizes.txt; then
            echo "Contract exceeds 24KB limit"
            exit 1
          fi
```

**CI/CD Best Practices:**

1. **Run all test types** (unit, fuzz, invariant) on every PR
2. **Cache Foundry installation** to speed up CI (GitHub Actions cache)
3. **Fail build on:**
   - Test failures (any single test fails)
   - Coverage drop (below 95% threshold)
   - Gas regression (>5% increase without justification)
   - Slither critical/high findings
   - Contract size exceeds 24KB
4. **Generate artifacts:**
   - Coverage reports (upload to Codecov)
   - Gas reports (comment on PR)
   - Slither reports (attach to PR)
5. **Run fork tests separately** (scheduled nightly, not on every PR)

---

### 5.3 Build Commands
```bash
# Standard compilation
forge build

# Force recompilation (clear cache)
forge build --force

# Show contract sizes (verify <24KB for mainnet)
forge build --sizes

# Compile with optimizer
forge build --optimize --optimizer-runs 200

# Generate ABI and bytecode
forge build --extra-output-files abi --extra-output-files bin
```

---

### 5.4 Complete Testing Command Reference

**Unit Tests:**
```bash
# Run all tests
forge test

# Verbose output (show logs)
forge test -vv       # Minimal verbosity
forge test -vvv      # Medium verbosity (logs + stack traces)
forge test -vvvv     # Maximum verbosity (all internal calls)

# Run specific test
forge test --match-test test_SuccessfulArbitrage

# Run specific test contract
forge test --match-contract FlashArbTest

# Run tests matching pattern
forge test --match-path "test/FlashArb*.t.sol"
```

**Fuzz Tests:**
```bash
# Run all fuzz tests (10,000 runs per test)
forge test --match-test testFuzz_

# Custom fuzz runs
forge test --match-test testFuzz_ --fuzz-runs 50000

# Reproduce specific fuzz failure
forge test --match-test testFuzz_Example --fuzz-seed 0xdeadbeef
```

**Invariant Tests:**
```bash
# Run invariant tests (1,000 runs, depth 100)
forge test --match-contract Invariant

# Deep invariant testing (overnight run)
forge test --match-contract Invariant --invariant-runs 5000 --invariant-depth 500
```

**Fork Tests:**
```bash
# Run fork tests against mainnet
forge test --fork-url $MAINNET_RPC_URL --match-test testFork_

# Pin to specific block
forge test --fork-url $MAINNET_RPC_URL --fork-block-number 18000000
```

**Coverage & Profiling:**
```bash
# Generate coverage report
forge coverage

# Generate LCOV report
forge coverage --report lcov

# Generate gas report
forge test --gas-report

# Create gas snapshot
forge snapshot

# Compare gas snapshot
forge snapshot --diff
```

---

### 5.5 Test Debugging Strategies

**Debugging Failed Tests:**

1. **Increase Verbosity:**
```bash
   forge test --match-test test_FailingTest -vvvv
   # Shows: logs, stack traces, internal calls, storage changes
```

2. **Isolate the Failure:**
```bash
   # Run only the failing test
   forge test --match-test test_FailingTest
   
   # Add console.log statements
   import "forge-std/console.sol";
   console.log("Debug value:", someVariable);
```

3. **Inspect State:**
```solidity
   // Use console.log liberally
   console.log("Balance before:", tokenA.balanceOf(address(arb)));
   arb.someFunction();
   console.log("Balance after:", tokenA.balanceOf(address(arb)));
   
   // Log addresses for verification
   console.log("Router address:", address(router1));
   console.log("Token address:", address(tokenA));
```

4. **Reproduce with Hardcoded Values:**
```solidity
   // If fuzz test fails, extract failing values from output
   function test_DebugFuzzFailure() public {
       uint256 failingAmount = 123456789;  // From fuzz output
       // ... reproduce exact scenario
   }
```

5. **Use Foundry Debugger:**
```bash
   # Interactive debugger (step through execution)
   forge test --debug test_FailingTest
```

**Common Test Failures:**

| Error | Likely Cause | Solution |
|-------|--------------|----------|
| `Arithmetic over/underflow` | Unchecked math in Solidity <0.8 | Use Solidity 0.8+ or SafeMath |
| `Revert: reason string` | Expected revert not triggered | Check `vm.expectRevert()` usage |
| `OutOfGas` | Function exceeds gas limit | Optimize code or increase gas |
| `EvmError: InvalidFEOpcode` | Calling non-existent function | Verify ABI and selector |
| `Setup failed` | `setUp()` reverted | Debug setup code in isolation |

---

**CRITICAL REMINDER FOR AI AGENTS:**

- **Tests are not optional** - they are the PRIMARY security mechanism
- **Every PR MUST include tests** for all new/modified code
- **Coverage MUST be ≥95%** before PR approval
- **All test types MUST pass** (unit, fuzz, invariant, static analysis)
- **Gas profiling MUST be reviewed** for optimization regressions
- **DO NOT merge code without green CI/CD status**

**When in doubt, write MORE tests, not fewer.**

### 5.6 Testing Anti-Patterns & Common Mistakes

**AVOID THESE PATTERNS:**

#### ❌ Anti-Pattern 1: Testing Implementation Details
```solidity
// BAD: Testing internal implementation
function test_Bad_InternalImplementation() public {
    // Don't test HOW something works internally
    assertEq(arb.getInternalCounter(), 5);  // Testing private state
}

// GOOD: Testing public behavior/outcomes
function test_Good_PublicBehavior() public {
    arb.executeFunction();
    // Test WHAT the function achieves (externally observable)
    assertEq(arb.profits(token), expectedProfit);
}
```

#### ❌ Anti-Pattern 2: Overly Complex Test Setup
```solidity
// BAD: Massive setup that obscures test purpose
function test_Bad_ComplexSetup() public {
    // 50 lines of setup code...
    // ... lost track of what we're testing
}

// GOOD: Extract setup to helper functions
function test_Good_ClearSetup() public {
    _setupProfitableArbitrage();  // Clear intent
    arb.startFlashLoan(params);
    _assertProfitRecorded(tokenA, minProfit);
}
```

#### ❌ Anti-Pattern 3: Multiple Assertions Without Clear Failure Messages
```solidity
// BAD: Generic assertions
function test_Bad_GenericAssertions() public {
    assertTrue(condition1);
    assertTrue(condition2);  // Which assertion failed?
    assertTrue(condition3);
}

// GOOD: Descriptive failure messages
function test_Good_DescriptiveAssertions() public {
    assertTrue(condition1, "Flash loan not initiated");
    assertTrue(condition2, "Slippage exceeded maximum");
    assertTrue(condition3, "Profit below minimum threshold");
}
```

#### ❌ Anti-Pattern 4: Ignoring Edge Cases
```solidity
// BAD: Only happy path
function test_Bad_OnlyHappyPath() public {
    arb.startFlashLoan(1000e18, params);  // Normal case only
}

// GOOD: Test boundaries and edge cases
function test_Good_EdgeCases_ZeroAmount() public {
    vm.expectRevert("amount-zero");
    arb.startFlashLoan(0, params);
}

function test_Good_EdgeCases_MaxAmount() public {
    uint256 maxAmount = type(uint128).max;
    // Test maximum boundary
}
```

#### ❌ Anti-Pattern 5: Test Interdependence
```solidity
// BAD: Tests depend on execution order
uint256 public sharedState;  // Mutable shared state

function test_Bad_First() public {
    sharedState = 100;  // Modifies global state
}

function test_Bad_Second() public {
    assertEq(sharedState, 100);  // Depends on test_Bad_First
}

// GOOD: Isolated tests with fresh state
function test_Good_Isolated() public {
    uint256 localState = 100;  // Local state only
    assertEq(localState, 100);
}
```

---

### 5.7 Testing Quick Reference Card

**Before Every Commit:**
```bash
forge fmt                  # Format code
forge build                # Verify compilation
forge test                 # Run all tests
forge coverage             # Verify ≥95% coverage
slither .                  # Run static analysis
```

**Before Every PR:**
```bash
forge test --gas-report    # Check gas usage
forge snapshot --diff      # Compare gas changes
forge coverage --report lcov  # Generate coverage report
forge test --match-test testFuzz_ --fuzz-runs 10000  # Deep fuzz
```

**Before Mainnet Deploy:**
```bash
forge test --fork-url $MAINNET_RPC_URL  # Fork tests
slither . --checklist > audit-prep.md    # Audit checklist
forge test --invariant-runs 5000         # Deep invariant testing
# + Professional security audit
```

**Test Type Selection Matrix:**

| Scenario | Test Type | Example |
|----------|-----------|---------|
| Verify function works correctly | Unit test | `test_StartFlashLoan_Success` |
| Verify function reverts | Failure test | `testFail_Unauthorized` |
| Test numeric boundaries | Fuzz test | `testFuzz_Amount_Boundaries` |
| Test system properties | Invariant test | `invariant_LoanRepaid` |
| Test against real mainnet | Fork test | `testFork_RealUniswap` |
| Test gas optimization | Gas test | `test_Gas_InfiniteApprovals` |

**This comprehensive testing framework ensures production-grade quality for DeFi protocols.** 🧪

## 6. Git Workflow & PR Instructions

*   **Pre-Commit Checks:** 
    **MANDATORY before every commit:**
```bash
    forge fmt                 # Format all Solidity files
    forge build               # Ensure compilation succeeds
    forge test                # Verify all tests pass
    slither . --exclude-dependencies  # Run static analysis
```

*   **Branching Strategy:**
    *   **NEVER** commit directly to `main` branch
    *   Create feature branches: `feature/<descriptive-name>` or `fix/<issue-description>`
    *   Keep branches short-lived (merge within 3-5 days)
    *   One feature per branch; avoid mixing unrelated changes

*   **Commit Messages:**
    Follow **Conventional Commits** specification:
```
    <type>(<scope>): <subject>
    
    <body>
    
    <footer>
```
    
    **Types:**
    *   `feat`: New feature (e.g., `feat(adapter): add Uniswap V3 adapter support`)
    *   `fix`: Bug fix (e.g., `fix(validation): correct deadline boundary check`)
    *   `test`: Test additions/modifications (e.g., `test(invariant): add flash loan repayment invariant`)
    *   `docs`: Documentation updates (e.g., `docs(security): update 2025 toolchain extensions`)
    *   `refactor`: Code restructuring without behavior changes
    *   `perf`: Performance improvements
    *   `chore`: Build process or tooling changes
    
    **Scope:** Contract or module name (`adapter`, `validation`, `flash-loan`, `security`)
    
    **Subject:** Imperative mood, lowercase, no period, max 72 characters
    
    **Body:** Explain WHAT changed and WHY (not HOW - code shows that). Include:
    *   Motivation for the change
    *   Security implications if any
    *   Breaking changes with migration notes
    
    **Footer:** Reference issues (`Closes #123`) or note breaking changes (`BREAKING CHANGE: ...`)

*   **Pull Request (PR) Process:**
    1. **Push feature branch to remote**
    2. **Open PR with descriptive title** (follow commit message format)
    3. **PR Description MUST include:**
```markdown
       ## Description
       [Clear explanation of changes]
       
       ## Motivation
       [Why this change is necessary]
       
       ## Testing Done
       - [ ] Unit tests added/updated
       - [ ] Fuzz tests added/updated
       - [ ] Invariant tests verified
       - [ ] Manual testing performed
       - [ ] Gas profiling reviewed
       
       ## Security Considerations
       [Any security implications or audit notes]
       
       ## Breaking Changes
       [List any breaking changes and migration steps, or write "None"]
```
    4. **Ensure all CI checks pass** (build, test, format, security analysis)
    5. **Request review** from code owners
    6. **Address review feedback** promptly
    7. **Squash commits before merge** (maintain clean history)

*   **Force Pushes:**
    *   **NEVER** use `git push --force` on `main` branch
    *   Use `git push --force-with-lease` on feature branches if needed (after rebasing or amending)
    *   Communicate force pushes to team members working on same branch

*   **Clean State:**
    **You MUST leave your worktree in a clean state after completing a task:**
```bash
    git status  # Should show "nothing to commit, working tree clean"
```
    *   No untracked files (except intentional additions)
    *   No uncommitted changes
    *   No stash entries unless explicitly documented

## 7. Security Considerations

**THIS IS A HIGH-RISK DEFI PROTOCOL. SECURITY IS PARAMOUNT.**

**Real-World Context**: In 2024, smart contract vulnerabilities caused $1.09B in losses: Access control violations ($953.2M), logic errors ($63.8M), reentrancy ($35.7M), and flash loans ($33.8M). This project implements multiple defense layers to prevent these attack vectors.

### 7.1 OWASP Smart Contract Top 10 (2025) - Project Compliance Matrix

This contract addresses all OWASP Smart Contract Top 10 vulnerabilities through the following mechanisms:

#### **SC01:2025 - Access Control Vulnerabilities** ✅ **MITIGATED**

**Risk**: Unauthorized minting, asset transfers, or critical function execution.

**Project Defenses**:
*   ✅ OpenZeppelin's `Ownable` pattern restricts privileged functions to contract owner
*   ✅ `trustedInitiators` mapping prevents unauthorized flash loan execution
*   ✅ `onlyOwner` modifier on all configuration functions (setRouterWhitelist, setTokenWhitelist, setDexAdapter, approveAdapter)
*   ✅ `executeOperation` validates that `opInitiator == owner()` before executing arbitrage
*   ✅ Two-step adapter approval (address + bytecode hash) prevents privilege escalation

**AI Agent Requirements**:
*   **NEVER** bypass access control modifiers
*   **ALWAYS** use `onlyOwner` for privileged operations
*   **VERIFY** caller identity in callback functions (e.g., `executeOperation`)
*   **TEST** unauthorized access attempts with `vm.expectRevert()` in Foundry tests

#### **SC02:2025 - Price Oracle Manipulation** ✅ **MITIGATED**

**Risk**: Attackers tamper with external data feeds to manipulate token prices.

**Project Defenses**:
*   ✅ On-chain slippage protection via `maxSlippageBps` (default 2%, max 10%)
*   ✅ Post-swap balance validation (`require(balanceAfterFirstSwap >= out1)`)
*   ✅ Minimum acceptable output calculation: `minAcceptableOutput = (_amount * (10000 - maxSlippageBps)) / 10000`
*   ✅ DEX router whitelisting prevents interaction with manipulated/malicious AMMs
*   ✅ Path validation ensures arbitrage loops are closed (same token in/out)

**AI Agent Requirements**:
*   **ALWAYS** validate slippage tolerance is reasonable (<10%)
*   **NEVER** remove balance validation checks
*   **TEST** slippage edge cases (0%, 2%, 9.99%, 10%, 10.01%) in unit tests
*   **CONSIDER** adding Chainlink oracle sanity checks for high-value trades (future enhancement)

#### **SC03:2025 - Logic Errors** ✅ **MITIGATED**

**Risk**: Business logic deviations causing incorrect token distribution or fund loss.

**Project Defenses**:
*   ✅ Comprehensive invariant test suite (`FlashArbInvariantTest.t.sol`)
*   ✅ Strict path validation: `path1[0] == _reserve`, `path2[path2.length - 1] == _reserve`
*   ✅ Profit calculation verification: `profit = finalBalance - totalDebt`
*   ✅ Flash loan repayment validation: `require(finalBalance >= totalDebt)`
*   ✅ Intermediate token validation: `require(path2[0] == intermediate)`

**AI Agent Requirements**:
*   **ALWAYS** maintain invariants in code changes (see `invariant_` tests)
*   **VERIFY** arithmetic logic with Echidna fuzzing before committing
*   **TEST** profit calculation edge cases (zero profit, minimal profit, high profit)
*   **DOCUMENT** all business logic assumptions in NatSpec comments

#### **SC04:2025 - Lack of Input Validation** ✅ **MITIGATED**

**Risk**: Malicious payloads bypass intended limits; incorrect function execution.

**Project Defenses**:
*   ✅ Router whitelist validation: `require(routerWhitelist[router1])`
*   ✅ Token whitelist validation: `require(tokenWhitelist[path1[i]])`
*   ✅ Deadline boundary checks: `require(deadline >= block.timestamp && deadline <= block.timestamp + MAX_DEADLINE)`
*   ✅ Array length validation: `require(path1.length >= 2 && path2.length >= 2)`
*   ✅ Zero-address checks: `require(_provider != address(0))`
*   ✅ Adapter validation: `require(adapter.code.length > 0, "adapter-not-contract")`

**AI Agent Requirements**:
*   **ALWAYS** add `require()` statements for all public/external function parameters
*   **NEVER** trust user-provided addresses, amounts, or array lengths
*   **VALIDATE** boundaries: non-zero values, reasonable ranges, array length limits
*   **TEST** invalid inputs with `vm.expectRevert()` assertions

#### **SC05:2025 - Reentrancy Attacks** ✅ **MITIGATED**

**Risk**: Exploiting withdrawal functions through recursive calls to drain funds.

**Project Defenses**:
*   ✅ OpenZeppelin's `ReentrancyGuard` on all owner functions
*   ✅ `nonReentrant` modifier on: setRouterWhitelist, setTrustedInitiator, setDexAdapter, approveAdapter, approveAdapterCodeHash
*   ✅ Check-Effects-Interactions pattern: state updates before external calls
*   ✅ Profit accounting updated before withdrawal in `withdraw()` function
*   ✅ Adapter validation runtime checks prevent malicious reentrancy via adapters

**AI Agent Requirements**:
*   **ALWAYS** follow Check-Effects-Interactions pattern: 1) Validate, 2) Update state, 3) External call
*   **NEVER** remove `nonReentrant` modifiers from existing functions
*   **ADD** `nonReentrant` to any new function making external calls
*   **TEST** reentrancy attacks using mock contracts that attempt recursive calls

#### **SC06:2025 & SC10:2023 - Unchecked External Calls** ✅ **MITIGATED**

**Risk**: Failures in verifying external call results cause unintended consequences.

**Project Defenses**:
*   ✅ Balance validation after every swap: `require(balanceAfterFirstSwap >= out1)`
*   ✅ Total debt repayment check: `require(finalBalance >= totalDebt)`
*   ✅ Allowance verification before approvals: `if (IERC20(_reserve).allowance(...) < totalDebt)`
*   ✅ SafeERC20 library usage for all token interactions (handles non-standard ERC20s)
*   ✅ Adapter execution wrapped with approval validation

**AI Agent Requirements**:
*   **ALWAYS** use SafeERC20's `safeTransfer`, `safeTransferFrom`, `safeApprove`
*   **NEVER** assume external calls succeed without validation
*   **CHECK** return values or use try-catch blocks for critical external calls
*   **TEST** failed external calls with mock contracts that return false/revert

#### **SC07:2025 - Flash Loan Attacks** ✅ **ADDRESSED** (This IS a Flash Loan Contract)

**Risk**: Manipulating liquidity via rapid multi-action transactions within single blocks.

**Project Defenses**:
*   ✅ This contract legitimately uses flash loans for arbitrage (not a vulnerability)
*   ✅ MEV protection via 30-second deadline constraint prevents stale execution
*   ✅ Slippage protection prevents sandwich attacks
*   ✅ Trusted initiator validation prevents unauthorized flash loan triggers
*   ✅ On-chain profitability validation: `require(profit >= minProfit)`
*   ✅ Whitelist-only execution (routers, tokens, adapters) limits attack surface

**AI Agent Requirements**:
*   **UNDERSTAND** this contract intentionally executes flash loans (not a bug)
*   **MAINTAIN** deadline enforcement (NEVER extend MAX_DEADLINE beyond 30 seconds)
*   **PRESERVE** slippage limits and profitability checks
*   **TEST** unprofitable scenarios (contract should revert, not lose funds)

#### **SC08:2025 - Integer Overflow and Underflow** ✅ **MITIGATED**

**Risk**: Fixed-size integer arithmetic errors causing severe vulnerabilities.

**Project Defenses**:
*   ✅ Solidity 0.8.21+ with automatic overflow/underflow checks (no SafeMath needed)
*   ✅ Explicit range validation where needed: `require(bps <= 1000, "max 10% allowed")`
*   ✅ Fuzz testing of numeric parameters via Foundry/Echidna
*   ✅ Safe arithmetic operations: `profit = finalBalance - totalDebt` (checked by compiler)

**AI Agent Requirements**:
*   **NEVER** use `unchecked` blocks unless gas-critical and security-reviewed
*   **ALWAYS** use Solidity 0.8.0+ for automatic overflow protection
*   **VALIDATE** numeric inputs have reasonable bounds
*   **TEST** boundary conditions: uint256 max, zero values, near-overflow scenarios

#### **SC09:2025 - Insecure Randomness** ✅ **NOT APPLICABLE**

**Risk**: Predictable RNG in sensitive functions exploitable by attackers.

**Project Status**: This contract does NOT use randomness. No RNG vulnerabilities.

**AI Agent Requirements**:
*   **IF** adding any random selection (e.g., random DEX routing), use Chainlink VRF
*   **NEVER** use `block.timestamp`, `block.number`, or `blockhash` for randomness
*   **CONSULT** security team before implementing any stochastic features

---

### 7.2 OWASP Smart Contract Security Verification Standard (SCSVS) Checklist

**Pre-Deployment Security Audit Checklist** (per OWASP SCSVS v0.0.1):

#### **Architecture & Design**

- [x] Contract follows upgradeable proxy pattern (UUPS) with proper initialization
- [x] Separation of concerns: configuration, execution, accounting in distinct functions
- [x] Minimal external dependencies (only battle-tested OpenZeppelin + Aave)
- [x] No circular dependencies or complex inheritance chains
- [x] Clear ownership model (single owner, no multi-sig complexity)

#### **Access Control & Authorization**

- [x] All privileged functions gated by `onlyOwner` modifier
- [x] Callback functions validate caller identity (`initiator == address(this)`, `opInitiator == owner()`)
- [x] Trusted initiator mapping prevents unauthorized flash loan execution
- [x] Principle of least privilege: only owner can modify critical state
- [x] No admin functions can be renounced accidentally (owner transfer is explicit)

#### **Reentrancy Protection**

- [x] `ReentrancyGuard` applied to all owner functions with external calls
- [x] Check-Effects-Interactions pattern followed throughout
- [x] State updates committed before external calls (profit accounting, allowances)
- [x] Fallback function (`receive()`) properly secured (only accepts ETH, no logic)
- [x] No cross-function reentrancy vulnerabilities (each function is atomic)

#### **Arithmetic Safety**

- [x] Solidity 0.8.21+ for built-in overflow/underflow protection
- [x] No division by zero risks (all divisors validated or constant)
- [x] Rounding errors considered in slippage calculations
- [x] Numeric parameters have reasonable bounds (bps ≤ 1000, deadline ≤ 30s)

#### **Input Validation**

- [x] All public/external function parameters validated with `require()`
- [x] Type checking at contract boundaries (address non-zero, array length ≥ 2)
- [x] Whitelist validation before processing (routers, tokens, adapters)
- [x] Path integrity checks (start/end tokens match reserve/intermediate)
- [x] Deadline validation prevents execution of stale transactions

#### **External Dependencies & Integrations**

- [x] DEX interactions via whitelisted routers only (Uniswap V2, Sushiswap)
- [x] Aave V2 flash loan integration validated (mainnet addresses hardcoded)
- [x] Token whitelist prevents interaction with malicious ERC20s
- [x] SafeERC20 handles non-standard token implementations
- [x] No reliance on external oracles (on-chain price discovery via DEX swaps)

#### **Gas Optimization & DoS Prevention**

- [x] No unbounded loops (all iterations have fixed maximum size)
- [x] Gas limits respected (no operations near block gas limit)
- [x] Infinite approvals for trusted routers (eliminates approval transactions)
- [x] No storage reads in loops (minimal SLOAD operations)
- [x] Event emission for off-chain monitoring (not gas-critical paths)

#### **Blockchain Data Integrity**

- [x] Timestamp dependency limited to deadline validation (not used for randomness)
- [x] Block number not used for security-critical logic
- [x] No reliance on `tx.origin` for authentication
- [x] `msg.sender` validated in all access-controlled functions

#### **Economic Attack Resistance**

- [x] Slippage protection prevents sandwich attacks
- [x] Deadline constraints prevent MEV exploitation of stale transactions
- [x] Profitability validation prevents forced unprofitable execution
- [x] Whitelist-based execution limits composability attack surface
- [x] Balance validation after every swap prevents price manipulation impact

---

### 7.3 Industry-Standard Security Tooling

**PRIMARY TOOLS (ALWAYS RUN BEFORE EVERY PR):**
```bash
# Slither - Comprehensive static analysis (93+ detectors)
slither . --exclude-dependencies --detect all
slither . --checklist > security-checklist.md  # Generate audit checklist

# Echidna - Property-based fuzzing (10,000+ runs)
echidna-test . --contract FlashArbEchidnaTest --config echidna.yaml
```

**SECONDARY TOOLS (RUN WEEKLY OR FOR HIGH-RISK CHANGES):**
```bash
# Mythril - Deep security analysis via symbolic execution
myth analyze src/FlashArbMainnetReady.sol --solv 0.8.21

# Manticore - Symbolic execution for complex path exploration
manticore src/FlashArbMainnetReady.sol --contract FlashArbMainnetReady

# Semgrep - Pattern-based vulnerability detection with custom rules
semgrep --config p/smart-contracts src/

# Oyente - EVM bytecode analysis
oyente -s src/FlashArbMainnetReady.sol
```

**OPTIONAL TOOLS (BASED ON RISK PROFILE - High-Value Deployments):**
```bash
# Aderyn - Rust-based fast static analysis
aderyn analyze src/ --output security-report.json --format json

# Halmos - Formal verification for critical functions
halmos --contract FlashArbMainnetReady --function executeOperation --solver z3

# Recon - Invariant testing as a service (cloud-based)
recon test --contract src/FlashArbMainnetReady.sol --invariants test/ --parallel 8
```

**Tool Integration Matrix:**

| Tool | Purpose | When to Use | CI/CD Integration |
|------|---------|-------------|-------------------|
| **Slither** | Dataflow analysis, code optimization | Every PR (mandatory) | Pre-commit hook + GitHub Actions |
| **Echidna** | Property-based fuzzing | Every PR (mandatory) | Weekly scheduled run |
| **Mythril** | Symbolic execution, bytecode inspection | High-risk changes | Manual before audit |
| **Manticore** | Complex path exploration | Multi-signature, complex logic | Manual before mainnet deploy |
| **Semgrep** | Custom security pattern detection | Weekly security scan | GitHub Actions weekly |
| **Aderyn** | Fast static analysis (Rust) | Large codebase changes | Optional CI job |
| **Halmos** | Formal verification | Critical function changes | Manual for auditor review |
| **Recon** | Cloud invariant testing | Pre-mainnet deployment | Scheduled after major releases |

---

### 7.4 Pre-Deployment Security Workflow

**MANDATORY CHECKLIST BEFORE MAINNET DEPLOYMENT:**

1. **✅ Unit Test Coverage ≥ 95%**
```bash
   forge coverage
   # Verify coverage report shows ≥95% line coverage for src/FlashArbMainnetReady.sol
```

2. **✅ All Static Analysis Tools Pass**
```bash
   slither . --exclude-dependencies  # Must show 0 critical/high issues
   semgrep --config p/smart-contracts src/  # Must pass all security rules
```

3. **✅ Fuzz Testing Completes 10,000+ Runs**
```bash
   forge test --fuzz-runs 10000  # All fuzz tests must pass
   echidna-test . --contract FlashArbEchidnaTest  # All properties must hold
```

4. **✅ Invariant Tests Validate System Properties**
```bash
   forge test --match-contract Invariant  # All invariants must pass
   # Verify: Flash loan repayment, profit accuracy, path validity
```

5. **✅ Manual Code Review Against OWASP Top 10**
   - [ ] SC01: Access control reviewed (2 reviewers)
   - [ ] SC02: Oracle manipulation risks assessed
   - [ ] SC03: Logic errors validated via invariant tests
   - [ ] SC04: Input validation comprehensive
   - [ ] SC05: Reentrancy protections verified
   - [ ] SC06/SC10: External calls checked
   - [ ] SC07: Flash loan security reviewed
   - [ ] SC08: Arithmetic safety confirmed
   - [ ] SC09: No randomness used (N/A)

6. **✅ Gas Profiling Analyzed**
```bash
   forge test --gas-report
   # Verify no functions exceed 5M gas (stay well under block gas limit)
```

7. **✅ Upgrade Safety Validated**
```bash
   # Verify storage layout compatibility with existing proxy
   forge inspect FlashArbMainnetReady storage --pretty
```

8. **✅ Professional Security Audit (External)**
   - [ ] Audit by reputable firm (OpenZeppelin, Trail of Bits, Consensys Diligence)
   - [ ] All critical/high findings resolved
   - [ ] Medium findings mitigated or accepted with documentation
   - [ ] Audit report published before mainnet launch

9. **✅ Testnet Deployment & Validation**
```bash
   # Deploy to Sepolia testnet
   forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
   # Execute real arbitrage scenarios on testnet for 48 hours minimum
```

10. **✅ Mainnet Deployment Checklist**
    - [ ] Multi-sig ownership transfer plan documented
    - [ ] Emergency pause mechanism tested
    - [ ] Upgrade timelock configured (if applicable)
    - [ ] Monitoring alerts configured (large withdrawals, failed transactions)
    - [ ] Bug bounty program launched (e.g., Immunefi, Code4rena)

---

### 7.5 Key Distinctions from Traditional OWASP

**Critical differences for AI agents working on smart contracts vs. web applications:**

#### **Immutable Code - No Patches After Deployment**
*   **Web Apps**: Deploy hotfix in minutes
*   **Smart Contracts**: Upgradeability via proxy is complex; prevention is the ONLY defense
*   **AI Impact**: **EVERY code change must be perfect**. No room for "we'll fix it later."

#### **Economic Attacks Unique to DeFi**
*   **Not in Web OWASP**: Flash loans, oracle manipulation, MEV extraction, liquidity attacks
*   **Smart Contract Reality**: Attackers profit directly from exploits (financial incentive)
*   **AI Impact**: **Must understand economic incentives**, not just technical vulnerabilities

#### **Composability Risk - Protocol Interdependencies**
*   **Web Apps**: Isolated systems with defined API boundaries
*   **Smart Contracts**: Permissionless interaction; one protocol's bug cascades across ecosystem
*   **AI Impact**: **Consider downstream effects** of any state change on other protocols

#### **Formal Verification Matters More**
*   **Web Apps**: Unit tests sufficient for most logic
*   **Smart Contracts**: Mathematical proofs of correctness critical for high-value protocols
*   **AI Impact**: **Invest in formal methods** (Halmos, Certora) for critical functions

#### **Financial Stakes - Higher Bar for Security**
*   **Web Apps**: Data breach → reputation damage
*   **Smart Contracts**: Vulnerability → $100M+ loss in hours (see 2024 loss data)
*   **AI Impact**: **Security is existential**, not just "important"

---

### 7.6 Sensitive Data Handling

*   **NEVER** commit private keys, mnemonics, or API keys to version control
*   Use environment variables (`.env`) for all sensitive configuration
*   **NEVER** log sensitive data (keys, balances, addresses) in production
*   Store mainnet RPC URLs and API keys in secure password managers
*   **NEVER** include `.env` files in Git (verify `.gitignore` includes `.env`)
*   Use hardware wallets (Ledger, Trezor) for mainnet deployments

---

### 7.7 Smart Contract Security Resources

**Official Frameworks:**
*   [OWASP Smart Contract Top 10](https://owasp.org/www-project-smart-contract-top-10/) - Primary vulnerability classification
*   [OWASP SCSVS](https://owasp.org/www-project-smart-contract-security-verification-standard/) - Comprehensive security standard

**Community Resources:**
*   [Solidity Security Audit Checklist (GitHub)](https://github.com/iAnonymous3000/solidity-security-audit-checklist) - Community-maintained checklist
*   [OpenZeppelin Audit Readiness Guide](https://learn.openzeppelin.com/security-audits/readiness-guide) - Pre-audit preparation

**Continuous Learning:**
*   [Ethernaut](https://ethernaut.openzeppelin.com/) - Smart contract security wargames
*   [Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/) - DeFi security challenges
*   [Secureum](https://secureum.substack.com/) - Smart contract security newsletter

---

**CRITICAL REMINDER FOR AI AGENTS:**

This is a **$1B+ risk category protocol** (flash loan arbitrage). The 2024 loss data shows:
*   **$953.2M** lost to access control violations
*   **$35.7M** lost to reentrancy attacks  
*   **$33.8M** lost to flash loan exploits

**EVERY line of code you write must assume an attacker with:**
*   Unlimited computing resources
*   Perfect knowledge of your contract's source code
*   Strong financial incentive to exploit vulnerabilities
*   Ability to execute attacks in single atomic transactions

**When in doubt about security, STOP and request human review.**

### 8.1 Security-Focused Development Checklist for AI Agents

**Before writing ANY code that modifies security-critical functions:**

1. **Read the OWASP Smart Contract Top 10 section above** ✅
2. **Identify which vulnerability categories your change affects** ✅
3. **Review existing mitigations for those categories** ✅
4. **Write security-focused tests FIRST** (test-driven development for security)
5. **Implement the feature with mitigations in place**
6. **Run ALL security tools** (Slither, Echidna, Mythril)
7. **Document security assumptions** in NatSpec comments
8. **Request human security review** before marking task complete

**Security-Critical Functions (EXTRA CAUTION REQUIRED):**

*   `executeOperation()` - Core flash loan callback (reentrancy, validation, arithmetic)
*   `setDexAdapter()` - Adapter configuration (bytecode hash validation)
*   `approveAdapter()` / `approveAdapterCodeHash()` - Adapter security (two-step approval)
*   `withdraw()` - Fund withdrawal (reentrancy, access control)
*   `setRouterWhitelist()` - Router management (access control, reentrancy)
*   `_authorizeUpgrade()` - Upgrade authorization (access control)

**Security Test Template:**
```solidity
// Test: Negative case - unauthorized access
function testFail_UnauthorizedAccess() public {
    vm.prank(attacker);  // Simulate malicious actor
    arb.criticalFunction();  // Should revert
}

// Test: Negative case - reentrancy attack
function testFail_ReentrancyAttack() public {
    MaliciousContract attacker = new MaliciousContract(address(arb));
    vm.expectRevert("ReentrancyGuard: reentrant call");
    attacker.attack();
}

// Test: Edge case - boundary validation
function testFuzz_BoundaryValidation(uint256 amount) public {
    vm.assume(amount > 0 && amount < type(uint128).max);
    // Test logic...
}
```

4. **NEVER SKIP SECURITY**: Even for "minor" changes, consider security implications and test edge cases.
5. **DOCUMENT ASSUMPTIONS**: If you make any assumptions about contract behavior or external dependencies, document them clearly in code comments.

**This AGENTS.md is a living document. Update it as the project evolves.**
