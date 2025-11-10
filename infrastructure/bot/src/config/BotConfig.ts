/**
 * Bot configuration loaded from environment variables
 */
export interface BotConfig {
  // Network
  network: 'mainnet' | 'sepolia';
  chainId: number;

  // RPC Providers
  rpcAlchemyUrl: string;
  rpcInfuraUrl: string;
  rpcQuicknodeUrl: string;

  // Flashbots
  flashbotsEnabled: boolean;
  flashbotsRelayUrl: string;
  flashbotsAuthSigner: string;
  flashbotsMaxBlocksWait: number;

  // Simulation
  forkRpcUrl: string;
  simulationEnabled: boolean;
  simulationTimeoutMs: number;

  // Transaction Signer
  privateKey: string;

  // Contract
  flashArbContract: string;

  // Profitability
  minProfitWei: bigint;
  minProfitUsd: number;

  // Gas
  maxGasPriceGwei: number;
  priorityFeeGwei: number;

  // Monitoring
  monitorIntervalMs: number;
  healthCheckIntervalMs: number;

  // Logging
  logLevel: 'debug' | 'info' | 'warn' | 'error';
  logToFile: boolean;
  logFilePath: string;

  // Emergency
  emergencyShutdownAddress?: string;
  maxConsecutiveFailures: number;
}

/**
 * Load configuration from environment variables
 */
export function loadConfig(): BotConfig {
  return {
    network: (process.env.NETWORK as 'mainnet' | 'sepolia') || 'mainnet',
    chainId: parseInt(process.env.CHAIN_ID || '1'),

    rpcAlchemyUrl: process.env.RPC_ALCHEMY_URL || '',
    rpcInfuraUrl: process.env.RPC_INFURA_URL || '',
    rpcQuicknodeUrl: process.env.RPC_QUICKNODE_URL || '',

    flashbotsEnabled: process.env.FLASHBOTS_ENABLED === 'true',
    flashbotsRelayUrl:
      process.env.FLASHBOTS_RELAY_URL || 'https://relay.flashbots.net',
    flashbotsAuthSigner: process.env.FLASHBOTS_AUTH_SIGNER || '',
    flashbotsMaxBlocksWait: parseInt(process.env.FLASHBOTS_MAX_BLOCKS_WAIT || '25'),

    forkRpcUrl: process.env.FORK_RPC_URL || process.env.RPC_ALCHEMY_URL || '',
    simulationEnabled: process.env.SIMULATION_ENABLED === 'true',
    simulationTimeoutMs: parseInt(process.env.SIMULATION_TIMEOUT_MS || '10000'),

    privateKey: process.env.PRIVATE_KEY || '',

    flashArbContract: process.env.FLASH_ARB_CONTRACT || '',

    minProfitWei: BigInt(process.env.MIN_PROFIT_WEI || '10000000000000000'),
    minProfitUsd: parseFloat(process.env.MIN_PROFIT_USD || '30'),

    maxGasPriceGwei: parseInt(process.env.MAX_GAS_PRICE_GWEI || '100'),
    priorityFeeGwei: parseInt(process.env.PRIORITY_FEE_GWEI || '2'),

    monitorIntervalMs: parseInt(process.env.MONITOR_INTERVAL_MS || '12000'),
    healthCheckIntervalMs: parseInt(process.env.HEALTH_CHECK_INTERVAL_MS || '30000'),

    logLevel: (process.env.LOG_LEVEL as 'debug' | 'info' | 'warn' | 'error') || 'info',
    logToFile: process.env.LOG_TO_FILE === 'true',
    logFilePath: process.env.LOG_FILE_PATH || './logs/arbitrage-bot.log',

    emergencyShutdownAddress: process.env.EMERGENCY_SHUTDOWN_ADDRESS,
    maxConsecutiveFailures: parseInt(process.env.MAX_CONSECUTIVE_FAILURES || '5')
  };
}

/**
 * Validate configuration
 */
export function validateConfig(config: BotConfig): void {
  const errors: string[] = [];

  if (!config.rpcAlchemyUrl) errors.push('RPC_ALCHEMY_URL is required');
  if (!config.privateKey) errors.push('PRIVATE_KEY is required');
  if (!config.flashArbContract) errors.push('FLASH_ARB_CONTRACT is required');

  if (config.flashbotsEnabled && !config.flashbotsAuthSigner) {
    errors.push('FLASHBOTS_AUTH_SIGNER is required when Flashbots is enabled');
  }

  if (config.simulationEnabled && !config.forkRpcUrl) {
    errors.push('FORK_RPC_URL is required when simulation is enabled');
  }

  if (errors.length > 0) {
    throw new Error(`Configuration validation failed:\n${errors.join('\n')}`);
  }
}
