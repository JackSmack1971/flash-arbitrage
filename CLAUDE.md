# AGENTS.md: AI Collaboration Guide

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

*   **Local Development Setup:**
    1. **Install Foundry:**
```bash
       curl -L https://foundry.paradigm.xyz | bash
       foundryup
```
    2. **Clone and install dependencies:**
```bash
       git clone <repository>
       cd flash-arbitrage
       forge install  # Installs dependencies from foundry.toml remappings
```
    3. **Verify installation:**
```bash
       forge --version
       forge build  # Should compile without errors
```
    4. **Environment Configuration:**
```bash
       cp .env.example .env
       # Configure: MAINNET_RPC_URL, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY, PRIVATE_KEY
```

*   **Build Commands:**
```bash
    forge build                    # Compile all contracts
    forge build --force            # Force recompilation
    forge build --sizes            # Show contract sizes (max 24KB for mainnet)
```

*   **Testing Commands:** 
    **CRITICAL: All new features REQUIRE comprehensive test coverage across multiple testing methodologies.**
```bash
    # Unit Tests (Foundry)
    forge test                           # Run all tests
    forge test --match-test testProfit   # Run specific test
    forge test -vvv                      # Verbose output with stack traces
    forge test --gas-report              # Generate gas usage report
    
    # Invariant Tests (Foundry)
    forge test --match-contract Invariant    # Run invariant test suite
    
    # Fuzz Tests (Foundry built-in)
    # Configured in foundry.toml: 10,000 runs per fuzz test
    forge test --match-test testFuzz_
    
    # Echidna Property Tests (requires Echidna installation)
    echidna-test . --contract FlashArbEchidnaTest --config echidna.yaml
    
    # Coverage Analysis
    forge coverage                       # Generate coverage report
    forge coverage --report lcov         # Export LCOV format for tooling
```
    
    **Test Requirements:**
    *   **Unit tests**: Every public/external function must have positive and negative test cases
    *   **Fuzz tests**: Critical numeric inputs (amounts, slippage, deadlines) require fuzz coverage
    *   **Invariant tests**: System invariants (flash loan repayment, profit accuracy, path validity) must be continuously validated
    *   **Mock all external dependencies**: Use MockRouter, MockLendingPool, MockToken to avoid mainnet dependencies
    *   **Test file naming**: `<ContractName>Test.t.sol` for unit tests, `<ContractName>InvariantTest.t.sol` for invariants

*   **Formatting Commands:**
```bash
    forge fmt                            # Format all Solidity files
    forge fmt --check                    # Verify formatting without changes
```

*   **Security Analysis Commands:** 
    **PRIMARY TOOLS (ALWAYS RUN):**
```bash
    # Slither Static Analysis (93+ built-in detectors)
    slither . --exclude-dependencies
    slither . --checklist                 # Generate audit checklist
    
    # Echidna Fuzzing (10,000+ runs per property)
    echidna-test . --contract FlashArbEchidnaTest
```
    
    **OPTIONAL GATES (based on risk profile):**
```bash
    # Aderyn Fast Static Analysis (Rust-based alternative to Slither)
    aderyn analyze src/ --output security-report.json
    
    # Halmos Formal Verification (for critical functions)
    halmos --contract FlashArbMainnetReady --function executeOperation
    
    # Recon Invariant Testing as a Service (for high-risk deployments)
    recon test --contract src/FlashArbMainnetReady.sol --invariants test/ --parallel 8
```
    
    **See `docs/security/2025-toolchain-extensions.md` for comprehensive security tooling guidance.**

*   **Deployment Workflow:**
```bash
    # Dry-run deployment (simulation)
    forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL
    
    # Actual deployment (requires private key)
    forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY --broadcast
    
    # Verify on Etherscan
    forge verify-contract <CONTRACT_ADDRESS> FlashArbMainnetReady --chain mainnet
```

*   **CI/CD Process Overview:**
    *   **Trigger**: Every push to feature branches and pull requests to `main`
    *   **Pipeline Steps**:
        1. **Build**: `forge build` (compile all contracts)
        2. **Test**: `forge test` (run entire test suite with gas reporting)
        3. **Format Check**: `forge fmt --check` (enforce consistent formatting)
        4. **Static Analysis**: `slither .` (detect vulnerabilities)
        5. **Coverage**: `forge coverage` (ensure adequate test coverage)
        6. **Security Gates**: Optional Echidna/Aderyn/Halmos runs based on risk profile
    *   **Merge Requirements**: All checks must pass (green status) before PR can merge to `main`
    *   **Deployment**: Manual deployment from `main` branch via `forge script` after security review

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
