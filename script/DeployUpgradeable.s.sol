// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/upgradeable/AgentRegistryUpgradeable.sol";
import "../src/upgradeable/MessageRouterUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployUpgradeableScript
 * @dev Deployment script for upgradeable A2A Network contracts using UUPS proxy pattern
 */
contract DeployUpgradeableScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying upgradeable A2A Network contracts...");
        console.log("Deployer address:", deployer);

        // 1. Deploy AgentRegistry implementation
        AgentRegistryUpgradeable registryImpl = new AgentRegistryUpgradeable();
        console.log("AgentRegistry implementation deployed to:", address(registryImpl));

        // 2. Deploy AgentRegistry proxy with initialization data
        bytes memory registryInitData = abi.encodeWithSelector(
            AgentRegistryUpgradeable.initialize.selector,
            deployer // initial owner
        );

        ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), registryInitData);
        console.log("AgentRegistry proxy deployed to:", address(registryProxy));

        // 3. Deploy MessageRouter implementation
        MessageRouterUpgradeable routerImpl = new MessageRouterUpgradeable();
        console.log("MessageRouter implementation deployed to:", address(routerImpl));

        // 4. Deploy MessageRouter proxy with initialization data
        bytes memory routerInitData = abi.encodeWithSelector(
            MessageRouterUpgradeable.initialize.selector,
            address(registryProxy), // registry address
            deployer // initial owner
        );

        ERC1967Proxy routerProxy = new ERC1967Proxy(address(routerImpl), routerInitData);
        console.log("MessageRouter proxy deployed to:", address(routerProxy));

        // 5. Verify deployments by calling version functions
        AgentRegistryUpgradeable registry = AgentRegistryUpgradeable(address(registryProxy));
        MessageRouterUpgradeable router = MessageRouterUpgradeable(address(routerProxy));

        console.log("AgentRegistry version:", registry.version());
        console.log("MessageRouter version:", router.version());
        console.log("Registry owner:", registry.owner());
        console.log("Router owner:", router.owner());

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("AgentRegistry Implementation:", address(registryImpl));
        console.log("AgentRegistry Proxy (Use this address):", address(registryProxy));
        console.log("MessageRouter Implementation:", address(routerImpl));
        console.log("MessageRouter Proxy (Use this address):", address(routerProxy));
        console.log("Owner:", deployer);
        console.log("\nTo interact with the contracts, use the proxy addresses.");
        console.log("To upgrade contracts, deploy new implementations and call upgradeTo().");
    }
}
