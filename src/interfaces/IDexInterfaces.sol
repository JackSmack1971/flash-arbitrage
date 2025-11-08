// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title DEX Adapter Interfaces
 * @notice Shared interfaces for DEX integration
 */

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IDexAdapter {
    function swap(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint256 maxAllowance
    ) external returns (uint256 amountOut);
}
