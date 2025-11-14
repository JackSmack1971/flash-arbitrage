// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockNonStandardToken
 * @notice Mock ERC20 token simulating USDT's non-standard approve behavior
 * @dev USDT and similar tokens require allowance to be 0 before changing to non-zero value
 * @dev Used to test M-3 remediation: SafeERC20.forceApprove pattern
 *
 * USDT Behavior:
 * - approve(spender, X) when allowance > 0 → REVERTS
 * - Must first approve(spender, 0), then approve(spender, X)
 *
 * This mock replicates that behavior for comprehensive testing.
 */
contract MockNonStandardToken is ERC20 {
    /**
     * @notice Deploy mock token with initial supply
     * @param initialSupply Total supply to mint to deployer
     */
    constructor(uint256 initialSupply) ERC20("MockNonStandardToken", "MNST") {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @notice Non-standard approve function mimicking USDT behavior
     * @dev Reverts if trying to change from non-zero allowance to different non-zero value
     * @dev This matches USDT's actual implementation to prevent front-running attacks
     * @param spender Address to approve
     * @param amount New allowance amount
     * @return success Always true if no revert
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);

        // USDT behavior: Cannot change non-zero allowance to different non-zero value
        // Must first reset to 0, then set to new value
        if (currentAllowance != 0 && amount != 0 && currentAllowance != amount) {
            revert("MockNonStandardToken: approve from non-zero to non-zero not allowed");
        }

        return super.approve(spender, amount);
    }

    /**
     * @notice Mint additional tokens (test helper)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens (test helper)
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
