# @flash-arbitrage/rpc-provider

Multi-RPC provider failover infrastructure with health checks for production-grade Ethereum applications.

## Features

- **Automatic Failover**: Seamlessly switch to backup providers when primary fails
- **Priority-Based Routing**: Configure provider priorities (Alchemy: 2, Infura: 1, QuickNode: 1)
- **Health Monitoring**: Periodic checks with exponential backoff (10s → 30s → 60s → 300s)
- **Alert System**: Emit alerts after 3 consecutive provider failures
- **Production-Ready**: Battle-tested patterns for 99.99% uptime
- **TypeScript**: Full type safety with comprehensive typings

## Installation

```bash
cd infrastructure/rpc-provider
npm install
```

## Quick Start

### 1. Configuration

Copy the environment template:

```bash
cp .env.example .env
```

Edit `.env` with your RPC endpoints:

```env
RPC_ALCHEMY_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
RPC_INFURA_URL=https://mainnet.infura.io/v3/YOUR_KEY
RPC_QUICKNODE_URL=https://YOUR_ENDPOINT.quiknode.pro/YOUR_KEY
```

### 2. Basic Usage

```typescript
import { FallbackProvider, HealthCheck } from '@flash-arbitrage/rpc-provider';
import dotenv from 'dotenv';

dotenv.config();

// Create provider with failover
const provider = new FallbackProvider([
  {
    url: process.env.RPC_ALCHEMY_URL!,
    name: 'Alchemy',
    priority: 2,        // Highest priority
    stallTimeout: 5000  // 5 second timeout
  },
  {
    url: process.env.RPC_INFURA_URL!,
    name: 'Infura',
    priority: 1,
    stallTimeout: 5000
  },
  {
    url: process.env.RPC_QUICKNODE_URL!,
    name: 'QuickNode',
    priority: 1,
    stallTimeout: 5000
  }
], 1); // Quorum: 1 provider must respond

// Use provider (automatically fails over on errors)
const blockNumber = await provider.getBlockNumber();
console.log('Current block:', blockNumber);

// Setup health monitoring
const healthCheck = new HealthCheck(provider.getConfigs(), 30000, 5000);

healthCheck.on('failure', (failure) => {
  console.warn(`Provider ${failure.providerName} failed:`, failure.error);
});

healthCheck.on('alert', (failure) => {
  console.error(`ALERT: ${failure.providerName} has ${failure.failureCount} consecutive failures`);
  // Trigger alerting system (PagerDuty, Slack, etc.)
});

healthCheck.start();
```

## API Reference

### FallbackProvider

#### Constructor

```typescript
new FallbackProvider(configs: ProviderConfig[], quorum?: number)
```

**Parameters**:
- `configs`: Array of provider configurations
- `quorum`: Number of providers that must agree (default: 1)

**ProviderConfig**:
```typescript
interface ProviderConfig {
  url: string;         // RPC endpoint URL
  name: string;        // Provider name for logging
  priority: number;    // Priority weight (higher = preferred)
  stallTimeout: number; // Timeout in milliseconds
}
```

#### Methods

```typescript
// Get current block number
getBlockNumber(): Promise<number>

// Get network information
getNetwork(): Promise<ethers.Network>

// Get gas price
getGasPrice(): Promise<bigint>

// Get fee data (EIP-1559)
getFeeData(): Promise<ethers.FeeData>

// Send transaction
sendTransaction(signedTx: string): Promise<ethers.TransactionResponse>

// Get transaction receipt
getTransactionReceipt(txHash: string): Promise<ethers.TransactionReceipt | null>

// Wait for transaction
waitForTransaction(txHash: string, confirmations?: number, timeout?: number): Promise<ethers.TransactionReceipt | null>

// Estimate gas
estimateGas(tx: ethers.TransactionRequest): Promise<bigint>

// Get underlying ethers provider
getProvider(): ethers.FallbackProvider

// Get configurations
getConfigs(): ProviderConfig[]

// Clean up resources
destroy(): Promise<void>
```

### HealthCheck

#### Constructor

```typescript
new HealthCheck(
  configs: ProviderConfig[],
  checkInterval?: number,  // Default: 30000ms (30s)
  checkTimeout?: number    // Default: 5000ms (5s)
)
```

#### Methods

```typescript
// Start periodic health checks
start(): void

// Stop health checks
stop(): void

// Check all providers
checkAll(): Promise<HealthCheckResult[]>

// Check single provider
checkProvider(config: ProviderConfig): Promise<HealthCheckResult>

// Register event listener
on(event: 'success' | 'failure' | 'alert', callback: (data: any) => void): void

// Get failure count
getFailureCount(providerName: string): number

// Get current backoff delay
getBackoffDelay(providerName: string): number

// Clean up
destroy(): void
```

#### Events

**success**: Emitted on successful health check
```typescript
{
  providerName: string;
  isHealthy: true;
  blockNumber: number;
  timestamp: number;
  responseTime: number;
}
```

**failure**: Emitted on provider failure
```typescript
{
  providerName: string;
  failureCount: number;
  error: string;
  timestamp: number;
}
```

**alert**: Emitted after 3 consecutive failures
```typescript
{
  providerName: string;
  failureCount: number;
  error: string;
  timestamp: number;
}
```

## Exponential Backoff

Failed providers are retried with exponential backoff:

| Failure Count | Backoff Delay |
|---------------|---------------|
| 1             | 10 seconds    |
| 2             | 30 seconds    |
| 3             | 60 seconds    |
| 4             | 180 seconds   |
| 5+            | 300 seconds (max) |

## Testing

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Generate coverage report
npm run test:coverage
```

## Build

```bash
# Compile TypeScript
npm run build

# Output: dist/
```

## Best Practices

### 1. Provider Priority

Configure priorities based on reliability and performance:

```typescript
// Recommended priorities
Alchemy:    2 (highest - most reliable)
Infura:     1 (fallback)
QuickNode:  1 (fallback)
```

### 2. Health Check Interval

Balance between responsiveness and API rate limits:

```typescript
// Production: 30 seconds
const healthCheck = new HealthCheck(configs, 30000, 5000);

// Development: 60 seconds (reduce API calls)
const healthCheck = new HealthCheck(configs, 60000, 5000);
```

### 3. Alert Integration

Integrate with your alerting system:

```typescript
healthCheck.on('alert', async (failure) => {
  // Send to PagerDuty
  await pagerduty.trigger({
    severity: 'critical',
    summary: `RPC Provider ${failure.providerName} failing`,
    details: failure
  });

  // Send to Slack
  await slack.send({
    channel: '#alerts',
    text: `🚨 RPC Alert: ${failure.providerName} has ${failure.failureCount} failures`
  });
});
```

### 4. Graceful Shutdown

Always clean up on process exit:

```typescript
process.on('SIGINT', async () => {
  console.log('Shutting down gracefully...');
  healthCheck.stop();
  await provider.destroy();
  process.exit(0);
});
```

## Architecture

```
┌─────────────────────────────────────────┐
│         FallbackProvider                │
│  - Alchemy (priority: 2, stall: 5s)    │
│  - Infura (priority: 1, stall: 5s)     │
│  - QuickNode (priority: 1, stall: 5s)  │
└─────────────────────────────────────────┘
                  ▲
                  │
                  │ getBlockNumber()
                  │ sendTransaction()
                  │
┌─────────────────┴───────────────────────┐
│         Application / Bot                │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│         HealthCheck                      │
│  - Periodic checks every 30s            │
│  - Exponential backoff on failure       │
│  - Alert after 3 consecutive failures   │
└─────────────────────────────────────────┘
```

## Troubleshooting

### Provider not failing over

**Symptom**: Primary provider fails but requests don't switch to backup

**Solution**: Verify `stallTimeout` is set correctly (5000ms recommended)

```typescript
const configs = [{
  url: alchemyUrl,
  name: 'Alchemy',
  priority: 2,
  stallTimeout: 5000  // Must be set
}];
```

### High failure rates

**Symptom**: Health checks report frequent failures

**Solution**: Check RPC endpoint validity and rate limits

```bash
# Test endpoints manually
curl -X POST $RPC_ALCHEMY_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### Memory leaks

**Symptom**: Memory usage grows over time

**Solution**: Ensure health checks are stopped and providers destroyed

```typescript
// Always clean up
healthCheck.destroy();
await provider.destroy();
```

## License

MIT

## Contributing

See main project CONTRIBUTING.md

## Support

For issues or questions:
- GitHub Issues: [flash-arbitrage/issues](https://github.com/your-org/flash-arbitrage/issues)
- Documentation: `/docs/infrastructure/rpc-provider.md`
