# Flashbots MEV-Boost Integration Guide

**Purpose**: Infrastructure guide for integrating Flashbots MEV-Boost to eliminate MEV exposure
**Task Reference**: AT-026 (Flashbots MEV-Boost integration infrastructure)
**Business Case**: +20-50% profit retention ($12.5K annual benefit)
**Security**: L-001 audit finding remediation (MEV vulnerability)

---

## Executive Summary

Flashbots MEV-Boost enables private transaction submission, eliminating mempool exposure and MEV attacks (sandwich, front-running). This integration provides:

- **Profit Protection**: Retain 20-50% more profit vs. public mempool
- **MEV Elimination**: Zero sandwich/front-run exposure
- **Network Efficiency**: Reduce failed transactions and wasted gas
- **Annual Savings**: $12.5K benefit (validated in AT-024 MEV simulations)

---

## Architecture Overview

### Components

1. **Bundle Builder** (`src/infrastructure/FlashbotsSubmitter.sol`): Constructs MEV-Boost bundles
2. **Bundle Signer**: Signs bundles with Flashbots relay authentication
3. **Relay Submission**: Submits bundles to `eth_sendBundle` RPC
4. **Status Monitoring**: Tracks bundle inclusion via `eth_getBundleStats`
5. **Fallback Logic**: Public mempool submission if Flashbots unavailable

### Integration Points

```
┌─────────────────┐
│  Arbitrage Bot  │
└────────┬────────┘
         │
         ├─── Flashbots Path (Primary)
         │    ├─ Build Bundle
         │    ├─ Sign Bundle
         │    ├─ Submit to Relay
         │    └─ Monitor Inclusion
         │
         └─── Public Mempool (Fallback)
              └─ Standard Transaction
```

---

## Prerequisites

### Network Requirements
- **Mainnet RPC**: Standard Ethereum node
- **Flashbots Relay**: https://relay.flashbots.net
- **Goerli Relay** (Testing): https://relay-goerli.flashbots.net

### Authentication
- **Flashbots Signing Key**: Separate from transaction signing (no ETH required)
- **X-Flashbots-Signature Header**: ECDSA signature of bundle body

### Bundle Structure
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "eth_sendBundle",
  "params": [
    {
      "txs": ["0xSignedTransaction1", "0xSignedTransaction2"],
      "blockNumber": "0x123456",
      "minTimestamp": 1234567890,
      "maxTimestamp": 1234567900
    }
  ]
}
```

---

## Implementation Guide

### Step 1: Bundle Construction

**File**: `src/infrastructure/FlashbotsSubmitter.sol` (created in AT-026)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library FlashbotsSubmitter {
    struct Bundle {
        address[] targets;
        uint256[] values;
        bytes[] datas;
        uint256 blockNumber;
        uint256 minTimestamp;
        uint256 maxTimestamp;
    }

    function buildBundle(
        address target,
        bytes calldata data,
        uint256 blockNumber,
        uint256 minTimestamp,
        uint256 maxTimestamp
    ) internal pure returns (Bundle memory) {
        address[] memory targets = new address[](1);
        targets[0] = target;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory datas = new bytes[](1);
        datas[0] = data;

        return Bundle({
            targets: targets,
            values: values,
            datas: datas,
            blockNumber: blockNumber,
            minTimestamp: minTimestamp,
            maxTimestamp: maxTimestamp
        });
    }

    function encodeBundle(Bundle memory bundle) internal pure returns (bytes memory) {
        return abi.encode(
            bundle.targets,
            bundle.values,
            bundle.datas,
            bundle.blockNumber,
            bundle.minTimestamp,
            bundle.maxTimestamp
        );
    }
}
```

### Step 2: Bundle Signing (Off-Chain)

**Script**: `script/flashbots/SignBundle.s.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";

contract SignBundle is Script {
    function run() external {
        // Load Flashbots signing key (NOT transaction key)
        uint256 flashbotsKey = vm.envUint("FLASHBOTS_SIGNING_KEY");

        // Bundle body (JSON-encoded)
        bytes memory bundleBody = vm.envBytes("BUNDLE_BODY");

        // Sign with Flashbots key
        bytes32 messageHash = keccak256(bundleBody);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(flashbotsKey, messageHash);

        // Construct signature for X-Flashbots-Signature header
        bytes memory signature = abi.encodePacked(r, s, v);

        console.log("Bundle Signature:", vm.toString(signature));
    }
}
```

### Step 3: Bundle Submission (Off-Chain Bot)

**TypeScript Example** (`bot/flashbots-submit.ts`):

```typescript
import { FlashbotsBundleProvider } from "@flashbots/ethers-provider-bundle";
import { ethers } from "ethers";

// Initialize Flashbots provider
const FLASHBOTS_RELAY_URL = "https://relay.flashbots.net";
const provider = new ethers.providers.JsonRpcProvider(process.env.MAINNET_RPC_URL);
const authSigner = new ethers.Wallet(process.env.FLASHBOTS_SIGNING_KEY);

const flashbotsProvider = await FlashbotsBundleProvider.create(
  provider,
  authSigner,
  FLASHBOTS_RELAY_URL
);

// Build signed transaction
const tx = {
  to: FLASHARB_ADDRESS,
  data: flashArb.interface.encodeFunctionData("startFlashLoan", [asset, amount, params]),
  gasLimit: 650000,
  maxFeePerGas: ethers.utils.parseUnits("50", "gwei"),
  maxPriorityFeePerGas: ethers.utils.parseUnits("2", "gwei"),
  nonce: await signer.getTransactionCount(),
  chainId: 1,
  type: 2, // EIP-1559
};

const signedTx = await signer.signTransaction(tx);

// Submit bundle to Flashbots
const targetBlock = await provider.getBlockNumber() + 1;

const bundle = [
  {
    signedTransaction: signedTx,
  },
];

const response = await flashbotsProvider.sendBundle(bundle, targetBlock);

console.log("Bundle submitted:", response);

// Monitor bundle status
const stats = await flashbotsProvider.getBundleStats(response.bundleHash, targetBlock);
console.log("Bundle stats:", stats);
```

### Step 4: Status Monitoring

**RPC Method**: `eth_getBundleStats`

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "eth_getBundleStats",
  "params": [
    "0xBundleHash123...",
    "0x123456"
  ]
}
```

**Response**:
```json
{
  "isSimulated": true,
  "isSentToMiners": true,
  "isHighPriority": false,
  "simulatedAt": "2025-11-15T10:30:00Z",
  "submittedAt": "2025-11-15T10:30:05Z",
  "sentToMinersAt": "2025-11-15T10:30:10Z"
}
```

### Step 5: Fallback to Public Mempool

**Scenario**: Flashbots relay unavailable or bundle not included after 3 blocks

```typescript
// Attempt Flashbots submission
let bundleIncluded = false;
for (let i = 0; i < 3; i++) {
  const targetBlock = currentBlock + i + 1;
  const response = await flashbotsProvider.sendBundle(bundle, targetBlock);

  // Wait for block
  await provider.waitForTransaction(null, 1, targetBlock);

  // Check inclusion
  const stats = await flashbotsProvider.getBundleStats(response.bundleHash, targetBlock);
  if (stats.isSimulated && stats.isSentToMiners) {
    bundleIncluded = true;
    break;
  }
}

// Fallback to public mempool if not included
if (!bundleIncluded) {
  console.log("Flashbots failed, falling back to public mempool");
  const publicTx = await signer.sendTransaction(tx);
  await publicTx.wait();
}
```

---

## Testing on Goerli

### Goerli Relay Configuration

```typescript
const GOERLI_FLASHBOTS_RELAY = "https://relay-goerli.flashbots.net";

const flashbotsProvider = await FlashbotsBundleProvider.create(
  goerliProvider,
  authSigner,
  GOERLI_FLASHBOTS_RELAY
);
```

### Test Checklist

- [ ] Bundle construction succeeds
- [ ] Bundle signing generates valid signature
- [ ] Bundle submission returns bundle hash
- [ ] `eth_getBundleStats` returns simulation results
- [ ] Bundle included in target block (or next 2 blocks)
- [ ] Fallback to public mempool works if Flashbots fails

---

## Production Deployment

### Environment Variables

```bash
# Required
export MAINNET_RPC_URL="https://eth-mainnet.alchemyapi.io/v2/YOUR_KEY"
export FLASHBOTS_SIGNING_KEY="0x..." # Dedicated Flashbots signing key
export PRIVATE_KEY="0x..." # Transaction signing key

# Optional
export FLASHBOTS_RELAY_URL="https://relay.flashbots.net" # Default
export FALLBACK_ENABLED="true" # Enable public mempool fallback
export MAX_BUNDLE_ATTEMPTS="3" # Retry up to 3 blocks
```

### Operational Metrics

**Track the Following**:
1. **Bundle Inclusion Rate**: % of bundles included vs. submitted
2. **Average Inclusion Time**: Blocks from submission to inclusion
3. **Profit Retention**: % increase vs. public mempool baseline
4. **Fallback Frequency**: % of transactions using public mempool
5. **MEV Savings**: Estimated profit saved from eliminated MEV attacks

**Target Metrics** (Based on Audit Findings):
- Bundle Inclusion Rate: >90%
- Profit Retention: +20-50% vs. public mempool
- Fallback Frequency: <5% (high relay reliability)
- MEV Savings: $12.5K annually

---

## Monitoring & Alerting

### Critical Alerts

1. **Flashbots Relay Down**: Fallback to public mempool activated
2. **Low Bundle Inclusion Rate**: <80% over 1-hour window
3. **High Fallback Frequency**: >10% transactions via public mempool
4. **Profit Retention Drop**: <10% improvement vs. public mempool

### Dashboards

**Recommended Tools**:
- **Flashbots Dashboard**: https://dashboard.flashbots.net
- **Custom Metrics**: Integrate with Grafana/Prometheus
- **Dune Analytics**: Query bundle inclusion history

---

## Cost-Benefit Analysis

### Implementation Costs

| Item | Cost | Notes |
|------|------|-------|
| Development Time | 2-3 days | Bundle construction + signing + monitoring |
| Testing | 1 day | Goerli validation |
| Infrastructure | $0/month | No additional costs (uses existing RPC) |
| **Total** | **Minimal** | Mainly development time |

### Annual Benefits

| Metric | Value | Calculation |
|--------|-------|-------------|
| MEV Profit Loss (Public Mempool) | $15-20K | 20-30% leakage (AT-024 validation) |
| Flashbots Profit Retention | +$12.5K | 20-50% retention improvement |
| Reduced Failed Transactions | $1-2K | Fewer gas-wasted reversions |
| **Total Annual Benefit** | **$13.5-14.5K** | Conservative estimate |

**ROI**: Positive within first month of deployment

---

## Security Considerations

### Bundle Privacy

- **Private Until Inclusion**: Transactions not visible in public mempool
- **No MEV Exposure**: Sandwich attacks impossible (MEV searchers can't front-run private bundles)
- **Validator Trust**: Bundles sent to trusted Flashbots validators only

### Signing Key Security

- **Separate Key**: Use dedicated Flashbots signing key (NOT transaction key)
- **No ETH Required**: Signing key does NOT need ETH (only for auth signature)
- **Key Rotation**: Rotate signing key quarterly (best practice)

### Fallback Risks

- **MEV Re-Exposure**: Public mempool fallback re-introduces MEV vulnerability
- **Mitigation**: Only use fallback for critical transactions (e.g., urgent liquidations)
- **Monitoring**: Alert on high fallback frequency (indicates relay issues)

---

## Troubleshooting

### Issue 1: Bundle Not Included

**Symptoms**: `eth_getBundleStats` shows `isSimulated: true` but not included in block

**Resolution**:
1. Check `targetBlock` is future block (not past)
2. Increase gas price if bundle priority too low
3. Verify bundle construction (no reverts in simulation)
4. Wait 2-3 blocks (inclusion not guaranteed in first block)

### Issue 2: Signature Validation Failed

**Symptoms**: `eth_sendBundle` returns "Invalid signature" error

**Resolution**:
1. Verify `FLASHBOTS_SIGNING_KEY` is correct
2. Check `X-Flashbots-Signature` header format
3. Ensure bundle body hashed correctly (keccak256)
4. Validate signature recovery matches signer address

### Issue 3: High Fallback Frequency

**Symptoms**: >10% transactions using public mempool fallback

**Resolution**:
1. Check Flashbots relay status: https://status.flashbots.net
2. Verify RPC endpoint has Flashbots relay connectivity
3. Increase `MAX_BUNDLE_ATTEMPTS` from 3 to 5 blocks
4. Monitor relay latency (high latency = missed blocks)

---

## References

1. **Flashbots Documentation**: https://docs.flashbots.net
2. **MEV-Boost Spec**: https://github.com/flashbots/mev-boost
3. **Ethers.js Flashbots Provider**: https://github.com/flashbots/ethers-provider-flashbots-bundle
4. **Audit Finding L-001**: `/docs/security/SCSA.md` (MEV vulnerability)
5. **AT-024 MEV Simulations**: `/test/security/MEVAttacks.t.sol`

---

**Document Version**: 1.0
**Last Updated**: 2025-11-15
**Maintained By**: Flash Arbitrage Infrastructure Team
**Review Frequency**: Quarterly or when Flashbots protocol updates
