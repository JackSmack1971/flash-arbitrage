/**
 * @flash-arbitrage/rpc-provider
 *
 * Multi-RPC provider failover infrastructure with health checks
 *
 * Features:
 * - Automatic failover to backup providers on failure
 * - Priority-based provider selection (Alchemy prioritized)
 * - Health monitoring with exponential backoff
 * - Alert emission after 3 consecutive failures
 *
 * @example
 * ```typescript
 * import { FallbackProvider, HealthCheck } from '@flash-arbitrage/rpc-provider';
 *
 * const provider = new FallbackProvider([
 *   { url: alchemyUrl, name: 'Alchemy', priority: 2, stallTimeout: 5000 },
 *   { url: infuraUrl, name: 'Infura', priority: 1, stallTimeout: 5000 },
 *   { url: quicknodeUrl, name: 'QuickNode', priority: 1, stallTimeout: 5000 }
 * ]);
 *
 * const healthCheck = new HealthCheck(provider.getConfigs());
 * healthCheck.on('alert', (failure) => {
 *   console.error(`ALERT: ${failure.providerName} failed`);
 * });
 * healthCheck.start();
 *
 * const blockNumber = await provider.getBlockNumber();
 * ```
 */

export { FallbackProvider } from './FallbackProvider';
export { HealthCheck } from './HealthCheck';
export { FlashbotsProvider } from './FlashbotsProvider';
export {
  ProviderConfig,
  HealthCheckResult,
  ProviderFailure,
  BackoffConfig
} from './types/ProviderConfig';
export {
  FlashbotsConfig,
  FlashbotsBundle,
  FlashbotsSimulation,
  FlashbotsBundleStatus,
  FlashbotsBundleTransaction
} from './types/FlashbotsConfig';
