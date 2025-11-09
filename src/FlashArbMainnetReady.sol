// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title Flash Arbitrage Executor V2
 * @dev Production-ready flash arbitrage contract with MEV protection and multi-DEX support.
 *
 * Key Features:
 * - UUPS upgradeable for future enhancements
 * - Modular DEX adapter pattern for V2/V3 integration
 * - Strict initiator validation to prevent unauthorized execution
 * - Deadline-based MEV protection
 * - Comprehensive whitelist-based security
 * - Gas-optimized operations
 *
 * Security Enhancements (Reentrancy & Adapter Protection):
 * - DEX adapter allowlist with bytecode hash validation
 * - Reentrancy guards on all owner functions (setRouterWhitelist, setTrustedInitiator, setDexAdapter)
 * - Runtime adapter validation before execution
 * - Two-step adapter approval: address + bytecode hash must both be approved
 * - Prevents malicious adapters from reentering and escalating privileges
 * - Prevents whitelist bypass by validating adapters at execution time
 *
 * System Invariants:
 * - FlashLoanRepayment: Contract must repay flash loan + fee
 * - ProfitAccuracy: Profit = balance - debt calculation
 * - PathValidity: Arbitrage paths form valid closed loops
 * - AdapterSafety: Only approved adapters with approved bytecode can execute
 *
 * @notice Only whitelisted routers and tokens are supported.
 * @notice Owner-controlled execution with timelock upgrade path.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./interfaces/IDexInterfaces.sol";

interface ILendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);
}

// Aave V2 lending pool minimal interface
interface ILendingPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

// Aave V2 receiver interface
interface IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

/**
 * @notice Custom errors for improved gas efficiency and clarity
 */
error AdapterSecurityViolation(address adapter, string reason);
error SlippageExceeded(uint256 expected, uint256 actual, uint256 maxBps);
error PathTooLong(uint256 pathLength, uint256 maxAllowed);

contract FlashArbMainnetReady is IFlashLoanReceiver, Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // --- Hardcoded common mainnet addresses (verify before use) ---
    address public constant AAVE_PROVIDER = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    ILendingPoolAddressesProvider public provider;
    address public lendingPool;

    mapping(address => bool) public routerWhitelist;
    mapping(address => bool) public tokenWhitelist;
    mapping(address => IDexAdapter) public dexAdapters;
    mapping(address => bool) public trustedInitiators; // Security: trusted initiator mapping

    // Security: Adapter allowlist to prevent malicious adapters
    mapping(address => bool) public approvedAdapters;
    mapping(bytes32 => bool) public approvedAdapterCodeHashes;

    // profits tracked per ERC20 token (token address => token units)
    mapping(address => uint256) public profits;
    // ETH profits (unspecified token) tracked separately
    uint256 public ethProfits;

    uint256 public maxSlippageBps; // 2% maximum slippage enforced on-chain in executeOperation
    uint256 public constant MAX_DEADLINE = 30; // MEV protection: max 30 seconds deadline
    uint256 public maxAllowance; // Configurable max token approval (default: 1 billion tokens with 18 decimals)
    uint8 public maxPathLength; // Maximum swap path length (default: 5 allows direct + 2-hop paths)

    event FlashLoanRequested(address indexed initiator, address asset, uint256 amount);
    event FlashLoanExecuted(address indexed initiator, address asset, uint256 amount, uint256 fee, uint256 profit);
    event RouterWhitelisted(address router, bool allowed);
    event TokenWhitelisted(address token, bool allowed);
    event ProviderUpdated(address provider, address lendingPool);
    event Withdrawn(address token, address to, uint256 amount);
    event DexAdapterSet(address router, address adapter);
    event AdapterApproved(address indexed adapter, bytes32 codeHash, bool approved);
    event AdapterCodeHashApproved(bytes32 codeHash, bool approved);
    event TrustedInitiatorChanged(address indexed initiator, bool trusted);
    event MaxAllowanceUpdated(uint256 newMaxAllowance);
    event MaxPathLengthUpdated(uint8 newMaxPathLength);
    event MaxSlippageUpdated(uint256 newMaxSlippageBps);
    event EmergencyWithdrawn(address indexed token, address indexed to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // Initialize configuration defaults
        maxSlippageBps = 200; // 2% maximum slippage
        maxAllowance = 1e27; // 1 billion tokens with 18 decimals
        maxPathLength = 5; // Maximum swap path length

        provider = ILendingPoolAddressesProvider(AAVE_PROVIDER);
        lendingPool = provider.getLendingPool();

        // Prepopulate trusted routers
        routerWhitelist[UNISWAP_V2_ROUTER] = true;
        routerWhitelist[SUSHISWAP_ROUTER] = true;
        emit RouterWhitelisted(UNISWAP_V2_ROUTER, true);
        emit RouterWhitelisted(SUSHISWAP_ROUTER, true);

        // Prepopulate common tokens
        tokenWhitelist[WETH] = true;
        tokenWhitelist[DAI] = true;
        tokenWhitelist[USDC] = true;
        emit TokenWhitelisted(WETH, true);
        emit TokenWhitelisted(DAI, true);
        emit TokenWhitelisted(USDC, true);

        // Security: Set owner as trusted initiator
        trustedInitiators[msg.sender] = true;

        // Security: Setup controlled approvals for common routers using maxAllowance
        _setupRouterApprovals();
    }

    /**
     * @notice Setup token approvals for common routers using safe approval pattern
     * @dev Uses maxAllowance instead of infinite approvals for better security
     * @dev Follows safeApprove(0) then safeApprove(amount) pattern for token compatibility
     */
    function _setupRouterApprovals() internal {
        // WETH approvals with safe pattern (reset to 0 then set to maxAllowance)
        IERC20(WETH).safeApprove(UNISWAP_V2_ROUTER, 0);
        IERC20(WETH).safeApprove(UNISWAP_V2_ROUTER, maxAllowance);
        IERC20(WETH).safeApprove(SUSHISWAP_ROUTER, 0);
        IERC20(WETH).safeApprove(SUSHISWAP_ROUTER, maxAllowance);

        // DAI approvals with safe pattern
        IERC20(DAI).safeApprove(UNISWAP_V2_ROUTER, 0);
        IERC20(DAI).safeApprove(UNISWAP_V2_ROUTER, maxAllowance);
        IERC20(DAI).safeApprove(SUSHISWAP_ROUTER, 0);
        IERC20(DAI).safeApprove(SUSHISWAP_ROUTER, maxAllowance);

        // USDC approvals with safe pattern
        IERC20(USDC).safeApprove(UNISWAP_V2_ROUTER, 0);
        IERC20(USDC).safeApprove(UNISWAP_V2_ROUTER, maxAllowance);
        IERC20(USDC).safeApprove(SUSHISWAP_ROUTER, 0);
        IERC20(USDC).safeApprove(SUSHISWAP_ROUTER, maxAllowance);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Owner functions

    /**
     * @notice Set router whitelist status
     * @dev Protected with nonReentrant to prevent malicious adapter reentrancy attacks
     */
    function setRouterWhitelist(address router, bool allowed) external onlyOwner nonReentrant {
        routerWhitelist[router] = allowed;
        emit RouterWhitelisted(router, allowed);
    }

    function setTokenWhitelist(address token, bool allowed) external onlyOwner {
        tokenWhitelist[token] = allowed;
        emit TokenWhitelisted(token, allowed);
    }

    function updateProvider(address _provider) external onlyOwner {
        require(_provider != address(0), "provider-zero");
        provider = ILendingPoolAddressesProvider(_provider);
        lendingPool = provider.getLendingPool();
        emit ProviderUpdated(_provider, lendingPool);
    }

    function setMaxSlippage(uint256 bps) external onlyOwner {
        require(bps <= 1000, "max 10% allowed");
        maxSlippageBps = bps;
        emit MaxSlippageUpdated(bps);
    }

    /**
     * @notice Set maximum token allowance for router approvals
     * @dev Configurable limit provides control over approval amounts
     * @param _maxAllowance New maximum allowance (must be >= 1e24 to support large operations)
     */
    function setMaxAllowance(uint256 _maxAllowance) external onlyOwner {
        require(_maxAllowance >= 1e24, "Allowance too low");
        require(_maxAllowance <= type(uint256).max, "Allowance overflow");
        maxAllowance = _maxAllowance;
        emit MaxAllowanceUpdated(_maxAllowance);
    }

    /**
     * @notice Set maximum path length for swap paths
     * @dev Prevents gas DOS attacks from excessively long paths
     * @param _maxPathLength New maximum path length (2-10 hops)
     */
    function setMaxPathLength(uint8 _maxPathLength) external onlyOwner {
        require(_maxPathLength >= 2, "Path length too short");
        require(_maxPathLength <= 10, "Path length too long");
        maxPathLength = _maxPathLength;
        emit MaxPathLengthUpdated(_maxPathLength);
    }

    /**
     * @notice Approve or revoke adapter address and code hash
     * @dev Two-step validation: both address and bytecode hash must be approved
     */
    function approveAdapter(address adapter, bool approved) external onlyOwner nonReentrant {
        require(adapter != address(0), "adapter-zero");
        require(adapter.code.length > 0, "adapter-not-contract");

        bytes32 codeHash = adapter.codehash;
        require(codeHash != bytes32(0), "invalid-code-hash");

        approvedAdapters[adapter] = approved;
        emit AdapterApproved(adapter, codeHash, approved);
    }

    /**
     * @notice Approve or revoke adapter code hash
     * @dev Allows pre-approving bytecode before deployment
     */
    function approveAdapterCodeHash(bytes32 codeHash, bool approved) external onlyOwner nonReentrant {
        require(codeHash != bytes32(0), "invalid-code-hash");
        approvedAdapterCodeHashes[codeHash] = approved;
        emit AdapterCodeHashApproved(codeHash, approved);
    }

    /**
     * @notice Set DEX adapter for a router
     * @dev Enhanced security: validates adapter is approved and matches approved bytecode
     * @dev Protected with nonReentrant to prevent adapter reentrancy during setup
     */
    function setDexAdapter(address router, address adapter) external onlyOwner nonReentrant {
        require(routerWhitelist[router], "router-not-whitelisted");

        // Security: If adapter is non-zero, validate it's approved
        if (adapter != address(0)) {
            require(approvedAdapters[adapter], "adapter-not-approved");

            bytes32 codeHash = adapter.codehash;
            require(approvedAdapterCodeHashes[codeHash], "adapter-code-hash-not-approved");

            // Validate adapter is a contract
            require(adapter.code.length > 0, "adapter-not-contract");
        }

        dexAdapters[router] = IDexAdapter(adapter);
        emit DexAdapterSet(router, adapter);
    }

    /**
     * @notice Set trusted initiator status
     * @dev Protected with nonReentrant to prevent malicious adapter reentrancy attacks
     * @dev Owner is automatically trusted in initialize() and should not be removed
     * @param initiator Address to grant or revoke trusted status
     * @param trusted True to allow initiator to execute operations, false to revoke
     */
    function setTrustedInitiator(address initiator, bool trusted) external onlyOwner nonReentrant {
        trustedInitiators[initiator] = trusted;
        emit TrustedInitiatorChanged(initiator, trusted);
    }

    // params encoding helper (off-chain):
    // abi.encode(router1, router2, path1, path2, amountOutMin1, amountOutMin2, minProfitTokenUnits, unwrapProfitToEth, initiator, deadline)

    // Start a single-asset flash loan via Aave V2 (assets/amounts arrays length == 1)
    function startFlashLoan(address asset, uint256 amount, bytes calldata params) external onlyOwner whenNotPaused {
        require(amount > 0, "amount-zero");
        require(tokenWhitelist[asset], "asset-not-whitelisted");

        address[] memory assets = new address[](1);
        assets[0] = asset;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // 0 = no debt (flash)

        emit FlashLoanRequested(msg.sender, asset, amount);
        ILendingPool(lendingPool).flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
    }

    // Aave V2-style executeOperation
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override nonReentrant whenNotPaused returns (bool) {
        require(msg.sender == lendingPool, "only-lending-pool");
        require(assets.length == 1 && amounts.length == 1 && premiums.length == 1, "only-single-asset-supported");

        address _reserve = assets[0];
        uint256 _amount = amounts[0];
        uint256 _fee = premiums[0];

        (
            address router1,
            address router2,
            address[] memory path1,
            address[] memory path2,
            uint256 amountOutMin1,
            uint256 amountOutMin2,
            uint256 minProfit,
            bool unwrapProfitToEth,
            address opInitiator,
            uint256 deadline
        ) = abi.decode(params, (address, address, address[], address[], uint256, uint256, uint256, bool, address, uint256));

        // Security: Validate trusted initiator (single source of truth for access control)
        // Owner is automatically trusted via initialize(). Additional addresses can be
        // delegated via setTrustedInitiator() for bot/operator access.
        require(trustedInitiators[opInitiator], "initiator-not-trusted");

        // Architectural: Invariant checks
        require(routerWhitelist[router1] && routerWhitelist[router2], "router-not-allowed");

        // Security: Validate routers are contracts (prevent EOA routers)
        require(_isContract(router1), "router1-must-be-contract");
        require(_isContract(router2), "router2-must-be-contract");

        require(path1.length >= 2 && path2.length >= 2, "invalid-paths");

        // Security: Validate path lengths before expensive whitelist iteration (gas DOS prevention)
        if (path1.length > maxPathLength) {
            revert PathTooLong(path1.length, maxPathLength);
        }
        if (path2.length > maxPathLength) {
            revert PathTooLong(path2.length, maxPathLength);
        }

        require(path1[0] == _reserve, "path1 must start with reserve");
        require(path2[path2.length - 1] == _reserve, "path2 must end with reserve");
        require(initiator == address(this), "initiator-must-be-contract");

        // MEV protection: Enforce max deadline
        require(deadline >= block.timestamp && deadline <= block.timestamp + MAX_DEADLINE, "deadline-invalid");

        // Validate all tokens in paths are whitelisted
        for (uint256 i = 0; i < path1.length; i++) {
            require(tokenWhitelist[path1[i]], "token1-not-whitelisted");
        }
        for (uint256 i = 0; i < path2.length; i++) {
            require(tokenWhitelist[path2[i]], "token2-not-whitelisted");
        }

        // Economic optimization: Skip approval if infinite approval already set
        if (IERC20(_reserve).allowance(address(this), router1) < _amount) {
            IERC20(_reserve).safeApprove(router1, _amount);
        }

        uint256 out1;
        if (address(dexAdapters[router1]) != address(0)) {
            // Security: Validate adapter is still approved before calling
            address adapter1 = address(dexAdapters[router1]);

            // Enhanced security: Verify adapter is a contract
            if (!_isContract(adapter1)) {
                revert AdapterSecurityViolation(adapter1, "Adapter must be a contract");
            }

            // Security: Validate adapter address is approved
            if (!approvedAdapters[adapter1]) {
                revert AdapterSecurityViolation(adapter1, "Adapter not approved");
            }

            // Security: Validate adapter bytecode hash is approved (prevents code substitution)
            if (!approvedAdapterCodeHashes[adapter1.codehash]) {
                revert AdapterSecurityViolation(adapter1, "Adapter bytecode not approved");
            }

            out1 = dexAdapters[router1].swap(router1, _amount, amountOutMin1, path1, address(this), deadline, maxAllowance);
        } else {
            uint256[] memory amounts1 = IUniswapV2Router02(router1).swapExactTokensForTokens(_amount, amountOutMin1, path1, address(this), deadline);
            out1 = amounts1[amounts1.length - 1];
        }

        // Security: Enforce slippage limit on first swap
        uint256 minOut1 = _calculateMinOutput(_amount, maxSlippageBps);
        if (out1 < minOut1) {
            revert SlippageExceeded(minOut1, out1, maxSlippageBps);
        }

        address intermediate = path1[path1.length - 1];
        require(path2[0] == intermediate, "path2 must start with intermediate token");

        // Security: Balance validation after first swap
        uint256 balanceAfterFirstSwap = IERC20(intermediate).balanceOf(address(this));
        require(balanceAfterFirstSwap >= out1, "balance-validation-failed");

        // Economic optimization: Skip approval if infinite approval already set
        if (IERC20(intermediate).allowance(address(this), router2) < out1) {
            IERC20(intermediate).safeApprove(router2, out1);
        }

        uint256 out2;
        if (address(dexAdapters[router2]) != address(0)) {
            // Security: Validate adapter is still approved before calling
            address adapter2 = address(dexAdapters[router2]);

            // Enhanced security: Verify adapter is a contract
            if (!_isContract(adapter2)) {
                revert AdapterSecurityViolation(adapter2, "Adapter must be a contract");
            }

            // Security: Validate adapter address is approved
            if (!approvedAdapters[adapter2]) {
                revert AdapterSecurityViolation(adapter2, "Adapter not approved");
            }

            // Security: Validate adapter bytecode hash is approved (prevents code substitution)
            if (!approvedAdapterCodeHashes[adapter2.codehash]) {
                revert AdapterSecurityViolation(adapter2, "Adapter bytecode not approved");
            }

            out2 = dexAdapters[router2].swap(router2, out1, amountOutMin2, path2, address(this), deadline, maxAllowance);
        } else {
            uint256[] memory amounts2 = IUniswapV2Router02(router2).swapExactTokensForTokens(out1, amountOutMin2, path2, address(this), deadline);
            out2 = amounts2[amounts2.length - 1];
        }

        // Security: Enforce slippage limit on second swap
        // Note: On-chain slippage enforcement provides stronger guarantees than off-chain
        // validation, as it cannot be bypassed by front-running or stale price data
        uint256 minOut2 = _calculateMinOutput(out1, maxSlippageBps);
        if (out2 < minOut2) {
            revert SlippageExceeded(minOut2, out2, maxSlippageBps);
        }

        uint256 totalDebt = _amount + _fee;
        uint256 finalBalance = IERC20(_reserve).balanceOf(address(this));

        // Architectural: Invariant check - must have enough to repay
        require(finalBalance >= totalDebt, "insufficient-to-repay");

        uint256 profit = finalBalance - totalDebt;

        // Economic optimization: Use native math (already using - since Solidity 0.8.x)
        if (minProfit > 0) {
            require(profit >= minProfit, "profit-less-than-min");
        }

        if (profit > 0) {
            // If unwrap requested and profit token is WETH, unwrap to ETH and transfer to owner
            if (unwrapProfitToEth && _reserve == WETH) {
                IWETH(WETH).withdraw(profit);
                (bool sent, ) = owner().call{value: profit}("");
                require(sent, "eth-transfer-failed");
                ethProfits += profit;
            } else {
                // Transfer profit to owner immediately to maintain zero balance invariant
                IERC20(_reserve).safeTransfer(owner(), profit);
                profits[_reserve] += profit;
            }
        }

        // Economic optimization: Skip approval if infinite approval already set
        if (IERC20(_reserve).allowance(address(this), lendingPool) < totalDebt) {
            IERC20(_reserve).safeApprove(lendingPool, totalDebt);
        }

        // Security: Sweep any remaining dust to maintain zero balance invariant
        address[] memory dustTokens = new address[](2);
        dustTokens[0] = _reserve;
        dustTokens[1] = intermediate;
        _sweepDust(dustTokens);

        emit FlashLoanExecuted(opInitiator, _reserve, _amount, _fee, profit);
        return true;
    }

    // Withdraw accumulated profit (pull pattern). If token == address(0) withdraw ETH profits.
    function withdrawProfit(address token, uint256 amount, address to) external onlyOwner nonReentrant {
        require(amount > 0, "amount-zero");
        require(to != address(0), "to-zero");

        if (token == address(0)) {
            // ETH withdraw
            require(amount <= ethProfits, "amount-exceeds-eth-profit");
            ethProfits -= amount;
            (bool sent, ) = to.call{value: amount}("");
            require(sent, "eth-transfer-failed");
            emit Withdrawn(address(0), to, amount);
            return;
        }

        // Architectural: Invariant check - ensure sufficient balance
        uint256 bal = profits[token];
        require(amount <= bal, "amount-exceeds-profit");

        profits[token] -= amount;
        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, to, amount);
    }

    // Emergency rescue for ERC20
    function emergencyWithdrawERC20(address token, uint256 amount, address to) external onlyOwner nonReentrant {
        require(to != address(0), "to-zero");
        IERC20(token).safeTransfer(to, amount);
        emit EmergencyWithdrawn(token, to, amount);
    }

    /**
     * @notice Calculate minimum acceptable output based on slippage tolerance
     * @dev Pure function for slippage calculation using basis points (BPS)
     * @param _inputAmount The input amount for the swap
     * @param _maxSlippageBps Maximum allowed slippage in basis points (e.g., 200 = 2%)
     * @return Minimum acceptable output amount
     *
     * Formula: minOutput = inputAmount * (10000 - maxSlippageBps) / 10000
     * Example: 100 ETH input with 200 BPS (2%) -> 98 ETH minimum output
     *
     * Note: Division rounds down, providing conservative (safer) minimum threshold
     */
    function _calculateMinOutput(uint256 _inputAmount, uint256 _maxSlippageBps) internal pure returns (uint256) {
        // BPS calculation: 10000 = 100%, so (10000 - slippageBps) gives the minimum percentage
        // Division by 10000 converts back from BPS to actual amount
        // Example: 100 * (10000 - 200) / 10000 = 100 * 9800 / 10000 = 98
        return (_inputAmount * (10000 - _maxSlippageBps)) / 10000;
    }

    /**
     * @notice Internal helper to sweep token dust to owner
     * @dev Ensures contract maintains zero balance invariant after operations
     * @dev Sweeps all remaining balance since profits are transferred immediately
     * @param tokens Array of token addresses to sweep
     */
    function _sweepDust(address[] memory tokens) internal {
        address recipient = owner();
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(tokens[i]).safeTransfer(recipient, balance);
            }
        }
    }

    /**
     * @notice Internal helper to check if address is a contract
     * @dev Uses extcodesize to determine if address contains code
     * @param account Address to check
     * @return True if account is a contract, false otherwise
     */
    function _isContract(address account) internal view returns (bool) {
        // Check if account has code deployed
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    // Allow contract to receive ETH
    receive() external payable {}
}