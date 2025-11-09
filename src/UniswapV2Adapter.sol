// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IDexInterfaces.sol";

/**
 * @title UniswapV2Adapter
 * @notice Adapter for Uniswap V2 compatible DEX swaps with defense-in-depth security
 * @dev Implements additional validation layer beyond FlashArbMainnetReady
 */

/// @notice Router is not whitelisted in the main contract
error RouterNotWhitelisted();

/// @notice Router address has no code (is not a contract)
error RouterNotContract();

/// @notice Caller is not authorized (must be FlashArbMainnetReady or approved caller)
error UnauthorizedCaller();

interface IFlashArbLike {
    function routerWhitelist(address) external view returns (bool);
}

contract UniswapV2Adapter is IDexAdapter {
    using SafeERC20 for IERC20;

    /// @notice Reference to FlashArbMainnetReady for whitelist validation
    IFlashArbLike public immutable flashArb;

    /**
     * @notice Deploy adapter with reference to main arbitrage contract
     * @param _flashArb Address of FlashArbMainnetReady contract
     */
    constructor(IFlashArbLike _flashArb) {
        require(address(_flashArb) != address(0), "flashArb-zero");
        flashArb = _flashArb;
    }

    /**
     * @notice Execute swap on Uniswap V2 compatible router
     * @dev Defense-in-depth: validates router whitelist even though FlashArb also checks
     * @param router Address of the DEX router
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum acceptable output amount
     * @param path Token swap path
     * @param to Recipient of output tokens
     * @param deadline Transaction deadline
     * @param maxAllowance Maximum token approval amount
     * @return amountOut Actual output amount received
     */
    function swap(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint256 maxAllowance
    ) external returns (uint256 amountOut) {
        require(path.length >= 2, "invalid-path");

        // Defense-in-depth: validate router is a contract
        if (router.code.length == 0) revert RouterNotContract();

        // Defense-in-depth: adapter enforces router whitelist too
        if (!flashArb.routerWhitelist(router)) revert RouterNotWhitelisted();

        // Additional safety: only allow calls from FlashArbMainnetReady (prevents arbitrary external calls)
        // The 'to' should be controlled by FlashArb, not arbitrary addresses
        if (msg.sender != address(flashArb)) revert UnauthorizedCaller();

        // Safe approval pattern: reset to 0 then set to maxAllowance
        IERC20(path[0]).safeApprove(router, 0);
        IERC20(path[0]).safeApprove(router, maxAllowance);

        uint256[] memory amounts = IUniswapV2Router02(router).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );

        return amounts[amounts.length - 1];
    }
}