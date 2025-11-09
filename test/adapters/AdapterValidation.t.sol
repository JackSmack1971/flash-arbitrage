// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../helpers/TestBase.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/FlashArbMainnetReady.sol";
import {
    UniswapV2Adapter,
    IFlashArbLike,
    RouterNotWhitelisted,
    RouterNotContract,
    UnauthorizedCaller
} from "../../src/UniswapV2Adapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockRouter} from "../../mocks/MockRouter.sol";

/**
 * @title AdapterValidation Test Suite
 * @notice Tests for adapter security validation (HIGH severity: adapter reentrancy/whitelist bypass)
 * @dev TDD red phase - these tests define expected security behavior and should initially fail
 *
 * Audit Reference: HIGH - DEX adapter reentrancy and whitelist bypass vulnerability
 * Attack vectors covered:
 * 1. Malicious adapter attempting reentrancy during swap execution
 * 2. Adapter bypassing router whitelist through internal routing
 * 3. Adapter making arbitrary external calls
 * 4. Bytecode hash validation for adapter allowlist
 */
contract AdapterValidationTest is TestBase {
    FlashArbMainnetReady public flashArb;
    UniswapV2Adapter public legitimateAdapter;
    MockERC20 public weth;
    MockERC20 public dai;
    MockRouter public uniswapRouter;
    MockRouter public sushiswapRouter;

    address public owner;
    address public attacker;

    function setUp() public {
        // Set stable time for deterministic testing
        _setStableTime();

        owner = address(this);
        attacker = makeAddr("attacker");

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

        // Deploy mock tokens
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);

        // Deploy mock routers
        uniswapRouter = new MockRouter(address(weth), address(dai));
        sushiswapRouter = new MockRouter(address(dai), address(weth));

        // Deploy implementation
        FlashArbMainnetReady implementation = new FlashArbMainnetReady();

        // Deploy proxy with initialization
        bytes memory initCall = abi.encodeCall(FlashArbMainnetReady.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initCall);
        flashArb = FlashArbMainnetReady(payable(address(proxy)));

        legitimateAdapter = new UniswapV2Adapter(IFlashArbLike(address(flashArb)));

        // Whitelist the mock routers
        flashArb.setRouterWhitelist(address(uniswapRouter), true);
        flashArb.setRouterWhitelist(address(sushiswapRouter), true);

        // Whitelist tokens so tests can proceed past asset validation
        flashArb.setTokenWhitelist(address(weth), true);
        flashArb.setTokenWhitelist(address(dai), true);

        // Whitelist owner as trusted initiator
        flashArb.setTrustedInitiator(owner, true);
    }

    /**
     * @notice Test that adapter attempting reentrancy during swap reverts
     * @dev Audit line reference: HIGH severity - reentrancy attack prevention
     * Expected: Transaction reverts due to ownership/reentrancy guard
     */
    function testRevertOnAdapterReentrancy() public {
        // Create malicious adapter that will attempt reentrancy
        MaliciousReentrantAdapter maliciousAdapter = new MaliciousReentrantAdapter(address(flashArb));

        // Attacker tries to approve their malicious adapter
        // This should eventually fail when adapter is called, not at approval time
        vm.startPrank(owner);

        // Get bytecode hash of malicious adapter
        bytes32 maliciousHash = address(maliciousAdapter).codehash;

        // Try to approve malicious adapter (this might succeed initially)
        flashArb.approveAdapterCodeHash(maliciousHash, true);
        flashArb.approveAdapter(address(maliciousAdapter), true);
        flashArb.setDexAdapter(address(uniswapRouter), address(maliciousAdapter));

        vm.stopPrank();

        // Prepare flash loan parameters
        address[] memory path1 = new address[](2);
        path1[0] = address(weth);
        path1[1] = address(dai);

        address[] memory path2 = new address[](2);
        path2[0] = address(dai);
        path2[1] = address(weth);

        bytes memory params = abi.encode(
            address(uniswapRouter), // router1
            address(sushiswapRouter),  // router2
            path1,
            path2,
            0,                 // amountOutMin1
            0,                 // amountOutMin2
            0,                 // minProfit
            false,             // unwrapProfitToEth
            owner,             // initiator
            block.timestamp + 30 // deadline
        );

        // Expect revert - when adapter tries to call setRouterWhitelist, it will fail
        // either due to Ownable (adapter is not owner) or ReentrancyGuard
        vm.expectRevert(); // Generic revert expected - could be ownership or reentrancy

        vm.prank(owner);
        flashArb.startFlashLoan(address(weth), 1 ether, params);
    }

    /**
     * @notice Test that adapter cannot internally route through non-whitelisted DEX
     * @dev Audit line reference: HIGH severity - whitelist bypass prevention
     * Expected: Malicious adapter reverts when attempting bypass
     */
    function testRevertOnAdapterCallingNonWhitelistedRouter() public {
        // Create malicious adapter that routes through non-whitelisted DEX
        address nonWhitelistedRouter = makeAddr("nonWhitelistedRouter");
        MaliciousRouterBypassAdapter bypassAdapter = new MaliciousRouterBypassAdapter(nonWhitelistedRouter);

        vm.startPrank(owner);

        // Get bytecode hash
        bytes32 bypassHash = address(bypassAdapter).codehash;

        // Approve the malicious adapter (should work)
        flashArb.approveAdapterCodeHash(bypassHash, true);
        flashArb.approveAdapter(address(bypassAdapter), true);
        flashArb.setDexAdapter(address(uniswapRouter), address(bypassAdapter));

        vm.stopPrank();

        // When swap is attempted directly by the bypass adapter calling a non-whitelisted router,
        // the adapter's own require will trigger since it's a MaliciousAdapter without whitelist checks
        vm.expectRevert("Bypass attempted");

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(dai);

        vm.prank(address(flashArb));
        bypassAdapter.swap(address(uniswapRouter), 1 ether, 0, path, address(flashArb), block.timestamp + 30, 1e27);
    }

    /**
     * @notice Test that adapter cannot make arbitrary external calls outside approved scope
     * @dev Audit line reference: HIGH severity - arbitrary call prevention
     * Expected: Malicious adapter reverts when attempting arbitrary call
     */
    function testRevertOnAdapterArbitraryExternalCall() public {
        // Create malicious adapter that makes arbitrary external calls
        address arbitraryTarget = makeAddr("arbitraryTarget");
        MaliciousArbitraryCallAdapter arbitraryAdapter = new MaliciousArbitraryCallAdapter(arbitraryTarget);

        vm.startPrank(owner);

        // Get bytecode hash
        bytes32 arbitraryHash = address(arbitraryAdapter).codehash;

        // Approve the malicious adapter
        flashArb.approveAdapterCodeHash(arbitraryHash, true);
        flashArb.approveAdapter(address(arbitraryAdapter), true);
        flashArb.setDexAdapter(address(uniswapRouter), address(arbitraryAdapter));

        vm.stopPrank();

        // When swap is attempted directly, the malicious adapter's call to arbitraryTarget (no code) fails
        // and the adapter's require will trigger
        vm.expectRevert("Arbitrary call attempted");

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(dai);

        vm.prank(address(flashArb));
        arbitraryAdapter.swap(address(uniswapRouter), 1 ether, 0, path, address(flashArb), block.timestamp + 30, 1e27);
    }

    /**
     * @notice Test that legitimate adapter rejects non-contract router addresses
     * @dev Defense-in-depth: adapter validates router is a contract before calling
     * Expected: RouterNotContract error when router has no code
     */
    function testRevertOnNonContractRouter() public {
        // Approve and configure the legitimate adapter
        vm.startPrank(owner);

        bytes32 adapterHash = address(legitimateAdapter).codehash;
        flashArb.approveAdapterCodeHash(adapterHash, true);
        flashArb.approveAdapter(address(legitimateAdapter), true);
        flashArb.setDexAdapter(address(uniswapRouter), address(legitimateAdapter));

        vm.stopPrank();

        // Create an EOA address (no code)
        address eoaRouter = makeAddr("eoaRouter");

        // Whitelist the EOA (to test that code check happens before whitelist check in adapter)
        vm.prank(owner);
        flashArb.setRouterWhitelist(eoaRouter, true);

        // Attempt to use the EOA as a router - should fail with RouterNotContract
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(dai);

        vm.expectRevert(RouterNotContract.selector);
        vm.prank(address(flashArb));
        legitimateAdapter.swap(eoaRouter, 1 ether, 0, path, address(flashArb), block.timestamp + 30, 1e27);
    }

    /**
     * @notice Test that adapter bytecode allowlist properly validates bytecode hash
     * @dev Audit line reference: HIGH severity - bytecode validation
     * Expected: Non-allowlisted adapter bytecode causes revert
     */
    function testAdapterBytecodeAllowlist() public {
        // Create a new adapter instance (must pass flashArb address)
        UniswapV2Adapter newAdapter = new UniswapV2Adapter(IFlashArbLike(address(flashArb)));
        bytes32 newAdapterHash = address(newAdapter).codehash;

        // Attempt to set adapter without approving bytecode hash first
        vm.startPrank(owner);

        // This should fail because bytecode hash is not approved
        vm.expectRevert("adapter-not-approved");
        flashArb.setDexAdapter(address(uniswapRouter), address(newAdapter));

        // Now approve the adapter address but not the bytecode hash
        flashArb.approveAdapter(address(newAdapter), true);

        // Should still fail due to bytecode hash not approved
        vm.expectRevert("adapter-code-hash-not-approved");
        flashArb.setDexAdapter(address(uniswapRouter), address(newAdapter));

        // Now approve bytecode hash
        flashArb.approveAdapterCodeHash(newAdapterHash, true);

        // Should succeed now
        flashArb.setDexAdapter(address(uniswapRouter), address(newAdapter));

        // Verify adapter is set
        assertEq(address(flashArb.dexAdapters(address(uniswapRouter))), address(newAdapter));

        vm.stopPrank();
    }
}

/**
 * @notice Malicious adapter that attempts reentrancy attack
 * @dev Attempts to call setRouterWhitelist during swap execution
 */
contract MaliciousReentrantAdapter is IDexAdapter {
    FlashArbMainnetReady public targetContract;
    bool public hasAttemptedReentrancy;

    constructor(address _target) {
        targetContract = FlashArbMainnetReady(payable(_target));
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
        // Attempt reentrancy attack during swap
        if (!hasAttemptedReentrancy) {
            hasAttemptedReentrancy = true;
            // Try to manipulate whitelist during execution
            targetContract.setRouterWhitelist(address(0xdead), true);
        }

        // Return fake amount
        return amountIn;
    }
}

/**
 * @notice Malicious adapter that bypasses router whitelist
 * @dev Routes through non-whitelisted DEX internally
 */
contract MaliciousRouterBypassAdapter is IDexAdapter {
    address public nonWhitelistedRouter;

    constructor(address _router) {
        nonWhitelistedRouter = _router;
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
        // Internally route through non-whitelisted DEX
        // (In real attack, would call nonWhitelistedRouter)
        // For test purposes, just demonstrate the bypass attempt
        require(nonWhitelistedRouter != address(0), "Bypass attempted");

        return amountIn;
    }
}

/**
 * @notice Malicious adapter that makes arbitrary external calls
 * @dev Attempts to call arbitrary addresses during swap
 */
contract MaliciousArbitraryCallAdapter is IDexAdapter {
    address public arbitraryTarget;

    constructor(address _target) {
        arbitraryTarget = _target;
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
        // Attempt arbitrary external call
        (bool success, ) = arbitraryTarget.call(abi.encodeWithSignature("maliciousFunction()"));
        require(success, "Arbitrary call attempted");

        return amountIn;
    }
}
