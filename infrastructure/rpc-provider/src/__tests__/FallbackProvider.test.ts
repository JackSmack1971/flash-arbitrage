import { FallbackProvider } from '../FallbackProvider';
import { ProviderConfig } from '../types/ProviderConfig';

describe('FallbackProvider', () => {
  const mockConfigs: ProviderConfig[] = [
    {
      url: 'https://eth-mainnet.g.alchemy.com/v2/test-key-1',
      name: 'Alchemy',
      priority: 2,
      stallTimeout: 5000
    },
    {
      url: 'https://mainnet.infura.io/v3/test-key-2',
      name: 'Infura',
      priority: 1,
      stallTimeout: 5000
    },
    {
      url: 'https://test.quiknode.pro/test-key-3',
      name: 'QuickNode',
      priority: 1,
      stallTimeout: 5000
    }
  ];

  describe('constructor', () => {
    it('should initialize with 3 endpoints', () => {
      const provider = new FallbackProvider(mockConfigs);
      expect(provider).toBeDefined();
      expect(provider.getConfigs()).toHaveLength(3);
    });

    it('should initialize with correct priority weights', () => {
      const provider = new FallbackProvider(mockConfigs);
      const configs = provider.getConfigs();

      expect(configs[0].priority).toBe(2); // Alchemy
      expect(configs[1].priority).toBe(1); // Infura
      expect(configs[2].priority).toBe(1); // QuickNode
    });

    it('should initialize with correct stall timeout configuration', () => {
      const provider = new FallbackProvider(mockConfigs);
      const configs = provider.getConfigs();

      configs.forEach((config) => {
        expect(config.stallTimeout).toBe(5000);
      });
    });

    it('should throw error when initialized with empty config array', () => {
      expect(() => new FallbackProvider([])).toThrow(
        'At least one provider configuration is required'
      );
    });

    it('should accept custom quorum parameter', () => {
      const provider = new FallbackProvider(mockConfigs, 2);
      expect(provider).toBeDefined();
    });
  });

  describe('getConfigs', () => {
    it('should return copy of configurations', () => {
      const provider = new FallbackProvider(mockConfigs);
      const configs = provider.getConfigs();

      // Modify returned configs
      configs[0].priority = 999;

      // Original configs should be unchanged
      const freshConfigs = provider.getConfigs();
      expect(freshConfigs[0].priority).toBe(2);
    });
  });

  describe('getProvider', () => {
    it('should return underlying ethers FallbackProvider', () => {
      const provider = new FallbackProvider(mockConfigs);
      const ethersProvider = provider.getProvider();

      expect(ethersProvider).toBeDefined();
      expect(typeof ethersProvider.getBlockNumber).toBe('function');
    });
  });

  describe('destroy', () => {
    it('should clean up resources without throwing', async () => {
      const provider = new FallbackProvider(mockConfigs);
      await expect(provider.destroy()).resolves.not.toThrow();
    });
  });

  describe('configuration validation', () => {
    it('should accept single provider configuration', () => {
      const singleConfig: ProviderConfig[] = [
        {
          url: 'https://eth-mainnet.g.alchemy.com/v2/test-key',
          name: 'Alchemy',
          priority: 1,
          stallTimeout: 5000
        }
      ];

      const provider = new FallbackProvider(singleConfig);
      expect(provider.getConfigs()).toHaveLength(1);
    });

    it('should preserve provider order', () => {
      const provider = new FallbackProvider(mockConfigs);
      const configs = provider.getConfigs();

      expect(configs[0].name).toBe('Alchemy');
      expect(configs[1].name).toBe('Infura');
      expect(configs[2].name).toBe('QuickNode');
    });
  });
});
