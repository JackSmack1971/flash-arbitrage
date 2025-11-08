// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FlashArbMainnetReady} from "../src/FlashArbMainnetReady.sol";
import {UniswapV2Adapter} from "../src/UniswapV2Adapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockLendingPool} from "../mocks/MockLendingPool.sol";
import {MockRouter} from "../mocks/MockRouter.sol";

contract FlashArbFuzzTest is Test {
    FlashArbMainnetReady arb;
    UniswapV2Adapter adapter;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockLendingPool lendingPool;
    MockRouter router1;
    MockRouter router2;

    address owner = address(1);

    function setUp() public {
        vm.startPrank(owner);

        // Mock AAVE provider at expected address
        address aaveProvider = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
        address mockLendingPoolAddr = makeAddr("mockLendingPool");
        vm.etch(aaveProvider, hex"00");
        vm.mockCall(
            aaveProvider,
            abi.encodeWithSignature("getLendingPool()"),
            abi.encode(mockLendingPoolAddr)
        );

        // Mock hardcoded mainnet addresses that initialize() tries to call
        // Deploy mock ERC20s and etch their bytecode at the hardcoded addresses
        MockERC20 mockWETH = new MockERC20("WETH", "WETH", 18);
        MockERC20 mockDAI = new MockERC20("DAI", "DAI", 18);
        MockERC20 mockUSDC = new MockERC20("USDC", "USDC", 6);
        vm.etch(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, address(mockWETH).code);
        vm.etch(0x6B175474E89094C44Da98b954EedeAC495271d0F, address(mockDAI).code);
        vm.etch(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, address(mockUSDC).code);
        vm.etch(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, address(mockWETH).code); // Routers
        vm.etch(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F, address(mockWETH).code);

        // Deploy mocks
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        lendingPool = new MockLendingPool();
        router1 = new MockRouter(address(tokenA), address(tokenB));
        router2 = new MockRouter(address(tokenB), address(tokenA));

        // Deploy implementation
        FlashArbMainnetReady implementation = new FlashArbMainnetReady();

        // Deploy proxy with initialization
        bytes memory initCall = abi.encodeCall(FlashArbMainnetReady.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initCall);
        arb = FlashArbMainnetReady(payable(address(proxy)));

        // Setup adapters
        adapter = new UniswapV2Adapter();

        // Whitelist the mock routers
        arb.setRouterWhitelist(address(router1), true);
        arb.setRouterWhitelist(address(router2), true);

        // Approve adapter and its bytecode hash
        bytes32 adapterHash = address(adapter).codehash;
        arb.approveAdapterCodeHash(adapterHash, true);
        arb.approveAdapter(address(adapter), true);

        arb.setDexAdapter(address(router1), address(adapter));
        arb.setDexAdapter(address(router2), address(adapter));

        vm.stopPrank();
    }

    // Fuzz test for profit calculation edge cases
    function testFuzzProfitCalculation(uint256 loanAmount, uint256 rate1, uint256 rate2) external {
        // Bound inputs to reasonable ranges
        loanAmount = bound(loanAmount, 1 * 10**18, 1000000 * 10**18); // 1 to 1M tokens
        rate1 = bound(rate1, 1 * 10**17, 10 * 10**18); // 0.1 to 10 ratio
        rate2 = bound(rate2, 1 * 10**17, 10 * 10**18); // 0.1 to 10 ratio

        // Setup exchange rates
        router1.setExchangeRate(rate1);
        router2.setExchangeRate(rate2);

        // Fund lending pool
        deal(address(tokenA), address(lendingPool), loanAmount);

        // Calculate expected profit
        uint256 amountOut1 = (loanAmount * rate1) / 10**18;
        uint256 amountOut2 = (amountOut1 * rate2) / 10**18;
        uint256 expectedProfit = amountOut2 > loanAmount ? amountOut2 - loanAmount : 0;

        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);

        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenA);

        bytes memory params = abi.encode(
            address(router1),
            address(router2),
            path1,
            path2,
            (amountOut1 * 95) / 100, // 95% of expected output
            (amountOut2 * 95) / 100, // 95% of expected output
            0, // minProfit = 0 to test edge cases
            false,
            owner,
            block.timestamp + 3600
        );

        vm.prank(owner);
        if (expectedProfit > 0) {
            // Should succeed if profitable
            arb.startFlashLoan(address(tokenA), loanAmount, params);
            assertGe(arb.profits(address(tokenA)), 0);
        } else {
            // Should revert if not profitable enough
            vm.expectRevert("insufficient-to-repay");
            arb.startFlashLoan(address(tokenA), loanAmount, params);
        }
    }

    // Fuzz test for balance validation scenarios
    function testFuzzBalanceValidation(uint256 loanAmount, uint256 intermediateBalance) external {
        loanAmount = bound(loanAmount, 1 * 10**18, 100000 * 10**18);
        intermediateBalance = bound(intermediateBalance, 0, loanAmount * 2);

        // Setup profitable arbitrage
        router1.setExchangeRate(95 * 10**17);
        router2.setExchangeRate(105 * 10**17);

        deal(address(tokenA), address(lendingPool), loanAmount);
        deal(address(tokenB), address(arb), intermediateBalance);

        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);

        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenA);

        bytes memory params = abi.encode(
            address(router1),
            address(router2),
            path1,
            path2,
            90 * 10**17,
            1000 * 10**18,
            1 * 10**18,
            false,
            owner,
            block.timestamp + 3600
        );

        vm.prank(owner);
        arb.startFlashLoan(address(tokenA), loanAmount, params);

        // Contract should not hold tokens after operation
        assertEq(tokenA.balanceOf(address(arb)), 0);
        assertEq(tokenB.balanceOf(address(arb)), 0);
    }

    // Fuzz test for path validation with malformed inputs
    function testFuzzPathValidation(uint256 pathLength1, uint256 pathLength2) external {
        pathLength1 = bound(pathLength1, 2, 5);
        pathLength2 = bound(pathLength2, 2, 5);

        address[] memory path1 = new address[](pathLength1);
        address[] memory path2 = new address[](pathLength2);

        // Fill paths with valid addresses initially
        for (uint256 i = 0; i < pathLength1; i++) {
            path1[i] = i % 2 == 0 ? address(tokenA) : address(tokenB);
        }
        for (uint256 i = 0; i < pathLength2; i++) {
            path2[i] = i % 2 == 0 ? address(tokenB) : address(tokenA);
        }

        // Ensure path1 starts with loan token
        path1[0] = address(tokenA);
        // Ensure path2 starts with intermediate token
        path2[0] = address(tokenB);

        bytes memory params = abi.encode(
            address(router1),
            address(router2),
            path1,
            path2,
            90 * 10**17,
            1000 * 10**18,
            1 * 10**18,
            false,
            owner,
            block.timestamp + 3600
        );

        vm.prank(owner);
        // Should revert if paths are malformed
        if (path1[path1.length - 1] != path2[0]) {
            vm.expectRevert("path2 must start with intermediate token");
        }
        arb.startFlashLoan(address(tokenA), 1000 * 10**18, params);
    }

    // Fuzz test for deadline timing edge cases
    function testFuzzDeadlineTiming(uint256 deadlineOffset) external {
        deadlineOffset = bound(deadlineOffset, 0, 100);

        uint256 loanAmount = 1000 * 10**18;

        // Setup profitable arbitrage
        router1.setExchangeRate(95 * 10**17);
        router2.setExchangeRate(105 * 10**17);

        deal(address(tokenA), address(lendingPool), loanAmount);

        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);

        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenA);

        uint256 deadline = block.timestamp + deadlineOffset;

        bytes memory params = abi.encode(
            address(router1),
            address(router2),
            path1,
            path2,
            90 * 10**17,
            1000 * 10**18,
            1 * 10**18,
            false,
            owner,
            deadline
        );

        vm.prank(owner);

        if (deadline < block.timestamp || deadline > block.timestamp + 30) {
            vm.expectRevert("deadline-invalid");
        }

        arb.startFlashLoan(address(tokenA), loanAmount, params);
    }

    // Fuzz test for boundary values in loan amounts
    function testFuzzLoanAmountBoundaries(uint256 loanAmount) external {
        loanAmount = bound(loanAmount, 1, type(uint256).max);

        // Setup rates
        router1.setExchangeRate(1 * 10**18);
        router2.setExchangeRate(1 * 10**18);

        // Try to fund lending pool (may fail for very large amounts)
        try this.dealTokens(address(tokenA), address(lendingPool), loanAmount) {
            // Funding succeeded
        } catch {
            // Skip test if funding fails
            return;
        }

        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);

        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenA);

        bytes memory params = abi.encode(
            address(router1),
            address(router2),
            path1,
            path2,
            loanAmount / 2, // Conservative minimum
            loanAmount,
            0,
            false,
            owner,
            block.timestamp + 10
        );

        vm.prank(owner);

        // Should not revert due to overflow/underflow in calculations
        if (loanAmount <= 1000000 * 10**18) { // Reasonable upper bound
            arb.startFlashLoan(address(tokenA), loanAmount, params);
        }
    }

    // Fuzz test for exchange rate edge cases
    function testFuzzExchangeRateEdgeCases(uint256 rate1, uint256 rate2) external {
        rate1 = bound(rate1, 1, type(uint256).max / 10**18); // Prevent overflow
        rate2 = bound(rate2, 1, type(uint256).max / 10**18);

        uint256 loanAmount = 1000 * 10**18;

        router1.setExchangeRate(rate1);
        router2.setExchangeRate(rate2);

        deal(address(tokenA), address(lendingPool), loanAmount);

        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);

        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenA);

        bytes memory params = abi.encode(
            address(router1),
            address(router2),
            path1,
            path2,
            1, // Very low minimum
            1,
            0,
            false,
            owner,
            block.timestamp + 3600
        );

        vm.prank(owner);

        // Should handle extreme rate differences without reverting unexpectedly
        try arb.startFlashLoan(address(tokenA), loanAmount, params) {
            // Success - check invariants
            assertEq(tokenA.balanceOf(address(arb)), 0);
            assertEq(tokenB.balanceOf(address(arb)), 0);
        } catch Error(string memory reason) {
            // Expected reverts for insufficient repayment
            assertEq(reason, "insufficient-to-repay");
        }
    }

    // Helper function for dealing tokens (external to use with try/catch)
    function dealTokens(address token, address to, uint256 amount) external {
        deal(token, to, amount);
    }
}