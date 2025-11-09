// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {TestBase} from "./helpers/TestBase.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FlashArbMainnetReady} from "../src/FlashArbMainnetReady.sol";
import {UniswapV2Adapter, IFlashArbLike} from "../src/UniswapV2Adapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockLendingPool} from "../mocks/MockLendingPool.sol";
import {MockRouter} from "../mocks/MockRouter.sol";

contract FlashArbFuzzTest is TestBase {
    FlashArbMainnetReady arb;
    UniswapV2Adapter adapter;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockLendingPool lendingPool;
    MockRouter router1;
    MockRouter router2;

    address owner = address(1);

    function setUp() public {
        // Set stable time for deterministic testing
        _setStableTime();

        vm.startPrank(owner);

        // Deploy mocks FIRST so we can use their addresses
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        lendingPool = new MockLendingPool();
        router1 = new MockRouter(address(tokenA), address(tokenB));
        router2 = new MockRouter(address(tokenB), address(tokenA));

        // STEP 1: FUND ALL ACTORS BEFORE ANY OPERATIONS
        uint256 MASSIVE_LIQUIDITY = 1e30; // 1e12 tokens with 18 decimals

        deal(address(tokenA), address(this), MASSIVE_LIQUIDITY);
        deal(address(tokenB), address(this), MASSIVE_LIQUIDITY);
        deal(address(tokenA), owner, MASSIVE_LIQUIDITY);
        deal(address(tokenB), owner, MASSIVE_LIQUIDITY);
        vm.deal(address(this), 100 ether);
        vm.deal(owner, 100 ether);

        // STEP 2: Mock AAVE provider and mainnet addresses
        address aaveProvider = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
        vm.etch(aaveProvider, hex"00");
        vm.mockCall(
            aaveProvider,
            abi.encodeWithSignature("getLendingPool()"),
            abi.encode(address(lendingPool))
        );

        // Mock hardcoded mainnet addresses
        MockERC20 mockWETH = new MockERC20("WETH", "WETH", 18);
        MockERC20 mockDAI = new MockERC20("DAI", "DAI", 18);
        MockERC20 mockUSDC = new MockERC20("USDC", "USDC", 6);
        vm.etch(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, address(mockWETH).code);
        vm.etch(0x6B175474E89094C44Da98b954EedeAC495271d0F, address(mockDAI).code);
        vm.etch(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, address(mockUSDC).code);
        vm.etch(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, address(mockWETH).code);
        vm.etch(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F, address(mockWETH).code);

        // STEP 3: Deploy and initialize proxy
        FlashArbMainnetReady implementation = new FlashArbMainnetReady();
        bytes memory initCall = abi.encodeCall(FlashArbMainnetReady.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initCall);
        arb = FlashArbMainnetReady(payable(address(proxy)));

        // STEP 4: Setup adapters
        adapter = new UniswapV2Adapter(IFlashArbLike(address(arb)));

        // STEP 5: Whitelist routers and tokens
        arb.setRouterWhitelist(address(router1), true);
        arb.setRouterWhitelist(address(router2), true);
        arb.setTokenWhitelist(address(tokenA), true);
        arb.setTokenWhitelist(address(tokenB), true);

        // STEP 6: Approve and configure adapters
        bytes32 adapterHash = address(adapter).codehash;
        arb.approveAdapterCodeHash(adapterHash, true);
        arb.approveAdapter(address(adapter), true);
        arb.setDexAdapter(address(router1), address(adapter));
        arb.setDexAdapter(address(router2), address(adapter));

        // STEP 7: Set trusted initiator
        arb.setTrustedInitiator(owner, true);

        // STEP 8: Configure pool liquidity
        tokenA.approve(address(lendingPool), type(uint256).max);
        tokenB.approve(address(lendingPool), type(uint256).max);
        lendingPool.deposit(address(tokenA), MASSIVE_LIQUIDITY);
        lendingPool.deposit(address(tokenB), MASSIVE_LIQUIDITY);

        vm.stopPrank();
    }

    // Fuzz test for profit calculation edge cases
    function testFuzzProfitCalculation(uint256 loanAmount, uint256 rate1, uint256 rate2) external {
        // Bound inputs using centralized bounds
        loanAmount = _boundFlashLoan(loanAmount);
        rate1 = _boundExchangeRate(rate1);
        rate2 = _boundExchangeRate(rate2);

        // Setup exchange rates
        router1.setExchangeRate(rate1);
        router2.setExchangeRate(rate2);

        // Pool already seeded with massive liquidity in setUp

        // Calculate expected profit accounting for flash loan fee
        uint256 fee = _flashLoanFee(loanAmount);
        uint256 totalDebt = loanAmount + fee;
        uint256 amountOut1 = (loanAmount * rate1) / 10**18;
        uint256 amountOut2 = (amountOut1 * rate2) / 10**18;
        uint256 expectedProfit = amountOut2 > totalDebt ? amountOut2 - totalDebt : 0;

        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);

        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenA);

        // Use safer slippage calculation (5% slippage)
        uint256 minOut1 = _minOutAfterSlippage(amountOut1, 500);
        uint256 minOut2 = _minOutAfterSlippage(amountOut2, 500);

        bytes memory params = abi.encode(
            address(router1),
            address(router2),
            path1,
            path2,
            minOut1,
            minOut2,
            0, // minProfit = 0 to test edge cases
            false,
            owner,
            _deadlineFromNow(30) // 30 seconds (within MAX_DEADLINE)
        );

        vm.prank(owner);
        if (expectedProfit > 0) {
            // Should succeed if profitable
            arb.startFlashLoan(address(tokenA), loanAmount, params);
            assertGe(arb.profits(address(tokenA)), 0);
        } else {
            // Should revert if not profitable enough - error may not have data through callback
            vm.expectRevert();
            arb.startFlashLoan(address(tokenA), loanAmount, params);
        }
    }

    // Fuzz test for balance validation scenarios
    function testFuzzBalanceValidation(uint256 loanAmount, uint256 intermediateBalance) external {
        // Bound to amounts pool can support using helper
        loanAmount = _boundFlashLoan(loanAmount);
        intermediateBalance = bound(intermediateBalance, 0, _boundTrade(loanAmount * 2));

        // Setup profitable arbitrage
        uint256 rate1 = 95 * 10**17;
        uint256 rate2 = 105 * 10**17;
        router1.setExchangeRate(rate1);
        router2.setExchangeRate(rate2);

        // Pool already seeded; optionally add intermediate balance to arb contract
        if (intermediateBalance > 0) {
            deal(address(tokenB), address(arb), intermediateBalance);
        }

        // Calculate expected outputs
        uint256 amountOut1 = (loanAmount * rate1) / 10**18;
        uint256 amountOut2 = (amountOut1 * rate2) / 10**18;

        // Use safer slippage calculation
        uint256 minOut1 = _minOutAfterSlippage(amountOut1, 500);
        uint256 minOut2 = _minOutAfterSlippage(amountOut2, 500);

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
            minOut1,
            minOut2,
            1 * 10**18,
            false,
            owner,
            _deadlineFromNow(30) // 30 seconds (within MAX_DEADLINE)
        );

        // Calculate if this will be profitable
        uint256 fee = _flashLoanFee(loanAmount);
        uint256 totalDebt = loanAmount + fee;
        bool shouldBeRrofitable = amountOut2 >= totalDebt + 1 * 10**18;

        vm.prank(owner);
        if (shouldBeRrofitable) {
            arb.startFlashLoan(address(tokenA), loanAmount, params);
            // Contract should not hold tokens after operation
            assertEq(tokenA.balanceOf(address(arb)), 0);
            assertEq(tokenB.balanceOf(address(arb)), 0);
        } else {
            // Should revert if not profitable enough
            vm.expectRevert();
            arb.startFlashLoan(address(tokenA), loanAmount, params);
        }
    }

    // Fuzz test for path validation with malformed inputs
    function testFuzzPathValidation(uint256 pathLength1, uint256 pathLength2) external {
        // Bound path lengths to reasonable range
        pathLength1 = bound(pathLength1, FuzzBounds.MIN_PATH_LENGTH, FuzzBounds.MAX_PATH_LENGTH);
        pathLength2 = bound(pathLength2, FuzzBounds.MIN_PATH_LENGTH, FuzzBounds.MAX_PATH_LENGTH);

        address[] memory path1 = new address[](pathLength1);
        address[] memory path2 = new address[](pathLength2);

        // Fill paths with valid addresses initially
        for (uint256 i = 0; i < pathLength1; i++) {
            path1[i] = i % 2 == 0 ? address(tokenA) : address(tokenB);
        }
        for (uint256 i = 0; i < pathLength2; i++) {
            path2[i] = i % 2 == 0 ? address(tokenB) : address(tokenA);
        }

        // Ensure path1 starts with loan token (reserve)
        path1[0] = address(tokenA);
        // Ensure path2 starts with intermediate token (path1's end)
        path2[0] = address(tokenB);
        // CRITICAL: Ensure path2 ends with reserve token (path validation requirement)
        path2[path2.length - 1] = address(tokenA);

        uint256 loanAmount = 1000 * 10**18;

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
            _deadlineFromNow(30) // 30 seconds (within MAX_DEADLINE)
        );

        vm.prank(owner);
        // Should revert if paths are malformed - error may not have data through callback
        if (path1[path1.length - 1] != path2[0]) {
            vm.expectRevert();
        }
        arb.startFlashLoan(address(tokenA), loanAmount, params);
    }

    // Fuzz test for deadline timing edge cases
    function testFuzzDeadlineTiming(uint256 deadlineOffset) external {
        // Bound to reasonable deadline window (contract allows max 30 seconds)
        // Start from 1 (not 0) to ensure deadline > block.timestamp
        deadlineOffset = bound(deadlineOffset, 1, 35); // Test both valid (1-30) and invalid (31-35)

        uint256 loanAmount = 1000 * 10**18;

        // Setup profitable arbitrage
        router1.setExchangeRate(95 * 10**17);
        router2.setExchangeRate(105 * 10**17);

        // Pool already seeded in setUp

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

        // Deadline validation error may not have data through callback
        if (deadline < block.timestamp || deadline > block.timestamp + 30) {
            vm.expectRevert();
        }

        arb.startFlashLoan(address(tokenA), loanAmount, params);
    }

    // Fuzz test for boundary values in loan amounts
    function testFuzzLoanAmountBoundaries(uint256 loanAmount) external {
        // Use bounded flash loan amount
        loanAmount = _boundFlashLoan(loanAmount);

        // Setup rates to ensure profitability (need >100% to cover flash loan fee)
        // With 0.09% fee, we need slightly more than 1:1
        uint256 rate1 = 100 * 10**16; // 1.00 (1:1)
        uint256 rate2 = 101 * 10**16; // 1.01 (1% profit to cover fee)
        router1.setExchangeRate(rate1);
        router2.setExchangeRate(rate2);

        // Pool already seeded with sufficient liquidity in setUp
        // No need to deal additional tokens

        // Calculate expected outputs
        uint256 amountOut1 = (loanAmount * rate1) / 10**18;
        uint256 amountOut2 = (amountOut1 * rate2) / 10**18;

        // Calculate total debt including fee
        uint256 fee = _flashLoanFee(loanAmount);
        uint256 totalDebt = loanAmount + fee;

        // Use conservative slippage
        uint256 minOut1 = _minOutAfterSlippage(amountOut1, 100); // 1% slippage
        uint256 minOut2 = _minOutAfterSlippage(amountOut2, 100); // 1% slippage

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
            minOut1,
            minOut2,
            0, // No minimum profit requirement
            false,
            owner,
            _deadlineFromNow(10) // 10 seconds (within MAX_DEADLINE)
        );

        // Should succeed - we have profitable rates and bounded amounts
        vm.prank(owner);
        // Ensure we have enough to repay
        if (amountOut2 >= totalDebt) {
            arb.startFlashLoan(address(tokenA), loanAmount, params);
        } else {
            // Should revert if cannot repay
            vm.expectRevert();
            arb.startFlashLoan(address(tokenA), loanAmount, params);
        }
    }

    // Fuzz test for exchange rate edge cases
    function testFuzzExchangeRateEdgeCases(uint256 rate1, uint256 rate2) external {
        // Bound to reasonable exchange rates using helper
        rate1 = _boundExchangeRate(rate1);
        rate2 = _boundExchangeRate(rate2);

        uint256 loanAmount = 1000 * 10**18;

        router1.setExchangeRate(rate1);
        router2.setExchangeRate(rate2);

        // Pool already seeded in setUp

        // Calculate expected outputs
        uint256 amountOut1 = (loanAmount * rate1) / 10**18;
        uint256 amountOut2 = (amountOut1 * rate2) / 10**18;

        // Calculate if this will be profitable
        uint256 fee = _flashLoanFee(loanAmount);
        uint256 totalDebt = loanAmount + fee;

        // Use very permissive slippage for edge case testing
        uint256 minOut1 = _minOutAfterSlippage(amountOut1, 500); // 5% slippage
        uint256 minOut2 = _minOutAfterSlippage(amountOut2, 500); // 5% slippage

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
            minOut1,
            minOut2,
            0,
            false,
            owner,
            _deadlineFromNow(30) // 30 seconds (within MAX_DEADLINE)
        );

        vm.prank(owner);

        // Should handle extreme rate differences without reverting unexpectedly
        if (amountOut2 >= totalDebt) {
            // Should succeed if can repay
            arb.startFlashLoan(address(tokenA), loanAmount, params);
            // Success - check invariants
            assertEq(tokenA.balanceOf(address(arb)), 0);
            assertEq(tokenB.balanceOf(address(arb)), 0);
        } else {
            // Should revert if cannot repay
            vm.expectRevert();
            arb.startFlashLoan(address(tokenA), loanAmount, params);
        }
    }

    // Helper function for dealing tokens (external to use with try/catch)
    function dealTokens(address token, address to, uint256 amount) external {
        deal(token, to, amount);
    }
}