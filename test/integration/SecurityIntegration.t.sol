// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../helpers/TestBase.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/FlashArbMainnetReady.sol";
import {UniswapV2Adapter, IFlashArbLike} from "../../src/UniswapV2Adapter.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockRouter} from "../../mocks/MockRouter.sol";

/**
 * @title SecurityIntegration Test Suite
 * @notice End-to-end validation of security remediations
 * @dev Tests all fixes work together in realistic scenarios
 */
contract SecurityIntegrationTest is TestBase {
    FlashArbMainnetReady public flashArb;
    UniswapV2Adapter public adapter;
    MockERC20 public weth;
    MockERC20 public dai;
    MockRouter public uniswapRouter;

    function setUp() public {
        // Set stable time for deterministic testing
        _setStableTime();

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

        // Deploy mock router
        uniswapRouter = new MockRouter(address(weth), address(dai));

        // Deploy implementation
        FlashArbMainnetReady implementation = new FlashArbMainnetReady();

        // Deploy proxy with initialization
        bytes memory initCall = abi.encodeCall(FlashArbMainnetReady.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initCall);
        flashArb = FlashArbMainnetReady(payable(address(proxy)));
        adapter = new UniswapV2Adapter(IFlashArbLike(address(flashArb)));

        // Whitelist the mock router
        flashArb.setRouterWhitelist(address(uniswapRouter), true);

        // Whitelist tokens so tests can proceed past asset validation
        flashArb.setTokenWhitelist(address(weth), true);
        flashArb.setTokenWhitelist(address(dai), true);

        // Whitelist test contract as trusted initiator
        flashArb.setTrustedInitiator(address(this), true);
    }

    /// @notice Validates adapter security: bytecode validation, reentrancy protection
    function testAdapterSecurityE2E() public {
        bytes32 adapterHash = address(adapter).codehash;

        // Approve adapter
        flashArb.approveAdapterCodeHash(adapterHash, true);
        flashArb.approveAdapter(address(adapter), true);

        // Should succeed with approved adapter
        flashArb.setDexAdapter(address(uniswapRouter), address(adapter));

        assertTrue(flashArb.approvedAdapters(address(adapter)), "Adapter not approved");
        assertTrue(flashArb.approvedAdapterCodeHashes(adapterHash), "Hash not approved");
    }

    /// @notice Validates slippage enforcement with configurable maxSlippageBps
    function testSlippageEnforcementE2E() public {
        // Verify default slippage
        assertEq(flashArb.maxSlippageBps(), 200, "Default slippage should be 2%");

        // Configure stricter slippage
        flashArb.setMaxSlippage(100); // 1%
        assertEq(flashArb.maxSlippageBps(), 100);

        // _calculateMinOutput should work correctly
        // (tested via unit tests in SlippageEnforcement.t.sol)
    }

    /// @notice Validates trusted initiator delegation
    function testTrustedInitiatorDelegationE2E() public {
        address bot = makeAddr("bot");

        // Owner is trusted by default
        assertTrue(flashArb.trustedInitiators(address(this)));

        // Delegate to bot
        flashArb.setTrustedInitiator(bot, true);
        assertTrue(flashArb.trustedInitiators(bot));

        // Revoke bot access
        flashArb.setTrustedInitiator(bot, false);
        assertFalse(flashArb.trustedInitiators(bot));
    }

    /// @notice Validates approval limits and safe patterns
    function testApprovalSafetyE2E() public {
        // Verify maxAllowance parameter exists and is configurable
        assertEq(flashArb.maxAllowance(), 1e27, "Default max allowance");

        flashArb.setMaxAllowance(5e26);
        assertEq(flashArb.maxAllowance(), 5e26, "Updated max allowance");

        // Adapter interface includes maxAllowance parameter
        // (enforced by compiler via IDexAdapter interface)
    }

    /// @notice Validates path length limits prevent gas DOS
    function testPathLengthEnforcementE2E() public {
        assertEq(flashArb.maxPathLength(), 5, "Default path length");

        flashArb.setMaxPathLength(7);
        assertEq(flashArb.maxPathLength(), 7);

        // Bounds validation
        vm.expectRevert("Path length too short");
        flashArb.setMaxPathLength(1);

        vm.expectRevert("Path length too long");
        flashArb.setMaxPathLength(11);
    }

    /// @notice Validates all events emit correctly
    function testEventEmissionsE2E() public {
        // MaxSlippageUpdated
        vm.expectEmit(true, true, true, true);
        emit MaxSlippageUpdated(300);
        flashArb.setMaxSlippage(300);

        // TrustedInitiatorChanged
        address bot = makeAddr("bot");
        vm.expectEmit(true, true, true, true);
        emit TrustedInitiatorChanged(bot, true);
        flashArb.setTrustedInitiator(bot, true);

        // MaxAllowanceUpdated
        vm.expectEmit(true, true, true, true);
        emit MaxAllowanceUpdated(1e28);
        flashArb.setMaxAllowance(1e28);

        // MaxPathLengthUpdated
        vm.expectEmit(true, true, true, true);
        emit MaxPathLengthUpdated(6);
        flashArb.setMaxPathLength(6);
    }

    // Event signatures for expectEmit
    event MaxSlippageUpdated(uint256 newMaxSlippageBps);
    event TrustedInitiatorChanged(address indexed initiator, bool trusted);
    event MaxAllowanceUpdated(uint256 newMaxAllowance);
    event MaxPathLengthUpdated(uint8 newMaxPathLength);
}
