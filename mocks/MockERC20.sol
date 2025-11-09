// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        // Prevent overflow by capping mint amounts to reasonable values
        // Max supply: 1e30 (1 trillion tokens with 18 decimals)
        require(amount <= 1e30, "mint amount too large");
        require(totalSupply() + amount <= type(uint128).max, "total supply overflow");
        _mint(to, amount);
    }
}