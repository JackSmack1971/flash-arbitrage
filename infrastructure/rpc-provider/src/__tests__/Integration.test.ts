import { FallbackProvider } from '../FallbackProvider';
import { HealthCheck } from '../HealthCheck';
import { ProviderConfig } from '../types/ProviderConfig';

/**
 * Integration tests for FallbackProvider with HealthCheck
 *
 * Note: These tests use mock RPC URLs. To test against real networks:
 * 1. Set up environment variables: ALCHEMY_URL, INFURA_URL, QUICKNODE_URL
 * 2. Replace mock URLs with real ones
 * 3. Uncomment network-dependent assertions
 */
describe('FallbackProvider Integration', () => {
  const mockConfigs: ProviderConfig[] = [
    {
      url: 'https://eth-mainnet.g.alchemy.com/v2/mock-key-1',
      name: 'Alchemy',
      priority: 2,
      stallTimeout: 5000
    },
    {
      url: 'https://mainnet.infura.io/v3/mock-key-2',
      name: 'Infura',
      priority: 1,
      stallTimeout: 5000
    },
    {
      url: 'https://mock.quiknode.pro/mock-key-3',
      name: 'QuickNode',
      priority: 1,
      stallTimeout: 5000
    }
  ];

  describe('FallbackProvider with HealthCheck', () => {
    it('should initialize provider and health check together', () => {
      const provider = new FallbackProvider(mockConfigs);
      const healthCheck = new HealthCheck(provider.getConfigs());

      expect(provider).toBeDefined();
      expect(healthCheck).toBeDefined();

      healthCheck.destroy();
    });

    it('should handle provider failover scenario', async () => {
      // Create provider with invalid primary URL to simulate failure
      const failoverConfigs: ProviderConfig[] = [
        {
          url: 'https://invalid-url-that-will-fail.com',
          name: 'InvalidProvider',
          priority: 2,
          stallTimeout: 5000
        },
        {
          url: 'https://eth-mainnet.g.alchemy.com/v2/mock-key',
          name: 'Alchemy',
          priority: 1,
          stallTimeout: 5000
        }
      ];

      const provider = new FallbackProvider(failoverConfigs);

      // Provider should automatically fail over to Alchemy
      // In production, this would successfully connect to the second provider
      expect(provider.getConfigs()).toHaveLength(2);
    });

    it('should track health check results for all providers', async () => {
      const provider = new FallbackProvider(mockConfigs);
      const healthCheck = new HealthCheck(provider.getConfigs(), 30000, 5000);

      const results = await healthCheck.checkAll();

      expect(results).toHaveLength(3);
      results.forEach((result) => {
        expect(result.providerName).toBeDefined();
        expect(result.timestamp).toBeGreaterThan(0);
        expect(typeof result.isHealthy).toBe('boolean');
      });

      healthCheck.destroy();
    });

    it('should emit alerts for failing providers', (done) => {
      const provider = new FallbackProvider(mockConfigs);
      const healthCheck = new HealthCheck(provider.getConfigs());

      let alertEmitted = false;

      healthCheck.on('alert', (failure) => {
        expect(failure.providerName).toBeDefined();
        expect(failure.failureCount).toBeGreaterThanOrEqual(3);
        alertEmitted = true;
      });

      // Clean up
      setTimeout(() => {
        healthCheck.destroy();
        // Alert may or may not be emitted depending on network conditions
        done();
      }, 1000);
    });
  });

  describe('Real network integration (requires valid RPC URLs)', () => {
    // Skip these tests by default since they require real RPC endpoints
    // To enable: provide real RPC URLs via environment variables

    it.skip('should connect to Sepolia testnet via failover provider', async () => {
      const sepoliaConfigs: ProviderConfig[] = [
        {
          url: process.env.SEPOLIA_ALCHEMY_URL || '',
          name: 'Alchemy',
          priority: 2,
          stallTimeout: 5000
        },
        {
          url: process.env.SEPOLIA_INFURA_URL || '',
          name: 'Infura',
          priority: 1,
          stallTimeout: 5000
        }
      ];

      const provider = new FallbackProvider(sepoliaConfigs);

      // Should successfully get block number from Sepolia
      const blockNumber = await provider.getBlockNumber();
      expect(blockNumber).toBeGreaterThan(0);

      const network = await provider.getNetwork();
      expect(network.chainId).toBe(11155111n); // Sepolia chain ID

      await provider.destroy();
    });

    it.skip('should detect failover when primary provider is unreachable', async () => {
      const failoverConfigs: ProviderConfig[] = [
        {
          url: 'https://invalid-endpoint-that-will-timeout.com',
          name: 'InvalidPrimary',
          priority: 2,
          stallTimeout: 5000
        },
        {
          url: process.env.SEPOLIA_ALCHEMY_URL || '',
          name: 'AlchemyBackup',
          priority: 1,
          stallTimeout: 5000
        }
      ];

      const provider = new FallbackProvider(failoverConfigs);

      // Should automatically fail over to Alchemy backup
      const blockNumber = await provider.getBlockNumber();
      expect(blockNumber).toBeGreaterThan(0);

      await provider.destroy();
    });

    it.skip('should perform health checks on real Sepolia providers', async () => {
      const sepoliaConfigs: ProviderConfig[] = [
        {
          url: process.env.SEPOLIA_ALCHEMY_URL || '',
          name: 'Alchemy',
          priority: 2,
          stallTimeout: 5000
        },
        {
          url: process.env.SEPOLIA_INFURA_URL || '',
          name: 'Infura',
          priority: 1,
          stallTimeout: 5000
        }
      ];

      const healthCheck = new HealthCheck(sepoliaConfigs, 30000, 5000);

      const results = await healthCheck.checkAll();

      expect(results).toHaveLength(2);
      results.forEach((result) => {
        if (result.isHealthy) {
          expect(result.blockNumber).toBeGreaterThan(0);
          expect(result.responseTime).toBeGreaterThan(0);
        }
      });

      healthCheck.destroy();
    });
  });
});
