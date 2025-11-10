/**
 * @flash-arbitrage/simulation
 *
 * Forked mainnet simulation for pre-flight arbitrage validation
 *
 * Features:
 * - Anvil fork management at current block
 * - Transaction simulation with profitability analysis
 * - Gas cost and flash loan fee calculations
 * - Automatic fork cleanup (no zombie processes)
 * - Timeout protection (10 seconds max)
 *
 * @example
 * ```typescript
 * import { SimulationOrchestrator } from '@flash-arbitrage/simulation';
 * import { parseEther } from 'ethers';
 *
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
 *   console.log('Profitable! Net profit:', result.netProfit);
 *   console.log('Gas cost:', result.gasCost);
 *   console.log('Flash loan fee:', result.flashLoanFee);
 * }
 * ```
 */

export { AnvilFork } from './AnvilFork';
export { ProfitCalculator } from './ProfitCalculator';
export { SimulationOrchestrator } from './SimulationOrchestrator';
export {
  SimulationResult,
  ArbitrageParams,
  GasConfig,
  ProfitThreshold
} from './types/SimulationResult';
