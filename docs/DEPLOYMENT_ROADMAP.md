# Flash Arbitrage Protocol - Deployment Roadmap

**Document Version**: 1.0
**Last Updated**: 2025-11-11
**Status**: ACTIVE
**Source**: SCSA.md Security Audit Recommendations

---

## Executive Summary

This document outlines the phased deployment strategy for the Flash Arbitrage Protocol, with escalating security controls as Total Value Locked (TVL) increases. The roadmap ensures systematic risk management while enabling incremental validation of the protocol's functionality and security posture.

**Overall Risk Assessment**: MEDIUM (per SCSA.md audit)
**Deployment Recommendation**: CONDITIONAL APPROVAL - PHASED DEPLOYMENT REQUIRED

**Key Principles**:
- Security controls escalate with financial exposure
- Each phase has explicit entry/exit criteria
- Multi-signature governance MANDATORY before mainnet >$100K TVL
- Timelock controller MANDATORY before mainnet >$1M TVL
- External audit MANDATORY before Phase 3 progression

---

## Phased Deployment Overview

| Phase | Environment | TVL Limit | Duration | Status | Security Gate |
|-------|-------------|-----------|----------|--------|---------------|
| **Phase 1** | Sepolia Testnet | N/A | 7-14 days | APPROVED | Single owner + hardware wallet |
| **Phase 2** | Mainnet | <$100K | 30+ days | CONDITIONAL | Multi-sig REQUIRED |
| **Phase 3** | Mainnet | <$1M | 60+ days | CONDITIONAL | Multi-sig + Timelock |
| **Phase 4** | Mainnet | Unlimited | Ongoing | BLOCKED | Timelock + External Audit + Insurance |

**Current Phase**: Phase 1 (Sepolia Testnet Deployment)

---

## Phase 1: Sepolia Testnet Deployment

### Overview

**Objective**: Validate core protocol functionality, security controls, and operational procedures in a risk-free testnet environment.

**Status**: APPROVED (per SCSA.md - EEA EthTrust [S] Level Compliant)

**Duration**: Minimum 7-14 days
**TVL Limit**: N/A (testnet ETH has no financial value)
**Risk Level**: MINIMAL (testnet only)

### Prerequisites (MUST COMPLETE BEFORE TESTNET DEPLOYMENT)

#### 1. Code Quality Validation

**Compilation & Testing**:
```bash
# Compile contracts
forge build --sizes

# Verify contract size <24KB (mainnet limit)
# FlashArbMainnetReady should be ~22-23KB

# Run complete test suite
forge test

# Expected: All tests passing
# Coverage: ≥95% line coverage
```

**Coverage Validation**:
```bash
# Generate coverage report
forge coverage

# Verify coverage thresholds:
# - Line coverage: ≥95%
# - Branch coverage: ≥90%
# - Function coverage: 100%
```

#### 2. Security Analysis (ALL MUST PASS)

**Static Analysis**:
```bash
# Slither analysis (ZERO HIGH/CRITICAL findings allowed)
slither . --exclude-dependencies --detect all

# Expected output: 0 critical, 0 high
# Medium/Low findings acceptable with documentation

# Generate audit checklist
slither . --checklist > security-checklist.md
```

**Additional Security Tools**:
```bash
# Semgrep security patterns
semgrep --config p/smart-contracts src/

# Mythril symbolic execution (optional but recommended)
myth analyze src/FlashArbMainnetReady.sol --solv 0.8.21
```

#### 3. Fuzz Testing (10,000+ RUNS MINIMUM)

**Foundry Fuzzing**:
```bash
# Run all fuzz tests with 10,000 runs per test
forge test --fuzz-runs 10000 --match-test testFuzz_

# All fuzz tests MUST pass
# No unexpected reverts or edge case failures
```

**Echidna Property-Based Fuzzing**:
```bash
# Run Echidna tests (if configured)
echidna-test . --contract FlashArbEchidnaTest --config echidna.yaml

# All Echidna properties MUST hold
```

#### 4. Invariant Testing (1,000+ RUNS MINIMUM)

**Invariant Validation**:
```bash
# Run invariant tests
forge test --match-contract FlashArbInvariantTest

# Verify all invariants hold:
# - I-1: Flash loan always repaid
# - I-2: Profit accounting accuracy
# - I-3: Access control enforcement
```

**Critical Invariants** (from SCSA.md):
- Flash loan repayment MUST succeed or transaction reverts
- Recorded profits MUST match actual token balances
- Non-owner addresses CANNOT execute privileged functions

#### 5. Gas Profiling

**Gas Benchmarking**:
```bash
# Generate gas report
forge test --gas-report | tee gas-report.txt

# Verify no function exceeds 5M gas (safety threshold)
# Total arbitrage execution ~650k gas expected

# Generate gas snapshot for future regression testing
forge snapshot
```

**Gas Optimization Validation**:
- Verify infinite approvals working (second execution cheaper than first)
- No storage reads in loops
- Event emissions optimized

### Deployment Steps

#### Step 1: Prepare Deployment Environment

**Environment Configuration**:
```bash
# Copy environment template
cp .env.example .env

# Configure Sepolia testnet variables
# SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
# ETHERSCAN_API_KEY=YOUR_ETHERSCAN_KEY
# PRIVATE_KEY=YOUR_HARDWARE_WALLET_DERIVED_KEY

# NEVER commit .env to version control
grep ".env" .gitignore  # Verify .env is gitignored
```

**Hardware Wallet Setup** (MANDATORY):
```bash
# Use hardware wallet (Ledger, Trezor, GridPlus Lattice1)
# Derive Sepolia testnet account from hardware wallet
# Fund account with Sepolia ETH from faucet

# Recommended: Use Ledger Live or Trezor Suite derivation
# Path: m/44'/60'/0'/0/0 (standard Ethereum derivation)
```

#### Step 2: Deploy to Sepolia Testnet

**Deployment Script Execution**:
```bash
# Dry-run deployment (no broadcast)
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL

# Review deployment parameters:
# - AAVE_PROVIDER: 0x... (Sepolia Aave V2 provider)
# - Initial owner: Hardware wallet address
# - Initialization parameters

# Execute deployment (requires hardware wallet confirmation)
forge script script/Deploy.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY

# Save deployment addresses to docs/deployments/sepolia.json
```

**Post-Deployment Verification**:
```bash
# Verify contract on Etherscan
# Check source code matches compiled artifacts
# Verify proxy implementation address

# Verify initialization
cast call <PROXY_ADDRESS> "owner()(address)" --rpc-url $SEPOLIA_RPC_URL
# Expected: Your hardware wallet address

# Verify UUPS implementation
cast call <PROXY_ADDRESS> "proxiableUUID()(bytes32)" --rpc-url $SEPOLIA_RPC_URL
# Expected: Non-zero bytes32 value (UUPS compliant)
```

#### Step 3: Configure Protocol Parameters

**Initial Configuration**:
```bash
# Connect to deployed contract
cast send <PROXY_ADDRESS> \
    "setMaxSlippage(uint256)" 200 \  # 2% default slippage
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Set maximum path length
cast send <PROXY_ADDRESS> \
    "setMaxPathLength(uint8)" 5 \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Set maximum flash loan amount (testnet appropriate)
cast send <PROXY_ADDRESS> \
    "setMaxFlashLoanAmount(uint256)" 1000000000000000000000 \  # 1000 tokens
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

**Whitelist Sepolia DEX Routers**:
```bash
# Whitelist Uniswap V2 Router (Sepolia)
cast send <PROXY_ADDRESS> \
    "setRouterWhitelist(address,bool)" \
    <UNISWAP_V2_ROUTER_SEPOLIA> true \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Whitelist common test tokens
cast send <PROXY_ADDRESS> \
    "setTokenWhitelist(address,bool)" \
    <WETH_SEPOLIA> true \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

### Testing & Validation (7-14 DAYS MINIMUM)

#### Day 1-3: Functional Testing

**Test Scenarios**:

1. **Profitable Arbitrage Execution**:
   - Identify price discrepancy between Sepolia DEXes
   - Execute flash loan arbitrage via startFlashLoan()
   - Verify profit recorded in profits[token] mapping
   - Verify tokens received in contract balance

2. **Unprofitable Trade Rejection**:
   - Submit arbitrage with negative expected profit
   - Verify transaction reverts with "profit-less-than-min"
   - Verify no funds lost (flash loan fully reverted)

3. **Slippage Protection**:
   - Execute trade with high slippage conditions
   - Verify transaction reverts with "slippage-exceeded"
   - Test slippage limits at 2%, 5%, 9.99%, 10%, 10.01%

4. **Access Control Validation**:
   - Attempt privileged operations from non-owner address
   - Verify all attempts revert with "Ownable: caller is not the owner"
   - Test: setRouterWhitelist, setDexAdapter, approveAdapter

5. **Emergency Procedures**:
   - Test pause/unpause functionality
   - Test emergencyWithdrawERC20() with various tokens
   - Verify all operations blocked when paused

#### Day 4-7: Edge Case Testing

**Complex Scenarios**:

1. **Multi-Hop Path Testing**:
   - Test 2-hop paths (A → B → A)
   - Test 3-hop paths (A → B → C → A)
   - Test 5-hop paths (maximum allowed)
   - Verify gas consumption scales linearly

2. **Token Edge Cases**:
   - Test with tokens having different decimals (6, 8, 18)
   - Test with fee-on-transfer tokens (if applicable)
   - Test with rebasing tokens (if applicable)

3. **Deadline Enforcement**:
   - Test with deadline = block.timestamp (immediate)
   - Test with deadline = block.timestamp + 30 seconds (max)
   - Test with deadline = block.timestamp + 31 seconds (should revert)

#### Day 8-14: Operational Validation

**Monitoring & Observability**:

1. **Event Monitoring Setup**:
   - Configure Tenderly alerts for FlashLoanExecuted events
   - Monitor RouterWhitelisted, AdapterApproved events
   - Set up Discord/Telegram notifications for critical events

2. **Performance Metrics**:
   - Track average gas consumption per arbitrage
   - Track success/failure ratio
   - Track average profit per successful arbitrage

3. **Incident Response Testing**:
   - Simulate compromised bot scenario (revoke trustedInitiator)
   - Simulate malicious adapter detection (remove adapter approval)
   - Simulate emergency fund recovery (emergencyWithdrawERC20)

### Success Criteria (ALL MUST BE MET)

- [ ] **Functional Tests**: All 5 functional test scenarios passed
- [ ] **Edge Case Tests**: All edge case scenarios validated
- [ ] **Operational Tests**: 7+ days continuous testnet operation with zero critical incidents
- [ ] **Monitoring**: Event monitoring operational with alerting configured
- [ ] **Emergency Procedures**: All emergency procedures tested and documented
- [ ] **Gas Profiling**: Gas consumption within expected ranges (<5M per transaction)
- [ ] **Documentation**: All operational procedures documented
- [ ] **Zero Critical Findings**: No new security issues discovered during testnet operation

### Exit Criteria (MUST COMPLETE BEFORE PHASE 2)

1. **Minimum 7 days testnet operation** without critical incidents
2. **All test scenarios validated** with documented results
3. **Monitoring infrastructure operational**
4. **Emergency procedures tested** and documented
5. **Team training completed** on operational procedures
6. **Phase 2 prerequisites prepared** (multi-sig setup plan documented)

**Approval Required**: Development team lead sign-off

---

## Phase 2: Mainnet Deployment <$100K TVL

### Overview

**Objective**: Deploy to Ethereum mainnet with limited TVL exposure while validating production readiness.

**Status**: CONDITIONAL APPROVAL (REQUIRES multi-sig implementation per SCSA.md Finding M-002)

**Duration**: Minimum 30 days
**TVL Limit**: <$100,000 USD equivalent
**Risk Level**: MEDIUM (limited financial exposure)

### MANDATORY Prerequisites (MUST COMPLETE BEFORE MAINNET)

#### 1. Multi-Signature Ownership Transfer (CRITICAL)

**Requirement**: Replace single owner with multi-signature wallet before ANY mainnet deployment exceeding testnet.

**Why This is MANDATORY** (per SCSA.md M-002):
- Single owner key compromise = full protocol control
- Historical context: $953.2M lost to access control failures in 2024
- Attack vector: Compromised key can whitelist malicious adapters, upgrade to malicious implementation, drain all funds

**Implementation Steps**:

**Step 1: Deploy Gnosis Safe Multi-Sig**
```bash
# Option A: Use Gnosis Safe UI (Recommended for non-technical teams)
# Visit: https://app.safe.global/
# 1. Connect wallet
# 2. Create new Safe
# 3. Configure signers (2-of-3 or 3-of-5 recommended)
# 4. Deploy Safe to mainnet

# Option B: Deploy via script (Advanced)
forge script script/DeployMultiSig.s.sol \
    --rpc-url $MAINNET_RPC_URL \
    --broadcast \
    --verify

# Save Safe address to .env
# GNOSIS_SAFE_ADDRESS=0x...
```

**Step 2: Configure Multi-Sig Signers**

**Recommended Signer Configuration**:

**For 2-of-3 Configuration**:
- Signer 1: Development team lead (geographic location A)
- Signer 2: Security officer (geographic location B)
- Signer 3: Operations lead (geographic location C)
- Threshold: 2 signatures required

**For 3-of-5 Configuration** (Recommended for higher security):
- Signer 1: Development team lead
- Signer 2: Security officer
- Signer 3: Operations lead
- Signer 4: External advisor / Board member
- Signer 5: Backup key (cold storage)
- Threshold: 3 signatures required

**Security Best Practices**:
- Geographic distribution (prevent single-location compromise)
- Organizational diversity (prevent single-party control)
- Hardware wallet requirement for ALL signers
- Documented key backup procedures
- Signer rotation policy (annual review)

**Step 3: Transfer Contract Ownership to Multi-Sig**

**Pre-Transfer Validation**:
```bash
# Verify Safe configuration BEFORE ownership transfer
cast call $GNOSIS_SAFE_ADDRESS "getThreshold()(uint256)" --rpc-url $MAINNET_RPC_URL
# Expected: ≥2 (minimum 2-of-N)

cast call $GNOSIS_SAFE_ADDRESS "getOwners()(address[])" --rpc-url $MAINNET_RPC_URL
# Expected: Array of 3+ addresses

cast call $GNOSIS_SAFE_ADDRESS "isOwner(address)(bool)" <SIGNER_ADDRESS> --rpc-url $MAINNET_RPC_URL
# Verify each signer is registered
```

**Execute Ownership Transfer**:
```bash
# Transfer ownership from EOA to multi-sig
# This is ONE-WAY and IRREVERSIBLE - verify carefully!

cast send $FLASH_ARB_PROXY \
    "transferOwnership(address)" \
    $GNOSIS_SAFE_ADDRESS \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --legacy  # Use legacy transaction for safety

# Verify ownership transferred
cast call $FLASH_ARB_PROXY "owner()(address)" --rpc-url $MAINNET_RPC_URL
# Expected: $GNOSIS_SAFE_ADDRESS
```

**Step 4: Test Multi-Sig Operations on Testnet FIRST**

**Critical: Test ALL owner functions via multi-sig on Sepolia BEFORE mainnet**:
```bash
# Test 1: setRouterWhitelist() via multi-sig
# Via Gnosis Safe UI: Transaction Builder
# Function: setRouterWhitelist(address,bool)
# Params: <test_router_address>, true

# Test 2: approveAdapter() via multi-sig
# Function: approveAdapter(address,bool)
# Params: <test_adapter_address>, true

# Test 3: Emergency pause via multi-sig
# Function: pause()

# Test 4: Emergency withdrawal via multi-sig
# Function: emergencyWithdrawERC20(address,address,uint256)

# All tests MUST succeed with proper multi-sig approvals
# Document time-to-execute for each operation type
```

**Step 5: Document Multi-Sig Operational Procedures**

Create `/docs/operations/multisig-procedures.md` with:
- Signer contact information and roles
- Multi-sig proposal workflow
- Emergency response procedures
- Signer key backup procedures
- Signer rotation policy
- Incident escalation matrix

#### 2. Custom Error Migration (RECOMMENDED)

**Finding Reference**: SCSA.md M-001 - Gas Optimization

**Benefits**:
- 10% bytecode size reduction
- ~$25 deployment savings (at 50 gwei)
- 5% runtime gas savings on reverts
- ~$375 annual savings at 100 trades/year

**Implementation**:
```bash
# Already defined in src/contracts/errors/FlashArbErrors.sol
# Migrate all require() statements to custom errors

# Example migration:
# Before:
require(msg.sender == lendingPool, "only-lending-pool");

# After:
if (msg.sender != lendingPool) {
    revert UnauthorizedCaller(msg.sender);
}

# Complete migration script
forge script script/MigrateCustomErrors.s.sol --broadcast

# Verify 10% bytecode reduction
forge build --sizes | grep FlashArbMainnetReady
```

**Timeline**: 3-4 hours development + testing

#### 3. Monitoring Infrastructure Setup

**Deploy Monitoring Tools**:

**Option A: Tenderly Monitoring** (Recommended)
```bash
# Sign up: https://tenderly.co/
# Create project: flash-arbitrage-mainnet
# Add contract: <MAINNET_PROXY_ADDRESS>

# Configure alerts:
# 1. FlashLoanExecuted event (monitor all executions)
# 2. AdapterApproved event (alert on any adapter changes)
# 3. TrustedInitiatorChanged event (alert on access grants)
# 4. Emergency events (EmergencyWithdrawn, Paused)
# 5. Large profit events (profit > 10 ETH)
# 6. Failed transactions (monitor revert reasons)
```

**Option B: OpenZeppelin Defender** (Alternative)
```bash
# Sign up: https://defender.openzeppelin.com/
# Create Sentinel: Monitor flash arbitrage contract

# Configure notifications:
# - Discord webhook for critical events
# - Telegram bot for all events
# - Email for emergency events
# - PagerDuty integration for 24/7 monitoring (optional)
```

**Metrics Dashboard**:
- Total arbitrage executions
- Success/failure ratio
- Cumulative profit per token
- Average gas consumption
- Alert count by severity

#### 4. Bug Bounty Program Launch

**Platform Selection**:

**Option A: Immunefi** (Recommended for DeFi)
```
1. Submit project application: https://immunefi.com/
2. Define reward tiers:
   - Critical (funds at risk): $10,000 - $50,000
   - High (partial risk): $5,000 - $10,000
   - Medium (limited risk): $1,000 - $5,000
   - Low (best practices): $500 - $1,000
3. Publish scope: FlashArbMainnetReady contract only
4. Set response SLA: 24 hours acknowledgment
```

**Option B: Code4rena** (Alternative)
```
1. Schedule audit competition: https://code4rena.com/
2. Define contest duration: 7-14 days
3. Set prize pool: $25,000 - $50,000
4. Provide documentation and test environment
```

**Disclosure Policy**:
- Coordinated disclosure (90-day responsible disclosure period)
- Severity assessment within 48 hours
- Fix deployment timeline based on severity
- Public disclosure after fix deployment

### Deployment Steps

#### Step 1: Mainnet Deployment Preparation

**Pre-Flight Checklist**:
```bash
# 1. Verify all Phase 1 success criteria met
# 2. Verify multi-sig deployed and tested
# 3. Verify monitoring infrastructure ready
# 4. Verify bug bounty program ready to launch

# 5. Final security scans
slither . --exclude-dependencies --detect all
semgrep --config p/smart-contracts src/

# 6. Final test suite run
forge test --gas-report
forge coverage

# 7. Gas price check (deploy during low gas period)
cast gas-price --rpc-url $MAINNET_RPC_URL
# Target: <30 gwei for economical deployment
```

#### Step 2: Mainnet Deployment Execution

**Deploy to Mainnet** (ONE-WAY OPERATION - NO UNDO):
```bash
# Dry-run deployment FIRST
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL

# Review:
# - Deployment gas estimate
# - Constructor parameters
# - Initialization parameters
# - Owner address (should be multi-sig)

# Execute deployment with hardware wallet
forge script script/Deploy.s.sol \
    --rpc-url $MAINNET_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --legacy  # Use legacy tx for safer deployment

# WAIT for Etherscan verification (5-10 minutes)
# Verify source code matches compiled artifacts

# Save deployment details
echo "MAINNET_PROXY: <address>" >> docs/deployments/mainnet.json
echo "DEPLOYMENT_BLOCK: <block_number>" >> docs/deployments/mainnet.json
echo "DEPLOYMENT_DATE: $(date)" >> docs/deployments/mainnet.json
```

#### Step 3: Post-Deployment Configuration

**Initial Configuration via Multi-Sig**:

All configuration changes MUST go through multi-sig approval process:

1. **Configure Slippage Parameters** (via Gnosis Safe UI):
   ```
   Function: setMaxSlippage(uint256)
   Parameter: 200  # 2% default
   ```

2. **Whitelist Mainnet Routers** (via Gnosis Safe UI):
   ```
   Function: setRouterWhitelist(address,bool)
   Uniswap V2: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, true
   Sushiswap: 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F, true
   ```

3. **Whitelist Mainnet Tokens** (via Gnosis Safe UI):
   ```
   Function: setTokenWhitelist(address,bool)
   WETH: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, true
   DAI: 0x6B175474E89094C44Da98b954EedeAC495271d0F, true
   USDC: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, true
   ```

4. **Deploy and Approve Adapters** (via Gnosis Safe UI):
   ```
   # Deploy UniswapV2Adapter
   forge script script/DeployUniswapV2Adapter.s.sol --rpc-url $MAINNET_RPC_URL --broadcast

   # Approve adapter via multi-sig
   Function: approveAdapter(address,bool)
   Parameter: <UNISWAP_V2_ADAPTER>, true

   Function: setDexAdapter(address,address)
   Parameters: <UNISWAP_V2_ROUTER>, <UNISWAP_V2_ADAPTER>
   ```

### Operational Phase (30+ DAYS MINIMUM)

#### TVL Monitoring & Limits

**TVL Calculation**:
```bash
# Monitor contract balance for all whitelisted tokens
cast call $WETH "balanceOf(address)(uint256)" $FLASH_ARB_PROXY --rpc-url $MAINNET_RPC_URL
cast call $DAI "balanceOf(address)(uint256)" $FLASH_ARB_PROXY --rpc-url $MAINNET_RPC_URL

# Convert to USD equivalent using price feeds
# Sum all token balances in USD

# Alert if TVL approaches $80K (80% of $100K limit)
# MANDATORY Phase 3 transition at $100K
```

**Automated TVL Monitoring Script** (`scripts/monitor-tvl.ts`):
```typescript
// Monitor TVL every 1 hour
// Send alert if TVL > $80,000
// Send CRITICAL alert if TVL > $95,000
// Recommend Phase 3 transition preparation
```

#### Incident Response Procedures

**Level 1: Routine Operations**
- Normal arbitrage executions
- Profit withdrawals
- Configuration changes via multi-sig

**Level 2: Elevated Monitoring**
- Unusual profit/loss patterns
- Failed transactions spike
- Gas price anomalies

**Level 3: Security Incident**
- Unauthorized access attempts
- Unexpected adapter approvals
- Emergency withdrawal needed

**Level 4: Critical Emergency**
- Active exploit detected
- Immediate pause required
- Emergency fund recovery

**Escalation Matrix**:
```
Level 1: Monitor via dashboard (no action required)
Level 2: Alert operations team (investigate within 4 hours)
Level 3: Alert security team (respond within 1 hour)
Level 4: Execute emergency pause (respond immediately)
```

### Success Criteria (ALL MUST BE MET)

- [ ] **Multi-Sig Operational**: All privileged operations executed via multi-sig
- [ ] **30+ Days Operation**: Zero critical incidents for 30+ days
- [ ] **TVL <$100K**: Total value locked remains below $100,000 USD
- [ ] **Monitoring Active**: All monitoring alerts functional and tested
- [ ] **Bug Bounty Live**: Program active with defined response procedures
- [ ] **Performance Validated**: Gas consumption, success rate, profitability within targets
- [ ] **Documentation Complete**: All operational procedures documented and tested
- [ ] **Team Trained**: All signers trained on multi-sig procedures and emergency response

### Exit Criteria (MUST COMPLETE BEFORE PHASE 3)

1. **Minimum 30 days mainnet operation** without critical incidents
2. **TVL approaching $100K limit** (triggers Phase 3 preparation)
3. **Multi-sig governance validated** (all operations via multi-sig for 30+ days)
4. **Monitoring validated** (all alert types tested and functional)
5. **Incident response tested** (at least one Level 2 or Level 3 incident handled successfully)
6. **Phase 3 prerequisites prepared** (Timelock deployment plan, external audit scheduled)

**Approval Required**: Security team lead + Operations lead sign-off

---

## Phase 3: Mainnet Deployment <$1M TVL

### Overview

**Objective**: Scale protocol operations with enhanced security controls for higher TVL exposure.

**Status**: CONDITIONAL APPROVAL (REQUIRES timelock + enhanced monitoring)

**Duration**: Minimum 60 days
**TVL Limit**: <$1,000,000 USD equivalent
**Risk Level**: MEDIUM-HIGH (significant financial exposure)

### MANDATORY Prerequisites

#### 1. TimelockController Integration (CRITICAL)

**Requirement**: All administrative changes MUST have 24-48 hour delay to allow community reaction time.

**Why This is MANDATORY** (per SCSA.md M-002 Full Resolution):
- Provides 48-hour window to detect malicious administrative changes
- Enables community/DAO to react to compromised multi-sig
- Establishes precedent for governance decentralization
- Industry standard for protocols >$1M TVL

**Implementation Steps**:

**Step 1: Deploy TimelockController**
```bash
# Deploy OpenZeppelin TimelockController
forge script script/DeployTimelock.s.sol \
    --rpc-url $MAINNET_RPC_URL \
    --broadcast \
    --verify

# Parameters:
# - minDelay: 48 hours (172800 seconds)
# - proposers: [GNOSIS_SAFE_ADDRESS]
# - executors: [GNOSIS_SAFE_ADDRESS]
# - admin: address(0)  # Renounced for trustlessness
```

**Step 2: Configure Emergency Role**
```bash
# Emergency role bypasses timelock for pause() operations
# Configure via multi-sig

cast send $TIMELOCK_ADDRESS \
    "grantRole(bytes32,address)" \
    $(cast keccak "EMERGENCY_ROLE") \
    $GNOSIS_SAFE_ADDRESS \
    --rpc-url $MAINNET_RPC_URL
    # Execute via multi-sig UI
```

**Step 3: Transfer Ownership to Timelock**
```bash
# THIS IS IRREVERSIBLE - TEST ON TESTNET FIRST

# Via multi-sig UI:
# Function: transferOwnership(address)
# Parameter: $TIMELOCK_ADDRESS

# Verify ownership transfer
cast call $FLASH_ARB_PROXY "owner()(address)" --rpc-url $MAINNET_RPC_URL
# Expected: $TIMELOCK_ADDRESS
```

**Step 4: Test Timelock Operations on Testnet FIRST**

**Test Scenario 1: Normal Administrative Change (48-hour delay)**:
```bash
# 1. Propose operation (via multi-sig)
cast send $TIMELOCK_ADDRESS \
    "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
    $FLASH_ARB_PROXY \  # target
    0 \  # value
    $(cast abi-encode "setMaxSlippage(uint256)" 300) \  # data
    0x0000000000000000000000000000000000000000000000000000000000000000 \  # predecessor
    $(cast keccak "salt-12345") \  # salt
    172800  # delay (48 hours)

# 2. Wait 48 hours (use block.timestamp + 48 hours on testnet)

# 3. Execute operation (via multi-sig)
cast send $TIMELOCK_ADDRESS \
    "execute(address,uint256,bytes,bytes32,bytes32)" \
    $FLASH_ARB_PROXY \
    0 \
    $(cast abi-encode "setMaxSlippage(uint256)" 300) \
    0x0000000000000000000000000000000000000000000000000000000000000000 \
    $(cast keccak "salt-12345")

# Verify change applied
cast call $FLASH_ARB_PROXY "maxSlippageBps()(uint256)" --rpc-url $SEPOLIA_RPC_URL
# Expected: 300
```

**Test Scenario 2: Emergency Pause (immediate execution)**:
```bash
# Emergency pause bypasses timelock delay
# Via multi-sig directly (not through timelock)

cast send $FLASH_ARB_PROXY \
    "pause()" \
    --rpc-url $SEPOLIA_RPC_URL
    # Execute via multi-sig with EMERGENCY_ROLE

# Verify paused
cast call $FLASH_ARB_PROXY "paused()(bool)" --rpc-url $SEPOLIA_RPC_URL
# Expected: true
```

#### 2. External Security Audit (MANDATORY)

**Requirement**: Professional security audit by reputable firm BEFORE Phase 3 deployment.

**Recommended Audit Firms**:
1. **Trail of Bits** - https://www.trailofbits.com/
   - Deep expertise in DeFi protocols
   - Formal verification capabilities
   - Estimated cost: $50,000 - $150,000
   - Timeline: 4-6 weeks

2. **OpenZeppelin** - https://openzeppelin.com/security-audits
   - Creators of security primitives used in project
   - Comprehensive testing methodologies
   - Estimated cost: $40,000 - $120,000
   - Timeline: 3-5 weeks

3. **Consensys Diligence** - https://consensys.net/diligence/
   - Extensive Ethereum ecosystem experience
   - Automated + manual review
   - Estimated cost: $45,000 - $130,000
   - Timeline: 4-6 weeks

**Audit Scope**:
- FlashArbMainnetReady.sol (primary contract)
- All DEX adapters (UniswapV2Adapter, future adapters)
- Upgrade mechanisms (UUPS proxy pattern)
- Access control mechanisms (multi-sig + timelock integration)
- Flash loan integration (Aave V2 callback validation)

**Audit Process**:
1. **Preparation** (1-2 weeks):
   - Freeze codebase (no changes during audit)
   - Provide comprehensive documentation
   - Set up secure communication channel
   - Provide test environment access

2. **Audit Execution** (3-6 weeks):
   - Static analysis + manual review
   - Fuzz testing with custom properties
   - Formal verification (if applicable)
   - Economic modeling

3. **Remediation** (1-2 weeks):
   - Address all critical/high findings
   - Mitigate or document medium findings
   - Respond to low/informational findings

4. **Re-Audit** (1 week):
   - Verify all fixes implemented correctly
   - No new vulnerabilities introduced

5. **Publication** (immediately after deployment):
   - Publish audit report publicly
   - Transparency builds trust
   - Disclose any accepted risks

**Exit Criteria**:
- Zero critical findings (MUST FIX all critical)
- Zero high findings (MUST FIX all high)
- Medium findings mitigated or accepted with documentation
- Low findings addressed or documented as won't-fix
- Audit report published on website and GitHub

#### 3. Enhanced Monitoring & Alerting

**Advanced Monitoring Requirements**:

1. **Real-Time On-Chain Monitoring**:
   - Monitor ALL transactions to contract
   - Alert on unexpected function calls
   - Alert on unusual gas consumption patterns
   - Alert on large profit/loss events

2. **Anomaly Detection**:
   - Machine learning-based anomaly detection (optional)
   - Statistical outlier detection (Z-score >3)
   - Pattern recognition (unusual access patterns)

3. **Circuit Breaker Integration** (optional):
   - Automatic pause if anomalies detected
   - Requires governance approval to implement
   - Risk: False positives could disrupt operations

4. **24/7 Operations Team**:
   - Dedicated on-call rotation
   - Response SLA: <15 minutes for critical alerts
   - Escalation procedures documented
   - Regular incident response drills

### Deployment Steps

**Phase 3 deployment follows similar pattern to Phase 2 with additional security layers.**

**Key Differences**:
- All administrative changes go through timelock (48-hour delay)
- External audit MUST be complete before deployment
- Enhanced monitoring with 24/7 ops team required
- Insurance coverage recommended (optional but strongly advised)

### Success Criteria

- [ ] **Timelock Operational**: All admin operations via 48-hour timelock
- [ ] **External Audit Complete**: All findings remediated
- [ ] **60+ Days Operation**: Zero critical incidents for 60+ days
- [ ] **TVL <$1M**: Total value locked remains below $1,000,000 USD
- [ ] **Enhanced Monitoring**: 24/7 monitoring with anomaly detection operational
- [ ] **Incident Response Validated**: Multiple Level 2/3 incidents handled successfully
- [ ] **Performance Validated**: Gas, success rate, profitability meet targets at scale

---

## Phase 4: Mainnet Deployment Unlimited TVL

### Overview

**Objective**: Full production deployment with unlimited TVL capacity.

**Status**: REQUIRES additional controls beyond Phase 3

**Duration**: Ongoing
**TVL Limit**: Unlimited (with appropriate risk management)
**Risk Level**: HIGH (unlimited financial exposure)

### MANDATORY Prerequisites

1. **Insurance Coverage** (MANDATORY):
   - Protocol insurance via Nexus Mutual, InsurAce, or similar
   - Coverage minimum: 25% of average TVL
   - Annual renewal and coverage review

2. **Formal Verification** (RECOMMENDED):
   - Critical functions verified with Certora or Halmos
   - Mathematical proof of correctness
   - Estimated cost: $20,000 - $50,000

3. **DAO Governance Transition** (LONG-TERM):
   - Consider decentralized governance
   - Token-based voting on protocol changes
   - Progressive decentralization roadmap

4. **Regular Security Audits**:
   - Quarterly security reviews
   - Annual comprehensive audits
   - Continuous bug bounty program

### Success Criteria

- All Phase 3 criteria maintained
- Insurance coverage active and sufficient
- Formal verification complete (if pursued)
- Quarterly audit cadence established
- DAO governance transition plan (if applicable)

---

## Pre-Deployment Security Validation Checklist

**Source**: SCSA.md lines 722-752

**This checklist MUST be completed before EACH phase deployment:**

### 1. Unit Tests (100% Pass Required)

```bash
# Run complete test suite
forge test --match-contract FlashArbTest

# Expected: All tests passing
# Coverage: ≥95% line coverage
# Time: ~30-60 seconds
```

**Validation**:
- [ ] All unit tests passing (0 failures)
- [ ] Code coverage ≥95% (verify with `forge coverage`)
- [ ] All edge cases covered (zero amounts, max amounts, boundary conditions)
- [ ] All revert cases tested (unauthorized access, invalid parameters)

### 2. Fuzz Tests (10,000 runs minimum)

```bash
# Run fuzz tests with 10,000 runs per test
forge test --fuzz-runs 10000 --match-test testFuzz_

# Expected: All fuzz tests passing
# Time: ~5-10 minutes
```

**Validation**:
- [ ] All fuzz tests passing (no unexpected reverts)
- [ ] Input ranges properly bounded (realistic scenarios)
- [ ] Edge cases handled gracefully (zero, max, overflow)
- [ ] No assertion failures across 10,000+ runs

### 3. Invariant Tests (All properties hold)

```bash
# Run invariant tests with 1,000 runs minimum
forge test --match-contract FlashArbInvariantTest

# Expected: All invariants holding
# Time: ~2-5 minutes
```

**Critical Invariants** (MUST ALWAYS HOLD):
- [ ] **I-1**: Flash loan always repaid (finalBalance ≥ totalDebt)
- [ ] **I-2**: Profit accounting accurate (recorded profit = actual balance)
- [ ] **I-3**: Access control enforced (non-owner calls revert)
- [ ] **I-4**: Path validation (start token = end token in closed-loop arbitrage)
- [ ] **I-5**: Slippage protection (post-swap balance ≥ minOutput)

### 4. Gas Profiling (No function >5M gas)

```bash
# Generate gas report
forge test --gas-report | tee gas-report.txt

# Analyze gas consumption per function
# Target: <650k gas per full arbitrage execution
```

**Validation**:
- [ ] No single function exceeds 5,000,000 gas (safety margin)
- [ ] Total arbitrage execution <650,000 gas (competitive threshold)
- [ ] Gas consumption within documented estimates
- [ ] No unexpected gas spikes (regressions from previous version)

### 5. Static Analysis (Zero HIGH findings)

```bash
# Run Slither with all detectors
slither . --exclude-dependencies --detect all

# Expected: 0 critical, 0 high severity findings
# Medium/Low acceptable with documentation
```

**Validation**:
- [ ] Zero CRITICAL severity findings
- [ ] Zero HIGH severity findings
- [ ] All MEDIUM findings reviewed and documented/mitigated
- [ ] LOW/INFORMATIONAL findings reviewed

### 6. Integration Tests

```bash
# Run integration tests (if implemented)
forge test --match-contract SecurityIntegration

# Test end-to-end workflows with real DEX interactions
```

**Validation**:
- [ ] Multi-DEX arbitrage paths validated
- [ ] Flash loan integration tested (Aave V2)
- [ ] Adapter integration validated (UniswapV2Adapter)
- [ ] Emergency procedures tested (pause, withdraw)

### 7. Fork Tests (Against live Aave V2 pool)

```bash
# Run fork tests against mainnet state
forge test --fork-url $MAINNET_RPC_URL --match-test testFork_

# Test with real mainnet contracts and liquidity
```

**Validation**:
- [ ] Fork tests passing with real Aave V2 pool
- [ ] Real DEX liquidity validates slippage assumptions
- [ ] Gas costs match mainnet expectations
- [ ] Real token interactions validated (WETH, DAI, USDC)

---

## Rollback Procedures

**Emergency Rollback Scenarios:**

### Scenario 1: Critical Vulnerability Discovered

**Immediate Actions**:
1. Execute emergency pause via multi-sig
2. Halt all bot operations
3. Assess vulnerability severity and exploitability
4. Coordinate with security team for fix

**Rollback Options**:
- **Option A**: Deploy fix and upgrade via UUPS (if vulnerability in implementation)
- **Option B**: Emergency withdraw all funds to multi-sig (if critical risk)
- **Option C**: Deploy new contract and migrate users (if fundamental design flaw)

### Scenario 2: Multi-Sig Compromise Suspected

**Immediate Actions**:
1. Emergency pause via any non-compromised signer
2. Freeze all administrative operations
3. Initiate signer key rotation
4. Conduct forensic analysis

**Rollback Options**:
- Transfer ownership to new multi-sig with fresh keys
- Upgrade to version with timelock (if not already present)
- Consider formal governance transition

### Scenario 3: Phase Regression Required

**Reasons for Regression**:
- Persistent operational issues
- Insufficient monitoring/incident response capability
- Team capacity constraints
- Security audit findings require major refactoring

**Regression Process**:
1. Document reason for regression (post-mortem)
2. Implement corrective actions
3. Re-validate phase entry criteria
4. Re-deploy with improved controls

---

## Deployment Contacts & Responsibilities

### Key Roles

**Development Team Lead**:
- Responsible for: Smart contract deployment, configuration, testing
- Contact: [TBD]
- Multi-sig signer: Yes

**Security Officer**:
- Responsible for: Security audits, incident response, monitoring
- Contact: [TBD]
- Multi-sig signer: Yes

**Operations Lead**:
- Responsible for: Monitoring infrastructure, operational procedures, TVL tracking
- Contact: [TBD]
- Multi-sig signer: Yes

**External Auditor** (Phase 3+):
- Responsible for: External security audit, formal verification
- Contact: [TBD - select from recommended firms]
- Multi-sig signer: No

---

## Appendix: Security Tooling Reference

### Static Analysis Tools

**Slither** (MANDATORY - every PR):
```bash
slither . --exclude-dependencies --detect all
```

**Semgrep** (MANDATORY - weekly):
```bash
semgrep --config p/smart-contracts src/
```

**Mythril** (OPTIONAL - high-risk changes):
```bash
myth analyze src/FlashArbMainnetReady.sol --solv 0.8.21
```

### Dynamic Analysis Tools

**Echidna** (RECOMMENDED - pre-deployment):
```bash
echidna-test . --contract FlashArbEchidnaTest --config echidna.yaml
```

**Foundry Fuzzing** (MANDATORY - every PR):
```bash
forge test --fuzz-runs 10000
```

### Formal Verification Tools

**Halmos** (OPTIONAL - Phase 4):
```bash
halmos --contract FlashArbMainnetReady --function executeOperation --solver z3
```

**Certora** (OPTIONAL - Phase 4):
```bash
# Commercial tool - requires license
certoraRun src/FlashArbMainnetReady.sol --verify FlashArbMainnetReady:certora/specs/FlashArb.spec
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-11-11 | DeFi Product Manager Agent | Initial comprehensive deployment roadmap based on SCSA.md audit findings |

---

**CRITICAL REMINDER**:

This deployment roadmap is NOT optional. The phased approach with escalating security controls is MANDATORY based on:
- SCSA.md Security Audit findings (M-002: Single Owner Key Risk)
- $953.2M historical losses from access control failures (2024 data)
- Industry best practices for DeFi protocol deployment

**Each phase gate is a HARD REQUIREMENT**. Do NOT proceed to next phase without completing all prerequisites and success criteria.

**When in doubt, prioritize security over speed.**
