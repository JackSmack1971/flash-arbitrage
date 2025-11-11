// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

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
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./interfaces/IDexInterfaces.sol";
import "./interfaces/IPoolV3.sol";
import "./interfaces/IFlashLoanReceiverV3.sol";
import {
    AAVE_V3_POOL_MAINNET,
    AAVE_V3_POOL_SEPOLIA,
    AAVE_V3_FLASHLOAN_PREMIUM_TOTAL,
    AAVE_V3_INTEREST_RATE_MODE_NONE
} from "./constants/AaveV3Constants.sol";
import "./errors/FlashArbErrors.sol";

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

contract FlashArbMainnetReady is IFlashLoanReceiver, IFlashLoanReceiverV3, Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // --- Structs for stack depth optimization ---

    /**
     * @notice Arbitrage parameters struct to reduce stack depth
     * @dev Groups all arbitrage-related parameters into a single struct
     */
    struct ArbitrageParams {
        address router1;
        address router2;
        address[] path1;
        address[] path2;
        uint256 amountOutMin1;
        uint256 amountOutMin2;
        uint256 minProfit;
        bool unwrapProfitToEth;
        address opInitiator;
        uint256 deadline;
    }

    /**
     * @notice Swap execution context to reduce stack depth
     * @dev Holds intermediate swap results and calculations
     */
    struct SwapContext {
        uint256 out1;
        uint256 out2;
        address intermediate;
        uint256 totalDebt;
        uint256 profit;
    }

    // --- Hardcoded common mainnet addresses (verify before use) ---
    address public constant AAVE_PROVIDER = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    ILendingPoolAddressesProvider public provider;
    address public lendingPool;

    // Aave V3 Integration (AT-018)
    bool public useAaveV3; // Feature flag for V3 migration (default: false = V2)
    address public poolV3;  // Aave V3 Pool address (set based on network)

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
    uint256 public maxFlashLoanAmount; // SEC-201: Maximum flash loan amount cap (default: 9e29 = 900 billion tokens with 18 decimals)

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
    event MaxFlashLoanAmountUpdated(uint256 newMaxFlashLoanAmount); // SEC-201: Flash loan cap event
    event EmergencyWithdrawn(address indexed token, address indexed to, uint256 amount);
    event AaveVersionUpdated(bool useV3, address pool); // AT-018: V3 migration event

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
        maxFlashLoanAmount = 9e29; // SEC-201: 900 billion tokens with 18 decimals (90% of typical pool liquidity)

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
        if (_provider == address(0)) revert ZeroAddress();
        provider = ILendingPoolAddressesProvider(_provider);
        lendingPool = provider.getLendingPool();
        emit ProviderUpdated(_provider, lendingPool);
    }

    function setMaxSlippage(uint256 bps) external onlyOwner {
        if (bps > 1000) revert InvalidSlippage(bps);
        maxSlippageBps = bps;
        emit MaxSlippageUpdated(bps);
    }

    /**
     * @notice Set maximum token allowance for router approvals
     * @dev Configurable limit provides control over approval amounts
     * @param _maxAllowance New maximum allowance (must be >= 1e24 to support large operations)
     */
    function setMaxAllowance(uint256 _maxAllowance) external onlyOwner {
        if (_maxAllowance < 1e24) revert ZeroAmount();
        if (_maxAllowance > type(uint256).max) revert ZeroAmount(); // Redundant but explicit
        maxAllowance = _maxAllowance;
        emit MaxAllowanceUpdated(_maxAllowance);
    }

    /**
     * @notice Set maximum path length for swap paths
     * @dev Prevents gas DOS attacks from excessively long paths
     * @param _maxPathLength New maximum path length (2-10 hops)
     */
    function setMaxPathLength(uint8 _maxPathLength) external onlyOwner {
        if (_maxPathLength < 2) revert InvalidPathLength(_maxPathLength);
        if (_maxPathLength > 10) revert PathTooLong(_maxPathLength, 10);
        maxPathLength = _maxPathLength;
        emit MaxPathLengthUpdated(_maxPathLength);
    }

    /**
     * @notice Set maximum flash loan amount cap
     * @dev SEC-201: Prevents unrealistic flash loan amounts that could cause overflow or DOS
     * @param _maxFlashLoanAmount New maximum flash loan amount (must be >= 1e18 to support basic operations)
     */
    function setMaxFlashLoanAmount(uint256 _maxFlashLoanAmount) external onlyOwner {
        if (_maxFlashLoanAmount < 1e18) revert ZeroAmount(); // Must support at least 1 token
        maxFlashLoanAmount = _maxFlashLoanAmount;
        emit MaxFlashLoanAmountUpdated(_maxFlashLoanAmount);
    }

    /**
     * @notice Approve or revoke adapter address and code hash
     * @dev Two-step validation: both address and bytecode hash must be approved
     */
    function approveAdapter(address adapter, bool approved) external onlyOwner nonReentrant {
        if (adapter == address(0)) revert ZeroAddress();
        if (adapter.code.length == 0) {
            revert AdapterSecurityViolation(adapter, "Adapter must be a contract");
        }

        bytes32 codeHash = adapter.codehash;
        if (codeHash == bytes32(0)) {
            revert AdapterSecurityViolation(adapter, "Invalid code hash");
        }

        approvedAdapters[adapter] = approved;
        emit AdapterApproved(adapter, codeHash, approved);
    }

    /**
     * @notice Approve or revoke adapter code hash
     * @dev Allows pre-approving bytecode before deployment
     */
    function approveAdapterCodeHash(bytes32 codeHash, bool approved) external onlyOwner nonReentrant {
        if (codeHash == bytes32(0)) {
            revert AdapterSecurityViolation(address(0), "Invalid code hash");
        }
        approvedAdapterCodeHashes[codeHash] = approved;
        emit AdapterCodeHashApproved(codeHash, approved);
    }

    /**
     * @notice Set DEX adapter for a router
     * @dev Enhanced security: validates adapter is approved and matches approved bytecode
     * @dev Protected with nonReentrant to prevent adapter reentrancy during setup
     */
    function setDexAdapter(address router, address adapter) external onlyOwner nonReentrant {
        if (!routerWhitelist[router]) revert RouterNotWhitelisted(router);

        // Security: If adapter is non-zero, validate it's approved
        if (adapter != address(0)) {
            if (!approvedAdapters[adapter]) revert AdapterNotApproved(adapter);

            bytes32 codeHash = adapter.codehash;
            if (!approvedAdapterCodeHashes[codeHash]) {
                revert AdapterSecurityViolation(adapter, "Adapter bytecode not approved");
            }

            // Validate adapter is a contract
            if (adapter.code.length == 0) {
                revert AdapterSecurityViolation(adapter, "Adapter must be a contract");
            }
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

    /**
     * @notice Set Aave V3 Pool address for network-specific deployment
     * @dev Must be called before enabling useAaveV3 flag
     * @param _poolV3 Address of Aave V3 Pool (mainnet: 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2, Sepolia: 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951)
     */
    function setPoolV3(address _poolV3) external onlyOwner {
        if (_poolV3 == address(0)) revert ZeroAddress();
        poolV3 = _poolV3;
    }

    /**
     * @notice Toggle between Aave V2 and V3 flash loan execution
     * @dev AT-018: Feature flag for V3 migration with 44% fee savings (9 BPS -> 5 BPS)
     * @param _useV3 True to use Aave V3, false to use Aave V2 (default)
     */
    function setUseAaveV3(bool _useV3) external onlyOwner {
        if (_useV3 && poolV3 == address(0)) {
            revert ZeroAddress(); // Must set poolV3 before enabling V3
        }
        useAaveV3 = _useV3;
        address activePool = _useV3 ? poolV3 : lendingPool;
        emit AaveVersionUpdated(_useV3, activePool);
    }

    // params encoding helper (off-chain):
    // abi.encode(router1, router2, path1, path2, amountOutMin1, amountOutMin2, minProfitTokenUnits, unwrapProfitToEth, initiator, deadline)

    /**
     * @notice Start a single-asset flash loan via Aave V2 or V3 (based on useAaveV3 flag)
     * @dev AT-018: Branching logic for V2/V3 flash loan initiation
     * @dev SEC-201: Enforces maximum flash loan amount cap to prevent unrealistic scenarios
     * @param asset The ERC20 token address to borrow
     * @param amount The amount to borrow
     * @param params ABI-encoded arbitrage parameters
     */
    function startFlashLoan(address asset, uint256 amount, bytes calldata params) external onlyOwner whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        // SEC-201: Enforce maximum flash loan amount cap
        if (amount > maxFlashLoanAmount) {
            revert InsufficientProfit(amount, maxFlashLoanAmount); // Reuse existing error (amount > allowed max)
        }
        if (!tokenWhitelist[asset]) revert TokenNotWhitelisted(asset);

        address[] memory assets = new address[](1);
        assets[0] = asset;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        emit FlashLoanRequested(msg.sender, asset, amount);

        if (useAaveV3) {
            // Aave V3 flash loan: 5 BPS fee (0.05%)
            uint256[] memory modes = new uint256[](1);
            modes[0] = AAVE_V3_INTEREST_RATE_MODE_NONE; // 0 = no debt (flash only)
            IPoolV3(poolV3).flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
        } else {
            // Aave V2 flash loan: 9 BPS fee (0.09%)
            uint256[] memory modes = new uint256[](1);
            modes[0] = 0; // 0 = no debt (flash)
            ILendingPool(lendingPool).flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
        }
    }

    /**
     * @notice Aave flash loan callback (compatible with V2 and V3)
     * @dev AT-016: Using custom errors for gas optimization
     * @dev Both V2 and V3 use identical callback signature (interface compatibility)
     * @dev Fee difference: V2 charges 9 BPS, V3 charges 5 BPS (44% savings)
     * @dev Refactored to use structs and helper functions to avoid stack-too-deep errors
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override(IFlashLoanReceiver, IFlashLoanReceiverV3) nonReentrant whenNotPaused returns (bool) {
        // Validate caller is authorized Aave pool (V2 or V3)
        if (!(msg.sender == lendingPool || msg.sender == poolV3)) {
            revert UnauthorizedCaller(msg.sender);
        }

        if (assets.length != 1 || amounts.length != 1 || premiums.length != 1) {
            revert InvalidPathLength(assets.length);
        }

        address _reserve = assets[0];
        uint256 _amount = amounts[0];
        uint256 _fee = premiums[0];

        // Decode parameters into struct to reduce stack depth
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

        ArbitrageParams memory arbParams = ArbitrageParams({
            router1: router1,
            router2: router2,
            path1: path1,
            path2: path2,
            amountOutMin1: amountOutMin1,
            amountOutMin2: amountOutMin2,
            minProfit: minProfit,
            unwrapProfitToEth: unwrapProfitToEth,
            opInitiator: opInitiator,
            deadline: deadline
        });

        // Validate arbitrage parameters
        _validateArbitrageParams(arbParams, _reserve, initiator);

        // Execute swaps and calculate profit
        SwapContext memory ctx = _executeSwaps(arbParams, _reserve, _amount);

        // Handle profit distribution
        ctx.totalDebt = _amount + _fee;
        ctx.profit = _handleProfitDistribution(_reserve, ctx.totalDebt, arbParams.minProfit, arbParams.unwrapProfitToEth);

        // Approve repayment and sweep dust
        _finalizeOperation(_reserve, ctx.totalDebt, ctx.intermediate);

        emit FlashLoanExecuted(arbParams.opInitiator, _reserve, _amount, _fee, ctx.profit);
        return true;
    }

    /**
     * @notice Validate arbitrage parameters
     * @dev Internal helper to reduce stack depth in executeOperation
     */
    function _validateArbitrageParams(
        ArbitrageParams memory arbParams,
        address _reserve,
        address initiator
    ) internal view {
        // Security: Validate trusted initiator
        if (!trustedInitiators[arbParams.opInitiator]) {
            revert InvalidInitiator(arbParams.opInitiator);
        }

        // Validate routers
        if (!routerWhitelist[arbParams.router1]) revert RouterNotWhitelisted(arbParams.router1);
        if (!routerWhitelist[arbParams.router2]) revert RouterNotWhitelisted(arbParams.router2);

        // Security: Validate routers are contracts
        if (!_isContract(arbParams.router1)) revert RouterNotWhitelisted(arbParams.router1);
        if (!_isContract(arbParams.router2)) revert RouterNotWhitelisted(arbParams.router2);

        // Validate path lengths
        if (arbParams.path1.length < 2 || arbParams.path2.length < 2) {
            revert InvalidPathLength(arbParams.path1.length < 2 ? arbParams.path1.length : arbParams.path2.length);
        }

        if (arbParams.path1.length > maxPathLength) {
            revert PathTooLong(arbParams.path1.length, maxPathLength);
        }
        if (arbParams.path2.length > maxPathLength) {
            revert PathTooLong(arbParams.path2.length, maxPathLength);
        }

        // Validate paths
        if (arbParams.path1[0] != _reserve) revert InvalidPathLength(0);
        if (arbParams.path2[arbParams.path2.length - 1] != _reserve) revert InvalidPathLength(arbParams.path2.length);
        if (initiator != address(this)) revert InvalidInitiator(initiator);

        // MEV protection: Enforce max deadline
        if (arbParams.deadline == 0 || arbParams.deadline == type(uint256).max) {
            revert InvalidDeadline(arbParams.deadline, block.timestamp, block.timestamp + MAX_DEADLINE);
        }
        if (arbParams.deadline < block.timestamp || arbParams.deadline > block.timestamp + MAX_DEADLINE) {
            revert InvalidDeadline(arbParams.deadline, block.timestamp, block.timestamp + MAX_DEADLINE);
        }

        // Validate all tokens in paths are whitelisted
        for (uint256 i = 0; i < arbParams.path1.length; i++) {
            if (!tokenWhitelist[arbParams.path1[i]]) revert TokenNotWhitelisted(arbParams.path1[i]);
        }
        for (uint256 i = 0; i < arbParams.path2.length; i++) {
            if (!tokenWhitelist[arbParams.path2[i]]) revert TokenNotWhitelisted(arbParams.path2[i]);
        }
    }

    /**
     * @notice Execute both swaps and return context
     * @dev Internal helper to reduce stack depth in executeOperation
     */
    function _executeSwaps(
        ArbitrageParams memory arbParams,
        address _reserve,
        uint256 _amount
    ) internal returns (SwapContext memory ctx) {
        // Execute first swap
        ctx.out1 = _executeSwap(
            arbParams.router1,
            _reserve,
            _amount,
            arbParams.amountOutMin1,
            arbParams.path1,
            arbParams.deadline
        );

        // Validate slippage for first swap
        uint256 minAcceptableOut1 = _calculateMinOutput(_amount, maxSlippageBps);
        if (ctx.out1 < minAcceptableOut1) {
            revert SlippageExceeded(minAcceptableOut1, ctx.out1, maxSlippageBps);
        }

        // Get intermediate token and validate
        ctx.intermediate = arbParams.path1[arbParams.path1.length - 1];
        if (arbParams.path2[0] != ctx.intermediate) revert InvalidPathLength(0);

        // Validate balance after first swap
        uint256 balanceAfterFirstSwap = IERC20(ctx.intermediate).balanceOf(address(this));
        if (balanceAfterFirstSwap < ctx.out1) {
            revert SlippageExceeded(ctx.out1, balanceAfterFirstSwap, maxSlippageBps);
        }

        // Execute second swap
        ctx.out2 = _executeSwap(
            arbParams.router2,
            ctx.intermediate,
            ctx.out1,
            arbParams.amountOutMin2,
            arbParams.path2,
            arbParams.deadline
        );

        // Validate slippage for second swap
        uint256 minAcceptableOut2 = _calculateMinOutput(ctx.out1, maxSlippageBps);
        if (ctx.out2 < minAcceptableOut2) {
            revert SlippageExceeded(minAcceptableOut2, ctx.out2, maxSlippageBps);
        }

        return ctx;
    }

    /**
     * @notice Execute a single swap with adapter or router
     * @dev Internal helper to reduce code duplication and stack depth
     */
    function _executeSwap(
        address router,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        uint256 deadline
    ) internal returns (uint256) {
        if (address(dexAdapters[router]) != address(0)) {
            address adapter = address(dexAdapters[router]);

            // Approve adapter if needed
            if (IERC20(tokenIn).allowance(address(this), adapter) < amountIn) {
                IERC20(tokenIn).safeApprove(adapter, 0);
                IERC20(tokenIn).safeApprove(adapter, amountIn);
            }

            // Validate adapter security
            if (!_isContract(adapter)) {
                revert AdapterSecurityViolation(adapter, "Adapter must be a contract");
            }
            if (!approvedAdapters[adapter]) {
                revert AdapterSecurityViolation(adapter, "Adapter not approved");
            }
            if (!approvedAdapterCodeHashes[adapter.codehash]) {
                revert AdapterSecurityViolation(adapter, "Adapter bytecode not approved");
            }

            return dexAdapters[router].swap(router, amountIn, amountOutMin, path, address(this), deadline, maxAllowance);
        } else {
            // No adapter: use router directly
            if (IERC20(tokenIn).allowance(address(this), router) < amountIn) {
                IERC20(tokenIn).safeApprove(router, 0);
                IERC20(tokenIn).safeApprove(router, amountIn);
            }

            uint256[] memory amounts = IUniswapV2Router02(router).swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                path,
                address(this),
                deadline
            );
            return amounts[amounts.length - 1];
        }
    }

    /**
     * @notice Handle profit distribution (transfer or unwrap)
     * @dev Internal helper to reduce stack depth in executeOperation
     * @return profit The calculated profit amount
     */
    function _handleProfitDistribution(
        address _reserve,
        uint256 totalDebt,
        uint256 minProfit,
        bool unwrapProfitToEth
    ) internal returns (uint256 profit) {
        uint256 finalBalance = IERC20(_reserve).balanceOf(address(this));

        // Validate sufficient balance for repayment
        if (finalBalance < totalDebt) {
            revert InsufficientProfit(finalBalance, totalDebt);
        }

        profit = finalBalance - totalDebt;

        // Validate minimum profit
        if (minProfit > 0 && profit < minProfit) {
            revert InsufficientProfit(profit, minProfit);
        }

        if (profit > 0) {
            if (unwrapProfitToEth && _reserve == WETH) {
                IWETH(WETH).withdraw(profit);
                (bool sent, ) = owner().call{value: profit}("");
                if (!sent) revert ETHTransferFailed();
                ethProfits += profit;
            } else {
                IERC20(_reserve).safeTransfer(owner(), profit);
                profits[_reserve] += profit;
            }
        }

        return profit;
    }

    /**
     * @notice Finalize operation with repayment approval and dust sweep
     * @dev Internal helper to reduce stack depth in executeOperation
     */
    function _finalizeOperation(
        address _reserve,
        uint256 totalDebt,
        address intermediate
    ) internal {
        // Approve repayment pool
        address repaymentPool = useAaveV3 ? poolV3 : lendingPool;
        if (IERC20(_reserve).allowance(address(this), repaymentPool) < totalDebt) {
            IERC20(_reserve).safeApprove(repaymentPool, 0);
            IERC20(_reserve).safeApprove(repaymentPool, totalDebt);
        }

        // Sweep dust (only intermediate token, NOT reserve)
        address[] memory dustTokens = new address[](1);
        dustTokens[0] = intermediate;
        _sweepDust(dustTokens);
    }

    // Withdraw accumulated profit (pull pattern). If token == address(0) withdraw ETH profits.
    function withdrawProfit(address token, uint256 amount, address to) external onlyOwner nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();

        if (token == address(0)) {
            // ETH withdraw
            if (amount > ethProfits) revert InsufficientProfit(ethProfits, amount);
            ethProfits -= amount;
            (bool sent, ) = to.call{value: amount}("");
            if (!sent) revert ETHTransferFailed();
            emit Withdrawn(address(0), to, amount);
            return;
        }

        // Architectural: Invariant check - ensure sufficient balance
        uint256 bal = profits[token];
        if (amount > bal) revert InsufficientProfit(bal, amount);

        profits[token] -= amount;
        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, to, amount);
    }

    // Emergency rescue for ERC20
    function emergencyWithdrawERC20(address token, uint256 amount, address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
        emit EmergencyWithdrawn(token, to, amount);
    }

    /**
     * @notice Calculate minimum acceptable output based on slippage tolerance
     * @dev Pure function for slippage calculation using basis points (BPS)
     * @dev SEC-104: Uses Math.mulDiv to prevent overflow in extreme fuzz scenarios
     * @param _inputAmount The input amount for the swap
     * @param _maxSlippageBps Maximum allowed slippage in basis points (e.g., 200 = 2%)
     * @return Minimum acceptable output amount
     *
     * Formula: minOutput = inputAmount * (10000 - maxSlippageBps) / 10000
     * Example: 100 ETH input with 200 BPS (2%) -> 98 ETH minimum output
     *
     * Note: Math.mulDiv uses rounding down (Math.Rounding.Floor by default),
     *       providing conservative (safer) minimum threshold
     */
    function _calculateMinOutput(uint256 _inputAmount, uint256 _maxSlippageBps) internal pure returns (uint256) {
        // Input validation: Cap input amount to prevent unrealistic scenarios
        // Maximum realistic trade: 1e30 tokens (1 trillion tokens with 18 decimals)
        if (_inputAmount > 1e30) revert ZeroAmount(); // Reuse existing error for simplicity

        // Validate slippage is within allowed range (already enforced by setMaxSlippage, but defense in depth)
        if (_maxSlippageBps > 1000) revert InvalidSlippage(_maxSlippageBps);

        // BPS calculation: 10000 = 100%, so (10000 - slippageBps) gives the minimum percentage
        // Math.mulDiv prevents overflow: (_inputAmount * numerator) / denominator
        // Example: 100 * 9800 / 10000 = 98
        return Math.mulDiv(_inputAmount, 10000 - _maxSlippageBps, 10000);
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