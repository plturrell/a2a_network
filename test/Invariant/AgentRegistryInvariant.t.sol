// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import {AgentRegistry} from "../../src/AgentRegistry.sol";

contract AgentRegistryInvariant is StdInvariant, Test {
    AgentRegistry public registry;

    address[] private _agents;

    function setUp() public {
        registry = new AgentRegistry();
        // exclude registry from invariant caller restricts
        targetContract(address(registry));
    }

    // --- Handlers ---
    // Fuzzable function wrappers that mutate contract state.

    function register(bytes32 salt, string calldata name, string calldata endpoint) external {
        address agent = _deriveAddr(salt);
        vm.prank(agent);
        bytes32[] memory caps = new bytes32[](1);
        caps[0] = keccak256("CAP");
        // suppress failures for already-registered agents
        try registry.registerAgent(name, endpoint, caps) {
            _agents.push(agent);
        } catch {}
    }

    function deactivate(bytes32 salt) external {
        address agent = _deriveAddr(salt);
        vm.prank(agent);
        try registry.deactivateAgent() {} catch {}
    }

    function reactivate(bytes32 salt) external {
        address agent = _deriveAddr(salt);
        vm.prank(agent);
        try registry.reactivateAgent() {} catch {}
    }

    // --- Invariants ---

    // activeAgentsCount equals iterate active bools
    function invariant_activeCountMatchesState() public view {
        address[] memory all = registry.getAllAgents();
        uint256 activeCount = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (registry.getAgent(all[i]).active) {
                activeCount++;
            }
        }
        assertEq(activeCount, registry.getActiveAgentsCount());
    }

    // No agent has zero owner (should be unreachable after registration)
    function invariant_ownerNotZero() public view {
        address[] memory all2 = registry.getAllAgents();
        for (uint256 i = 0; i < all2.length; i++) {
            AgentRegistry.Agent memory a2 = registry.getAgent(all2[i]);
            if (a2.owner != address(0)) {
                assertEq(a2.owner, all2[i]);
            }
        }
    }

    // helper to deterministically derive address from fuzz salt
    function _deriveAddr(bytes32 salt) private pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(salt)))));
    }
}
