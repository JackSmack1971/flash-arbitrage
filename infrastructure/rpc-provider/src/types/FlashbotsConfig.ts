import { TransactionRequest } from 'ethers';

/**
 * Configuration for Flashbots bundle submission
 */
export interface FlashbotsConfig {
  /** Flashbots relay RPC URL */
  relayUrl: string;

  /** Target block number for bundle inclusion */
  targetBlock: number;

  /** Maximum block number (bundle expires after this) */
  maxBlockNumber?: number;

  /** Transaction hashes that are allowed to revert */
  revertingTxHashes?: string[];

  /** Minimum timestamp for bundle (optional) */
  minTimestamp?: number;

  /** Maximum timestamp for bundle (optional) */
  maxTimestamp?: number;
}

/**
 * Flashbots bundle transaction
 */
export interface FlashbotsBundleTransaction {
  /** Signed transaction hex */
  signedTransaction: string;

  /** Transaction request (for simulation) */
  transaction?: TransactionRequest;
}

/**
 * Flashbots bundle
 */
export interface FlashbotsBundle {
  /** Array of signed transactions */
  transactions: FlashbotsBundleTransaction[];

  /** Target block number */
  targetBlock: number;

  /** Maximum block number */
  maxBlockNumber?: number;

  /** Reverting transaction hashes */
  revertingTxHashes?: string[];
}

/**
 * Flashbots simulation result
 */
export interface FlashbotsSimulation {
  /** Whether simulation succeeded */
  success: boolean;

  /** Error message (if failed) */
  error?: string;

  /** Gas used */
  gasUsed?: bigint;

  /** Effective gas price */
  effectiveGasPrice?: bigint;

  /** Coinbase payment */
  coinbaseDiff?: bigint;

  /** Total gas fees */
  totalGasFees?: bigint;

  /** Bundle hash */
  bundleHash?: string;
}

/**
 * Flashbots bundle status
 */
export interface FlashbotsBundleStatus {
  /** Whether bundle was included */
  isIncluded: boolean;

  /** Block number where included (if applicable) */
  blockNumber?: number;

  /** Transaction hashes in bundle */
  transactionHashes?: string[];

  /** Whether bundle was cancelled */
  isCancelled?: boolean;

  /** Error message (if any) */
  error?: string;
}

/**
 * Flashbots relay response
 */
export interface FlashbotsRelayResponse {
  /** JSON-RPC ID */
  id: number;

  /** JSON-RPC version */
  jsonrpc: string;

  /** Result (if successful) */
  result?: any;

  /** Error (if failed) */
  error?: {
    code: number;
    message: string;
    data?: any;
  };
}
