import { ethers, FallbackProvider as EthersFallbackProvider, JsonRpcProvider } from 'ethers';
import { ProviderConfig } from './types/ProviderConfig';

/**
 * Multi-RPC provider with automatic failover and priority weighting
 *
 * Features:
 * - Automatic failover to backup providers on failure
 * - Priority-based provider selection (Alchemy prioritized)
 * - Stall detection and automatic retry
 * - Quorum-based consensus (configurable)
 *
 * @example
 * ```typescript
 * const provider = new FallbackProvider([
 *   { url: alchemyUrl, name: 'Alchemy', priority: 2, stallTimeout: 5000 },
 *   { url: infuraUrl, name: 'Infura', priority: 1, stallTimeout: 5000 },
 *   { url: quicknodeUrl, name: 'QuickNode', priority: 1, stallTimeout: 5000 }
 * ]);
 *
 * const blockNumber = await provider.getBlockNumber();
 * ```
 */
export class FallbackProvider {
  private provider: EthersFallbackProvider;
  private configs: ProviderConfig[];

  /**
   * Create a new FallbackProvider with multiple RPC endpoints
   *
   * @param configs - Array of provider configurations
   * @param quorum - Number of providers that must agree (default: 1)
   */
  constructor(configs: ProviderConfig[], quorum: number = 1) {
    if (configs.length === 0) {
      throw new Error('At least one provider configuration is required');
    }

    this.configs = configs;

    // Create JsonRpcProvider instances with FallbackProviderConfig
    const providers = configs.map((config) => ({
      provider: new JsonRpcProvider(config.url),
      priority: config.priority,
      stallTimeout: config.stallTimeout,
      weight: config.priority // Weight equals priority for simplicity
    }));

    // Create ethers FallbackProvider with quorum
    this.provider = new EthersFallbackProvider(providers, undefined, { quorum });

    console.log(`[FallbackProvider] Initialized with ${configs.length} providers (quorum: ${quorum})`);
    configs.forEach((config) => {
      console.log(`  - ${config.name} (priority: ${config.priority}, stall: ${config.stallTimeout}ms)`);
    });
  }

  /**
   * Get the underlying ethers FallbackProvider
   */
  getProvider(): EthersFallbackProvider {
    return this.provider;
  }

  /**
   * Get current block number
   * Automatically fails over if primary provider is unavailable
   */
  async getBlockNumber(): Promise<number> {
    try {
      return await this.provider.getBlockNumber();
    } catch (error) {
      console.error('[FallbackProvider] Error getting block number:', error);
      throw error;
    }
  }

  /**
   * Get network information
   */
  async getNetwork(): Promise<ethers.Network> {
    try {
      return await this.provider.getNetwork();
    } catch (error) {
      console.error('[FallbackProvider] Error getting network:', error);
      throw error;
    }
  }

  /**
   * Get current gas price
   */
  async getGasPrice(): Promise<bigint> {
    try {
      const feeData = await this.provider.getFeeData();
      return feeData.gasPrice || 0n;
    } catch (error) {
      console.error('[FallbackProvider] Error getting gas price:', error);
      throw error;
    }
  }

  /**
   * Get fee data (EIP-1559)
   */
  async getFeeData(): Promise<ethers.FeeData> {
    try {
      return await this.provider.getFeeData();
    } catch (error) {
      console.error('[FallbackProvider] Error getting fee data:', error);
      throw error;
    }
  }

  /**
   * Send a transaction
   */
  async sendTransaction(signedTransaction: string): Promise<ethers.TransactionResponse> {
    try {
      return await this.provider.broadcastTransaction(signedTransaction);
    } catch (error) {
      console.error('[FallbackProvider] Error sending transaction:', error);
      throw error;
    }
  }

  /**
   * Get transaction receipt
   */
  async getTransactionReceipt(txHash: string): Promise<ethers.TransactionReceipt | null> {
    try {
      return await this.provider.getTransactionReceipt(txHash);
    } catch (error) {
      console.error('[FallbackProvider] Error getting transaction receipt:', error);
      throw error;
    }
  }

  /**
   * Wait for transaction confirmation
   */
  async waitForTransaction(
    txHash: string,
    confirmations: number = 1,
    timeout?: number
  ): Promise<ethers.TransactionReceipt | null> {
    try {
      return await this.provider.waitForTransaction(txHash, confirmations, timeout);
    } catch (error) {
      console.error('[FallbackProvider] Error waiting for transaction:', error);
      throw error;
    }
  }

  /**
   * Estimate gas for a transaction
   */
  async estimateGas(transaction: ethers.TransactionRequest): Promise<bigint> {
    try {
      return await this.provider.estimateGas(transaction);
    } catch (error) {
      console.error('[FallbackProvider] Error estimating gas:', error);
      throw error;
    }
  }

  /**
   * Get provider configurations
   */
  getConfigs(): ProviderConfig[] {
    return [...this.configs];
  }

  /**
   * Destroy provider and clean up resources
   */
  async destroy(): Promise<void> {
    try {
      await this.provider.destroy();
      console.log('[FallbackProvider] Provider destroyed');
    } catch (error) {
      console.error('[FallbackProvider] Error destroying provider:', error);
      throw error;
    }
  }
}
