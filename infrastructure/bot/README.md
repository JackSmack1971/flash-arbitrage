# @flash-arbitrage/bot

Production-ready arbitrage bot orchestrator integrating multi-RPC failover, Flashbots, and pre-flight simulation.

## Features

- **Multi-RPC Failover**: Automatic failover across Alchemy, Infura, QuickNode (AT-020)
- **Flashbots Integration**: Private transaction submission with MEV protection (AT-021)
- **Pre-Flight Simulation**: Anvil fork validation before real submission (AT-022)
- **Profitability Validation**: Gas + flash loan fee calculations
- **Graceful Shutdown**: Clean resource cleanup on SIGINT/SIGTERM
- **Health Monitoring**: Periodic provider and contract health checks
- **Emergency Safeguards**: Auto-pause after consecutive failures

## Installation

```bash
cd infrastructure/bot
npm install
```

## Configuration

```bash
cp .env.example .env
# Edit .env with your configuration
```

### Required Environment Variables

```env
# RPC Providers (at least one required)
RPC_ALCHEMY_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
RPC_INFURA_URL=https://mainnet.infura.io/v3/YOUR_KEY
RPC_QUICKNODE_URL=https://YOUR_ENDPOINT.quiknode.pro/YOUR_KEY

# Transaction Signer (REQUIRED)
PRIVATE_KEY=0x...

# Flash Arbitrage Contract (REQUIRED)
FLASH_ARB_CONTRACT=0x...

# Flashbots (if enabled)
FLASHBOTS_ENABLED=true
FLASHBOTS_AUTH_SIGNER=0x...

# Simulation (if enabled)
SIMULATION_ENABLED=true
FORK_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
```

## Quick Start

```typescript
import { ArbitrageBot, loadConfig, validateConfig } from '@flash-arbitrage/bot';
import dotenv from 'dotenv';

dotenv.config();

const config = loadConfig();
validateConfig(config);

const bot = new ArbitrageBot(config);

await bot.start();

// Graceful shutdown
process.on('SIGINT', async () => {
  await bot.stop();
  process.exit(0);
});
```

## Architecture

```
┌─────────────────────────────────────────┐
│         ArbitrageBot                     │
│  - Opportunity monitoring                │
│  - Transaction execution                 │
│  - Health checks                         │
│  - Emergency safeguards                  │
└─────────────────────────────────────────┘
         │          │          │
         ▼          ▼          ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│ RPC Failover│ │  Flashbots  │ │ Simulation  │
│  (AT-020)   │ │  (AT-021)   │ │  (AT-022)   │
└─────────────┘ └─────────────┘ └─────────────┘
```

## Execution Flow

1. **Monitor**: Poll for arbitrage opportunities (12-second intervals)
2. **Simulate**: Pre-flight validation on Anvil fork (if enabled)
3. **Submit**: Send via Flashbots (if enabled) or public mempool
4. **Fallback**: If Flashbots fails after 25 blocks, submit publicly
5. **Monitor**: Wait for transaction confirmation
6. **Log**: Record execution results

## Development Status

**Current State**: Production-ready framework with placeholder opportunity detection

**TODO**: Implement opportunity detection (Phase 3)
- Multi-DEX price monitoring
- Spread calculation
- Real-time opportunity identification

**Implemented**:
- ✅ RPC failover infrastructure
- ✅ Flashbots integration
- ✅ Simulation framework
- ✅ Bot orchestration skeleton
- ✅ Configuration management
- ✅ Graceful shutdown
- ✅ Health monitoring

## Testing

```bash
npm test                # Run all tests
npm run test:watch      # Watch mode
npm run test:coverage   # Generate coverage report
```

## Build & Run

```bash
# Development
npm run dev

# Production
npm run build
npm start
```

## Monitoring

The bot emits structured logs with timestamps and transaction details:

```
[ArbitrageBot] Initialized
[ArbitrageBot] Starting...
[ArbitrageBot] Started
[ArbitrageBot] Checking for opportunities...
[ArbitrageBot] Health check passed
```

## Emergency Shutdown

The bot auto-pauses after `MAX_CONSECUTIVE_FAILURES` (default: 5) to prevent runaway losses.

Manual shutdown:
```bash
# Sends SIGINT for graceful shutdown
Ctrl+C
```

## License

MIT
