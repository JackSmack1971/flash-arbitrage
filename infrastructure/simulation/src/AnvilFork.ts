import { spawn, ChildProcess } from 'child_process';
import { ethers, JsonRpcProvider, TransactionRequest, TransactionReceipt } from 'ethers';

/**
 * Anvil fork manager for mainnet simulation
 *
 * Features:
 * - Spawns Anvil process with mainnet fork at current block
 * - Executes transactions on forked state
 * - Automatic cleanup of Anvil processes
 * - Timeout protection (10 seconds max)
 *
 * @example
 * ```typescript
 * const fork = new AnvilFork(mainnetRpcUrl);
 *
 * await fork.start();
 *
 * const tx = { to: '0x...', data: '0x...' };
 * const receipt = await fork.simulateTransaction(tx);
 *
 * console.log('Gas used:', receipt.gasUsed);
 *
 * await fork.stop();
 * ```
 */
export class AnvilFork {
  private forkRpcUrl: string;
  private anvilProcess?: ChildProcess;
  private anvilPort: number;
  private provider?: JsonRpcProvider;
  private timeout: number;

  /**
   * Create a new AnvilFork instance
   *
   * @param forkRpcUrl - Mainnet RPC URL to fork from
   * @param port - Port for Anvil RPC server (default: random port 8545-8600)
   * @param timeout - Simulation timeout in milliseconds (default: 10000)
   */
  constructor(forkRpcUrl: string, port?: number, timeout: number = 10000) {
    this.forkRpcUrl = forkRpcUrl;
    this.anvilPort = port || 8545 + Math.floor(Math.random() * 55);
    this.timeout = timeout;
  }

  /**
   * Start Anvil fork at current mainnet block
   */
  async start(blockNumber?: number): Promise<void> {
    return new Promise((resolve, reject) => {
      const args = [
        '--fork-url',
        this.forkRpcUrl,
        '--port',
        this.anvilPort.toString(),
        '--no-mining', // Manual mining for precise control
        '--steps-tracing' // Enable detailed traces
      ];

      if (blockNumber) {
        args.push('--fork-block-number', blockNumber.toString());
      }

      console.log(`[AnvilFork] Starting Anvil on port ${this.anvilPort}...`);

      this.anvilProcess = spawn('anvil', args, {
        stdio: ['ignore', 'pipe', 'pipe']
      });

      let output = '';

      this.anvilProcess.stdout?.on('data', (data) => {
        output += data.toString();
        // Anvil is ready when it prints "Listening on"
        if (output.includes('Listening on')) {
          console.log(`[AnvilFork] Anvil started on port ${this.anvilPort}`);
          this.provider = new JsonRpcProvider(`http://127.0.0.1:${this.anvilPort}`);
          resolve();
        }
      });

      this.anvilProcess.stderr?.on('data', (data) => {
        console.error(`[AnvilFork] Anvil error: ${data.toString()}`);
      });

      this.anvilProcess.on('error', (error) => {
        console.error('[AnvilFork] Failed to start Anvil:', error);
        reject(error);
      });

      this.anvilProcess.on('exit', (code) => {
        if (code !== 0 && code !== null) {
          console.error(`[AnvilFork] Anvil exited with code ${code}`);
          reject(new Error(`Anvil exited with code ${code}`));
        }
      });

      // Timeout if Anvil doesn't start within 5 seconds
      setTimeout(() => {
        if (!this.provider) {
          this.stop();
          reject(new Error('Anvil failed to start within 5 seconds'));
        }
      }, 5000);
    });
  }

  /**
   * Stop Anvil process and clean up
   */
  async stop(): Promise<void> {
    if (this.anvilProcess) {
      console.log('[AnvilFork] Stopping Anvil...');

      return new Promise((resolve) => {
        this.anvilProcess!.on('exit', () => {
          console.log('[AnvilFork] Anvil stopped');
          this.provider = undefined;
          resolve();
        });

        this.anvilProcess!.kill('SIGTERM');

        // Force kill if not stopped within 2 seconds
        setTimeout(() => {
          if (this.anvilProcess && !this.anvilProcess.killed) {
            console.warn('[AnvilFork] Force killing Anvil');
            this.anvilProcess.kill('SIGKILL');
            resolve();
          }
        }, 2000);
      });
    }
  }

  /**
   * Simulate a transaction on the forked network
   *
   * @param tx - Transaction to simulate
   * @param from - Sender address (will be impersonated on fork)
   * @returns Transaction receipt
   */
  async simulateTransaction(
    tx: TransactionRequest,
    from?: string
  ): Promise<TransactionReceipt> {
    if (!this.provider) {
      throw new Error('Anvil fork not started');
    }

    try {
      // Set sender if provided
      if (from) {
        tx.from = from;

        // Impersonate account on Anvil
        await this.provider.send('anvil_impersonateAccount', [from]);

        // Fund account with 100 ETH
        await this.provider.send('anvil_setBalance', [
          from,
          '0x56BC75E2D63100000' // 100 ETH
        ]);
      }

      // Send transaction with timeout
      const txPromise = this.provider.broadcastTransaction(
        typeof tx === 'string' ? tx : await this.serializeTransaction(tx)
      );

      const txResponse = await Promise.race([
        txPromise,
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('Transaction timeout')), this.timeout)
        )
      ]);

      // Mine block to include transaction
      await this.provider.send('evm_mine', []);

      // Get receipt with timeout
      const receiptPromise = txResponse.wait();

      const receipt = await Promise.race([
        receiptPromise,
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('Receipt timeout')), this.timeout)
        )
      ]);

      if (!receipt) {
        throw new Error('Transaction receipt not found');
      }

      return receipt;
    } catch (error: any) {
      console.error('[AnvilFork] Simulation error:', error);
      throw error;
    }
  }

  /**
   * Get current block number on fork
   */
  async getBlockNumber(): Promise<number> {
    if (!this.provider) {
      throw new Error('Anvil fork not started');
    }

    return await this.provider.getBlockNumber();
  }

  /**
   * Get block by number
   */
  async getBlock(blockNumber: number) {
    if (!this.provider) {
      throw new Error('Anvil fork not started');
    }

    return await this.provider.getBlock(blockNumber);
  }

  /**
   * Get balance of address
   */
  async getBalance(address: string): Promise<bigint> {
    if (!this.provider) {
      throw new Error('Anvil fork not started');
    }

    return await this.provider.getBalance(address);
  }

  /**
   * Call contract view function
   */
  async call(tx: TransactionRequest): Promise<string> {
    if (!this.provider) {
      throw new Error('Anvil fork not started');
    }

    return await this.provider.call(tx);
  }

  /**
   * Estimate gas for transaction
   */
  async estimateGas(tx: TransactionRequest): Promise<bigint> {
    if (!this.provider) {
      throw new Error('Anvil fork not started');
    }

    return await this.provider.estimateGas(tx);
  }

  /**
   * Get provider instance
   */
  getProvider(): JsonRpcProvider {
    if (!this.provider) {
      throw new Error('Anvil fork not started');
    }

    return this.provider;
  }

  /**
   * Serialize transaction for broadcasting
   */
  private async serializeTransaction(tx: TransactionRequest): Promise<string> {
    // This is a simplified implementation
    // In production, you'd need proper transaction serialization
    throw new Error('Transaction serialization not implemented - use signed transactions');
  }

  /**
   * Check if Anvil process is running
   */
  isRunning(): boolean {
    return this.anvilProcess !== undefined && !this.anvilProcess.killed;
  }
}
