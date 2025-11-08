// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FlashArbMainnetReady} from "../src/FlashArbMainnetReady.sol";
import {UniswapV2Adapter} from "../src/UniswapV2Adapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockLendingPool} from "../mocks/MockLendingPool.sol";
import {MockRouter} from "../mocks/MockRouter.sol";

contract FlashArbEchidnaTest is Test {
    FlashArbMainnetReady arb;
    UniswapV2Adapter adapter;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockLendingPool lendingPool;
    MockRouter router1;
    MockRouter router2;

    address owner = address(1);
    address attacker = address(0xdead);

    uint256 private constant MAX_LOAN = 1000000 * 10**18;

    constructor() {
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
        vm.etch(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, hex"00"); // WETH
        vm.etch(0x6B175474E89094C44Da98b954EedeAC495271d0F, hex"00"); // DAI
        vm.etch(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, hex"00"); // USDC
        vm.etch(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, hex"00"); // UNISWAP_V2_ROUTER
        vm.etch(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F, hex"00"); // SUSHISWAP_ROUTER

        // Deploy mocks
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        lendingPool = new MockLendingPool();
        router1 = new MockRouter(address(tokenA), address(tokenB));
        router2 = new MockRouter(address(tokenB), address(tokenA));

        // Deploy implementation
        FlashArbMainnetReady implementation = new FlashArbMainnetReady();

        // Deploy proxy with initialization
        vm.prank(owner);
        bytes memory initCall = abi.encodeCall(FlashArbMainnetReady.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initCall);
        arb = FlashArbMainnetReady(payable(address(proxy)));

        // Setup adapters
        vm.prank(owner);
        adapter = new UniswapV2Adapter();

        // Whitelist the mock routers
        vm.prank(owner);
        arb.setRouterWhitelist(address(router1), true);
        vm.prank(owner);
        arb.setRouterWhitelist(address(router2), true);

        // Approve adapter and its bytecode hash
        bytes32 adapterHash = address(adapter).codehash;
        vm.prank(owner);
        arb.approveAdapterCodeHash(adapterHash, true);
        vm.prank(owner);
        arb.approveAdapter(address(adapter), true);

        vm.prank(owner);
        arb.setDexAdapter(address(router1), address(adapter));
        vm.prank(owner);
        arb.setDexAdapter(address(router2), address(adapter));
    }

    // Property: Contract never holds tokens after operations
    function echidna_contract_never_holds_tokens() public returns (bool) {
        return tokenA.balanceOf(address(arb)) == 0 && tokenB.balanceOf(address(arb)) == 0;
    }

    // Property: Only owner can execute flash loans
    function echidna_only_owner_can_execute() public returns (bool) {
        // Try to execute as non-owner
        vm.prank(attacker);
        try arb.startFlashLoan(address(tokenA), 1000 * 10**18, "") {
            return false; // Should not succeed
        } catch {
            return true; // Should revert
        }
    }

    // Property: Flash loan always repays when profitable
    function echidna_flash_loan_repays_when_profitable(uint256 loanAmount, uint256 rate1, uint256 rate2) public returns (bool) {
        // Bound inputs
        loanAmount = loanAmount % MAX_LOAN + 1;
        rate1 = rate1 % (10 * 10**18) + 10**17; // 0.1 to 10
        rate2 = rate2 % (10 * 10**18) + 10**17;

        // Setup profitable rates
        router1.setExchangeRate(rate1);
        router2.setExchangeRate(rate2);

        // Fund lending pool
        deal(address(tokenA), address(lendingPool), loanAmount);

        // Calculate if profitable
        uint256 amountOut1 = (loanAmount * rate1) / 10**18;
        uint256 amountOut2 = (amountOut1 * rate2) / 10**18;
        bool isProfitable = amountOut2 > loanAmount;

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
            (amountOut1 * 95) / 100,
            (amountOut2 * 95) / 100,
            1 * 10**18,
            false,
            owner,
            block.timestamp + 3600
        );

        vm.prank(owner);
        try arb.startFlashLoan(address(tokenA), loanAmount, params) {
            // If execution succeeded, it should have been profitable
            return isProfitable;
        } catch Error(string memory reason) {
            // If it reverted, it should not have been profitable
            return !isProfitable && (keccak256(bytes(reason)) == keccak256(bytes("insufficient-to-repay")));
        } catch {
            // Other reverts are unexpected
            return false;
        }
    }

    // Property: Invalid paths always revert
    function echidna_invalid_paths_revert(uint256 pathConfig) public returns (bool) {
        uint256 loanAmount = 1000 * 10**18;

        address[] memory path1 = new address[](2);
        address[] memory path2 = new address[](2);

        // Create potentially invalid path configuration
        if (pathConfig % 2 == 0) {
            path1[0] = address(tokenA);
            path1[1] = address(tokenB);
            path2[0] = address(tokenA); // Invalid - should be tokenB
            path2[1] = address(tokenA);
        } else {
            path1[0] = address(tokenA);
            path1[1] = address(tokenB);
            path2[0] = address(tokenB);
            path2[1] = address(tokenA);
        }

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
        try arb.startFlashLoan(address(tokenA), loanAmount, params) {
            // Should only succeed with valid paths
            return path2[0] == address(tokenB);
        } catch Error(string memory reason) {
            // Should revert with invalid paths
            return path2[0] != address(tokenB) &&
                   (keccak256(bytes(reason)) == keccak256(bytes("path2 must start with intermediate token")));
        } catch {
            return false;
        }
    }

    // Property: Deadline validation works correctly
    function echidna_deadline_validation(uint256 deadline) public returns (bool) {
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
            deadline
        );

        vm.prank(owner);
        try arb.startFlashLoan(address(tokenA), loanAmount, params) {
            // Should only succeed with valid deadlines
            return deadline >= block.timestamp && deadline <= block.timestamp + 30;
        } catch Error(string memory reason) {
            // Should revert with invalid deadlines
            return (deadline < block.timestamp || deadline > block.timestamp + 30) &&
                   (keccak256(bytes(reason)) == keccak256(bytes("deadline-invalid")));
        } catch {
            return false;
        }
    }

    // Property: Only trusted initiators can execute
    function echidna_trusted_initiator_required(address initiator) public returns (bool) {
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
            initiator,
            block.timestamp + 10
        );

        vm.prank(owner);
        try arb.startFlashLoan(address(tokenA), loanAmount, params) {
            // Should only succeed with trusted initiators
            return arb.trustedInitiators(initiator);
        } catch Error(string memory reason) {
            // Should revert with untrusted initiators
            return !arb.trustedInitiators(initiator) &&
                   (keccak256(bytes(reason)) == keccak256(bytes("initiator-not-trusted")));
        } catch {
            return false;
        }
    }

    // Property: Contract state remains consistent
    function echidna_contract_state_consistent() public returns (bool) {
        // Check that contract maintains valid state
        return arb.owner() != address(0) &&
               address(arb).balance == 0; // Should not hold ETH
    }

    // Property: No unexpected token transfers
    function echidna_no_unexpected_transfers(uint256 loanAmount) public returns (bool) {
        loanAmount = loanAmount % MAX_LOAN + 1;

        uint256 balanceBeforeA = tokenA.balanceOf(address(arb));
        uint256 balanceBeforeB = tokenB.balanceOf(address(arb));

        // Setup and execute operation
        router1.setExchangeRate(1 * 10**18);
        router2.setExchangeRate(1 * 10**18);
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
            loanAmount / 2,
            loanAmount,
            0,
            false,
            owner,
            block.timestamp + 3600
        );

        vm.prank(owner);
        try arb.startFlashLoan(address(tokenA), loanAmount, params) {
            // After successful operation, contract should not hold tokens
            return tokenA.balanceOf(address(arb)) == 0 && tokenB.balanceOf(address(arb)) == 0;
        } catch {
            // On revert, balances should be unchanged
            return tokenA.balanceOf(address(arb)) == balanceBeforeA &&
                   tokenB.balanceOf(address(arb)) == balanceBeforeB;
        }
    }
}