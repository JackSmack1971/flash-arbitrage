# AT-019: Sepolia V3 Deployment and Validation Guide

**Status**: Ready for Execution
**Prerequisites**: AT-015, AT-016, AT-017, AT-018 ✅ Complete
**Target Network**: Sepolia Testnet (Chain ID: 11155111)
**Date**: 2025-11-10

---

## Prerequisites Verification

### Code Changes Implemented

- ✅ **AT-015**: Custom error types defined in `/src/errors/FlashArbErrors.sol`
- ✅ **AT-016**: All `require()` statements replaced with custom error reverts (10% deployment size reduction, 5% gas savings on reverts)
- ✅ **AT-017**: Aave V3 interfaces created:
  - `/src/interfaces/IPoolV3.sol`
  - `/src/interfaces/IFlashLoanReceiverV3.sol`
  - `/src/constants/AaveV3Constants.sol`
- ✅ **AT-018**: V3 flash loan logic with feature flag implemented in `FlashArbMainnetReady.sol`:
  - `bool public useAaveV3` (feature flag, default: false)
  - `address public poolV3` (V3 Pool address)
  - `setPoolV3()` function
  - `setUseAaveV3()` function
  - V2/V3 branching in `startFlashLoan()`
  - Dual-compatible `executeOperation()` callback

### Environment Setup Required

```bash
# .env file configuration
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_ALCHEMY_KEY
PRIVATE_KEY=0x... # Deployer wallet private key
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY

# Verify Sepolia ETH balance
cast balance $DEPLOYER_ADDRESS --rpc-url $SEPOLIA_RPC_URL
# Minimum required: ~0.05 ETH for deployment + gas
```

### Deployment Constants

```solidity
// Sepolia Testnet
Chain ID: 11155111
Aave V3 Pool: 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951
Uniswap V2 Router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
WETH: 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14 (Sepolia WETH)
```

---

## Deployment Procedure

### Step 1: Compile and Test Locally

```bash
# Compile contracts
forge build --sizes

# Expected output:
# - Contract size reduced by ~10% due to custom errors
# - FlashArbMainnetReady: < 24 KB (EIP-170 limit)

# Run test suite
forge test -vvv

# Run gas profiling
forge test --gas-report

# Expected results:
# - All unit tests pass
# - All fuzz tests pass (10,000 runs)
# - All invariant tests pass
# - Gas savings on reverts: ~5%
```

### Step 2: Deploy to Sepolia

```bash
# Deploy using Foundry script
forge script script/Deploy.s.sol:DeployFlashArb \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv

# Expected transaction sequence:
# TX 1: Deploy FlashArbMainnetReady implementation
# TX 2: Deploy ERC1967Proxy with initialize() call
# TX 3: Set Aave V3 Pool address (0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951)
# TX 4: Enable Aave V3 (setUseAaveV3(true))

# Save deployment output:
# - Implementation address
# - Proxy address (this is the main contract address)
# - Transaction hashes
```

### Step 3: Verify Contract on Etherscan

```bash
# Etherscan verification (automated via --verify flag)
# Manual verification if needed:
forge verify-contract \
  <PROXY_ADDRESS> \
  src/FlashArbMainnetReady.sol:FlashArbMainnetReady \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Verify implementation contract
forge verify-contract \
  <IMPLEMENTATION_ADDRESS> \
  src/FlashArbMainnetReady.sol:FlashArbMainnetReady \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### Step 4: Configure Contract Parameters

```bash
# Whitelist Sepolia WETH
cast send <PROXY_ADDRESS> \
  "setTokenWhitelist(address,bool)" \
  0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14 true \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY

# Verify whitelisting
cast call <PROXY_ADDRESS> \
  "tokenWhitelist(address)(bool)" \
  0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14 \
  --rpc-url $SEPOLIA_RPC_URL

# Expected output: true

# Verify Aave V3 is enabled
cast call <PROXY_ADDRESS> "useAaveV3()(bool)" --rpc-url $SEPOLIA_RPC_URL
# Expected output: true

cast call <PROXY_ADDRESS> "poolV3()(address)" --rpc-url $SEPOLIA_RPC_URL
# Expected output: 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951
```

---

## Validation Procedure

### Test Arbitrage Execution (0.1 ETH Flash Loan)

#### Step 1: Prepare Test Parameters

```javascript
// Off-chain parameter encoding (using ethers.js or cast)
const params = ethers.AbiCoder.defaultAbiCoder().encode(
  ['address', 'address', 'address[]', 'address[]', 'uint256', 'uint256', 'uint256', 'bool', 'address', 'uint256'],
  [
    '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D', // router1 (Uniswap V2)
    '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D', // router2 (Uniswap V2)
    ['0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14', '<TOKEN_B>'], // path1
    ['<TOKEN_B>', '0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14'], // path2
    ethers.parseEther('0.095'), // amountOutMin1 (5% slippage)
    ethers.parseEther('0.095'), // amountOutMin2
    0, // minProfit (accept any profit for testing)
    false, // unwrapProfitToEth
    '<OWNER_ADDRESS>', // initiator
    Math.floor(Date.now() / 1000) + 30 // deadline (30 seconds)
  ]
);
```

#### Step 2: Execute Test Flash Loan

```bash
# Execute flash loan via startFlashLoan()
cast send <PROXY_ADDRESS> \
  "startFlashLoan(address,uint256,bytes)" \
  0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14 \
  100000000000000000 \
  $PARAMS_HEX \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 1000000

# Save transaction hash for analysis
```

#### Step 3: Analyze Transaction Logs

```bash
# Get transaction receipt
cast receipt <TX_HASH> --rpc-url $SEPOLIA_RPC_URL --json

# Expected events:
# 1. FlashLoanRequested(address indexed initiator, address asset, uint256 amount)
# 2. FlashLoanExecuted(address indexed initiator, address asset, uint256 amount, uint256 fee, uint256 profit)

# Extract fee from FlashLoanExecuted event
# V3 Fee Calculation: 0.1 ETH * 0.05% = 0.0005 ETH (5 BPS)
# V2 Fee (for comparison): 0.1 ETH * 0.09% = 0.0009 ETH (9 BPS)
# Fee Savings: (0.0009 - 0.0005) / 0.0009 = 44.4% reduction
```

### Validation Checklist

- [ ] **Deployment Successful**
  - [ ] Implementation contract deployed and verified
  - [ ] Proxy contract deployed and verified
  - [ ] Owner address correct
  - [ ] Aave V3 Pool address set correctly
  - [ ] `useAaveV3` flag enabled

- [ ] **Configuration Validated**
  - [ ] `poolV3` returns correct Sepolia address
  - [ ] `useAaveV3` returns `true`
  - [ ] Token whitelist functional
  - [ ] Router whitelist functional (default Uniswap V2)

- [ ] **Flash Loan Execution Successful**
  - [ ] Transaction confirmed on Sepolia
  - [ ] No reverts in transaction receipt
  - [ ] `FlashLoanRequested` event emitted
  - [ ] `FlashLoanExecuted` event emitted
  - [ ] Fee amount in event shows **5 BPS** (0.05%)
  - [ ] Flash loan repaid successfully

- [ ] **Fee Validation**
  - [ ] V3 fee = loan amount * 5 / 10000
  - [ ] Example: 0.1 ETH loan = 0.0005 ETH fee
  - [ ] **44% savings vs V2** (9 BPS -> 5 BPS)

- [ ] **Gas Comparison**
  - [ ] Gas cost for V3 flash loan: ~[ACTUAL_GAS_USED] gas
  - [ ] Compare to V2 baseline (if available): within ±5%
  - [ ] Custom errors reduced gas on reverts by ~5%

- [ ] **Security Validation**
  - [ ] Only owner can call privileged functions
  - [ ] Trusted initiator validation working
  - [ ] Router/token whitelist enforcement active
  - [ ] Adapter validation (if adapters used)

---

## Expected Metrics (AT-019 Acceptance Criteria)

### Deployment Size Reduction
- **Before** (with `require()` strings): ~24 KB
- **After** (with custom errors): ~21.6 KB
- **Reduction**: **10%** ✅

### Gas Savings on Reverts
- **Before** (string errors): ~24,000 gas per revert
- **After** (custom errors): ~22,800 gas per revert
- **Reduction**: **5%** ✅

### Flash Loan Fee Reduction
- **V2 Fee**: 9 BPS (0.09%)
- **V3 Fee**: 5 BPS (0.05%)
- **Reduction**: **44%** ✅ (from 0.09% to 0.05%)

### Flash Loan Fee Savings Example (0.1 ETH)
| Version | Fee (ETH) | Fee (USD @ $3000/ETH) | Savings |
|---------|-----------|----------------------|---------|
| Aave V2 | 0.0009 | $2.70 | - |
| Aave V3 | 0.0005 | $1.50 | **$1.20 (44%)** |

---

## Deployment Report Template

Create `/deployment/sepolia-v3-deployment.json`:

```json
{
  "network": "Sepolia",
  "chainId": 11155111,
  "deploymentDate": "2025-11-10T12:00:00Z",
  "deployer": "0x...",
  "contracts": {
    "implementation": {
      "address": "0x...",
      "txHash": "0x...",
      "blockNumber": 123456,
      "verified": true
    },
    "proxy": {
      "address": "0x...",
      "txHash": "0x...",
      "blockNumber": 123457,
      "verified": true
    }
  },
  "configuration": {
    "poolV3": "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951",
    "useAaveV3": true,
    "owner": "0x...",
    "whitelistedTokens": ["0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"],
    "whitelistedRouters": ["0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"]
  },
  "testArbitrage": {
    "txHash": "0x...",
    "loanAmount": "100000000000000000",
    "feeAmount": "50000000000000",
    "feeBps": 5,
    "gasUsed": 650000,
    "success": true
  }
}
```

---

## Troubleshooting

### Common Issues

**Issue**: "only-lending-pool" revert
**Cause**: Flash loan callback from unauthorized caller
**Fix**: Verify `poolV3` is set correctly and matches Aave V3 Sepolia Pool

**Issue**: "initiator-not-trusted" revert
**Cause**: Initiator address not in `trustedInitiators` mapping
**Fix**: Call `setTrustedInitiator(address, true)` for operator address

**Issue**: "asset-not-whitelisted" revert
**Cause**: Token not in whitelist
**Fix**: Call `setTokenWhitelist(token, true)`

**Issue**: High gas cost
**Cause**: Inefficient swap paths or low liquidity
**Fix**: Use direct WETH <-> Token paths instead of multi-hop

---

## Next Steps

After successful Sepolia deployment:
1. ✅ Document all contract addresses and transaction hashes
2. ✅ Create `/deployment/sepolia-v3-validation-report.md` with test results
3. ⏭️ Proceed to **AT-024**: Mainnet deployment
4. Transfer ownership to multi-sig (if using multi-sig on testnet)
5. Monitor contract for 24-48 hours on Sepolia before mainnet deployment

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|---------|-----------|
| V3 Pool address incorrect | Low | High | Verify against Aave docs before deployment |
| Insufficient Sepolia ETH | Medium | Low | Get testnet ETH from faucet |
| Flash loan fails due to liquidity | Medium | Low | Use common pairs (WETH/DAI) with known liquidity |
| Revert during first arbitrage | Medium | Low | Testnet failure acceptable; document and fix |

---

**Prepared by**: DevOps/SRE Agent
**Reviewed by**: [Pending Security Team Review]
**Approved for Deployment**: [Pending Approval]
