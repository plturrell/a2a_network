// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/AgentRegistry.sol";
import "../src/MessageRouter.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        AgentRegistry registry = new AgentRegistry();
        console.log("AgentRegistry deployed to:", address(registry));

        MessageRouter router = new MessageRouter(address(registry));
        console.log("MessageRouter deployed to:", address(router));

        vm.stopBroadcast();
    }
}
