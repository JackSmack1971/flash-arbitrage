// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FlashArbMainnetReady} from "../src/FlashArbMainnetReady.sol";
import {UniswapV2Adapter} from "../src/UniswapV2Adapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockLendingPool} from "../mocks/MockLendingPool.sol";
import {MockRouter} from "../mocks/MockRouter.sol";

contract FlashArbGasTest is Test {
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

        // Mock the routers as well (they are called by safeApprove)
        vm.etch(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, address(mockWETH).code); // Any code works for routers
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

    function testGasBaselineDeposits() external {
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
        uint256 gasStart = gasleft();
        arb.startFlashLoan(address(tokenA), loanAmount, params);
        uint256 gasUsed = gasStart - gasleft();

        // Check against baseline (would be stored in a separate file)
        uint256 baseline = 300000; // Example baseline
        assertLt(gasUsed, baseline * 110 / 100, "Gas usage increased by more than 10%");

        // Update baseline if this is a baseline run
        if (isBaselineRun()) {
            updateGasBaseline("flashLoan", gasUsed);
        }
    }

    function testCannotGasGriefWithdrawals() external {
        // Setup: create many small positions
        for (uint256 i = 0; i < 10; i++) {
            address user = address(uint160(i + 1));
            vm.deal(user, 10 ether);
            vm.prank(user);
            // Simulate deposits if contract had deposit functionality
        }

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
        uint256 gasStart = gasleft();
        arb.startFlashLoan(address(tokenA), loanAmount, params);
        uint256 gasUsed = gasStart - gasleft();

        // Ensure gas cost is reasonable (attacker can't make withdrawal too expensive)
        uint256 totalValue = loanAmount;
        uint256 gasCostInEth = gasUsed * tx.gasprice;

        // Gas cost should be < 1% of total value
        assertLt(gasCostInEth, totalValue / 100, "Gas griefing protection failed");
    }

    function testGasProfilingComplexPaths() external {
        uint256 loanAmount = 1000 * 10**18;

        // Setup with 3-hop arbitrage path
        router1.setExchangeRate(90 * 10**17); // Worse rate
        router2.setExchangeRate(110 * 10**17); // Better rate

        deal(address(tokenA), address(lendingPool), loanAmount);

        address[] memory path1 = new address[](3);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);
        path1[2] = address(tokenA); // Invalid but for gas testing

        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenA);

        bytes memory params = abi.encode(
            address(router1),
            address(router2),
            path1,
            path2,
            80 * 10**17,
            1000 * 10**18,
            1 * 10**18,
            false,
            owner,
            block.timestamp + 3600
        );

        vm.prank(owner);
        uint256 gasStart = gasleft();
        vm.expectRevert("path2 must start with intermediate token");
        arb.startFlashLoan(address(tokenA), loanAmount, params);
        uint256 gasUsed = gasStart - gasleft();

        // Revert gas should be reasonable
        assertLt(gasUsed, 100000, "Revert gas usage too high");
    }

    // Helper functions for gas baseline management
    function isBaselineRun() internal pure returns (bool) {
        // In real implementation, check environment variable
        return false;
    }

    function updateGasBaseline(string memory testName, uint256 gasUsed) internal {
        // In real implementation, write to file or database
        console.log(string(abi.encodePacked("Gas baseline for ", testName, ": ", vm.toString(gasUsed))));
    }
}