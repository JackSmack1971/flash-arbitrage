# Multi-Sig Deployment Guide

**Audience**: Protocol Operators, DevOps Engineers, Governance Team
**Purpose**: Step-by-step guide for migrating FlashArbMainnetReady ownership to Gnosis Safe 2-of-3 multi-sig
**Security Level**: CRITICAL (M-001 Audit Finding Remediation)
**Reference**: Security audit finding M-001 - Single-owner EOA risk for TVL ≥ $100K

---

## Executive Summary

This document provides production-grade procedures for deploying and operating FlashArbMainnetReady under Gnosis Safe multi-signature governance. This migration is **MANDATORY** before Phase 2 deployment (mainnet TVL ≥ $100K) per audit finding M-001.

### Key Requirements
- **Minimum Signers**: 3 hardware wallet addresses (Ledger/Trezor recommended)
- **Signature Threshold**: 2-of-3 (66% consensus)
- **Emergency Role**: 1-of-3 for `pause()` function (fast-path security)
- **Operational Principle**: All privileged functions require 2-signer approval
- **Deployment Timeline**: Complete before mainnet TVL reaches $50K (50% safety margin)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Part 1: Gnosis Safe Creation](#part-1-gnosis-safe-creation)
3. [Part 2: Ownership Transfer](#part-2-ownership-transfer)
4. [Part 3: Operational Workflows](#part-3-operational-workflows)
5. [Part 4: Emergency Procedures](#part-4-emergency-procedures)
6. [Part 5: Monitoring & Alerting](#part-5-monitoring--alerting)
7. [Rollback Procedures](#rollback-procedures)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Hardware Requirements
- **3 Hardware Wallets** (Ledger Nano S/X or Trezor One/Model T)
  - Signer 1: Primary governance (CEO/CTO)
  - Signer 2: Technical governance (Lead Engineer)
  - Signer 3: Financial governance (CFO/Treasury)
- **Secure storage** for recovery phrases (fireproof safe, bank vault)
- **2FA-enabled** Gnosis Safe web interface access

### Network Requirements
- **Mainnet RPC**: Alchemy, Infura, or self-hosted node (archive mode recommended)
- **Etherscan API Key**: For transaction verification and monitoring
- **Gas Budget**: ~$200 USD for Safe creation + ownership transfer (at 50 gwei)

### Software Requirements
- **Gnosis Safe Web App**: https://app.safe.global
- **WalletConnect**: For hardware wallet integration
- **Foundry**: For ownership transfer script execution

### Knowledge Prerequisites
- Understanding of multi-sig security model
- Familiarity with Gnosis Safe UI and transaction flows
- Access to FlashArbMainnetReady deployment address
- Completion of AT-018 test suite validation (test/governance/OwnershipTransfer.t.sol)

---

## Part 1: Gnosis Safe Creation

### Step 1.1: Access Gnosis Safe Interface

1. Navigate to https://app.safe.global
2. Connect **Signer 1** hardware wallet via WalletConnect
3. Select **Ethereum Mainnet** (chain ID: 1)
4. Click **"Create new Safe"**

### Step 1.2: Configure Safe Parameters

**Safe Configuration**:
```yaml
Network: Ethereum Mainnet (1)
Safe Name: "FlashArb Governance Multi-Sig"
Owners:
  - Signer 1: 0x... (Primary Governance - Ledger)
  - Signer 2: 0x... (Technical Governance - Ledger)
  - Signer 3: 0x... (Financial Governance - Trezor)
Threshold: 2 out of 3
```

**CRITICAL VALIDATION**:
- ✅ Verify ALL 3 owner addresses are derived from hardware wallets
- ✅ Double-check addresses against hardware wallet display (not copy-paste)
- ✅ Confirm threshold is exactly `2` (not 1 or 3)
- ✅ Save Safe address IMMEDIATELY to secure location

### Step 1.3: Deploy Gnosis Safe

1. Review deployment transaction details:
   - Gas estimate: ~300k gas (~$30 at 50 gwei, $2000 ETH)
   - Safe creation via factory contract
2. **Sign transaction with Signer 1** (initial deployer pays gas)
3. Wait for transaction confirmation (2-3 blocks)
4. **Record Safe Address**: `0xSafeAddress123...` (CRITICAL - store in password manager)

### Step 1.4: Validate Safe Deployment

```bash
# Verify Safe deployment on Etherscan
open https://etherscan.io/address/0xSafeAddress123...

# Check Safe configuration via cast
cast call 0xSafeAddress123... "getThreshold()(uint256)" --rpc-url $MAINNET_RPC_URL
# Expected output: 2

cast call 0xSafeAddress123... "getOwners()(address[])" --rpc-url $MAINNET_RPC_URL
# Expected output: [0xSigner1, 0xSigner2, 0xSigner3]
```

**Validation Checklist**:
- [ ] Safe deployed and verified on Etherscan
- [ ] `getThreshold()` returns `2`
- [ ] `getOwners()` returns all 3 signer addresses
- [ ] Safe has ENS name registered (optional but recommended)
- [ ] All signers can view Safe in their Gnosis Safe app

---

## Part 2: Ownership Transfer

### Step 2.1: Pre-Transfer Validation

**CRITICAL**: Test ownership transfer on **Sepolia testnet** FIRST before mainnet.

#### Sepolia Validation Steps:
1. Deploy FlashArb to Sepolia (use deployment script)
2. Create Sepolia Safe with same 3 signers
3. Execute ownership transfer on Sepolia
4. Verify multi-sig can execute `setRouterWhitelist` on Sepolia
5. Document gas costs and timing

#### Mainnet Pre-Flight Checklist:
- [ ] Sepolia testnet transfer successful and validated
- [ ] All 3 signers available and online (scheduled transfer time)
- [ ] Current FlashArb owner address confirmed: `cast call <FlashArb> "owner()(address)"`
- [ ] Safe address copied and triple-verified
- [ ] Gas price below 100 gwei (defer if network congested)
- [ ] No pending flash loan transactions (check mempool)

### Step 2.2: Execute Ownership Transfer (Multi-Sig Proposal)

**Method**: Use Gnosis Safe web interface to propose ownership transfer.

#### Propose Transfer (Signer 1):
1. Open Gnosis Safe app → Select FlashArb Safe
2. Click **"New Transaction"** → **"Contract Interaction"**
3. **Contract Address**: `<FlashArbMainnetReady deployed address>`
4. **ABI**: Upload FlashArbMainnetReady ABI (from `out/FlashArbMainnetReady.sol/FlashArbMainnetReady.json`)
5. **Function**: `transferOwnership(address newOwner)`
6. **Parameters**:
   - `newOwner`: `<Gnosis Safe address>`
7. **Review**:
   ```solidity
   Function: transferOwnership(address)
   To: <FlashArb Contract>
   Value: 0 ETH
   Data: 0xf2fde38b000000000000000000000000<SafeAddress>
   ```
8. Click **"Create"** → Sign with Signer 1 hardware wallet
9. **Share transaction link** with Signer 2 for approval

#### Approve & Execute Transfer (Signer 2):
1. Open Safe app → Navigate to **"Transactions"** → **"Queue"**
2. Review proposed ownership transfer:
   - Verify `newOwner` address matches Safe address
   - Verify no additional parameters or value transfers
3. Click **"Confirm"** → Sign with Signer 2 hardware wallet
4. Transaction automatically executes (2-of-3 threshold met)
5. Wait for confirmation (2-3 blocks)

### Step 2.3: Verify Ownership Transfer

```bash
# Verify new owner is Gnosis Safe
cast call <FlashArbAddress> "owner()(address)" --rpc-url $MAINNET_RPC_URL
# Expected: <Gnosis Safe address>

# Verify previous owner NO LONGER has access (should revert)
cast send <FlashArbAddress> "setRouterWhitelist(address,bool)" \
  0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D true \
  --from <OldOwnerAddress> --rpc-url $MAINNET_RPC_URL
# Expected: Revert with "Ownable: caller is not the owner"
```

**Post-Transfer Validation Checklist**:
- [ ] `owner()` returns Safe address
- [ ] Old owner cannot execute privileged functions
- [ ] Safe appears as owner on Etherscan contract page
- [ ] Ownership transfer event emitted with correct parameters

---

## Part 3: Operational Workflows

### Workflow 3.1: Whitelist New Router

**Scenario**: Add Curve Finance router to whitelist for multi-pool arbitrage.

#### Step-by-Step:
1. **Research & Validation** (Off-Chain):
   - Verify router contract address on Etherscan
   - Review router audit reports
   - Test router integration on Sepolia fork
   - Document expected profit increase

2. **Propose Transaction** (Signer 1):
   ```
   Navigate to Safe app → New Transaction → Contract Interaction
   Contract: <FlashArb Address>
   Function: setRouterWhitelist(address router, bool allowed)
   Parameters:
     router: 0xCurveRouterAddress...
     allowed: true
   ```

3. **Governance Review** (All Signers):
   - Signer 2: Review technical validation (audit, integration tests)
   - Signer 3: Review financial impact (profit projections, risk assessment)
   - **Minimum 24-hour review period** for major changes

4. **Approval & Execution** (Signer 2):
   - Review transaction in Safe queue
   - Confirm router address matches research
   - Sign approval with hardware wallet
   - Transaction executes automatically

5. **Post-Execution Validation**:
   ```bash
   # Verify router whitelisted
   cast call <FlashArb> "routerWhitelist(address)(bool)" 0xCurveRouter... --rpc-url $MAINNET_RPC_URL
   # Expected: true
   ```

6. **Monitor First Execution**:
   - Execute test arbitrage with new router (small amount)
   - Monitor profit calculation and gas costs
   - Document results for future reference

### Workflow 3.2: Update Maximum Slippage

**Scenario**: Increase slippage tolerance from 2% to 3% during high volatility.

#### Governance Approval Process:
1. **Risk Assessment** (Signer 3):
   - Analyze recent slippage patterns
   - Quantify profit loss vs. execution rate
   - Calculate maximum acceptable slippage

2. **Technical Review** (Signer 2):
   - Verify new slippage within 10% hard cap (enforced by contract)
   - Review historical MEV attack patterns at higher slippage
   - Validate against test suite results

3. **Propose Transaction** (Signer 1):
   ```
   Function: setMaxSlippage(uint256 bps)
   Parameters: bps = 300 (3%)
   ```

4. **Approval & Monitoring**:
   - 2-signer approval
   - Monitor `HighSlippageWarning` events (emitted for slippage > 2%)
   - Revert to 2% after volatility subsides

### Workflow 3.3: Approve New DEX Adapter

**Scenario**: Deploy and approve adapter for Uniswap V3 integration.

**CRITICAL**: Adapter approval is a **two-step security process** (address + bytecode hash).

#### Step-by-Step:
1. **Adapter Development & Testing**:
   - Implement adapter following IDexAdapter interface
   - Complete security review by external auditor
   - Deploy adapter to mainnet (separate transaction)
   - Record deployed address and bytecode hash

2. **Step 1: Approve Adapter Bytecode Hash** (Proposal):
   ```
   Function: approveAdapterCodeHash(bytes32 codeHash, bool approved)
   Parameters:
     codeHash: 0xAdapterBytecodeHash... (from adapter.codehash)
     approved: true
   ```
   - Get 2-signer approval
   - Execute and confirm

3. **Step 2: Approve Adapter Address** (Proposal):
   ```
   Function: approveAdapter(address adapter, bool approved)
   Parameters:
     adapter: 0xAdapterAddress...
     approved: true
   ```
   - Get 2-signer approval
   - Execute and confirm

4. **Step 3: Set DEX Adapter** (Proposal):
   ```
   Function: setDexAdapter(address router, address adapter)
   Parameters:
     router: 0xUniswapV3Router...
     adapter: 0xAdapterAddress...
   ```
   - Contract validates BOTH address and bytecode hash approved
   - Get 2-signer approval
   - Execute and monitor first usage

---

## Part 4: Emergency Procedures

### Emergency Scenario 1: Contract Pause

**Trigger Conditions**:
- Suspected vulnerability discovered
- Unusual profit loss pattern detected
- MEV attack in progress
- Flash loan repayment failure

**FAST-PATH**: 1-of-3 emergency pause (no multi-sig delay).

#### Execute Immediate Pause:
```bash
# Any single signer can execute pause (owner-only function via Safe)
cast send <FlashArb> "pause()" \
  --from <SafeAddress> \
  --rpc-url $MAINNET_RPC_URL
```

**Alternative**: Use Safe app with single signer approval:
1. Safe app → New Transaction → Contract Interaction
2. Function: `pause()`
3. **CRITICAL**: Use "Execute immediately" (bypass multi-sig queue for emergencies)
4. Transaction confirms in 1-2 blocks

#### Post-Pause Actions:
1. **Incident Response**:
   - Freeze all flash loan operations (contract reverts)
   - Alert all signers via secure channel
   - Document incident timeline and root cause
   - Engage security auditor for analysis

2. **Resolution & Unpause**:
   - Implement fix (if contract vulnerability)
   - Deploy patch via UUPS upgrade (requires 2-of-3 approval)
   - Test fix on Sepolia fork
   - Propose `unpause()` transaction (2-of-3 approval required)

### Emergency Scenario 2: Ownership Recovery

**Trigger**: Safe compromised or signer keys lost.

#### Prevention:
- **Never** store recovery phrases digitally
- Use fireproof safe + bank vault redundancy
- Test recovery process annually on Sepolia

#### Recovery Procedure:
1. **If 2+ signers retain access**:
   - Create new Safe with fresh signers
   - Propose ownership transfer from old Safe to new Safe (2-of-3 approval)
   - Validate new Safe before transferring

2. **If <2 signers have access** (CRITICAL FAILURE):
   - **NO RECOVERY POSSIBLE** (by design - security trade-off)
   - Contract ownership permanently lost
   - Emergency procedures:
     - Deploy new FlashArb contract
     - Migrate liquidity and operations
     - Post-mortem analysis to prevent recurrence

### Emergency Scenario 3: Malicious Proposal Detection

**Trigger**: Suspicious transaction in Safe queue (e.g., unknown recipient, large value transfer).

#### Identification:
- Unknown contract interaction
- Unexpected function selector
- Value transfer to unverified address
- Rushed approval without review period

#### Response:
1. **DO NOT SIGN** suspicious transaction
2. **Reject transaction** in Safe app (requires 2 signers to reject)
3. **Rotate compromised signer** if insider threat suspected:
   - Propose Safe owner replacement
   - Remove compromised signer
   - Add new hardware wallet signer
   - Requires 2-of-3 approval (excluding compromised signer)

---

## Part 5: Monitoring & Alerting

### Monitoring Infrastructure

#### On-Chain Events:
```solidity
// Monitor critical events (integrate with Defender/Tenderly)
FlashLoanExecuted - Track all arbitrage executions
RouterWhitelisted - Alert on router changes
AdapterApproved - Alert on adapter approvals
AaveVersionUpdated - Alert on V2/V3 toggle
OwnershipTransferred - CRITICAL ALERT on ownership change
Paused - CRITICAL ALERT on emergency pause
```

#### Alerting Thresholds:
- **CRITICAL**: Ownership transfer, emergency pause, adapter approval
- **WARNING**: Router whitelist change, slippage > 2%, flash loan failure
- **INFO**: Successful arbitrage, profit withdrawal

### Recommended Tooling

1. **OpenZeppelin Defender**:
   - Sentinel monitoring for contract events
   - Automated alerting via email/Slack/PagerDuty
   - Transaction simulation for Safe proposals

2. **Tenderly**:
   - Real-time transaction monitoring
   - Gas profiling and optimization alerts
   - Forked simulations for governance testing

3. **Dune Analytics**:
   - Dashboard for profit tracking
   - Gas cost analysis
   - Flash loan success rate monitoring

### Operational Dashboards

#### Key Metrics:
```yaml
Governance Health:
  - Safe signer status (online/offline)
  - Pending transaction queue length
  - Average approval time (target: <24 hours)

Financial Metrics:
  - Total profit (ETH/USD)
  - Flash loan success rate (target: >95%)
  - Average profit per arbitrage
  - Gas costs vs. profit ratio

Security Metrics:
  - Failed flash loan attempts
  - Slippage events > 2%
  - MEV attack detections
  - Contract pause events
```

---

## Rollback Procedures

### Rollback Scenario 1: Safe Ownership Transfer Failure

**Symptoms**: Ownership transfer transaction reverts or Safe cannot execute functions.

#### Diagnosis:
```bash
# Check current owner
cast call <FlashArb> "owner()(address)"

# Verify Safe can make calls
cast call <Safe> "getOwners()(address[])"
```

#### Resolution:
- If transfer not confirmed: **No action needed** (revert original state)
- If transfer confirmed but Safe broken: **Deploy new Safe** and transfer again
- If irrecoverable: **Redeploy FlashArb** with new Safe as initial owner

### Rollback Scenario 2: Post-Transfer Operational Issues

**Symptoms**: Multi-sig approval process too slow, operational friction.

#### Option 1: Optimize Workflow
- Reduce approval latency (24/7 signer availability)
- Implement Safe Transaction Service for batching
- Use Snapshot for off-chain governance voting

#### Option 2: Temporary Single-Signer (NOT RECOMMENDED)
- Deploy new EOA-owned contract for emergency operations
- Maintain multi-sig as primary governance
- **Only for <$100K TVL deployments**

---

## Troubleshooting

### Issue 1: Safe Transaction Stuck in Queue

**Symptoms**: Transaction shows "Awaiting confirmations" for >48 hours.

**Resolution**:
1. Check signer availability (all 3 signers online?)
2. Review transaction in Safe app → "Transactions" → "Queue"
3. If Signer 2 unavailable, use Signer 3 as backup:
   - Signer 1 + Signer 3 approval (2-of-3 met)
4. If urgent, reject and re-propose with faster approval commitment

### Issue 2: Hardware Wallet Not Connecting

**Symptoms**: WalletConnect fails to detect Ledger/Trezor.

**Resolution**:
1. Update hardware wallet firmware (latest version)
2. Enable "Blind signing" in Ledger advanced settings
3. Use alternative WalletConnect bridge (switch regional server)
4. Fallback: Use MetaMask with hardware wallet integration

### Issue 3: Transaction Simulation Fails

**Symptoms**: Safe app shows "Simulation failed" on transaction proposal.

**Resolution**:
1. Check current contract state (paused? whitelists configured?)
2. Validate function parameters (correct types and values)
3. Test transaction on Tenderly fork before proposing
4. Review recent contract upgrades (UUPS implementation changes)

### Issue 4: Gas Price Spike During Execution

**Symptoms**: Transaction pending for hours due to low gas price.

**Resolution**:
1. **DO NOT** cancel and re-submit (nonce conflict)
2. Use Safe app "Speed up" feature (increase gas price)
3. For critical transactions, set gas price to Fast/Fastest tier
4. Budget $50-100 USD for emergency operations during congestion

---

## Appendix A: Safe Transaction Scripts

### Script: Propose Router Whitelist

```solidity
// script/governance/ProposeWhitelistChange.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {FlashArbMainnetReady} from "../../src/FlashArbMainnetReady.sol";

contract ProposeWhitelistChange is Script {
    function run() external {
        address flashArb = vm.envAddress("FLASHARB_ADDRESS");
        address newRouter = vm.envAddress("NEW_ROUTER_ADDRESS");

        // Generate calldata for Safe proposal
        bytes memory data = abi.encodeWithSelector(
            FlashArbMainnetReady.setRouterWhitelist.selector,
            newRouter,
            true
        );

        // Output for manual Safe proposal
        console.log("=== Gnosis Safe Transaction Parameters ===");
        console.log("To:", flashArb);
        console.log("Value: 0");
        console.log("Data:", vm.toString(data));
        console.log("Operation: CALL (0)");
    }
}
```

### Script: Batch Multiple Operations

```solidity
// script/governance/ProposeBatchOperations.s.sol
// For Safe Transaction Builder (batch multiple calls atomically)

// Example: Whitelist router + token in single atomic transaction
// 1. Export calldata for each operation
// 2. Use Safe Transaction Builder to combine
// 3. Execute as single multi-call transaction (gas savings)
```

---

## Appendix B: Emergency Contact List

```yaml
Critical Contacts:
  Signer 1 (Primary Governance):
    Name: [REDACTED]
    Signal: +1-XXX-XXX-XXXX
    Email: governance@flasharb.io
    Backup: Telegram @signer1

  Signer 2 (Technical Governance):
    Name: [REDACTED]
    Signal: +1-XXX-XXX-XXXX
    Email: tech@flasharb.io
    Backup: Discord @signer2

  Signer 3 (Financial Governance):
    Name: [REDACTED]
    Signal: +1-XXX-XXX-XXXX
    Email: treasury@flasharb.io
    Backup: Telegram @signer3

Security Auditor:
  Firm: OpenZeppelin / Trail of Bits
  Contact: audit-team@security-firm.com
  Emergency Hotline: +1-XXX-XXX-XXXX

Incident Response:
  PagerDuty: https://flasharb.pagerduty.com
  Status Page: https://status.flasharb.io
```

---

## Appendix C: Governance SLA

```yaml
Service Level Agreement:
  Transaction Approval Time:
    Routine Operations: <24 hours (2 signer approval)
    Critical Changes: <48 hours (3 signer review + 2 approval)
    Emergency Pause: <10 minutes (1 signer fast-path)

  Signer Availability:
    Minimum Online: 2 of 3 signers at all times
    Response Time: <2 hours during business hours
    Emergency Response: <30 minutes (24/7)

  Review Requirements:
    Router Whitelist: Technical + Financial review
    Adapter Approval: Security audit + Technical review
    Slippage Changes: Financial risk assessment
    Contract Upgrades: Full security audit + 3-signer approval
```

---

## References

1. **Gnosis Safe Documentation**: https://docs.safe.global
2. **Audit Finding M-001**: `/docs/security/SCSA.md` (Single-owner EOA risk)
3. **Test Validation**: `/test/governance/OwnershipTransfer.t.sol` (AT-018 test suite)
4. **OpenZeppelin Defender**: https://defender.openzeppelin.com
5. **Safe Transaction Service**: https://safe-transaction.mainnet.gnosis.io

---

**Document Version**: 1.0
**Last Updated**: 2025-11-15
**Maintained By**: Flash Arbitrage Governance Team
**Review Frequency**: Quarterly or after major protocol changes
