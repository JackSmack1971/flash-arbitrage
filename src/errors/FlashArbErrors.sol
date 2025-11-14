// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title FlashArbErrors
 * @notice Custom error types for gas-optimized error handling in FlashArbMainnetReady
 * @dev Solidity 0.8.4+ custom errors reduce deployment size by ~10% and revert gas by ~5%
 *      compared to string-based require() statements. Each error is mapped 1:1 with
 *      existing require() conditions for seamless migration.
 */

/**
 * @notice Thrown when attempting to use an adapter that has not been approved
 * @param adapter The address of the unapproved adapter
 */
error AdapterNotApproved(address adapter);

/**
 * @notice Thrown when attempting to use a router that is not whitelisted
 * @param router The address of the non-whitelisted router
 */
error RouterNotWhitelisted(address router);

/**
 * @notice Thrown when attempting to use a token that is not whitelisted
 * @param token The address of the non-whitelisted token
 */
error TokenNotWhitelisted(address token);

/**
 * @notice Thrown when deadline parameter is outside valid bounds
 * @param provided The deadline value provided
 * @param min Minimum acceptable deadline (block.timestamp)
 * @param max Maximum acceptable deadline (block.timestamp + MAX_DEADLINE)
 */
error InvalidDeadline(uint256 provided, uint256 min, uint256 max);

/**
 * @notice Thrown when profit is insufficient to repay flash loan debt
 * @param profit The actual profit amount (can be 0 or negative in uint underflow case)
 * @param debt The total debt amount (loan + premium)
 */
error InsufficientProfit(uint256 profit, uint256 debt);

/**
 * @notice Thrown when swap path array has invalid length
 * @param length The actual path length provided
 */
error InvalidPathLength(uint256 length);

/**
 * @notice Thrown when slippage tolerance is outside acceptable range
 * @param bps The basis points value provided (must be 1-1000 for 0.01%-10%)
 */
error InvalidSlippage(uint256 bps);

/**
 * @notice Thrown when a zero address is provided where a valid address is required
 */
error ZeroAddress();

/**
 * @notice Thrown when a zero amount is provided where a positive amount is required
 */
error ZeroAmount();

/**
 * @notice Thrown when an adapter fails security validation
 * @param adapter The address of the adapter that failed validation
 * @param reason Human-readable reason for the failure
 */
error AdapterSecurityViolation(address adapter, string reason);

/**
 * @notice Thrown when slippage exceeds maximum allowed tolerance
 * @param expected The expected output amount
 * @param actual The actual output amount received
 * @param maxBps The maximum slippage in basis points
 */
error SlippageExceeded(uint256 expected, uint256 actual, uint256 maxBps);

/**
 * @notice Thrown when swap path exceeds maximum allowed length
 * @param pathLength The provided path length
 * @param maxAllowed The maximum allowed path length
 */
error PathTooLong(uint256 pathLength, uint256 maxAllowed);

/**
 * @notice Thrown when an unauthorized caller attempts a restricted operation
 * @param caller The address of the unauthorized caller
 */
error UnauthorizedCaller(address caller);

/**
 * @notice Thrown when initiator validation fails in flash loan callback
 * @param initiator The initiator address that failed validation
 */
error InvalidInitiator(address initiator);

/**
 * @notice Thrown when ETH transfer to recipient fails
 * @dev Indicates low-level call failure when sending ETH (e.g., recipient reverted)
 */
error ETHTransferFailed();

/**
 * @notice Thrown when owner attempts to remove themselves as trusted initiator
 * @dev AUDIT FINDING M-2: Prevents contract execution brick by ensuring owner always trusted
 * @param owner The owner address that attempted self-removal
 */
error CannotRemoveOwnerAsInitiator(address owner);
