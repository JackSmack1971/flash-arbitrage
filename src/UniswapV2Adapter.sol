// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

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

contract UniswapV2Adapter is IDexAdapter {
    using SafeERC20 for IERC20;

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