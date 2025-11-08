// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract MockRouter {
    using SafeERC20 for IERC20;

    address public tokenIn;
    address public tokenOut;
    uint256 public exchangeRate; // amountOut per amountIn (18 decimals)

    constructor(address _tokenIn, address _tokenOut) {
        tokenIn = _tokenIn;
        tokenOut = _tokenOut;
        exchangeRate = 1 * 10**18; // Default 1:1
    }

    function setExchangeRate(uint256 _exchangeRate) external {
        exchangeRate = _exchangeRate;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "deadline exceeded");
        require(path.length >= 2, "invalid path");
        require(path[0] == tokenIn, "wrong input token");
        require(path[path.length - 1] == tokenOut, "wrong output token");

        // Transfer input tokens from sender
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Calculate output amount
        uint256 amountOut = (amountIn * exchangeRate) / 10**18;
        require(amountOut >= amountOutMin, "insufficient output");

        // Mint output tokens (in a real DEX, these would come from liquidity)
        // For testing, assume we have infinite liquidity
        MockERC20(tokenOut).mint(to, amountOut);

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOut;

        return amounts;
    }
}

// Helper to access mint function
contract MockERC20 is IERC20 {
    function mint(address to, uint256 amount) external;
}