# Multi-Sig Operations Checklist

**Purpose**: Pre-flight checklist for all Gnosis Safe multi-sig operations on FlashArbMainnetReady
**Audience**: Multi-sig signers, DevOps engineers, Protocol operators
**Compliance**: AT-019 operational requirements

---

## Pre-Deployment Checklist (One-Time Setup)

### Sepolia Testnet Validation
- [ ] Deploy FlashArbMainnetReady to Sepolia testnet
- [ ] Create Sepolia Gnosis Safe (same 3 signers as mainnet)
- [ ] Transfer ownership to Sepolia Safe
- [ ] Execute test transactions: `setRouterWhitelist`, `setTrustedInitiator`, `setMaxSlippage`
- [ ] Verify 2-of-3 signature requirement enforced
- [ ] Document gas costs and approval latency
- [ ] All signers familiar with Safe UI and WalletConnect flow

### Mainnet Safe Creation
- [ ] All 3 hardware wallets (Ledger/Trezor) available and updated
- [ ] Recovery phrases stored in secure locations (fireproof safe + bank vault)
- [ ] Each signer has tested hardware wallet connection to Safe app
- [ ] Safe name registered: "FlashArb Governance Multi-Sig"
- [ ] Safe threshold confirmed: 2-of-3
- [ ] All 3 owner addresses verified against hardware wallet displays
- [ ] Safe deployment transaction confirmed (300k gas budget)
- [ ] Safe address recorded in password manager and operational docs

### Ownership Transfer to Safe
- [ ] Sepolia testnet transfer successful
- [ ] All 3 signers available and online
- [ ] Current FlashArb owner confirmed via `cast call <FlashArb> "owner()"`
- [ ] Gas price < 100 gwei (defer if network congested)
- [ ] No pending flash loan transactions
- [ ] Ownership transfer proposed via Safe app
- [ ] 2-of-3 signers approved and executed transfer
- [ ] Ownership transfer validated: `owner()` returns Safe address
- [ ] Old owner access revoked (test with failed privileged function call)

---

## Routine Operations Checklist

### Router Whitelist Update

#### Pre-Proposal Research
- [ ] Router contract verified on Etherscan
- [ ] Router security audit reviewed (OpenZeppelin/Trail of Bits/Consensys)
- [ ] Router tested on Sepolia fork with mock arbitrage
- [ ] Expected profit increase quantified
- [ ] Risk assessment completed (smart contract risk, liquidity risk)

#### Proposal Creation (Signer 1)
- [ ] Navigate to Safe app → New Transaction → Contract Interaction
- [ ] Contract address: `<FlashArbMainnetReady>`
- [ ] Function: `setRouterWhitelist(address router, bool allowed)`
- [ ] Parameters validated:
  - [ ] Router address matches Etherscan verification
  - [ ] `allowed = true` (or `false` for removal)
- [ ] Transaction details reviewed:
  - [ ] Value = 0 ETH
  - [ ] Operation = CALL (0)
  - [ ] Correct function selector: `0x...`
- [ ] Transaction created and signed by Signer 1
- [ ] Transaction link shared with Signer 2 & 3 for review

#### Governance Review (24-Hour Minimum)
- [ ] **Signer 2 (Technical)**: Router integration tests passed
- [ ] **Signer 3 (Financial)**: ROI analysis and risk assessment approved
- [ ] **All Signers**: No red flags or security concerns
- [ ] **Minimum 24-hour review period** elapsed

#### Execution (Signer 2)
- [ ] Transaction reviewed in Safe queue
- [ ] Router address re-verified (no copy-paste errors)
- [ ] Signer 2 approval signed with hardware wallet
- [ ] Transaction automatically executed (2-of-3 threshold met)
- [ ] Transaction confirmed on Etherscan (2-3 blocks)

#### Post-Execution Validation
- [ ] Router whitelisted: `cast call <FlashArb> "routerWhitelist(address)" <RouterAddress>`
- [ ] Test arbitrage executed with new router (0.1 ETH max)
- [ ] Profit calculation validated
- [ ] Gas costs documented
- [ ] Results logged in operations spreadsheet

---

### Token Whitelist Update

#### Pre-Proposal Research
- [ ] Token contract verified on Etherscan
- [ ] Token liquidity validated (>$1M on target DEX)
- [ ] Token security audit reviewed (if available)
- [ ] Price oracle availability confirmed (Chainlink/Uniswap V3 TWAP)
- [ ] Test arbitrage opportunity identified

#### Proposal & Approval
- [ ] Same process as Router Whitelist (above)
- [ ] Function: `setTokenWhitelist(address token, bool allowed)`
- [ ] Validation: Token address matches Etherscan
- [ ] 2-of-3 approval obtained

#### Post-Execution Validation
- [ ] Token whitelisted: `cast call <FlashArb> "tokenWhitelist(address)" <TokenAddress>`
- [ ] Test swap executed on Sepolia fork
- [ ] Balance tracking validated

---

### Maximum Slippage Update

#### Trigger Conditions
- [ ] High volatility period (VIX > 30 or crypto fear/greed index)
- [ ] Recent arbitrage failures due to slippage > 2%
- [ ] Quantified profit loss vs. execution rate trade-off

#### Risk Assessment (Signer 3 - Financial)
- [ ] Historical slippage data analyzed (last 30 days)
- [ ] MEV attack risk quantified at proposed slippage level
- [ ] Acceptable slippage range determined (max 10% hard cap)
- [ ] Reversion plan documented (return to 2% after volatility)

#### Technical Review (Signer 2)
- [ ] Proposed slippage within contract limit (≤1000 BPS / 10%)
- [ ] `HighSlippageWarning` event monitoring configured (triggers for >2%)
- [ ] Test suite validated slippage enforcement

#### Proposal & Approval
- [ ] Function: `setMaxSlippage(uint256 bps)`
- [ ] Parameters: `bps` value (e.g., 300 for 3%)
- [ ] 2-of-3 approval obtained

#### Post-Execution Monitoring
- [ ] `MaxSlippageUpdated` event emitted with old/new values
- [ ] `HighSlippageWarning` events monitored for frequency
- [ ] Arbitrage success rate tracked (target: >95%)
- [ ] Revert to 2% when volatility subsides

---

### DEX Adapter Approval (Two-Step Process)

#### Pre-Approval Security Review
- [ ] Adapter contract deployed to mainnet
- [ ] Adapter follows IDexAdapter interface exactly
- [ ] External security audit completed (mandatory for mainnet)
- [ ] Audit report reviewed by all 3 signers
- [ ] Adapter bytecode hash recorded: `<AdapterAddress>.codehash`
- [ ] Adapter tested on Sepolia fork (5+ successful swaps)

#### Step 1: Approve Adapter Bytecode Hash
- [ ] Function: `approveAdapterCodeHash(bytes32 codeHash, bool approved)`
- [ ] Parameters validated:
  - [ ] `codeHash` matches adapter.codehash from Etherscan
  - [ ] `approved = true`
- [ ] 2-of-3 approval obtained
- [ ] `AdapterCodeHashApproved` event validated

#### Step 2: Approve Adapter Address
- [ ] Function: `approveAdapter(address adapter, bool approved)`
- [ ] Parameters validated:
  - [ ] `adapter` address matches deployment
  - [ ] `approved = true`
- [ ] 2-of-3 approval obtained
- [ ] `AdapterApproved` event validated

#### Step 3: Set DEX Adapter
- [ ] Function: `setDexAdapter(address router, address adapter)`
- [ ] Parameters validated:
  - [ ] `router` already whitelisted
  - [ ] `adapter` approved in Steps 1 & 2
- [ ] Contract validates BOTH address and bytecode approved (dual-check)
- [ ] 2-of-3 approval obtained
- [ ] `DexAdapterSet` event validated

#### Post-Approval Testing
- [ ] Test arbitrage with adapter (0.1 ETH max)
- [ ] Gas cost profiling (compare vs. direct router call)
- [ ] Profit calculation validated
- [ ] Adapter performance documented

---

### Aave V3 Migration

#### Pre-Migration Validation
- [ ] AT-020 Aave V3 interfaces deployed
- [ ] AT-021 Aave V3 integration tested on Sepolia
- [ ] V3 Pool address confirmed (mainnet: 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2)
- [ ] 44% fee reduction validated (9 BPS → 5 BPS)
- [ ] Gas cost comparison completed (V2 vs. V3)

#### Configuration (2-Step Process)

**Step 1: Set V3 Pool Address**
- [ ] Function: `setPoolV3(address _poolV3)`
- [ ] Parameters: `_poolV3 = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2` (mainnet)
- [ ] 2-of-3 approval obtained

**Step 2: Enable Aave V3**
- [ ] Function: `setUseAaveV3(bool _useV3)`
- [ ] Parameters: `_useV3 = true`
- [ ] 2-of-3 approval obtained
- [ ] `AaveVersionUpdated` event validated (useV3=true, pool=V3 address)

#### Post-Migration Monitoring (First 24 Hours)
- [ ] First 5 arbitrages use V3 flash loans
- [ ] Premium calculation correct (5 BPS)
- [ ] Gas costs within expected range (±5% vs. V2)
- [ ] Total debt repayment validated
- [ ] Profit margin increased by ~0.04% (44% of 0.09% fee)

#### Rollback Plan (If Issues Detected)
- [ ] Function: `setUseAaveV3(false)` (revert to V2)
- [ ] 1-signer emergency execution (fast-path)
- [ ] Incident analysis and resolution before re-enabling V3

---

## Emergency Procedures Checklist

### Emergency Pause (1-of-3 Fast-Path)

#### Trigger Conditions (Any of the Following)
- [ ] Suspected smart contract vulnerability
- [ ] Flash loan repayment failure detected
- [ ] MEV attack in progress (abnormal profit loss)
- [ ] Security researcher disclosure (zero-day)
- [ ] Unusual on-chain behavior (monitoring alert)

#### Execution (ANY Single Signer)
- [ ] Assess severity and confirm emergency status
- [ ] Execute `pause()` immediately:
  - Option A: Via Safe app with "Execute immediately" (skip multi-sig queue)
  - Option B: Via `cast send <FlashArb> "pause()"`
- [ ] Verify contract paused: `cast call <FlashArb> "paused()(bool)"` → true
- [ ] All flash loan attempts revert (contract frozen)

#### Post-Pause Actions (Within 1 Hour)
- [ ] Alert all 3 signers via Signal/Telegram/PagerDuty
- [ ] Create incident report (timeline, root cause, impact)
- [ ] Engage security auditor for analysis (if vulnerability suspected)
- [ ] Coordinate on resolution plan (upgrade, configuration change, unpause)
- [ ] Document lessons learned

#### Unpause Process (2-of-3 Approval Required)
- [ ] Root cause identified and resolved
- [ ] Fix tested on Sepolia fork (10+ test arbitrages)
- [ ] All signers reviewed incident report and fix
- [ ] Function: `unpause()`
- [ ] 2-of-3 approval obtained
- [ ] Contract resumed and monitoring intensified

---

### UUPS Contract Upgrade

#### Pre-Upgrade Requirements (CRITICAL)
- [ ] **Security audit completed** for new implementation
- [ ] Upgrade tested on Sepolia testnet (full functionality validation)
- [ ] Storage layout compatibility verified (no collisions)
- [ ] All invariant tests pass for new implementation
- [ ] Gas cost comparison completed (new vs. old)
- [ ] Rollback plan documented

#### Upgrade Proposal (3-Signer Review Required)
- [ ] Deploy new implementation contract to mainnet
- [ ] Implementation address verified on Etherscan
- [ ] Function: `upgradeTo(address newImplementation)`
- [ ] Parameters: `newImplementation = <NewImplementationAddress>`
- [ ] **48-hour minimum review period** (allow community review)

#### Approval & Execution (2-of-3 Required)
- [ ] **All 3 signers** reviewed audit report
- [ ] **Signer 2 (Technical)**: Implementation code diff reviewed
- [ ] **Signer 3 (Financial)**: Cost-benefit analysis approved
- [ ] 2-of-3 approval obtained
- [ ] Upgrade executed and confirmed

#### Post-Upgrade Validation (Within 1 Hour)
- [ ] Implementation address updated: `cast call <Proxy> "implementation()(address)"`
- [ ] All state variables preserved (owner, whitelists, profits)
- [ ] Test arbitrage executed successfully (0.1 ETH max)
- [ ] All privileged functions accessible via Safe
- [ ] Gas costs validated (within ±10% of pre-upgrade)

---

### Ownership Transfer (Safe Migration)

#### Trigger Conditions
- [ ] Safe compromise suspected (unauthorized transaction attempts)
- [ ] Signer key loss (2+ signers lost access - CRITICAL FAILURE)
- [ ] Governance model change (e.g., move to DAO)

#### New Safe Creation
- [ ] Deploy new Safe with fresh hardware wallets
- [ ] Verify all new owner addresses
- [ ] Test new Safe with Sepolia deployment (ownership transfer)

#### Ownership Transfer from Old Safe to New Safe
- [ ] **Requires 2-of-3 approval from OLD Safe**
- [ ] Function: `transferOwnership(address newOwner)`
- [ ] Parameters: `newOwner = <NewSafeAddress>`
- [ ] Minimum 72-hour review period (allow governance objection)
- [ ] 2-of-3 approval obtained (from OLD Safe)
- [ ] Ownership transferred and validated

#### Post-Transfer Validation
- [ ] New Safe is owner: `cast call <FlashArb> "owner()"`
- [ ] Old Safe access revoked
- [ ] New Safe can execute privileged functions
- [ ] Old Safe retired (no longer used)

---

## Monitoring & Alerting Checklist

### Daily Operations
- [ ] Check Safe transaction queue (pending approvals < 24 hours)
- [ ] Review recent flash loan executions (success rate > 95%)
- [ ] Monitor profit tracking (daily profit > gas costs)
- [ ] Validate gas costs within budget (< $50/day at 50 gwei)

### Weekly Operations
- [ ] Review all `RouterWhitelisted` events (no unauthorized changes)
- [ ] Review all `AdapterApproved` events (validate against governance log)
- [ ] Audit `MaxSlippageUpdated` events (ensure within policy)
- [ ] Generate profitability report (send to Signer 3)

### Monthly Operations
- [ ] Full governance review meeting (all 3 signers)
- [ ] Security posture assessment (audit status, pending vulnerabilities)
- [ ] Hardware wallet firmware updates (Ledger/Trezor latest)
- [ ] Recovery phrase location verification (safe + vault accessible)
- [ ] Operational metrics review (approval latency, profit trends)

---

## Testing & Validation Checklist

### Before Every Mainnet Proposal
- [ ] Transaction simulated on Tenderly fork (success confirmed)
- [ ] Gas cost estimated (within budget)
- [ ] Function parameters validated (types and values correct)
- [ ] Expected outcomes documented (what should change on-chain)

### Before Every Major Change (Router, Adapter, Upgrade)
- [ ] Full test suite executed on Sepolia:
  - [ ] `forge test --match-contract FlashArbTest`
  - [ ] `forge test --match-contract FlashArbInvariantTest`
  - [ ] `forge test --match-contract FlashArbFuzzTest`
- [ ] Sepolia deployment mirrors mainnet configuration
- [ ] Test execution successful (10+ iterations)
- [ ] Results documented and shared with all signers

---

## Incident Response Checklist

### Detection
- [ ] Alert received (Defender/Tenderly/PagerDuty)
- [ ] Severity assessed (Critical/High/Medium/Low)
- [ ] Incident responder assigned (on-call signer)

### Containment
- [ ] Emergency pause executed (if Critical/High severity)
- [ ] Flash loan operations frozen
- [ ] All signers notified (Signal/Telegram)

### Investigation
- [ ] Transaction logs reviewed (Etherscan/Tenderly)
- [ ] Root cause identified (smart contract bug, MEV attack, operator error)
- [ ] Impact quantified (funds at risk, profit loss)

### Resolution
- [ ] Fix implemented (contract upgrade, configuration change, process improvement)
- [ ] Fix tested on Sepolia fork
- [ ] Fix deployed to mainnet (2-of-3 approval)
- [ ] Unpause executed (2-of-3 approval)

### Post-Mortem
- [ ] Incident report published (internal document)
- [ ] Lessons learned documented
- [ ] Process improvements implemented
- [ ] Security audit follow-up (if vulnerability)

---

## Reference Artifacts

### Live Documents
- [ ] Multi-sig Deployment Guide: `/docs/governance/MULTISIG_DEPLOYMENT.md`
- [ ] Audit Report: `/docs/security/SCSA.md`
- [ ] Test Suite: `/test/governance/OwnershipTransfer.t.sol`

### Operational Dashboards
- [ ] Gnosis Safe App: https://app.safe.global
- [ ] Etherscan FlashArb: https://etherscan.io/address/<FlashArbAddress>
- [ ] OpenZeppelin Defender: https://defender.openzeppelin.com
- [ ] Tenderly Monitoring: https://dashboard.tenderly.co

### Emergency Contacts
- [ ] Signer 1 Signal: +1-XXX-XXX-XXXX
- [ ] Signer 2 Signal: +1-XXX-XXX-XXXX
- [ ] Signer 3 Signal: +1-XXX-XXX-XXXX
- [ ] Security Auditor Hotline: +1-XXX-XXX-XXXX

---

**Checklist Version**: 1.0
**Last Updated**: 2025-11-15
**Maintained By**: Flash Arbitrage Governance Team
**Review Frequency**: After every major protocol change or incident
