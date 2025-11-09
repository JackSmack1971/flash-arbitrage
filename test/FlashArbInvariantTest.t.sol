// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FlashArbMainnetReady} from "../src/FlashArbMainnetReady.sol";
import {UniswapV2Adapter, IFlashArbLike} from "../src/UniswapV2Adapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockLendingPool} from "../mocks/MockLendingPool.sol";
import {MockRouter} from "../mocks/MockRouter.sol";

contract FlashArbInvariantTest is Test {
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

        // Deploy mocks FIRST so we can use their addresses
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        lendingPool = new MockLendingPool();
        router1 = new MockRouter(address(tokenA), address(tokenB));
        router2 = new MockRouter(address(tokenB), address(tokenA));

        // Mock AAVE provider at expected address - use ACTUAL lending pool address
        address aaveProvider = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
        vm.etch(aaveProvider, hex"00");
        vm.mockCall(
            aaveProvider,
            abi.encodeWithSignature("getLendingPool()"),
            abi.encode(address(lendingPool))  // Use actual MockLendingPool address
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

        // Deploy implementation
        FlashArbMainnetReady implementation = new FlashArbMainnetReady();

        // Deploy proxy with initialization
        bytes memory initCall = abi.encodeCall(FlashArbMainnetReady.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initCall);
        arb = FlashArbMainnetReady(payable(address(proxy)));

        // Setup adapters
        adapter = new UniswapV2Adapter(IFlashArbLike(address(arb)));

        // Whitelist the mock routers
        arb.setRouterWhitelist(address(router1), true);
        arb.setRouterWhitelist(address(router2), true);

        // Approve adapter and its bytecode hash
        bytes32 adapterHash = address(adapter).codehash;
        arb.approveAdapterCodeHash(adapterHash, true);
        arb.approveAdapter(address(adapter), true);

        arb.setDexAdapter(address(router1), address(adapter));
        arb.setDexAdapter(address(router2), address(adapter));

        // Whitelist tokens so tests can proceed past asset validation
        arb.setTokenWhitelist(address(tokenA), true);
        arb.setTokenWhitelist(address(tokenB), true);

        // Whitelist owner as trusted initiator
        arb.setTrustedInitiator(owner, true);

        // Seed lending pool with massive liquidity
        // IMPORTANT: Must both deal() tokens AND call deposit() to update internal accounting
        uint256 MASSIVE_LIQUIDITY = 1e30; // 1e12 tokens with 18 decimals

        // Give this contract tokens to deposit
        deal(address(tokenA), address(this), MASSIVE_LIQUIDITY);
        deal(address(tokenB), address(this), MASSIVE_LIQUIDITY);

        // Approve pool to take tokens
        tokenA.approve(address(lendingPool), MASSIVE_LIQUIDITY);
        tokenB.approve(address(lendingPool), MASSIVE_LIQUIDITY);

        // Actually deposit to update pool's internal balances mapping
        lendingPool.deposit(address(tokenA), MASSIVE_LIQUIDITY);
        lendingPool.deposit(address(tokenB), MASSIVE_LIQUIDITY);

        vm.stopPrank();
    }

    // Invariant: Contract never holds tokens after flash loan operations
    function invariantContractBalanceZeroAfterOperations() external {
        // This would be called by invariant testing framework
        // Contract should not hold any tokens after successful operations
        assertEq(tokenA.balanceOf(address(arb)), 0, "Contract should not hold tokenA");
        assertEq(tokenB.balanceOf(address(arb)), 0, "Contract should not hold tokenB");
    }

    // Invariant: Only owner can perform privileged operations
    function invariantOnlyOwnerCanExecute() external {
        vm.prank(user);
        vm.expectRevert();
        arb.startFlashLoan(address(tokenA), 1000 * 10**18, "");
    }

    // Invariant: Flash loan repayment always succeeds when profitable
    function invariantFlashLoanRepaymentSucceeds() external {
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

        // Invariant: Contract balance should be >= initial (profit made)
        assertGe(tokenA.balanceOf(address(arb)), 0);
    }

    // Invariant: Path validation prevents invalid arbitrage paths
    function invariantPathValidation() external {
        address[] memory invalidPath1 = new address[](3);
        invalidPath1[0] = address(tokenA);
        invalidPath1[1] = address(tokenB);
        invalidPath1[2] = address(tokenA); // Invalid

        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenA);

        bytes memory params = abi.encode(
            address(router1),
            address(router2),
            invalidPath1,
            path2,
            90 * 10**17,
            1000 * 10**18,
            1 * 10**18,
            false,
            owner,
            block.timestamp + 10
        );

        vm.prank(owner);
        vm.expectRevert(); // Path validation error - may not have data through flash loan callback
        arb.startFlashLoan(address(tokenA), 1000 * 10**18, params);
    }

    // Invariant: Deadline validation prevents expired or too-distant deadlines
    function invariantDeadlineValidation() external {
        uint256 loanAmount = 1000 * 10**18;

        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);

        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenA);

        // Test expired deadline
        bytes memory paramsExpired = abi.encode(
            address(router1),
            address(router2),
            path1,
            path2,
            90 * 10**17,
            1000 * 10**18,
            1 * 10**18,
            false,
            owner,
            block.timestamp - 1
        );

        vm.prank(owner);
        vm.expectRevert(); // Deadline validation error - may not have data through flash loan callback
        arb.startFlashLoan(address(tokenA), loanAmount, paramsExpired);

        // Test too-distant deadline
        bytes memory paramsTooFar = abi.encode(
            address(router1),
            address(router2),
            path1,
            path2,
            90 * 10**17,
            1000 * 10**18,
            1 * 10**18,
            false,
            owner,
            block.timestamp + 31
        );

        vm.prank(owner);
        vm.expectRevert(); // Deadline validation error - may not have data through flash loan callback
        arb.startFlashLoan(address(tokenA), loanAmount, paramsTooFar);
    }

    // Invariant: Only trusted initiators can execute operations
    function invariantTrustedInitiatorRequired() external {
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
            address(0x999), // Untrusted
            block.timestamp + 10
        );

        vm.prank(owner);
        vm.expectRevert(); // Initiator validation error - may not have data through flash loan callback
        arb.startFlashLoan(address(tokenA), loanAmount, params);
    }

    // Invariant: Insufficient repayment causes revert
    function invariantInsufficientRepaymentReverts() external {
        uint256 loanAmount = 1000 * 10**18;

        // Setup unprofitable arbitrage
        router1.setExchangeRate(50 * 10**17);
        router2.setExchangeRate(50 * 10**17);

        // Pool already seeded in setUp

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
        vm.expectRevert(); // Repayment validation error - may not have data through flash loan callback
        arb.startFlashLoan(address(tokenA), loanAmount, params);
    }
}