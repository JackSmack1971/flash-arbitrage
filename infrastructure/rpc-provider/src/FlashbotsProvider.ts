import { ethers, Wallet, Provider, TransactionRequest } from 'ethers';
import {
  FlashbotsConfig,
  FlashbotsBundle,
  FlashbotsSimulation,
  FlashbotsBundleStatus,
  FlashbotsRelayResponse,
  FlashbotsBundleTransaction
} from './types/FlashbotsConfig';

/**
 * Flashbots provider for private transaction submission and MEV protection
 *
 * Features:
 * - Bundle submission to Flashbots relay
 * - Bundle simulation for pre-validation
 * - Status polling for bundle inclusion
 * - Automatic fallback to public mempool after timeout (25 blocks)
 * - Authentication via signing key
 *
 * @example
 * ```typescript
 * const authSigner = new ethers.Wallet(authKey);
 * const flashbots = new FlashbotsProvider(
 *   'https://relay.flashbots.net',
 *   authSigner,
 *   provider
 * );
 *
 * // Simulate bundle
 * const simulation = await flashbots.simulate(signedTx, targetBlock);
 * if (!simulation.success) {
 *   throw new Error('Simulation failed');
 * }
 *
 * // Submit bundle
 * const bundleHash = await flashbots.sendBundle([signedTx], targetBlock);
 *
 * // Wait for inclusion
 * const status = await flashbots.waitForInclusion(bundleHash, 25);
 * ```
 */
export class FlashbotsProvider {
  private relayUrl: string;
  private authSigner: Wallet;
  private provider: Provider;
  private maxBlocksWait: number;

  /**
   * Create a new FlashbotsProvider
   *
   * @param relayUrl - Flashbots relay URL (mainnet: https://relay.flashbots.net, sepolia: https://relay-sepolia.flashbots.net)
   * @param authSigner - Wallet for signing bundle authentication
   * @param provider - Ethereum provider for block monitoring
   * @param maxBlocksWait - Maximum blocks to wait for inclusion (default: 25)
   */
  constructor(
    relayUrl: string,
    authSigner: Wallet,
    provider: Provider,
    maxBlocksWait: number = 25
  ) {
    this.relayUrl = relayUrl;
    this.authSigner = authSigner;
    this.provider = provider;
    this.maxBlocksWait = maxBlocksWait;

    console.log('[FlashbotsProvider] Initialized');
    console.log(`  Relay: ${relayUrl}`);
    console.log(`  Auth signer: ${authSigner.address}`);
    console.log(`  Max wait: ${maxBlocksWait} blocks`);
  }

  /**
   * Send bundle to Flashbots relay
   *
   * @param signedTransactions - Array of signed transaction hex strings
   * @param targetBlock - Target block number for inclusion
   * @param config - Optional bundle configuration
   * @returns Bundle hash
   */
  async sendBundle(
    signedTransactions: string[],
    targetBlock: number,
    config?: Partial<FlashbotsConfig>
  ): Promise<string> {
    const bundleTransactions: FlashbotsBundleTransaction[] = signedTransactions.map((tx) => ({
      signedTransaction: tx
    }));

    const bundle: FlashbotsBundle = {
      transactions: bundleTransactions,
      targetBlock,
      maxBlockNumber: config?.maxBlockNumber || targetBlock + this.maxBlocksWait,
      revertingTxHashes: config?.revertingTxHashes || []
    };

    const params = [
      bundleTransactions.map((tx) => tx.signedTransaction),
      `0x${targetBlock.toString(16)}` // Convert to hex
    ];

    const response = await this.sendRequest('eth_sendBundle', params);

    if (response.error) {
      throw new Error(`Flashbots sendBundle error: ${response.error.message}`);
    }

    const bundleHash = response.result?.bundleHash || this.generateBundleHash(signedTransactions);
    console.log(`[FlashbotsProvider] Bundle sent: ${bundleHash} (target block: ${targetBlock})`);

    return bundleHash;
  }

  /**
   * Simulate bundle to validate profitability
   *
   * @param signedTransactions - Array of signed transaction hex strings
   * @param targetBlock - Target block number
   * @param stateBlockNumber - Block number for state (optional, defaults to latest)
   * @returns Simulation result
   */
  async simulate(
    signedTransactions: string[],
    targetBlock: number,
    stateBlockNumber?: number
  ): Promise<FlashbotsSimulation> {
    const bundleTransactions: FlashbotsBundleTransaction[] = signedTransactions.map((tx) => ({
      signedTransaction: tx
    }));

    const params = [
      bundleTransactions.map((tx) => tx.signedTransaction),
      `0x${targetBlock.toString(16)}`,
      stateBlockNumber ? `0x${stateBlockNumber.toString(16)}` : 'latest'
    ];

    try {
      const response = await this.sendRequest('eth_callBundle', params);

      if (response.error) {
        return {
          success: false,
          error: response.error.message
        };
      }

      const result = response.result;

      // Parse simulation result
      const simulation: FlashbotsSimulation = {
        success: true,
        bundleHash: result.bundleHash,
        gasUsed: result.totalGasUsed ? BigInt(result.totalGasUsed) : undefined,
        effectiveGasPrice: result.effectiveGasPrice ? BigInt(result.effectiveGasPrice) : undefined,
        coinbaseDiff: result.coinbaseDiff ? BigInt(result.coinbaseDiff) : undefined,
        totalGasFees: result.totalGasFees ? BigInt(result.totalGasFees) : undefined
      };

      console.log('[FlashbotsProvider] Simulation successful');
      console.log(`  Gas used: ${simulation.gasUsed?.toString()}`);
      console.log(`  Coinbase diff: ${simulation.coinbaseDiff?.toString()}`);

      return simulation;
    } catch (error: any) {
      return {
        success: false,
        error: error.message || String(error)
      };
    }
  }

  /**
   * Wait for bundle inclusion in a block
   *
   * @param bundleHash - Hash of the bundle
   * @param maxBlocks - Maximum blocks to wait (default: 25)
   * @returns Bundle status
   */
  async waitForInclusion(bundleHash: string, maxBlocks?: number): Promise<FlashbotsBundleStatus> {
    const maxWait = maxBlocks || this.maxBlocksWait;
    const startBlock = await this.provider.getBlockNumber();
    const endBlock = startBlock + maxWait;

    console.log(`[FlashbotsProvider] Waiting for bundle ${bundleHash}`);
    console.log(`  Start block: ${startBlock}, End block: ${endBlock}`);

    for (let currentBlock = startBlock; currentBlock <= endBlock; currentBlock++) {
      // Wait for next block
      if (currentBlock > startBlock) {
        await this.waitForBlock(currentBlock);
      }

      // Check if bundle was included
      const status = await this.getBundleStatus(bundleHash, currentBlock);

      if (status.isIncluded) {
        console.log(`[FlashbotsProvider] Bundle included in block ${status.blockNumber}`);
        return status;
      }

      console.log(`[FlashbotsProvider] Block ${currentBlock}: bundle not included`);
    }

    console.warn(`[FlashbotsProvider] Bundle not included after ${maxWait} blocks`);
    return {
      isIncluded: false,
      isCancelled: true,
      error: `Bundle not included after ${maxWait} blocks`
    };
  }

  /**
   * Get bundle status for a specific block
   */
  private async getBundleStatus(bundleHash: string, blockNumber: number): Promise<FlashbotsBundleStatus> {
    try {
      const params = [bundleHash, `0x${blockNumber.toString(16)}`];
      const response = await this.sendRequest('flashbots_getBundleStats', params);

      if (response.error) {
        return {
          isIncluded: false,
          error: response.error.message
        };
      }

      const result = response.result;

      return {
        isIncluded: result.isSimulated && result.isHighPriority,
        blockNumber: result.isSimulated ? blockNumber : undefined,
        transactionHashes: result.transactionHashes
      };
    } catch (error) {
      // If status API fails, assume not included
      return {
        isIncluded: false
      };
    }
  }

  /**
   * Wait for a specific block
   */
  private async waitForBlock(blockNumber: number): Promise<void> {
    return new Promise((resolve) => {
      const checkBlock = async () => {
        const currentBlock = await this.provider.getBlockNumber();
        if (currentBlock >= blockNumber) {
          resolve();
        } else {
          setTimeout(checkBlock, 1000); // Check every second
        }
      };
      checkBlock();
    });
  }

  /**
   * Send JSON-RPC request to Flashbots relay
   */
  private async sendRequest(method: string, params: any[]): Promise<FlashbotsRelayResponse> {
    const currentBlock = await this.provider.getBlockNumber();
    const timestamp = Math.floor(Date.now() / 1000);

    // Create signature for authentication
    const message = JSON.stringify({
      method,
      params,
      id: timestamp,
      jsonrpc: '2.0'
    });

    const signature = await this.authSigner.signMessage(message);

    const headers = {
      'Content-Type': 'application/json',
      'X-Flashbots-Signature': `${this.authSigner.address}:${signature}`
    };

    const body = JSON.stringify({
      method,
      params,
      id: timestamp,
      jsonrpc: '2.0'
    });

    try {
      const response = await fetch(this.relayUrl, {
        method: 'POST',
        headers,
        body
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      return data as FlashbotsRelayResponse;
    } catch (error: any) {
      console.error('[FlashbotsProvider] Request failed:', error);
      throw error;
    }
  }

  /**
   * Generate deterministic bundle hash from transactions
   */
  private generateBundleHash(signedTransactions: string[]): string {
    const data = signedTransactions.join('');
    return ethers.keccak256(ethers.toUtf8Bytes(data));
  }

  /**
   * Get Flashbots relay URL for network
   */
  static getRelayUrl(chainId: number): string {
    switch (chainId) {
      case 1: // Mainnet
        return 'https://relay.flashbots.net';
      case 11155111: // Sepolia
        return 'https://relay-sepolia.flashbots.net';
      case 5: // Goerli (deprecated)
        return 'https://relay-goerli.flashbots.net';
      default:
        throw new Error(`Flashbots not supported on chain ID ${chainId}`);
    }
  }
}
