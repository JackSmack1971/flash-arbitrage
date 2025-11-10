import { JsonRpcProvider } from 'ethers';
import { HealthCheckResult, ProviderConfig, ProviderFailure, BackoffConfig } from './types/ProviderConfig';

/**
 * Health monitoring for RPC providers with exponential backoff
 *
 * Features:
 * - Periodic health checks (default: every 30 seconds)
 * - Failure detection and counting
 * - Exponential backoff for failed providers (10s → 30s → 60s → 300s)
 * - Alert emission after 3 consecutive failures
 * - Automatic recovery detection
 *
 * @example
 * ```typescript
 * const healthCheck = new HealthCheck(providerConfigs);
 *
 * healthCheck.on('failure', (failure) => {
 *   console.log(`Provider ${failure.providerName} failed: ${failure.error}`);
 * });
 *
 * healthCheck.on('alert', (failure) => {
 *   console.error(`ALERT: ${failure.providerName} has ${failure.failureCount} consecutive failures`);
 * });
 *
 * healthCheck.start();
 * ```
 */
export class HealthCheck {
  private configs: ProviderConfig[];
  private providers: Map<string, JsonRpcProvider>;
  private intervalId?: NodeJS.Timeout;
  private checkInterval: number;
  private checkTimeout: number;
  private failureCounts: Map<string, number>;
  private backoffDelays: Map<string, number>;
  private lastCheckTimes: Map<string, number>;
  private backoffConfig: BackoffConfig;
  private eventListeners: Map<string, Array<(data: any) => void>>;

  /**
   * Create a new HealthCheck instance
   *
   * @param configs - Array of provider configurations
   * @param checkInterval - Health check interval in milliseconds (default: 30000ms = 30s)
   * @param checkTimeout - Health check timeout in milliseconds (default: 5000ms = 5s)
   */
  constructor(
    configs: ProviderConfig[],
    checkInterval: number = 30000,
    checkTimeout: number = 5000
  ) {
    this.configs = configs;
    this.checkInterval = checkInterval;
    this.checkTimeout = checkTimeout;
    this.providers = new Map();
    this.failureCounts = new Map();
    this.backoffDelays = new Map();
    this.lastCheckTimes = new Map();
    this.eventListeners = new Map();

    // Exponential backoff configuration: 10s → 30s → 60s → 300s
    this.backoffConfig = {
      initialDelay: 10000,   // 10 seconds
      maxDelay: 300000,      // 5 minutes
      multiplier: 3          // 3x multiplier (10s → 30s → 60s → 180s → 300s)
    };

    // Initialize providers
    configs.forEach((config) => {
      this.providers.set(config.name, new JsonRpcProvider(config.url));
      this.failureCounts.set(config.name, 0);
      this.backoffDelays.set(config.name, this.backoffConfig.initialDelay);
      this.lastCheckTimes.set(config.name, 0);
    });

    console.log(`[HealthCheck] Initialized with ${configs.length} providers`);
    console.log(`  Check interval: ${checkInterval}ms`);
    console.log(`  Check timeout: ${checkTimeout}ms`);
  }

  /**
   * Start periodic health checks
   */
  start(): void {
    if (this.intervalId) {
      console.warn('[HealthCheck] Already running');
      return;
    }

    console.log('[HealthCheck] Starting health checks');

    // Perform initial check immediately
    this.checkAll().catch((error) => {
      console.error('[HealthCheck] Initial check failed:', error);
    });

    // Schedule periodic checks
    this.intervalId = setInterval(() => {
      this.checkAll().catch((error) => {
        console.error('[HealthCheck] Periodic check failed:', error);
      });
    }, this.checkInterval);
  }

  /**
   * Stop periodic health checks
   */
  stop(): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = undefined;
      console.log('[HealthCheck] Stopped health checks');
    }
  }

  /**
   * Check all providers
   */
  async checkAll(): Promise<HealthCheckResult[]> {
    const results = await Promise.all(
      this.configs.map((config) => this.checkProvider(config))
    );

    // Log summary
    const healthy = results.filter((r) => r.isHealthy).length;
    const unhealthy = results.length - healthy;
    console.log(`[HealthCheck] Status: ${healthy} healthy, ${unhealthy} unhealthy`);

    return results;
  }

  /**
   * Check a single provider
   */
  async checkProvider(config: ProviderConfig): Promise<HealthCheckResult> {
    const now = Date.now();
    const lastCheck = this.lastCheckTimes.get(config.name) || 0;
    const backoffDelay = this.backoffDelays.get(config.name) || this.backoffConfig.initialDelay;

    // Skip check if in backoff period
    if (now - lastCheck < backoffDelay) {
      const remainingBackoff = backoffDelay - (now - lastCheck);
      return {
        providerName: config.name,
        isHealthy: false,
        error: `In backoff period (${Math.round(remainingBackoff / 1000)}s remaining)`,
        timestamp: now,
        responseTime: 0
      };
    }

    const provider = this.providers.get(config.name);
    if (!provider) {
      throw new Error(`Provider ${config.name} not found`);
    }

    const startTime = Date.now();

    try {
      // Attempt to get block number with timeout
      const blockNumber = await Promise.race([
        provider.getBlockNumber(),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('Timeout')), this.checkTimeout)
        )
      ]);

      const responseTime = Date.now() - startTime;

      // Success: reset failure count and backoff
      this.failureCounts.set(config.name, 0);
      this.backoffDelays.set(config.name, this.backoffConfig.initialDelay);
      this.lastCheckTimes.set(config.name, now);

      const result: HealthCheckResult = {
        providerName: config.name,
        isHealthy: true,
        blockNumber,
        timestamp: now,
        responseTime
      };

      console.log(`[HealthCheck] ${config.name}: OK (block: ${blockNumber}, ${responseTime}ms)`);
      this.emit('success', result);

      return result;
    } catch (error: any) {
      const responseTime = Date.now() - startTime;

      // Increment failure count
      const failureCount = (this.failureCounts.get(config.name) || 0) + 1;
      this.failureCounts.set(config.name, failureCount);
      this.lastCheckTimes.set(config.name, now);

      // Calculate exponential backoff
      const currentBackoff = this.backoffDelays.get(config.name) || this.backoffConfig.initialDelay;
      const newBackoff = Math.min(
        currentBackoff * this.backoffConfig.multiplier,
        this.backoffConfig.maxDelay
      );
      this.backoffDelays.set(config.name, newBackoff);

      const failure: ProviderFailure = {
        providerName: config.name,
        failureCount,
        error: error.message || String(error),
        timestamp: now
      };

      console.error(
        `[HealthCheck] ${config.name}: FAILED (${failureCount} consecutive, backoff: ${newBackoff / 1000}s) - ${failure.error}`
      );

      this.emit('failure', failure);

      // Emit alert after 3 consecutive failures
      if (failureCount === 3) {
        console.error(`[HealthCheck] ALERT: ${config.name} has ${failureCount} consecutive failures`);
        this.emit('alert', failure);
      }

      return {
        providerName: config.name,
        isHealthy: false,
        error: failure.error,
        timestamp: now,
        responseTime
      };
    }
  }

  /**
   * Register event listener
   */
  on(event: 'success' | 'failure' | 'alert', callback: (data: any) => void): void {
    if (!this.eventListeners.has(event)) {
      this.eventListeners.set(event, []);
    }
    this.eventListeners.get(event)!.push(callback);
  }

  /**
   * Emit event to listeners
   */
  private emit(event: string, data: any): void {
    const listeners = this.eventListeners.get(event) || [];
    listeners.forEach((callback) => {
      try {
        callback(data);
      } catch (error) {
        console.error(`[HealthCheck] Error in ${event} listener:`, error);
      }
    });
  }

  /**
   * Get current failure count for a provider
   */
  getFailureCount(providerName: string): number {
    return this.failureCounts.get(providerName) || 0;
  }

  /**
   * Get current backoff delay for a provider
   */
  getBackoffDelay(providerName: string): number {
    return this.backoffDelays.get(providerName) || this.backoffConfig.initialDelay;
  }

  /**
   * Clean up resources
   */
  destroy(): void {
    this.stop();
    this.providers.clear();
    this.failureCounts.clear();
    this.backoffDelays.clear();
    this.lastCheckTimes.clear();
    this.eventListeners.clear();
    console.log('[HealthCheck] Destroyed');
  }
}
