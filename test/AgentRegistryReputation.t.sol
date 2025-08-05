// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";

contract AgentRegistryReputationTest is Test {
    AgentRegistry private registry;
    address private pauser;
    address private agent;

    function setUp() public {
        registry = new AgentRegistry();
        pauser = address(this); // constructor sets msg.sender as pauser
        agent = address(0xA11CE);

        // register an agent for tests
        vm.prank(agent);
        bytes32[] memory caps = new bytes32[](1);
        caps[0] = keccak256("CAP");
        registry.registerAgent("Agent", "https://endpoint", caps);
    }

    function testIncreaseReputation() public {
        vm.prank(pauser);
        registry.increaseReputation(agent, 50);
        AgentRegistry.Agent memory data = registry.getAgent(agent);
        uint256 rep = data.reputation;
        assertEq(rep, 150);
    }

    function testIncreaseReputationCapsAtMax() public {
        vm.prank(pauser);
        registry.increaseReputation(agent, 500);
        AgentRegistry.Agent memory data = registry.getAgent(agent);
        uint256 rep = data.reputation;
        assertEq(rep, 200);
    }

    function testDecreaseReputation() public {
        vm.startPrank(pauser);
        registry.decreaseReputation(agent, 30);
        AgentRegistry.Agent memory data = registry.getAgent(agent);
        uint256 rep = data.reputation;
        assertEq(rep, 70);
        vm.stopPrank();
    }

    function testDecreaseReputationFloorsAtZero() public {
        vm.prank(pauser);
        registry.decreaseReputation(agent, 500);
        AgentRegistry.Agent memory data = registry.getAgent(agent);
        uint256 rep = data.reputation;
        assertEq(rep, 0);
    }

    function testOnlyPauserCanAdjust() public {
        address attacker = address(0xBEEF);
        vm.prank(attacker);
        vm.expectRevert("Pausable: caller is not the pauser");
        registry.increaseReputation(agent, 10);
    }
}
