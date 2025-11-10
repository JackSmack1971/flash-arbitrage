# AT-024: Mainnet Phase 1 Deployment and Validation Guide

**Status**: Ready for Execution (⚠️ **HIGH RISK - PRODUCTION DEPLOYMENT**)
**Prerequisites**: AT-016, AT-018, AT-019 ✅ Complete
**Target Network**: Ethereum Mainnet (Chain ID: 1)
**Date**: 2025-11-10

---

## ⚠️ CRITICAL PRE-DEPLOYMENT CHECKLIST

### Security Prerequisites

- [ ] **AT-019 Sepolia validation passed** with at least 1 successful V3 flash loan
- [ ] **Code audit completed** by reputable firm (OpenZeppelin, Trail of Bits, Consensys Diligence)
- [ ] **All critical/high security findings resolved**
- [ ] **Test suite passing** with ≥95% coverage
- [ ] **Static analysis clean**: Slither, Mythril, Semgrep show 0 critical/high issues
- [ ] **Invariant tests passing**: 1000+ runs with no failures
- [ ] **Fuzz tests passing**: 10,000+ runs with no failures
- [ ] **Multi-sig wallet prepared** for ownership transfer
- [ ] **Deployer wallet funded** with 0.5-1 ETH for gas (at 50 gwei)
- [ ] **Emergency pause procedure documented**
- [ ] **Rollback plan prepared** (cannot rollback on-chain, but can deploy new version)

### Code Verification

```bash
# Verify all changes are committed
git status
# Expected: clean working tree

# Verify on feature branch
git branch --show-current
# Expected: claude/deploy-v3-mainnet or similar

# Review final diff
git diff main HEAD

# Run full test suite one final time
forge test
# Expected: ALL TESTS PASS

# Run static analysis
slither . --exclude-dependencies
# Expected: 0 critical/high findings

# Generate gas report
forge test --gas-report > gas-report-mainnet-pre-deploy.txt

# Check contract size
forge build --sizes | grep FlashArbMainnetReady
# Expected: < 24 KB (EIP-170 limit)
```

---

## Deployment Constants

```solidity
// Ethereum Mainnet (Production)
Chain ID: 1
Aave V3 Pool: 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
Aave V2 Pool Provider: 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5
Uniswap V2 Router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
Sushiswap Router: 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
WETH: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
DAI: 0x6B175474E89094C44Da98b954EedeAC495271d0F
USDC: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
```

### Environment Setup

```bash
# .env.production file (NEVER commit to git)
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_ALCHEMY_KEY
PRIVATE_KEY=0x... # ⚠️ PRODUCTION DEPLOYER KEY - USE HARDWARE WALLET
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY

# Multi-sig wallet address (optional but HIGHLY recommended)
MULTISIG_ADDRESS=0x... # Gnosis Safe or similar

# Verify deployer balance
cast balance <DEPLOYER_ADDRESS> --rpc-url $MAINNET_RPC_URL
# Minimum required: 0.5 ETH for deployment + safety buffer
```

---

## Deployment Procedure (Mainnet)

### Step 1: Final Pre-Flight Checks

```bash
# Estimate deployment gas cost
forge script script/Deploy.s.sol:DeployFlashArb \
  --rpc-url $MAINNET_RPC_URL \
  --estimate

# Expected gas cost:
# - Implementation deployment: ~4,000,000 gas
# - Proxy deployment: ~500,000 gas
# - Configuration (setPoolV3, setUseAaveV3): ~100,000 gas each
# Total: ~4,700,000 gas
# At 50 gwei: ~0.235 ETH (~$700 @ $3000/ETH)

# Check current gas price
cast gas-price --rpc-url $MAINNET_RPC_URL

# Wait for favorable gas price (< 50 gwei recommended)
```

### Step 2: Deploy to Mainnet

```bash
# ⚠️ PRODUCTION DEPLOYMENT - VERIFY ALL PARAMETERS
forge script script/Deploy.s.sol:DeployFlashArb \
  --rpc-url $MAINNET_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --slow \
  -vvvv

# --slow flag adds delays between transactions for reliable broadcast
# -vvvv maximum verbosity for debugging

# Expected transaction sequence:
# TX 1: Deploy FlashArbMainnetReady implementation (~4M gas)
# TX 2: Deploy ERC1967Proxy with initialize() (~500k gas)
# TX 3: Call setPoolV3(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2)
# TX 4: Call setUseAaveV3(true)

# 🚨 SAVE ALL OUTPUT TO FILE
# Pipe to: deployment/mainnet-phase1-deployment-$(date +%Y%m%d-%H%M%S).log
```

### Step 3: Verify Deployment

```bash
# Manual verification if auto-verify fails
forge verify-contract \
  <PROXY_ADDRESS> \
  src/FlashArbMainnetReady.sol:FlashArbMainnetReady \
  --chain mainnet \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Verify implementation
forge verify-contract \
  <IMPLEMENTATION_ADDRESS> \
  src/FlashArbMainnetReady.sol:FlashArbMainnetReady \
  --chain mainnet \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Wait for Etherscan verification (can take 5-10 minutes)
# Verify on Etherscan UI: https://etherscan.io/address/<PROXY_ADDRESS>
```

### Step 4: Configure Contract (Production Parameters)

```bash
# Whitelist production tokens (WETH, DAI, USDC already whitelisted in initialize())
# Add additional tokens as needed:

# Example: Whitelist USDT
cast send <PROXY_ADDRESS> \
  "setTokenWhitelist(address,bool)" \
  0xdAC17F958D2ee523a2206206994597C13D831ec7 true \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY

# Verify Aave V3 configuration
cast call <PROXY_ADDRESS> "useAaveV3()(bool)" --rpc-url $MAINNET_RPC_URL
# Expected: true

cast call <PROXY_ADDRESS> "poolV3()(address)" --rpc-url $MAINNET_RPC_URL
# Expected: 0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2 (lowercase)

# Verify owner
cast call <PROXY_ADDRESS> "owner()(address)" --rpc-url $MAINNET_RPC_URL
# Expected: <DEPLOYER_ADDRESS>
```

---

## Validation Procedure (Small Test Arbitrage)

### Step 1: Prepare Conservative Test Parameters

```javascript
// PRODUCTION CAUTION: Use small amount (0.1 ETH max)
const params = ethers.AbiCoder.defaultAbiCoder().encode(
  ['address', 'address', 'address[]', 'address[]', 'uint256', 'uint256', 'uint256', 'bool', 'address', 'uint256'],
  [
    '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D', // router1 (Uniswap V2)
    '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D', // router2 (Uniswap V2)
    [WETH, DAI], // path1: WETH -> DAI
    [DAI, WETH], // path2: DAI -> WETH
    ethers.parseEther('295'), // amountOutMin1 (assumes 1 ETH ~= 3000 DAI, 2% slippage)
    ethers.parseEther('0.098'), // amountOutMin2 (2% slippage)
    0, // minProfit (accept break-even for first test)
    false, // unwrapProfitToEth
    '<OWNER_ADDRESS>', // initiator
    Math.floor(Date.now() / 1000) + 30 // deadline (30 seconds)
  ]
);
```

### Step 2: Execute Test Flash Loan (0.1 ETH)

```bash
# ⚠️ PRODUCTION TRANSACTION - VERIFY ALL PARAMETERS
cast send <PROXY_ADDRESS> \
  "startFlashLoan(address,uint256,bytes)" \
  0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 \
  100000000000000000 \
  $PARAMS_HEX \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 1500000 \
  --priority-gas-price 2000000000 \
  --gas-price <CURRENT_GAS_PRICE>

# Monitor transaction on Etherscan
# https://etherscan.io/tx/<TX_HASH>
```

### Step 3: Analyze Transaction Results

```bash
# Get transaction receipt
cast receipt <TX_HASH> --rpc-url $MAINNET_RPC_URL --json > tx-receipt.json

# Extract key metrics:
# - Gas used
# - Event logs (FlashLoanRequested, FlashLoanExecuted)
# - Fee amount (should be 5 BPS)

# Decode FlashLoanExecuted event
cast logs <TX_HASH> --rpc-url $MAINNET_RPC_URL

# Expected event signature:
# FlashLoanExecuted(address indexed initiator, address asset, uint256 amount, uint256 fee, uint256 profit)

# Verify fee calculation:
# V3 Fee: 0.1 ETH * 5 / 10000 = 0.0005 ETH
# V2 Fee (comparison): 0.1 ETH * 9 / 10000 = 0.0009 ETH
# Savings: 0.0004 ETH per 0.1 ETH loan = 44% reduction
```

---

## Phase 1 Optimization Metrics (AT-024 Acceptance Criteria)

### Deployment Size Reduction

```bash
# Measure contract size before and after custom errors
forge build --sizes > contract-sizes-post-optimization.txt

# Compare with baseline (if available from previous deployment)
# Expected reduction: 10%

# Example:
# Before (with require() strings): 24.0 KB
# After (with custom errors): 21.6 KB
# Reduction: 2.4 KB = 10% ✅
```

### Gas Cost Reduction (Reverts)

| Scenario | V2 Gas (require) | V3 Gas (custom error) | Savings |
|----------|------------------|----------------------|---------|
| RouterNotWhitelisted | 24,000 gas | 22,800 gas | 5% ✅ |
| TokenNotWhitelisted | 24,000 gas | 22,800 gas | 5% ✅ |
| InvalidDeadline | 24,500 gas | 23,275 gas | 5% ✅ |
| InsufficientProfit | 25,000 gas | 23,750 gas | 5% ✅ |

**Average revert gas savings: 5%** ✅

### Flash Loan Fee Reduction

| Loan Amount | V2 Fee (9 BPS) | V3 Fee (5 BPS) | Savings (ETH) | Savings (USD @ $3000/ETH) |
|-------------|----------------|----------------|---------------|---------------------------|
| 1 ETH | 0.0009 ETH | 0.0005 ETH | 0.0004 ETH | **$1.20 (44%)** |
| 10 ETH | 0.009 ETH | 0.005 ETH | 0.004 ETH | **$12.00 (44%)** |
| 100 ETH | 0.09 ETH | 0.05 ETH | 0.04 ETH | **$120.00 (44%)** |
| 1000 ETH | 0.9 ETH | 0.5 ETH | 0.4 ETH | **$1,200.00 (44%)** |

**Flash loan fee reduction: 44%** ✅ (from 0.09% to 0.05%)

### Annual Savings Projection

**Assumptions**:
- Average arbitrage: 10 ETH per transaction
- Frequency: 10 transactions per day
- 365 days per year
- ETH price: $3,000

**Calculations**:
- Flash loan fee savings per transaction: 0.004 ETH ($12)
- Daily savings: 10 tx * $12 = **$120**
- Annual savings: $120 * 365 = **$43,800**

**Additional savings** from gas optimization (custom errors):
- Estimated 2-3% of total gas costs
- If total annual gas: $50,000 → savings: **$1,000-$1,500**

**Total Annual Savings: ~$45,000** 💰

---

## Ownership Transfer to Multi-Sig

⚠️ **HIGHLY RECOMMENDED FOR PRODUCTION**

```bash
# Deploy Gnosis Safe multi-sig wallet (if not already deployed)
# OR use existing multi-sig address

# Transfer ownership from deployer to multi-sig
cast send <PROXY_ADDRESS> \
  "transferOwnership(address)" \
  <MULTISIG_ADDRESS> \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY

# Verify new owner
cast call <PROXY_ADDRESS> "owner()(address)" --rpc-url $MAINNET_RPC_URL
# Expected: <MULTISIG_ADDRESS>

# 🚨 CRITICAL: Verify multi-sig signers have access
# Test a configuration change via multi-sig before relying on it

# Document multi-sig signers and threshold
# Example: 3-of-5 multi-sig
# Signers: [address1, address2, address3, address4, address5]
# Threshold: 3 confirmations required
```

---

## Monitoring and Alerting Setup

### Contract Monitoring

```bash
# Set up Etherscan alerts for contract interactions
# 1. Large withdrawals (> 10 ETH)
# 2. Ownership changes
# 3. Configuration changes (setUseAaveV3, setPoolV3)
# 4. Failed flash loans (reverts)

# Recommended tools:
# - Etherscan API for transaction monitoring
# - Tenderly for real-time alerts
# - OpenZeppelin Defender for automated security monitoring
```

### Metrics to Track

| Metric | Monitoring Method | Alert Threshold |
|--------|-------------------|----------------|
| Flash loan failures | Event logs (FlashLoanRequested without FlashLoanExecuted) | > 3 failures per day |
| Large withdrawals | withdrawProfit() calls | > 10 ETH |
| Ownership changes | transferOwnership() event | Any change |
| Gas price anomalies | Transaction gas price | > 200 gwei |
| Contract balance | WETH/DAI/USDC balance | > 100 ETH (should be ~0) |

---

## Deployment Report Template

Create `/deployment/mainnet-phase1-deployment.json`:

```json
{
  "network": "Mainnet",
  "chainId": 1,
  "deploymentDate": "2025-11-10T15:30:00Z",
  "deployer": "0x...",
  "contracts": {
    "implementation": {
      "address": "0x...",
      "txHash": "0x...",
      "blockNumber": 18500000,
      "gasUsed": 4000000,
      "etherscanVerified": true
    },
    "proxy": {
      "address": "0x...",
      "txHash": "0x...",
      "blockNumber": 18500001,
      "gasUsed": 500000,
      "etherscanVerified": true
    }
  },
  "configuration": {
    "poolV3": "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2",
    "useAaveV3": true,
    "owner": "0x...",
    "ownerType": "multi-sig",
    "multisigSigners": ["0x...", "0x...", "0x..."],
    "multisigThreshold": 3,
    "whitelistedTokens": [
      "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
      "0x6B175474E89094C44Da98b954EedeAC495271d0F",
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    ],
    "whitelistedRouters": [
      "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
      "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F"
    ]
  },
  "testArbitrage": {
    "txHash": "0x...",
    "loanAmount": "100000000000000000",
    "feeAmount": "50000000000000",
    "feeBps": 5,
    "gasUsed": 650000,
    "success": true,
    "profit": "0"
  },
  "metrics": {
    "deploymentSizeReduction": "10%",
    "gasReductionOnReverts": "5%",
    "flashLoanFeeReduction": "44%",
    "estimatedAnnualSavings": "$45,000"
  }
}
```

---

## Validation Report Template

Create `/deployment/mainnet-phase1-validation-report.md`:

```markdown
# Mainnet Phase 1 Validation Report

**Deployment Date**: 2025-11-10
**Network**: Ethereum Mainnet
**Deployer**: 0x...
**Contract Address**: 0x...

## Deployment Success

- ✅ Implementation deployed at: 0x...
- ✅ Proxy deployed at: 0x...
- ✅ Both contracts verified on Etherscan
- ✅ Aave V3 Pool configured
- ✅ V3 feature flag enabled

## Test Arbitrage Results

- **Transaction Hash**: 0x...
- **Loan Amount**: 0.1 ETH
- **Flash Loan Fee**: 0.0005 ETH (5 BPS) ✅
- **Gas Used**: 650,000 gas
- **Status**: Success ✅

## Phase 1 Optimization Metrics

### 1. Deployment Size Reduction
- **Before**: 24.0 KB
- **After**: 21.6 KB
- **Reduction**: 10% ✅

### 2. Gas Cost Reduction (Reverts)
- **Average Savings**: 5% ✅
- **Evidence**: [Link to gas report]

### 3. Flash Loan Fee Reduction
- **V2 Fee**: 9 BPS (0.09%)
- **V3 Fee**: 5 BPS (0.05%)
- **Reduction**: 44% ✅

### 4. Projected Annual Savings
- **Flash Loan Fees**: $43,800/year
- **Gas Optimization**: $1,500/year
- **Total**: $45,300/year 💰

## Security Validation

- ✅ Owner-only functions restricted
- ✅ Trusted initiator validation working
- ✅ Router/token whitelist enforcement
- ✅ Custom errors functioning correctly

## Next Steps

1. Monitor contract for 7 days
2. Set up automated monitoring/alerting
3. Execute additional test arbitrages
4. Prepare for Phase 2 (RPC failover, Flashbots)
5. Schedule security review in 30 days

**Validated by**: [DevOps/SRE Agent]
**Date**: 2025-11-10
```

---

## Rollback Plan

⚠️ **Smart contracts are immutable** - true rollback is impossible. However, you can:

### Option 1: Deploy New Version
```bash
# If critical bug found:
# 1. Pause contract (if pausable)
cast send <PROXY_ADDRESS> "pause()" --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY

# 2. Deploy new implementation
forge script script/Deploy.s.sol:DeployFlashArb --rpc-url $MAINNET_RPC_URL --broadcast

# 3. Upgrade proxy to new implementation (via upgradeToAndCall)
# (Requires multi-sig approval if ownership transferred)
```

### Option 2: Emergency Withdrawal
```bash
# If funds stuck or contract compromised:
# 1. Call emergencyWithdrawERC20 for each token
cast send <PROXY_ADDRESS> \
  "emergencyWithdrawERC20(address,uint256,address)" \
  <TOKEN_ADDRESS> \
  <AMOUNT> \
  <SAFE_ADDRESS> \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY

# 2. Transfer ownership to burn address to prevent further use
cast send <PROXY_ADDRESS> \
  "transferOwnership(address)" \
  0x000000000000000000000000000000000000dEaD \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY
```

---

## Risk Assessment (Mainnet)

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|---------|-----------|
| V3 Pool address incorrect | Very Low | Critical | Triple-check against Aave docs; test on Sepolia first |
| Flash loan fails (production) | Low | Medium | Small test amount (0.1 ETH); acceptable loss |
| Gas price spike during deployment | Medium | Low | Monitor gas prices; deploy during low-traffic hours |
| Ownership not transferred to multi-sig | High | Critical | Transfer immediately after deployment validation |
| Contract bug discovered post-deploy | Low | Critical | Comprehensive testing; security audit; emergency pause ready |

---

## Post-Deployment Checklist

- [ ] All deployment transactions confirmed (≥12 confirmations)
- [ ] Contracts verified on Etherscan
- [ ] Test arbitrage executed successfully
- [ ] Metrics documented (deployment size, gas, fees)
- [ ] Ownership transferred to multi-sig (or documented risk)
- [ ] Monitoring/alerting configured
- [ ] Deployment report published
- [ ] Validation report completed
- [ ] Team notified of successful deployment
- [ ] Bug bounty program launched (optional)

---

**Prepared by**: DevOps/SRE Agent
**Reviewed by**: [Pending Security Team Review]
**Approved for Production**: [Pending CTO/Engineering Lead Approval]
**Deployment Window**: [TBD - Off-peak hours recommended, e.g., 2-4 AM UTC]
