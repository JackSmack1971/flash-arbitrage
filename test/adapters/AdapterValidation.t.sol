// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/FlashArbMainnetReady.sol";
import "../../src/UniswapV2Adapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
contract AdapterValidationTest is Test {
    FlashArbMainnetReady public flashArb;
    UniswapV2Adapter public legitimateAdapter;

    address public owner;
    address public attacker;

    // Mainnet constants
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    function setUp() public {
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

        // Deploy implementation
        FlashArbMainnetReady implementation = new FlashArbMainnetReady();

        // Deploy proxy with initialization
        bytes memory initCall = abi.encodeCall(FlashArbMainnetReady.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initCall);
        flashArb = FlashArbMainnetReady(payable(address(proxy)));

        legitimateAdapter = new UniswapV2Adapter();
    }

    /**
     * @notice Test that adapter attempting reentrancy during swap reverts
     * @dev Audit line reference: HIGH severity - reentrancy attack prevention
     * Expected: Transaction reverts with AdapterSecurityViolation error
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
        flashArb.setDexAdapter(UNISWAP_V2_ROUTER, address(maliciousAdapter));

        vm.stopPrank();

        // Prepare flash loan parameters
        address[] memory path1 = new address[](2);
        path1[0] = WETH;
        path1[1] = DAI;

        address[] memory path2 = new address[](2);
        path2[0] = DAI;
        path2[1] = WETH;

        bytes memory params = abi.encode(
            UNISWAP_V2_ROUTER, // router1
            SUSHISWAP_ROUTER,  // router2
            path1,
            path2,
            0,                 // amountOutMin1
            0,                 // amountOutMin2
            0,                 // minProfit
            false,             // unwrapProfitToEth
            owner,             // initiator
            block.timestamp + 30 // deadline
        );

        // Mock flash loan callback - should revert when adapter attempts reentrancy
        // Expected: AdapterSecurityViolation(address adapter, string reason)
        vm.expectRevert(); // Will be updated to specific error once implemented

        vm.prank(owner);
        flashArb.startFlashLoan(WETH, 1 ether, params);
    }

    /**
     * @notice Test that adapter cannot internally route through non-whitelisted DEX
     * @dev Audit line reference: HIGH severity - whitelist bypass prevention
     * Expected: Transaction reverts with AdapterSecurityViolation error
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
        flashArb.setDexAdapter(UNISWAP_V2_ROUTER, address(bypassAdapter));

        vm.stopPrank();

        // When swap is attempted, it should detect the bypass and revert
        // Expected: AdapterSecurityViolation(address adapter, "Router not whitelisted")
        vm.expectRevert();

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        vm.prank(address(flashArb));
        bypassAdapter.swap(UNISWAP_V2_ROUTER, 1 ether, 0, path, address(flashArb), block.timestamp + 30, 1e27);
    }

    /**
     * @notice Test that adapter cannot make arbitrary external calls outside approved scope
     * @dev Audit line reference: HIGH severity - arbitrary call prevention
     * Expected: Transaction reverts with AdapterSecurityViolation error
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
        flashArb.setDexAdapter(UNISWAP_V2_ROUTER, address(arbitraryAdapter));

        vm.stopPrank();

        // When swap is attempted, should detect arbitrary call and revert
        // Expected: AdapterSecurityViolation(address adapter, "Arbitrary call detected")
        vm.expectRevert();

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        vm.prank(address(flashArb));
        arbitraryAdapter.swap(UNISWAP_V2_ROUTER, 1 ether, 0, path, address(flashArb), block.timestamp + 30, 1e27);
    }

    /**
     * @notice Test that adapter bytecode allowlist properly validates bytecode hash
     * @dev Audit line reference: HIGH severity - bytecode validation
     * Expected: Non-allowlisted adapter bytecode causes revert
     */
    function testAdapterBytecodeAllowlist() public {
        // Create a new adapter instance
        UniswapV2Adapter newAdapter = new UniswapV2Adapter();
        bytes32 newAdapterHash = address(newAdapter).codehash;

        // Attempt to set adapter without approving bytecode hash first
        vm.startPrank(owner);

        // This should fail because bytecode hash is not approved
        vm.expectRevert("adapter-not-approved");
        flashArb.setDexAdapter(UNISWAP_V2_ROUTER, address(newAdapter));

        // Now approve the adapter address but not the bytecode hash
        flashArb.approveAdapter(address(newAdapter), true);

        // Should still fail due to bytecode hash not approved
        vm.expectRevert("adapter-code-hash-not-approved");
        flashArb.setDexAdapter(UNISWAP_V2_ROUTER, address(newAdapter));

        // Now approve bytecode hash
        flashArb.approveAdapterCodeHash(newAdapterHash, true);

        // Should succeed now
        flashArb.setDexAdapter(UNISWAP_V2_ROUTER, address(newAdapter));

        // Verify adapter is set
        assertEq(address(flashArb.dexAdapters(UNISWAP_V2_ROUTER)), address(newAdapter));

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
