import { ethers, Wallet } from 'ethers';
import { FlashbotsProvider } from '../FlashbotsProvider';

describe('FlashbotsProvider', () => {
  let authSigner: Wallet;
  let mockProvider: any;

  beforeEach(() => {
    // Create auth signer
    authSigner = ethers.Wallet.createRandom();

    // Mock provider
    mockProvider = {
      getBlockNumber: jest.fn().mockResolvedValue(1000000),
      getNetwork: jest.fn().mockResolvedValue({ chainId: 1n })
    };
  });

  describe('constructor', () => {
    it('should initialize with correct configuration', () => {
      const flashbots = new FlashbotsProvider(
        'https://relay.flashbots.net',
        authSigner,
        mockProvider,
        25
      );

      expect(flashbots).toBeDefined();
    });

    it('should use default max blocks wait (25)', () => {
      const flashbots = new FlashbotsProvider(
        'https://relay.flashbots.net',
        authSigner,
        mockProvider
      );

      expect(flashbots).toBeDefined();
    });
  });

  describe('getRelayUrl', () => {
    it('should return mainnet relay URL for chain ID 1', () => {
      const url = FlashbotsProvider.getRelayUrl(1);
      expect(url).toBe('https://relay.flashbots.net');
    });

    it('should return Sepolia relay URL for chain ID 11155111', () => {
      const url = FlashbotsProvider.getRelayUrl(11155111);
      expect(url).toBe('https://relay-sepolia.flashbots.net');
    });

    it('should return Goerli relay URL for chain ID 5', () => {
      const url = FlashbotsProvider.getRelayUrl(5);
      expect(url).toBe('https://relay-goerli.flashbots.net');
    });

    it('should throw error for unsupported chain ID', () => {
      expect(() => FlashbotsProvider.getRelayUrl(999)).toThrow(
        'Flashbots not supported on chain ID 999'
      );
    });
  });

  describe('sendBundle', () => {
    it('should construct bundle with correct transaction format', async () => {
      const flashbots = new FlashbotsProvider(
        'https://relay.flashbots.net',
        authSigner,
        mockProvider
      );

      const mockTx = '0x02f873...'; // Mock signed transaction
      const targetBlock = 1000001;

      // Mock fetch globally
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          jsonrpc: '2.0',
          id: Date.now(),
          result: {
            bundleHash: '0xabc123...'
          }
        })
      });

      const bundleHash = await flashbots.sendBundle([mockTx], targetBlock);

      expect(bundleHash).toBeDefined();
      expect(typeof bundleHash).toBe('string');

      // Verify fetch was called
      expect(global.fetch).toHaveBeenCalled();
    });

    it('should include authentication signature in request headers', async () => {
      const flashbots = new FlashbotsProvider(
        'https://relay.flashbots.net',
        authSigner,
        mockProvider
      );

      const mockTx = '0x02f873...';
      const targetBlock = 1000001;

      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          jsonrpc: '2.0',
          id: Date.now(),
          result: {
            bundleHash: '0xabc123...'
          }
        })
      });

      await flashbots.sendBundle([mockTx], targetBlock);

      // Verify fetch was called with correct headers
      expect(global.fetch).toHaveBeenCalledWith(
        'https://relay.flashbots.net',
        expect.objectContaining({
          method: 'POST',
          headers: expect.objectContaining({
            'Content-Type': 'application/json',
            'X-Flashbots-Signature': expect.stringContaining(authSigner.address)
          })
        })
      );
    });

    it('should throw error on Flashbots API error', async () => {
      const flashbots = new FlashbotsProvider(
        'https://relay.flashbots.net',
        authSigner,
        mockProvider
      );

      const mockTx = '0x02f873...';
      const targetBlock = 1000001;

      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          jsonrpc: '2.0',
          id: Date.now(),
          error: {
            code: -32000,
            message: 'Bundle validation failed'
          }
        })
      });

      await expect(flashbots.sendBundle([mockTx], targetBlock)).rejects.toThrow(
        'Flashbots sendBundle error: Bundle validation failed'
      );
    });
  });

  describe('simulate', () => {
    it('should return successful simulation result', async () => {
      const flashbots = new FlashbotsProvider(
        'https://relay.flashbots.net',
        authSigner,
        mockProvider
      );

      const mockTx = '0x02f873...';
      const targetBlock = 1000001;

      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          jsonrpc: '2.0',
          id: Date.now(),
          result: {
            bundleHash: '0xabc123...',
            totalGasUsed: '0x5208',
            effectiveGasPrice: '0x3b9aca00',
            coinbaseDiff: '0x1bc16d674ec80000',
            totalGasFees: '0x1234'
          }
        })
      });

      const simulation = await flashbots.simulate([mockTx], targetBlock);

      expect(simulation.success).toBe(true);
      expect(simulation.bundleHash).toBe('0xabc123...');
      expect(simulation.gasUsed).toBeDefined();
      expect(simulation.coinbaseDiff).toBeDefined();
    });

    it('should return error on simulation failure', async () => {
      const flashbots = new FlashbotsProvider(
        'https://relay.flashbots.net',
        authSigner,
        mockProvider
      );

      const mockTx = '0x02f873...';
      const targetBlock = 1000001;

      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          jsonrpc: '2.0',
          id: Date.now(),
          error: {
            code: -32000,
            message: 'Simulation reverted'
          }
        })
      });

      const simulation = await flashbots.simulate([mockTx], targetBlock);

      expect(simulation.success).toBe(false);
      expect(simulation.error).toBe('Simulation reverted');
    });

    it('should accept optional state block number', async () => {
      const flashbots = new FlashbotsProvider(
        'https://relay.flashbots.net',
        authSigner,
        mockProvider
      );

      const mockTx = '0x02f873...';
      const targetBlock = 1000001;
      const stateBlock = 1000000;

      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          jsonrpc: '2.0',
          id: Date.now(),
          result: {
            bundleHash: '0xabc123...'
          }
        })
      });

      await flashbots.simulate([mockTx], targetBlock, stateBlock);

      expect(global.fetch).toHaveBeenCalled();
    });
  });

  describe('waitForInclusion', () => {
    it('should detect bundle inclusion', async () => {
      const flashbots = new FlashbotsProvider(
        'https://relay.flashbots.net',
        authSigner,
        mockProvider
      );

      const bundleHash = '0xabc123...';

      // Mock provider to advance blocks
      let currentBlock = 1000000;
      mockProvider.getBlockNumber.mockImplementation(() => {
        return Promise.resolve(currentBlock++);
      });

      // Mock fetch for bundle status
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          jsonrpc: '2.0',
          id: Date.now(),
          result: {
            isSimulated: true,
            isHighPriority: true,
            transactionHashes: ['0xtx1...']
          }
        })
      });

      const status = await flashbots.waitForInclusion(bundleHash, 3);

      expect(status.isIncluded).toBe(true);
      expect(status.blockNumber).toBeDefined();
    });

    it('should timeout after maximum blocks', async () => {
      jest.setTimeout(15000); // Increase timeout for this test

      const flashbots = new FlashbotsProvider(
        'https://relay.flashbots.net',
        authSigner,
        mockProvider
      );

      const bundleHash = '0xabc123...';

      // Mock provider to advance blocks quickly
      let currentBlock = 1000000;
      mockProvider.getBlockNumber.mockImplementation(() => {
        return Promise.resolve(currentBlock++);
      });

      // Mock fetch for bundle status (always not included)
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          jsonrpc: '2.0',
          id: Date.now(),
          result: {
            isSimulated: false,
            isHighPriority: false
          }
        })
      });

      const status = await flashbots.waitForInclusion(bundleHash, 2);

      expect(status.isIncluded).toBe(false);
      expect(status.isCancelled).toBe(true);
      expect(status.error).toContain('not included after');
    });
  });
});
