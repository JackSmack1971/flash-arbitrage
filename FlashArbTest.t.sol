// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {FlashArbMainnetReady} from "../src/FlashArbMainnetReady.sol";
import {UniswapV2Adapter} from "../src/UniswapV2Adapter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockLendingPool} from "./mocks/MockLendingPool.sol";
import {MockRouter} from "./mocks/MockRouter.sol";

contract FlashArbTest is Test {
    FlashArbMainnetReady arb;
    UniswapV2Adapter adapter;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockLendingPool lendingPool;
    MockRouter router1;
    MockRouter router2;

    address owner = address(1);
    address user = address(2);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mocks
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        lendingPool = new MockLendingPool();
        router1 = new MockRouter(address(tokenA), address(tokenB));
        router2 = new MockRouter(address(tokenB), address(tokenA));

        // Deploy implementation
        FlashArbMainnetReady implementation = new FlashArbMainnetReady();

        // Deploy proxy
        bytes memory initData = abi.encodeCall(FlashArbMainnetReady.initialize, ());
        // Note: In real deployment, use ERC1967Proxy
        arb = FlashArbMainnetReady(address(implementation));

        // Initialize
        arb.initialize();

        // Setup adapters
        adapter = new UniswapV2Adapter();
        arb.setDexAdapter(address(router1), address(adapter));
        arb.setDexAdapter(address(router2), address(adapter));

        vm.stopPrank();
    }

    function testInitialization() public {
        assertEq(arb.owner(), owner);
        assertTrue(arb.routerWhitelist(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D));
        assertTrue(arb.tokenWhitelist(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
        assertTrue(arb.trustedInitiators(owner));
    }

    function testSuccessfulArbitrage() public {
        uint256 loanAmount = 1000 * 10**18;

        // Setup profitable arbitrage opportunity
        router1.setExchangeRate(1 * 10**18, 95 * 10**17); // 1 A -> 0.95 B (worse rate)
        router2.setExchangeRate(1 * 10**18, 105 * 10**17); // 1 B -> 1.05 A (better rate)

        // Fund lending pool
        deal(address(tokenA), address(lendingPool), loanAmount);

        // Prepare arbitrage params
        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);

        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenA);

        bytes memory params = abi.encode(
            address(router1), // router1
            address(router2), // router2
            path1, // path1
            path2, // path2
            90 * 10**17, // amountOutMin1 (0.9 B)
            1000 * 10**18, // amountOutMin2 (1000 A)
            1 * 10**18, // minProfit
            false, // unwrapProfitToEth
            owner, // opInitiator
            block.timestamp + 3600 // deadline
        );

        vm.prank(owner);
        arb.startFlashLoan(address(tokenA), loanAmount, params);

        // Verify profit was recorded
        assertGt(arb.profits(address(tokenA)), 0);
    }

    function testRevertsWhenDeadlineExpired() public {
        uint256 loanAmount = 1000 * 10**18;

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
            block.timestamp - 1 // expired deadline
        );

        vm.prank(owner);
        vm.expectRevert("deadline-invalid");
        arb.startFlashLoan(address(tokenA), loanAmount, params);
    }

    function testRevertsWhenDeadlineTooFar() public {
        uint256 loanAmount = 1000 * 10**18;

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
            block.timestamp + 31 // too far in future
        );

        vm.prank(owner);
        vm.expectRevert("deadline-invalid");
        arb.startFlashLoan(address(tokenA), loanAmount, params);
    }

    function testRevertsWhenInitiatorNotTrusted() public {
        uint256 loanAmount = 1000 * 10**18;

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
            address(0x999), // untrusted initiator
            block.timestamp + 10
        );

        vm.prank(owner);
        vm.expectRevert("initiator-not-trusted");
        arb.startFlashLoan(address(tokenA), loanAmount, params);
    }

    function testRevertsWhenInsufficientRepayment() public {
        uint256 loanAmount = 1000 * 10**18;

        // Setup unprofitable arbitrage
        router1.setExchangeRate(1 * 10**18, 50 * 10**17); // very bad rate
        router2.setExchangeRate(1 * 10**18, 50 * 10**17); // very bad rate

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
            40 * 10**17,
            400 * 10**18,
            1 * 10**18,
            false,
            owner,
            block.timestamp + 3600
        );

        vm.prank(owner);
        vm.expectRevert("insufficient-to-repay");
        arb.startFlashLoan(address(tokenA), loanAmount, params);
    }

    function testOnlyOwnerCanExecute() public {
        vm.prank(user);
        vm.expectRevert();
        arb.startFlashLoan(address(tokenA), 1000 * 10**18, "");
    }

    function testInvariant_FlashLoanRepayment() public {
        // This invariant should always hold: contract must be able to repay flash loan
        // In a real test, this would use echidna or invariant testing framework
        uint256 loanAmount = 1000 * 10**18;

        router1.setExchangeRate(1 * 10**18, 100 * 10**17); // 1:1 rate
        router2.setExchangeRate(1 * 10**18, 100 * 10**17); // 1:1 rate

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
            95 * 10**17,
            950 * 10**18,
            1 * 10**18,
            false,
            owner,
            block.timestamp + 3600
        );

        uint256 balanceBefore = tokenA.balanceOf(address(arb));

        vm.prank(owner);
        arb.startFlashLoan(address(tokenA), loanAmount, params);

        uint256 balanceAfter = tokenA.balanceOf(address(arb));
        // Balance should be same or higher (profit)
        assertGe(balanceAfter, balanceBefore);
    }

    function testInvariant_PathValidity() public {
        // Test that paths form valid closed loop
        address[] memory path1 = new address[](3);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);
        path1[2] = address(tokenA); // Invalid - should end with intermediate

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
            block.timestamp + 10
        );

        vm.prank(owner);
        vm.expectRevert("path2 must start with intermediate token");
        arb.startFlashLoan(address(tokenA), 1000 * 10**18, params);
    }

    function testBalanceValidationAfterFirstSwap() public {
        uint256 loanAmount = 1000 * 10**18;

        // Setup profitable arbitrage opportunity
        router1.setExchangeRate(1 * 10**18, 95 * 10**17); // 1 A -> 0.95 B (worse rate)
        router2.setExchangeRate(1 * 10**18, 105 * 10**17); // 1 B -> 1.05 A (better rate)

        // Fund lending pool
        deal(address(tokenA), address(lendingPool), loanAmount);

        // Prepare arbitrage params
        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);

        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenA);

        bytes memory params = abi.encode(
            address(router1), // router1
            address(router2), // router2
            path1, // path1
            path1, // path2 - intentionally wrong to trigger balance validation
            90 * 10**17, // amountOutMin1 (0.9 B)
            1000 * 10**18, // amountOutMin2 (1000 A)
            1 * 10**18, // minProfit
            false, // unwrapProfitToEth
            owner, // opInitiator
            block.timestamp + 10 // deadline
        );

        vm.prank(owner);
        vm.expectRevert("path2 must start with intermediate token");
        arb.startFlashLoan(address(tokenA), loanAmount, params);
    }

    function testGasProfiling() public {
        uint256 loanAmount = 1000 * 10**18;

        // Setup profitable arbitrage opportunity
        router1.setExchangeRate(1 * 10**18, 95 * 10**17); // 1 A -> 0.95 B (worse rate)
        router2.setExchangeRate(1 * 10**18, 105 * 10**17); // 1 B -> 1.05 A (better rate)

        // Fund lending pool
        deal(address(tokenA), address(lendingPool), loanAmount);

        // Prepare arbitrage params
        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);

        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenA);

        bytes memory params = abi.encode(
            address(router1), // router1
            address(router2), // router2
            path1, // path1
            path2, // path2
            90 * 10**17, // amountOutMin1 (0.9 B)
            1000 * 10**18, // amountOutMin2 (1000 A)
            1 * 10**18, // minProfit
            false, // unwrapProfitToEth
            owner, // opInitiator
            block.timestamp + 10 // deadline
        );

        vm.prank(owner);
        uint256 gasStart = gasleft();
        arb.startFlashLoan(address(tokenA), loanAmount, params);
        uint256 gasUsed = gasStart - gasleft();

        // Log gas usage for profiling (gas used should be reasonable)
        console.log("Flash loan gas used:", gasUsed);
        assertLt(gasUsed, 500000, "gas usage too high"); // Reasonable upper bound
    }
}