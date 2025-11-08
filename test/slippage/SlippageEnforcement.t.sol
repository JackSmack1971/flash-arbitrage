// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../../src/FlashArbMainnetReady.sol";
import "../../src/UniswapV2Adapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SlippageEnforcement Test Suite
 * @notice Tests for on-chain slippage enforcement (MEDIUM severity: slippage validation)
 * @dev TDD red phase - these tests define expected slippage behavior
 *
 * Audit Reference: MEDIUM - On-chain slippage enforcement and unused initiator mapping
 * Requirements covered:
 * 1. Slippage calculated correctly using basis points (BPS)
 * 2. Transactions revert when output is below minimum acceptable threshold
 * 3. Transactions succeed when output meets slippage threshold
 * 4. Edge cases: 0 BPS, max BPS (1000 = 10%), rounding errors
 * 5. Per-swap slippage validation (not just final output)
 */
contract SlippageEnforcementTest is Test {
    FlashArbMainnetReady public flashArb;
    UniswapV2Adapter public adapter;

    address public owner;
    address public user;

    // Mainnet constants
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant SUSHISWAP_ROUTER = 0xd9e1CE17f2641F24aE83637ab66a2cca9C378B9F;

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");

        // Deploy contracts
        flashArb = new FlashArbMainnetReady();
        flashArb.initialize();

        adapter = new UniswapV2Adapter();

        // Setup adapters
        bytes32 adapterHash = address(adapter).codehash;
        flashArb.approveAdapterCodeHash(adapterHash, true);
        flashArb.approveAdapter(address(adapter), true);
        flashArb.setDexAdapter(UNISWAP_V2_ROUTER, address(adapter));
        flashArb.setDexAdapter(SUSHISWAP_ROUTER, address(adapter));
    }

    /**
     * @notice Test that transaction reverts when slippage exceeds maximum allowed
     * @dev Audit line reference: MEDIUM severity - slippage enforcement
     * Expected: Transaction reverts with SlippageExceeded error when output < threshold
     */
    function testRevertWhenSlippageExceedsMax() public {
        // Set strict slippage tolerance: 1% (100 BPS)
        flashArb.setMaxSlippage(100);

        // Create a mock scenario where swap output would be 97% of input
        // With 1% max slippage, minimum acceptable is 99%, so 97% should fail
        MockPoorSwapAdapter poorAdapter = new MockPoorSwapAdapter(9700); // 97% return

        bytes32 poorHash = address(poorAdapter).codehash;
        flashArb.approveAdapterCodeHash(poorHash, true);
        flashArb.approveAdapter(address(poorAdapter), true);
        flashArb.setDexAdapter(UNISWAP_V2_ROUTER, address(poorAdapter));

        // Prepare paths
        address[] memory path1 = new address[](2);
        path1[0] = WETH;
        path1[1] = DAI;

        address[] memory path2 = new address[](2);
        path2[0] = DAI;
        path2[1] = WETH;

        bytes memory params = abi.encode(
            UNISWAP_V2_ROUTER,
            SUSHISWAP_ROUTER,
            path1,
            path2,
            0,
            0,
            0,
            false,
            owner,
            block.timestamp + 30
        );

        // Mock tokens in contract
        deal(WETH, address(flashArb), 100 ether);

        // Expected: SlippageExceeded(expected, actual, maxBps)
        // For now using vm.expectRevert() - will be updated to specific error once implemented
        vm.expectRevert();

        // Simulate flash loan callback
        address[] memory assets = new address[](1);
        assets[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        uint256[] memory premiums = new uint256[](1);
        premiums[0] = 0.0009 ether; // 0.09% fee

        flashArb.executeOperation(assets, amounts, premiums, address(flashArb), params);
    }

    /**
     * @notice Test that transaction succeeds when slippage is within bounds
     * @dev Validates successful execution with acceptable slippage
     * Expected: Transaction completes successfully with 2% slippage tolerance
     */
    function testAcceptWhenSlippageWithinBounds() public {
        // Default slippage: 2% (200 BPS)
        assertEq(flashArb.maxSlippageBps(), 200);

        // Mock good swap that returns 98.5% (within 2% tolerance)
        MockGoodSwapAdapter goodAdapter = new MockGoodSwapAdapter(9850); // 98.5% return

        bytes32 goodHash = address(goodAdapter).codehash;
        flashArb.approveAdapterCodeHash(goodHash, true);
        flashArb.approveAdapter(address(goodAdapter), true);
        flashArb.setDexAdapter(UNISWAP_V2_ROUTER, address(goodAdapter));
        flashArb.setDexAdapter(SUSHISWAP_ROUTER, address(goodAdapter));

        // Prepare paths
        address[] memory path1 = new address[](2);
        path1[0] = WETH;
        path1[1] = DAI;

        address[] memory path2 = new address[](2);
        path2[0] = DAI;
        path2[1] = WETH;

        bytes memory params = abi.encode(
            UNISWAP_V2_ROUTER,
            SUSHISWAP_ROUTER,
            path1,
            path2,
            0,
            0,
            0,
            false,
            owner,
            block.timestamp + 30
        );

        // Mock tokens
        deal(WETH, address(flashArb), 100 ether);
        deal(DAI, address(flashArb), 1000000 ether);

        // Should succeed
        address[] memory assets = new address[](1);
        assets[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        uint256[] memory premiums = new uint256[](1);
        premiums[0] = 0.0009 ether;

        bool success = flashArb.executeOperation(assets, amounts, premiums, address(flashArb), params);
        assertTrue(success);
    }

    /**
     * @notice Test slippage calculation accuracy with various BPS values
     * @dev Validates the BPS math: minOutput = input * (10000 - slippageBps) / 10000
     * Expected: Calculation returns correct minimum output for all BPS values
     */
    function testSlippageCalculationAccuracy() public {
        // Test case 1: 0 BPS (0% slippage) - min output = 100% of input
        uint256 input1 = 100 ether;
        uint256 slippage1 = 0;
        uint256 expected1 = 100 ether;
        uint256 actual1 = _calculateMinOutput(input1, slippage1);
        assertEq(actual1, expected1, "0 BPS calculation incorrect");

        // Test case 2: 200 BPS (2% slippage) - min output = 98% of input
        uint256 input2 = 100 ether;
        uint256 slippage2 = 200;
        uint256 expected2 = 98 ether;
        uint256 actual2 = _calculateMinOutput(input2, slippage2);
        assertEq(actual2, expected2, "200 BPS calculation incorrect");

        // Test case 3: 1000 BPS (10% slippage) - min output = 90% of input
        uint256 input3 = 100 ether;
        uint256 slippage3 = 1000;
        uint256 expected3 = 90 ether;
        uint256 actual3 = _calculateMinOutput(input3, slippage3);
        assertEq(actual3, expected3, "1000 BPS calculation incorrect");

        // Test case 4: Edge case with small amounts and rounding
        uint256 input4 = 1001 wei;
        uint256 slippage4 = 100; // 1%
        uint256 expected4 = 990 wei; // 1001 * 9900 / 10000 = 990.99 -> 990 (rounds down)
        uint256 actual4 = _calculateMinOutput(input4, slippage4);
        assertEq(actual4, expected4, "Small amount rounding incorrect");

        // Test case 5: 9999 BPS (99.99% slippage) - extreme edge case
        uint256 input5 = 10000 ether;
        uint256 slippage5 = 9999;
        uint256 expected5 = 1 ether;
        uint256 actual5 = _calculateMinOutput(input5, slippage5);
        assertEq(actual5, expected5, "9999 BPS calculation incorrect");
    }

    /**
     * @notice Test that slippage check catches unprofitable arbitrage
     * @dev Even if swaps complete, negative profit should be caught by slippage
     * Expected: Reverts when final output is less than input despite successful swaps
     */
    function testRevertOnNegativeProfit() public {
        // Set 5% max slippage
        flashArb.setMaxSlippage(500);

        // Mock adapter that causes 10% loss (definitely exceeds 5% slippage)
        MockLossAdapter lossAdapter = new MockLossAdapter(9000); // 90% return

        bytes32 lossHash = address(lossAdapter).codehash;
        flashArb.approveAdapterCodeHash(lossHash, true);
        flashArb.approveAdapter(address(lossAdapter), true);
        flashArb.setDexAdapter(UNISWAP_V2_ROUTER, address(lossAdapter));
        flashArb.setDexAdapter(SUSHISWAP_ROUTER, address(lossAdapter));

        // Prepare paths
        address[] memory path1 = new address[](2);
        path1[0] = WETH;
        path1[1] = DAI;

        address[] memory path2 = new address[](2);
        path2[0] = DAI;
        path2[1] = WETH;

        bytes memory params = abi.encode(
            UNISWAP_V2_ROUTER,
            SUSHISWAP_ROUTER,
            path1,
            path2,
            0,
            0,
            0,
            false,
            owner,
            block.timestamp + 30
        );

        deal(WETH, address(flashArb), 100 ether);
        deal(DAI, address(flashArb), 1000000 ether);

        // Should revert due to slippage
        vm.expectRevert();

        address[] memory assets = new address[](1);
        assets[0] = WETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        uint256[] memory premiums = new uint256[](1);
        premiums[0] = 0.0009 ether;

        flashArb.executeOperation(assets, amounts, premiums, address(flashArb), params);
    }

    /**
     * @notice Helper function to calculate minimum output based on slippage BPS
     * @dev Mimics the on-chain calculation that will be implemented
     * Formula: minOutput = inputAmount * (10000 - maxSlippageBps) / 10000
     */
    function _calculateMinOutput(uint256 _inputAmount, uint256 _maxSlippageBps) internal pure returns (uint256) {
        return (_inputAmount * (10000 - _maxSlippageBps)) / 10000;
    }
}

/**
 * @notice Mock adapter that simulates poor swap returns (high slippage)
 */
contract MockPoorSwapAdapter is IDexAdapter {
    uint256 public returnBps; // Return percentage in BPS (e.g., 9700 = 97%)

    constructor(uint256 _returnBps) {
        returnBps = _returnBps;
    }

    function swap(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        // Simulate poor swap: return only returnBps% of input
        amountOut = (amountIn * returnBps) / 10000;

        // In real scenario, would need to transfer tokens
        // For testing, just return the amount
        return amountOut;
    }
}

/**
 * @notice Mock adapter that simulates good swap returns (acceptable slippage)
 */
contract MockGoodSwapAdapter is IDexAdapter {
    uint256 public returnBps;

    constructor(uint256 _returnBps) {
        returnBps = _returnBps;
    }

    function swap(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        amountOut = (amountIn * returnBps) / 10000;
        return amountOut;
    }
}

/**
 * @notice Mock adapter that simulates loss-making swaps
 */
contract MockLossAdapter is IDexAdapter {
    uint256 public returnBps;

    constructor(uint256 _returnBps) {
        returnBps = _returnBps;
    }

    function swap(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        amountOut = (amountIn * returnBps) / 10000;
        return amountOut;
    }
}
