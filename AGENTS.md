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

*   **General Security Practices:**
    *   **Assume all external contracts are malicious** until proven otherwise
    *   **Validate all inputs** from untrusted sources (user parameters, external calls)
    *   **Follow Check-Effects-Interactions pattern** religiously
    *   **Use reentrancy guards** on all functions with external calls
    *   **Never hardcode secrets** (private keys, API keys, sensitive addresses)
    *   **Principle of least privilege**: Minimize permissions and access control

*   **Sensitive Data Handling:**
    *   **NEVER** commit private keys or mnemonics to version control
    *   Use environment variables (`.env`) for all sensitive configuration
    *   **NEVER** log sensitive data (keys, balances, addresses) in production
    *   Store mainnet RPC URLs and API keys in secure password managers

*   **Smart Contract Security (Critical):**
    *   **Flash Loan Repayment**: ALWAYS verify sufficient balance before flash loan return (`require(finalBalance >= totalDebt)`)
    *   **Slippage Protection**: Enforce on-chain slippage limits via `maxSlippageBps` (never trust frontend-only validation)
    *   **Deadline Enforcement**: REJECT transactions older than `MAX_DEADLINE` (30 seconds) to prevent MEV exploitation
    *   **Adapter Validation**: Two-step validation (address + bytecode hash) prevents malicious adapter substitution
    *   **Whitelist Management**: Only owner can modify whitelists; validate all whitelist changes in tests
    *   **Reentrancy**: All owner functions (setRouterWhitelist, setTrustedInitiator, setDexAdapter) use `nonReentrant`
    *   **Integer Overflow**: Solidity 0.8.x provides automatic overflow checks; DO NOT use unchecked blocks unless gas-critical and security-reviewed
    *   **Access Control**: Only owner and trusted initiators can trigger flash loans; validate initiator in executeOperation
    *   **External Call Ordering**: Balance checks BEFORE and AFTER external swaps; validate intermediate token balances
    *   **Gas Griefing**: Use `gasleft()` validation for long-running operations if needed

*   **Vulnerability Avoidance (Top CWEs for Smart Contracts):**
    *   **CWE-284 (Improper Access Control)**: Use OpenZeppelin's Ownable; validate msg.sender in executeOperation
    *   **CWE-362 (Race Conditions/Reentrancy)**: Use ReentrancyGuard; follow Check-Effects-Interactions
    *   **CWE-682 (Incorrect Calculation)**: Test arithmetic operations with fuzz testing; use SafeMath patterns where appropriate
    *   **CWE-703 (Improper Check of Exceptional Conditions)**: Always validate external call returns; use try-catch for risky operations
    *   **CWE-829 (Inclusion of Untrusted Functionality)**: Validate adapter bytecode hashes; whitelist all external contracts

*   **Auditing & Review:**
    *   **Before mainnet deployment**: External smart contract audit from reputable firm (Trail of Bits, OpenZeppelin, Consensys Diligence)
    *   **After significant changes**: Internal security review + re-audit of modified components
    *   **Continuous monitoring**: Set up alerts for unusual contract activity (large withdrawals, failed transactions)

*   **Testing for Security:**
    *   **Invariant tests**: Validate that flash loans are ALWAYS repaid, profits are ALWAYS non-negative, paths are ALWAYS valid
    *   **Fuzz testing**: Use Echidna/Foundry fuzzing to discover edge cases in numeric inputs (amounts, slippage, deadlines)
    *   **Formal verification**: Use Halmos for critical functions (executeOperation, slippage validation, access control)
    *   **Fork testing**: Test against real mainnet state using `forge --fork-url $MAINNET_RPC_URL`

## 8. Specific Agent Instructions & Known Issues

*   **Tool Usage:**
    *   **Foundry Commands**: Use `forge` for all compilation, testing, and deployment (`forge build`, `forge test`, `forge script`)
    *   **Formatting**: ALWAYS run `forge fmt` before committing; use `forge fmt --check` in CI
    *   **Gas Profiling**: Use `forge test --gas-report` to optimize gas-intensive operations
    *   **Debugging**: Use `forge test -vvvv` for maximum verbosity with stack traces and internal calls
    *   **Forking**: Test against mainnet state using `forge test --fork-url $MAINNET_RPC_URL --fork-block-number <BLOCK>`

*   **Context Management:**
    *   **Large code changes**: Break into multiple PRs (e.g., PR1: Add adapter interface, PR2: Implement adapter, PR3: Integrate adapter)
    *   **Security-critical changes**: Create dedicated PRs with "SECURITY" prefix and request thorough review
    *   **Test organization**: Keep test files parallel to source files; use descriptive test names

*   **Quality Assurance & Verification:**
    **After making ANY code changes, you MUST:**
    1. Run `forge build` and verify NO compilation errors
    2. Run `forge test` and verify ALL tests pass (100% success rate)
    3. Run `forge test --gas-report` and verify gas usage is reasonable (no unexpected spikes)
    4. Run `slither .` and verify NO new critical/high severity issues
    5. Run `forge fmt --check` and verify formatting compliance
    6. **If ANY check fails**, debug and fix before considering the task complete
    
    **DO NOT claim task completion unless ALL programmatic checks pass.**

*   **Project-Specific Quirks/Antipatterns:**
    *   **Infinite Approvals**: The contract uses infinite approvals for trusted routers to save gas; this is INTENTIONAL and security-reviewed
    *   **String Errors**: The contract uses string-based errors (not custom error codes) for readability; this is a deliberate design choice
    *   **WETH Handling**: The contract supports unwrapping WETH profits to ETH; ensure `receive()` function can accept ETH
    *   **Deadline Constraints**: MAX_DEADLINE is 30 seconds; DO NOT increase without security review of MEV implications
    *   **Adapter Pattern**: When adding new DEX support, create a new IDexAdapter implementation; NEVER modify the main contract for DEX-specific logic
    *   **Mock Contracts**: Test mocks (MockRouter, MockToken) use simplified logic; DO NOT use for gas benchmarking or security analysis

*   **Troubleshooting & Debugging:**
    *   **Compilation Errors**: Check Solidity version (`pragma solidity ^0.8.21`), verify imports are correct, ensure dependencies are installed
    *   **Test Failures**: 
        *   Read error messages carefully (Foundry provides detailed traces)
        *   Use `forge test -vvvv --match-test <FAILING_TEST>` for maximum verbosity
        *   Check for incorrect assumptions (e.g., wrong exchange rates in mocks)
        *   Verify test setup (initial balances, approvals, whitelisting)
    *   **Gas Issues**: Use `forge test --gas-report` to identify gas-intensive operations; consider infinite approvals or storage optimizations
    *   **Slither False Positives**: Review Slither output; some detectors may flag intentional patterns (e.g., infinite approvals); document exceptions
    *   **Deployment Failures**: Verify RPC URL is correct, private key has sufficient ETH for gas, contract size is under 24KB limit

*   **Known Limitations & Future Improvements:**
    *   **DEX Support**: Currently supports Uniswap V2 and Sushiswap; Uniswap V3 support via adapters is planned
    *   **Multi-Hop Paths**: Current implementation supports 2-hop arbitrage (A→B→A); multi-hop support (A→B→C→A) requires additional testing
    *   **Gas Optimization**: Further gas optimizations possible (e.g., bitmap whitelisting, assembly optimizations) but require security-performance tradeoffs
    *   **Upgrade Path**: UUPS proxy pattern enables upgrades; ensure upgrade scripts thoroughly test state migration

---

**CRITICAL REMINDERS FOR AI AGENTS:**

1. **SECURITY FIRST**: This is a DeFi protocol handling real value. Every code change must be security-reviewed.
2. **TEST EVERYTHING**: 100% of new code requires comprehensive unit, fuzz, and invariant test coverage.
3. **VALIDATE BEFORE CLAIMING COMPLETION**: Run ALL programmatic checks (build, test, lint, security analysis) and verify they pass.
4. **NEVER SKIP SECURITY**: Even for "minor" changes, consider security implications and test edge cases.
5. **DOCUMENT ASSUMPTIONS**: If you make any assumptions about contract behavior or external dependencies, document them clearly in code comments.

**This AGENTS.md is a living document. Update it as the project evolves.**
