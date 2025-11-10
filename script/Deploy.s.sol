// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import "../src/FlashArbMainnetReady.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title FlashArbDeployScript
 * @notice Deployment script for FlashArbMainnetReady with UUPS proxy pattern
 * @dev Supports both Sepolia testnet and Ethereum mainnet deployments
 *
 * Usage:
 * Sepolia:
 *   forge script script/Deploy.s.sol:DeployFlashArb --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
 * Mainnet:
 *   forge script script/Deploy.s.sol:DeployFlashArb --rpc-url $MAINNET_RPC_URL --broadcast --verify
 */
contract DeployFlashArb is Script {
    // Aave V3 Pool addresses
    address constant AAVE_V3_POOL_MAINNET = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant AAVE_V3_POOL_SEPOLIA = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying FlashArbMainnetReady with account:", deployer);
        console.log("Account balance:", deployer.balance);

        // Detect network based on chain ID
        uint256 chainId = block.chainid;
        address poolV3;
        string memory network;

        if (chainId == 1) {
            // Ethereum Mainnet
            poolV3 = AAVE_V3_POOL_MAINNET;
            network = "Mainnet";
        } else if (chainId == 11155111) {
            // Sepolia Testnet
            poolV3 = AAVE_V3_POOL_SEPOLIA;
            network = "Sepolia";
        } else {
            revert("Unsupported network. Use Mainnet (chainId=1) or Sepolia (chainId=11155111)");
        }

        console.log("Deploying to:", network);
        console.log("Chain ID:", chainId);
        console.log("Aave V3 Pool:", poolV3);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy implementation contract
        FlashArbMainnetReady implementation = new FlashArbMainnetReady();
        console.log("Implementation deployed at:", address(implementation));

        // Step 2: Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            FlashArbMainnetReady.initialize.selector
        );

        // Step 3: Deploy ERC1967 proxy pointing to implementation
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console.log("Proxy deployed at:", address(proxy));

        // Step 4: Wrap proxy in FlashArbMainnetReady interface for configuration
        FlashArbMainnetReady flashArb = FlashArbMainnetReady(payable(address(proxy)));

        // Step 5: Configure Aave V3 Pool address
        flashArb.setPoolV3(poolV3);
        console.log("Aave V3 Pool configured:", poolV3);

        // Step 6: Enable Aave V3 by default (for fee savings: 9 BPS -> 5 BPS)
        flashArb.setUseAaveV3(true);
        console.log("Aave V3 enabled (5 BPS flash loan fee)");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Network:", network);
        console.log("Chain ID:", chainId);
        console.log("Implementation:", address(implementation));
        console.log("Proxy (FlashArbMainnetReady):", address(proxy));
        console.log("Owner:", deployer);
        console.log("Aave V3 Pool:", poolV3);
        console.log("Aave V3 Enabled: true");
        console.log("\nNext steps:");
        console.log("1. Verify contracts on Etherscan");
        console.log("2. Whitelist tokens: flashArb.setTokenWhitelist(token, true)");
        console.log("3. Whitelist routers: flashArb.setRouterWhitelist(router, true)");
        console.log("4. Approve adapters: flashArb.approveAdapter(adapter, true)");
        console.log("5. Execute test arbitrage");
        console.log("6. Transfer ownership to multi-sig (recommended)");
    }
}
