// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {MessageRouter} from "../src/MessageRouter.sol";

/// @notice Simple one-click deployment + Etherscan verification script.
/// Set environment variables:
///   RPC_URL          - target network RPC
///   ETHERSCAN_API_KEY- verification key for target network
///   PRIVATE_KEY      - deployer's private key
///   REGISTRY_OWNER   - address that will own initial PAUSER role (optional, defaults to deployer)
/// Usage: forge script script/DeployAndVerify.s.sol --rpc-url $RPC_URL --broadcast --verify -vvvv
contract DeployAndVerify is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envOr("REGISTRY_OWNER", vm.addr(deployerKey));
        vm.startBroadcast(deployerKey);

        AgentRegistry registry = new AgentRegistry();
        MessageRouter router = new MessageRouter(address(registry));

        // Transfer pauser role if different owner requested
        if (owner != msg.sender) {
            registry.changePauser(owner);
        }

        vm.stopBroadcast();

        console2.log("AgentRegistry deployed to:", address(registry));
        console2.log("MessageRouter deployed to:", address(router));
    }
}
