/**
 * @flash-arbitrage/bot
 *
 * Arbitrage bot orchestrator integrating all infrastructure components
 *
 * NOTE: This is a production-ready framework requiring opportunity detection
 * integration (future work: multi-DEX scanner, price monitoring, etc.)
 *
 * @example
 * ```typescript
 * import { ArbitrageBot, loadConfig, validateConfig } from '@flash-arbitrage/bot';
 * import dotenv from 'dotenv';
 *
 * dotenv.config();
 *
 * const config = loadConfig();
 * validateConfig(config);
 *
 * const bot = new ArbitrageBot(config);
 *
 * await bot.start();
 *
 * // Graceful shutdown
 * process.on('SIGINT', async () => {
 *   console.log('Shutting down gracefully...');
 *   await bot.stop();
 *   process.exit(0);
 * });
 * ```
 */

export { ArbitrageBot } from './ArbitrageBot';
export { BotConfig, loadConfig, validateConfig } from './config/BotConfig';
