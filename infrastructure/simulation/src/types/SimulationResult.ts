import { TransactionReceipt, TransactionRequest } from 'ethers';

/**
 * Simulation result with profitability analysis
 */
export interface SimulationResult {
  /** Whether simulation succeeded */
  success: boolean;

  /** Expected profit in wei (after all fees) */
  expectedProfit: bigint;

  /** Gas used by transaction */
  gasUsed: bigint;

  /** Gas price used (base fee + priority fee) */
  gasPrice: bigint;

  /** Total gas cost in wei */
  gasCost: bigint;

  /** Flash loan fee in wei */
  flashLoanFee: bigint;

  /** Total fees (gas + flash loan) in wei */
  totalFees: bigint;

  /** Gross profit before fees */
  grossProfit: bigint;

  /** Net profit after fees */
  netProfit: bigint;

  /** Revert reason (if simulation failed) */
  revertReason?: string;

  /** Error message (if simulation failed) */
  error?: string;

  /** Transaction receipt (if simulation succeeded) */
  receipt?: TransactionReceipt;

  /** Simulation timestamp */
  timestamp: number;

  /** Block number used for simulation */
  blockNumber: number;
}

/**
 * Arbitrage parameters for simulation
 */
export interface ArbitrageParams {
  /** Flash loan asset address */
  asset: string;

  /** Flash loan amount in wei */
  amount: bigint;

  /** First DEX router address */
  router1: string;

  /** Second DEX router address */
  router2: string;

  /** Swap path for first DEX */
  path1: string[];

  /** Swap path for second DEX */
  path2: string[];

  /** Minimum acceptable output for first swap */
  minOut1: bigint;

  /** Minimum acceptable output for second swap */
  minOut2: bigint;

  /** Deadline for transaction */
  deadline: number;
}

/**
 * Gas estimation configuration
 */
export interface GasConfig {
  /** Maximum gas price in wei */
  maxGasPrice: bigint;

  /** Base fee per gas (from block) */
  baseFee: bigint;

  /** Priority fee per gas */
  priorityFee: bigint;

  /** Gas limit */
  gasLimit: bigint;
}

/**
 * Profit threshold configuration
 */
export interface ProfitThreshold {
  /** Minimum profit in wei */
  minProfitWei: bigint;

  /** Minimum profit in USD (for logging) */
  minProfitUsd: number;
}
