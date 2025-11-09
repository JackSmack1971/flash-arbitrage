// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

contract MockLendingPool {
    mapping(address => uint256) public balances;

    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external {
        require(assets.length == 1 && amounts.length == 1 && modes.length == 1, "single asset only");
        require(modes[0] == 0, "flash loan only");

        address asset = assets[0];
        uint256 amount = amounts[0];
        uint256 fee = amount * 9 / 10000; // 0.09% fee

        require(balances[asset] >= amount, "insufficient pool balance");

        // Transfer loan amount to receiver
        balances[asset] -= amount;
        IERC20(asset).transfer(receiverAddress, amount);

        // Create fees array
        uint256[] memory fees = new uint256[](1);
        fees[0] = fee;

        // Call executeOperation
        // Pass receiverAddress as initiator to match Aave V2 behavior
        // (initiator is the contract that called flashLoan)
        bool success = IFlashLoanReceiver(receiverAddress).executeOperation(
            assets,
            amounts,
            fees,
            receiverAddress, // initiator is the receiver contract
            params
        );

        require(success, "executeOperation failed");

        // Check repayment
        uint256 totalDebt = amount + fee;
        require(IERC20(asset).balanceOf(address(this)) >= totalDebt, "repayment failed");

        // Update pool balance
        balances[asset] += totalDebt;
    }

    function deposit(address asset, uint256 amount) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        balances[asset] += amount;
    }
}