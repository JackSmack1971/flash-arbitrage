/**
 * Configuration for a single RPC provider
 */
export interface ProviderConfig {
  /** RPC endpoint URL */
  url: string;
  /** Provider name for logging */
  name: string;
  /** Priority weight (higher = preferred) */
  priority: number;
  /** Stall timeout in milliseconds */
  stallTimeout: number;
}

/**
 * Health check result for a provider
 */
export interface HealthCheckResult {
  /** Provider name */
  providerName: string;
  /** Whether the provider is healthy */
  isHealthy: boolean;
  /** Current block number (if healthy) */
  blockNumber?: number;
  /** Error message (if unhealthy) */
  error?: string;
  /** Timestamp of check */
  timestamp: number;
  /** Response time in milliseconds */
  responseTime: number;
}

/**
 * Provider failure event
 */
export interface ProviderFailure {
  /** Provider name */
  providerName: string;
  /** Consecutive failure count */
  failureCount: number;
  /** Error message */
  error: string;
  /** Timestamp of failure */
  timestamp: number;
}

/**
 * Exponential backoff configuration
 */
export interface BackoffConfig {
  /** Initial delay in milliseconds */
  initialDelay: number;
  /** Maximum delay in milliseconds */
  maxDelay: number;
  /** Backoff multiplier */
  multiplier: number;
}
