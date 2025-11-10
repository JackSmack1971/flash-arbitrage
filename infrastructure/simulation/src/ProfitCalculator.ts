import { SimulationResult, GasConfig, ProfitThreshold } from './types/SimulationResult';

/**
 * Profit calculator for arbitrage simulations
 *
 * Calculates:
 * - Gas costs (base fee + priority fee)
 * - Flash loan fees (Aave V3: 0.05%)
 * - Net profit after all fees
 * - Profitability validation against threshold
 *
 * @example
 * ```typescript
 * const calculator = new ProfitCalculator(5); // 5 BPS flash loan fee
 *
 * const profit = calculator.calculateProfit(
 *   grossProfit,  // 1 ETH
 *   gasUsed,      // 200,000 gas
 *   gasConfig,    // Current gas prices
 *   loanAmount    // 10 ETH
 * );
 *
 * if (calculator.isProfitable(profit, threshold)) {
 *   console.log('Profitable!', profit.netProfit);
 * }
 * ```
 */
export class ProfitCalculator {
  private flashLoanFeeBps: number;

  /**
   * Create a new ProfitCalculator
   *
   * @param flashLoanFeeBps - Flash loan fee in basis points (default: 5 for Aave V3)
   */
  constructor(flashLoanFeeBps: number = 5) {
    this.flashLoanFeeBps = flashLoanFeeBps;
  }

  /**
   * Calculate net profit after all fees
   *
   * @param grossProfit - Profit before fees (in wei)
   * @param gasUsed - Gas used by transaction
   * @param gasConfig - Gas price configuration
   * @param loanAmount - Flash loan amount (in wei)
   * @returns Partial simulation result with profit calculations
   */
  calculateProfit(
    grossProfit: bigint,
    gasUsed: bigint,
    gasConfig: GasConfig,
    loanAmount: bigint
  ): Partial<SimulationResult> {
    // Calculate total gas price (base fee + priority fee)
    const gasPrice = gasConfig.baseFee + gasConfig.priorityFee;

    // Calculate gas cost
    const gasCost = gasUsed * gasPrice;

    // Calculate flash loan fee
    const flashLoanFee = (loanAmount * BigInt(this.flashLoanFeeBps)) / 10000n;

    // Calculate total fees
    const totalFees = gasCost + flashLoanFee;

    // Calculate net profit
    const netProfit = grossProfit - totalFees;

    return {
      grossProfit,
      gasCost,
      flashLoanFee,
      totalFees,
      netProfit,
      gasUsed,
      gasPrice
    };
  }

  /**
   * Check if profit meets threshold
   *
   * @param result - Simulation result with profit calculations
   * @param threshold - Minimum profit threshold
   * @returns True if profit meets or exceeds threshold
   */
  isProfitable(result: Partial<SimulationResult>, threshold: ProfitThreshold): boolean {
    if (!result.netProfit) {
      return false;
    }

    return result.netProfit >= threshold.minProfitWei;
  }

  /**
   * Validate gas price against maximum
   *
   * @param gasConfig - Gas configuration
   * @returns True if gas price is within acceptable range
   */
  validateGasPrice(gasConfig: GasConfig): boolean {
    const totalGasPrice = gasConfig.baseFee + gasConfig.priorityFee;
    return totalGasPrice <= gasConfig.maxGasPrice;
  }

  /**
   * Calculate minimum gross profit needed for profitability
   *
   * @param gasUsed - Expected gas usage
   * @param gasConfig - Gas price configuration
   * @param loanAmount - Flash loan amount
   * @param threshold - Minimum profit threshold
   * @returns Minimum gross profit needed (in wei)
   */
  calculateMinimumGrossProfit(
    gasUsed: bigint,
    gasConfig: GasConfig,
    loanAmount: bigint,
    threshold: ProfitThreshold
  ): bigint {
    const gasPrice = gasConfig.baseFee + gasConfig.priorityFee;
    const gasCost = gasUsed * gasPrice;
    const flashLoanFee = (loanAmount * BigInt(this.flashLoanFeeBps)) / 10000n;
    const totalFees = gasCost + flashLoanFee;

    return totalFees + threshold.minProfitWei;
  }

  /**
   * Format profit for logging
   *
   * @param result - Simulation result
   * @returns Formatted profit string
   */
  formatProfit(result: Partial<SimulationResult>): string {
    if (!result.netProfit || !result.grossProfit || !result.gasCost || !result.flashLoanFee) {
      return 'N/A';
    }

    const ethProfit = Number(result.netProfit) / 1e18;
    const ethGross = Number(result.grossProfit) / 1e18;
    const ethGas = Number(result.gasCost) / 1e18;
    const ethFlashLoan = Number(result.flashLoanFee) / 1e18;

    return `Net: ${ethProfit.toFixed(6)} ETH (Gross: ${ethGross.toFixed(6)}, Gas: ${ethGas.toFixed(6)}, Flash Loan Fee: ${ethFlashLoan.toFixed(6)})`;
  }

  /**
   * Get flash loan fee in basis points
   */
  getFlashLoanFeeBps(): number {
    return this.flashLoanFeeBps;
  }

  /**
   * Update flash loan fee
   */
  setFlashLoanFeeBps(feeBps: number): void {
    if (feeBps < 0 || feeBps > 10000) {
      throw new Error('Flash loan fee must be between 0 and 10000 BPS');
    }
    this.flashLoanFeeBps = feeBps;
  }
}
