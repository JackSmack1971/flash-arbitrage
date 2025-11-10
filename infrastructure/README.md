# Flash Arbitrage Infrastructure

Off-chain infrastructure for production-grade flash arbitrage execution.

## Overview

This directory contains all off-chain infrastructure components implementing Phase 2 (Infrastructure Reliability) from the atomic tasks roadmap.

## Components

### 1. RPC Provider (`./rpc-provider/`)

Multi-RPC provider failover infrastructure with health checks.

**Implements**: AT-020 (RPC Failover), AT-021 (Flashbots)

**Features**:
- Automatic failover across Alchemy, Infura, QuickNode
- Priority-based routing (Alchemy: 2, others: 1)
- Health monitoring with exponential backoff (10s → 30s → 60s → 300s)
- Alert emission after 3 consecutive failures
- Flashbots bundle submission and simulation
- Status polling for bundle inclusion

**ROI**: +704% (Critical priority)

### 2. Simulation (`./simulation/`)

Forked mainnet simulation for pre-flight validation.

**Implements**: AT-022 (Simulation)

**Features**:
- Anvil fork management at current block
- Transaction simulation with gas + fee calculations
- Profitability validation (gas + flash loan fees)
- Automatic cleanup (no zombie processes)
- 10-second timeout protection

**ROI**: +71% (Medium priority)

### 3. Bot (`./bot/`)

Arbitrage bot orchestrator integrating all components.

**Implements**: AT-023 (Bot Orchestration)

**Features**:
- Multi-RPC failover integration
- Flashbots submission with fallback
- Pre-flight simulation validation
- Graceful shutdown (SIGINT/SIGTERM)
- Health monitoring and auto-pause
- Emergency safeguards

**Status**: Production-ready framework (requires opportunity detection)

## Installation

Each component is independently installable:

```bash
# Install all components
cd rpc-provider && npm install
cd ../simulation && npm install
cd ../bot && npm install

# Or install individually
cd <component> && npm install
```

## Quick Start

### RPC Provider

```typescript
import { FallbackProvider, HealthCheck, FlashbotsProvider } from '@flash-arbitrage/rpc-provider';

// Multi-RPC failover
const provider = new FallbackProvider([
  { url: alchemyUrl, name: 'Alchemy', priority: 2, stallTimeout: 5000 },
  { url: infuraUrl, name: 'Infura', priority: 1, stallTimeout: 5000 },
  { url: quicknodeUrl, name: 'QuickNode', priority: 1, stallTimeout: 5000 }
]);

// Health monitoring
const healthCheck = new HealthCheck(provider.getConfigs());
healthCheck.on('alert', (failure) => {
  console.error(`ALERT: ${failure.providerName} failed`);
});
healthCheck.start();

// Flashbots
const flashbots = new FlashbotsProvider(relayUrl, authSigner, provider.getProvider());
const simulation = await flashbots.simulate([signedTx], targetBlock);
if (simulation.success) {
  const bundleHash = await flashbots.sendBundle([signedTx], targetBlock);
  await flashbots.waitForInclusion(bundleHash, 25);
}
```

### Simulation

```typescript
import { SimulationOrchestrator } from '@flash-arbitrage/simulation';

const orchestrator = new SimulationOrchestrator(
  forkRpcUrl,
  { minProfitWei: parseEther('0.01'), minProfitUsd: 30 }
);

const result = await orchestrator.simulate(signedTx, arbitrageParams, gasConfig);

if (result.success && result.netProfit > 0) {
  console.log('Profitable!', result.netProfit);
}
```

### Bot

```typescript
import { ArbitrageBot, loadConfig, validateConfig } from '@flash-arbitrage/bot';

const config = loadConfig();
validateConfig(config);

const bot = new ArbitrageBot(config);
await bot.start();

process.on('SIGINT', async () => {
  await bot.stop();
  process.exit(0);
});
```

## Configuration

Each component requires environment configuration. Copy `.env.example` to `.env` in each directory:

```bash
# RPC Provider
cd rpc-provider && cp .env.example .env

# Simulation
cd ../simulation && cp .env.example .env

# Bot
cd ../bot && cp .env.example .env
```

## Testing

```bash
# Test all components
npm test

# Test individual component
cd <component> && npm test

# Coverage report
cd <component> && npm run test:coverage
```

## Build

```bash
# Build all components
cd rpc-provider && npm run build
cd ../simulation && npm run build
cd ../bot && npm run build
```

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                  Arbitrage Bot                        │
│                   (AT-023)                            │
└──────────────────────────────────────────────────────┘
         │                  │                  │
         ▼                  ▼                  ▼
┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│  RPC Failover  │  │   Flashbots    │  │   Simulation   │
│   (AT-020)     │  │   (AT-021)     │  │   (AT-022)     │
│                │  │                │  │                │
│ - Alchemy (2)  │  │ - Bundle send  │  │ - Anvil fork   │
│ - Infura (1)   │  │ - Simulation   │  │ - Gas calc     │
│ - QuickNode(1) │  │ - Status poll  │  │ - Profit calc  │
│ - Health check │  │ - 25 block wait│  │ - Threshold    │
└────────────────┘  └────────────────┘  └────────────────┘
```

## Phase 2 Metrics

| Component | Annual Benefit | Implementation Cost | ROI | Priority |
|-----------|---------------|---------------------|-----|----------|
| Multi-RPC Failover | $19,292 | $2,400 + $708/year | +704% | CRITICAL |
| Flashbots MEV-Boost | $12,250 | $3,600 + $500/year | +240% | HIGH |
| Forked Simulation | $6,550 | $3,600 + $0/year | +71% | MEDIUM |
| **Total Phase 2** | **$38,092** | **$9,600 + $1,208/year** | **+284%** | - |

## Roadmap

### Completed ✅

- AT-020: Multi-RPC provider failover
- AT-021: Flashbots integration
- AT-022: Forked mainnet simulation
- AT-023: Bot orchestration framework

### Phase 3 (Future Work)

- Multi-DEX opportunity scanner (Uniswap V3, Curve, Balancer)
- Real-time price monitoring and spread calculation
- Layer 2 deployment (Arbitrum, Optimism)
- dYdX flash loan integration (0% fees)
- Cross-chain arbitrage

## Development

### Project Structure

```
infrastructure/
├── rpc-provider/          # AT-020, AT-021
│   ├── src/
│   │   ├── FallbackProvider.ts
│   │   ├── HealthCheck.ts
│   │   ├── FlashbotsProvider.ts
│   │   └── __tests__/
│   ├── package.json
│   └── README.md
├── simulation/            # AT-022
│   ├── src/
│   │   ├── AnvilFork.ts
│   │   ├── ProfitCalculator.ts
│   │   ├── SimulationOrchestrator.ts
│   │   └── __tests__/
│   ├── package.json
│   └── README.md
├── bot/                   # AT-023
│   ├── src/
│   │   ├── ArbitrageBot.ts
│   │   ├── config/
│   │   └── __tests__/
│   ├── package.json
│   └── README.md
└── README.md             # This file
```

### Dependencies

All components use:
- **ethers.js v6**: Ethereum interaction
- **TypeScript 5.3+**: Type safety
- **Jest**: Testing framework
- **Node.js 18+**: Runtime

### Code Style

```bash
# Format code
cd <component> && npm run format

# Lint code
cd <component> && npm run lint
```

## Security Considerations

1. **Private Keys**: Never commit `.env` files. Use hardware wallets for mainnet.
2. **RPC Endpoints**: Rotate API keys periodically. Monitor rate limits.
3. **Flashbots Auth**: Use dedicated auth signer (separate from transaction signer).
4. **Simulation**: Always enable pre-flight simulation on mainnet.
5. **Emergency**: Configure `EMERGENCY_SHUTDOWN_ADDRESS` for kill switch.

## Monitoring & Alerts

Production deployments should integrate:

- **PagerDuty**: Critical RPC failures, contract errors
- **Slack**: Daily profit summaries, health check failures
- **Grafana**: Real-time metrics (uptime, gas costs, profits)
- **Sentry**: Error tracking and debugging

## Support

- **Issues**: [GitHub Issues](https://github.com/your-org/flash-arbitrage/issues)
- **Docs**: `/docs/infrastructure/`
- **Roadmap**: `/docs/phases/phase3-roadmap.md`

## License

MIT
