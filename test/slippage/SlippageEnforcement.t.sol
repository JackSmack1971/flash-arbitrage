// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/FlashArbMainnetReady.sol";
import "../../src/UniswapV2Adapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockRouter} from "../../mocks/MockRouter.sol";

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
    MockERC20 public weth;
    MockERC20 public dai;
    MockERC20 public usdc;
    MockRouter public uniswapRouter;
    MockRouter public sushiswapRouter;

    address public owner;
    address public user;

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");

        // Mock AAVE provider at expected address
        address aaveProvider = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
        address mockLendingPool = makeAddr("mockLendingPool");

        // Deploy mock provider bytecode
        vm.etch(aaveProvider, hex"00");
        vm.mockCall(
            aaveProvider,
            abi.encodeWithSignature("getLendingPool()"),
            abi.encode(mockLendingPool)
        );

        // Deploy mock tokens
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Deploy mock routers
        uniswapRouter = new MockRouter(address(weth), address(dai));
        sushiswapRouter = new MockRouter(address(dai), address(weth));

        // Deploy implementation
        FlashArbMainnetReady implementation = new FlashArbMainnetReady();

        // Deploy proxy with initialization
        bytes memory initCall = abi.encodeCall(FlashArbMainnetReady.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initCall);
        flashArb = FlashArbMainnetReady(payable(address(proxy)));

        adapter = new UniswapV2Adapter();

        // Setup adapters
        bytes32 adapterHash = address(adapter).codehash;
        flashArb.approveAdapterCodeHash(adapterHash, true);
        flashArb.approveAdapter(address(adapter), true);
        flashArb.setDexAdapter(address(uniswapRouter), address(adapter));
        flashArb.setDexAdapter(address(sushiswapRouter), address(adapter));
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
        flashArb.setDexAdapter(address(uniswapRouter), address(poorAdapter));

        // Prepare paths
        address[] memory path1 = new address[](2);
        path1[0] = address(weth);
        path1[1] = address(dai);

        address[] memory path2 = new address[](2);
        path2[0] = address(dai);
        path2[1] = address(weth);

        bytes memory params = abi.encode(
            address(uniswapRouter),
            address(sushiswapRouter),
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
        deal(address(weth), address(flashArb), 100 ether);

        // Expected: SlippageExceeded(expected, actual, maxBps)
        // For now using vm.expectRevert() - will be updated to specific error once implemented
        vm.expectRevert();

        // Simulate flash loan callback
        address[] memory assets = new address[](1);
        assets[0] = address(weth);
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
        flashArb.setDexAdapter(address(uniswapRouter), address(goodAdapter));
        flashArb.setDexAdapter(address(sushiswapRouter), address(goodAdapter));

        // Prepare paths
        address[] memory path1 = new address[](2);
        path1[0] = address(weth);
        path1[1] = address(dai);

        address[] memory path2 = new address[](2);
        path2[0] = address(dai);
        path2[1] = address(weth);

        bytes memory params = abi.encode(
            address(uniswapRouter),
            address(sushiswapRouter),
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
        deal(address(weth), address(flashArb), 100 ether);
        deal(address(dai), address(flashArb), 1000000 ether);

        // Should succeed
        address[] memory assets = new address[](1);
        assets[0] = address(weth);
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
        flashArb.setDexAdapter(address(uniswapRouter), address(lossAdapter));
        flashArb.setDexAdapter(address(sushiswapRouter), address(lossAdapter));

        // Prepare paths
        address[] memory path1 = new address[](2);
        path1[0] = address(weth);
        path1[1] = address(dai);

        address[] memory path2 = new address[](2);
        path2[0] = address(dai);
        path2[1] = address(weth);

        bytes memory params = abi.encode(
            address(uniswapRouter),
            address(sushiswapRouter),
            path1,
            path2,
            0,
            0,
            0,
            false,
            owner,
            block.timestamp + 30
        );

        deal(address(weth), address(flashArb), 100 ether);
        deal(address(dai), address(flashArb), 1000000 ether);

        // Should revert due to slippage
        vm.expectRevert();

        address[] memory assets = new address[](1);
        assets[0] = address(weth);
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
        uint256 deadline,
        uint256 maxAllowance
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
        uint256 deadline,
        uint256 maxAllowance
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
        uint256 deadline,
        uint256 maxAllowance
    ) external returns (uint256 amountOut) {
        amountOut = (amountIn * returnBps) / 10000;
        return amountOut;
    }
}
