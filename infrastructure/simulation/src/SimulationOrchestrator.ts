import { TransactionReceipt } from 'ethers';
import { AnvilFork } from './AnvilFork';
import { ProfitCalculator } from './ProfitCalculator';
import {
  SimulationResult,
  ArbitrageParams,
  GasConfig,
  ProfitThreshold
} from './types/SimulationResult';

/**
 * Orchestrates arbitrage simulations on forked mainnet
 *
 * Complete workflow:
 * 1. Spawn Anvil fork at current block
 * 2. Send arbitrage transaction to fork
 * 3. Analyze transaction receipt for profitability
 * 4. Calculate net profit (gross - gas - flash loan fee)
 * 5. Validate against minimum profit threshold
 * 6. Clean up Anvil process
 *
 * @example
 * ```typescript
 * const orchestrator = new SimulationOrchestrator(
 *   mainnetRpcUrl,
 *   { minProfitWei: parseEther('0.01'), minProfitUsd: 30 }
 * );
 *
 * const result = await orchestrator.simulate(
 *   signedTx,
 *   arbitrageParams,
 *   gasConfig
 * );
 *
 * if (result.success && result.expectedProfit > 0) {
 *   console.log('Profitable!', result.expectedProfit);
 * }
 * ```
 */
export class SimulationOrchestrator {
  private forkRpcUrl: string;
  private profitThreshold: ProfitThreshold;
  private profitCalculator: ProfitCalculator;
  private simulationTimeout: number;

  /**
   * Create a new SimulationOrchestrator
   *
   * @param forkRpcUrl - Mainnet RPC URL for forking
   * @param profitThreshold - Minimum profit threshold
   * @param flashLoanFeeBps - Flash loan fee in basis points (default: 5 for Aave V3)
   * @param simulationTimeout - Timeout in milliseconds (default: 10000)
   */
  constructor(
    forkRpcUrl: string,
    profitThreshold: ProfitThreshold,
    flashLoanFeeBps: number = 5,
    simulationTimeout: number = 10000
  ) {
    this.forkRpcUrl = forkRpcUrl;
    this.profitThreshold = profitThreshold;
    this.profitCalculator = new ProfitCalculator(flashLoanFeeBps);
    this.simulationTimeout = simulationTimeout;
  }

  /**
   * Simulate arbitrage transaction on forked mainnet
   *
   * @param signedTransaction - Signed transaction hex
   * @param params - Arbitrage parameters
   * @param gasConfig - Gas price configuration
   * @returns Simulation result with profitability analysis
   */
  async simulate(
    signedTransaction: string,
    params: ArbitrageParams,
    gasConfig: GasConfig
  ): Promise<SimulationResult> {
    const fork = new AnvilFork(this.forkRpcUrl, undefined, this.simulationTimeout);

    try {
      console.log('[SimulationOrchestrator] Starting simulation...');

      // Start Anvil fork at current block
      await fork.start();

      const blockNumber = await fork.getBlockNumber();
      console.log(`[SimulationOrchestrator] Forked at block ${blockNumber}`);

      // Validate gas price
      if (!this.profitCalculator.validateGasPrice(gasConfig)) {
        console.warn('[SimulationOrchestrator] Gas price exceeds maximum');
        await fork.stop();

        return {
          success: false,
          error: 'Gas price exceeds maximum',
          expectedProfit: 0n,
          gasUsed: 0n,
          gasPrice: gasConfig.baseFee + gasConfig.priorityFee,
          gasCost: 0n,
          flashLoanFee: 0n,
          totalFees: 0n,
          grossProfit: 0n,
          netProfit: 0n,
          timestamp: Date.now(),
          blockNumber
        };
      }

      // Simulate transaction
      let receipt: TransactionReceipt;
      try {
        receipt = await fork.simulateTransaction({ data: signedTransaction });
      } catch (error: any) {
        console.error('[SimulationOrchestrator] Transaction simulation failed:', error);
        await fork.stop();

        return {
          success: false,
          error: error.message || String(error),
          revertReason: error.reason || error.message,
          expectedProfit: 0n,
          gasUsed: 0n,
          gasPrice: gasConfig.baseFee + gasConfig.priorityFee,
          gasCost: 0n,
          flashLoanFee: 0n,
          totalFees: 0n,
          grossProfit: 0n,
          netProfit: 0n,
          timestamp: Date.now(),
          blockNumber
        };
      }

      // Check if transaction reverted
      if (receipt.status === 0) {
        console.warn('[SimulationOrchestrator] Transaction reverted');
        await fork.stop();

        return {
          success: false,
          error: 'Transaction reverted',
          revertReason: 'Transaction reverted on-chain',
          expectedProfit: 0n,
          gasUsed: receipt.gasUsed,
          gasPrice: receipt.gasPrice || (gasConfig.baseFee + gasConfig.priorityFee),
          gasCost: receipt.gasUsed * (receipt.gasPrice || (gasConfig.baseFee + gasConfig.priorityFee)),
          flashLoanFee: 0n,
          totalFees: 0n,
          grossProfit: 0n,
          netProfit: 0n,
          receipt,
          timestamp: Date.now(),
          blockNumber
        };
      }

      console.log(`[SimulationOrchestrator] Simulation succeeded (gas: ${receipt.gasUsed})`);

      // TODO: Calculate gross profit from logs
      // For now, we'll use a placeholder calculation
      // In production, you'd parse the transaction logs to determine actual profit
      const grossProfit = params.minOut2; // Placeholder - should be calculated from logs

      // Calculate profit after fees
      const profitCalc = this.profitCalculator.calculateProfit(
        grossProfit,
        receipt.gasUsed,
        gasConfig,
        params.amount
      );

      // Build result
      const result: SimulationResult = {
        success: true,
        expectedProfit: profitCalc.netProfit || 0n,
        gasUsed: receipt.gasUsed,
        gasPrice: receipt.gasPrice || (gasConfig.baseFee + gasConfig.priorityFee),
        gasCost: profitCalc.gasCost || 0n,
        flashLoanFee: profitCalc.flashLoanFee || 0n,
        totalFees: profitCalc.totalFees || 0n,
        grossProfit: profitCalc.grossProfit || 0n,
        netProfit: profitCalc.netProfit || 0n,
        receipt,
        timestamp: Date.now(),
        blockNumber
      };

      // Validate profitability
      if (!this.profitCalculator.isProfitable(result, this.profitThreshold)) {
        console.warn(
          `[SimulationOrchestrator] Unprofitable: ${this.profitCalculator.formatProfit(result)}`
        );
        result.success = false;
        result.error = `Profit below threshold (${this.profitCalculator.formatProfit(result)})`;
      } else {
        console.log(
          `[SimulationOrchestrator] Profitable: ${this.profitCalculator.formatProfit(result)}`
        );
      }

      await fork.stop();
      return result;
    } catch (error: any) {
      console.error('[SimulationOrchestrator] Simulation error:', error);

      // Ensure fork is stopped
      if (fork.isRunning()) {
        await fork.stop();
      }

      return {
        success: false,
        error: error.message || String(error),
        expectedProfit: 0n,
        gasUsed: 0n,
        gasPrice: gasConfig.baseFee + gasConfig.priorityFee,
        gasCost: 0n,
        flashLoanFee: 0n,
        totalFees: 0n,
        grossProfit: 0n,
        netProfit: 0n,
        timestamp: Date.now(),
        blockNumber: 0
      };
    }
  }

  /**
   * Update profit threshold
   */
  setProfitThreshold(threshold: ProfitThreshold): void {
    this.profitThreshold = threshold;
  }

  /**
   * Get current profit threshold
   */
  getProfitThreshold(): ProfitThreshold {
    return { ...this.profitThreshold };
  }

  /**
   * Update flash loan fee
   */
  setFlashLoanFee(feeBps: number): void {
    this.profitCalculator.setFlashLoanFeeBps(feeBps);
  }
}
