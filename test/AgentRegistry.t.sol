// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/AgentRegistry.sol";

contract AgentRegistryTest is Test {
    AgentRegistry public registry;
    address public agent1 = address(0x1);
    address public agent2 = address(0x2);

    function setUp() public {
        registry = new AgentRegistry();
    }

    function testRegisterAgent() public {
        vm.startPrank(agent1);
        
        bytes32[] memory capabilities = new bytes32[](2);
        capabilities[0] = keccak256("data_analysis");
        capabilities[1] = keccak256("market_research");

        registry.registerAgent("Agent1", "http://localhost:3000", capabilities);

        AgentRegistry.Agent memory agent = registry.getAgent(agent1);
        assertEq(agent.owner, agent1);
        assertEq(agent.name, "Agent1");
        assertEq(agent.endpoint, "http://localhost:3000");
        assertTrue(agent.active);
        assertEq(agent.reputation, 100);

        vm.stopPrank();
    }

    function testCannotRegisterTwice() public {
        vm.startPrank(agent1);
        
        bytes32[] memory capabilities = new bytes32[](1);
        capabilities[0] = keccak256("test");

        registry.registerAgent("Agent1", "http://localhost:3000", capabilities);
        
        vm.expectRevert("Agent already registered");
        registry.registerAgent("Agent1", "http://localhost:3001", capabilities);

        vm.stopPrank();
    }

    function testUpdateEndpoint() public {
        vm.startPrank(agent1);
        
        bytes32[] memory capabilities = new bytes32[](1);
        capabilities[0] = keccak256("test");

        registry.registerAgent("Agent1", "http://localhost:3000", capabilities);
        registry.updateEndpoint("http://localhost:4000");

        AgentRegistry.Agent memory agent = registry.getAgent(agent1);
        assertEq(agent.endpoint, "http://localhost:4000");

        vm.stopPrank();
    }

    function testFindAgentsByCapability() public {
        bytes32 capability = keccak256("data_analysis");
        
        vm.startPrank(agent1);
        bytes32[] memory capabilities1 = new bytes32[](1);
        capabilities1[0] = capability;
        registry.registerAgent("Agent1", "http://localhost:3000", capabilities1);
        vm.stopPrank();

        vm.startPrank(agent2);
        bytes32[] memory capabilities2 = new bytes32[](1);
        capabilities2[0] = capability;
        registry.registerAgent("Agent2", "http://localhost:3001", capabilities2);
        vm.stopPrank();

        address[] memory agents = registry.findAgentsByCapability(capability);
        assertEq(agents.length, 2);
        assertEq(agents[0], agent1);
        assertEq(agents[1], agent2);
    }

    function testDeactivateAgent() public {
        vm.startPrank(agent1);
        
        bytes32[] memory capabilities = new bytes32[](1);
        capabilities[0] = keccak256("test");

        registry.registerAgent("Agent1", "http://localhost:3000", capabilities);
        registry.deactivateAgent();

        AgentRegistry.Agent memory agent = registry.getAgent(agent1);
        assertFalse(agent.active);

        vm.stopPrank();
    }

    function testGetActiveAgentsCount() public {
        vm.startPrank(agent1);
        bytes32[] memory capabilities = new bytes32[](1);
        capabilities[0] = keccak256("test");
        registry.registerAgent("Agent1", "http://localhost:3000", capabilities);
        vm.stopPrank();

        vm.startPrank(agent2);
        registry.registerAgent("Agent2", "http://localhost:3001", capabilities);
        vm.stopPrank();

        assertEq(registry.getActiveAgentsCount(), 2);
        assertEq(registry.activeAgentsCount(), 2);

        vm.prank(agent1);
        registry.deactivateAgent();

        assertEq(registry.getActiveAgentsCount(), 1);
        assertEq(registry.activeAgentsCount(), 1);
    }

    function testReactivateAgent() public {
        vm.startPrank(agent1);
        bytes32[] memory capabilities = new bytes32[](1);
        capabilities[0] = keccak256("test");
        registry.registerAgent("Agent1", "http://localhost:3000", capabilities);
        
        // Deactivate
        registry.deactivateAgent();
        assertFalse(registry.getAgent(agent1).active);
        assertEq(registry.activeAgentsCount(), 0);
        
        // Reactivate
        registry.reactivateAgent();
        assertTrue(registry.getAgent(agent1).active);
        assertEq(registry.activeAgentsCount(), 1);
        
        // Cannot reactivate if already active
        vm.expectRevert("Agent already active");
        registry.reactivateAgent();
        
        vm.stopPrank();
    }

    function testPauseFunctionality() public {
        // Register agent1 first
        vm.startPrank(agent1);
        bytes32[] memory capabilities = new bytes32[](1);
        capabilities[0] = keccak256("test");
        registry.registerAgent("Agent1", "http://localhost:3000", capabilities);
        vm.stopPrank();
        
        // Only pauser can pause
        vm.prank(agent1);
        vm.expectRevert("Pausable: caller is not the pauser");
        registry.pause();
        
        // Pause the registry
        registry.pause();
        assertTrue(registry.paused());
        
        // Cannot register when paused
        vm.startPrank(agent2);
        vm.expectRevert("Pausable: paused");
        registry.registerAgent("Agent2", "http://localhost:3001", capabilities);
        vm.stopPrank();
        
        // Cannot update when paused
        vm.prank(agent1);
        vm.expectRevert("Pausable: paused");
        registry.updateEndpoint("http://localhost:4000");
        
        // Unpause
        registry.unpause();
        assertFalse(registry.paused());
        
        // Can register again
        vm.startPrank(agent2);
        registry.registerAgent("Agent2", "http://localhost:3001", capabilities);
        vm.stopPrank();
    }

    function testCannotDeactivateInactiveAgent() public {
        vm.startPrank(agent1);
        bytes32[] memory capabilities = new bytes32[](1);
        capabilities[0] = keccak256("test");
        registry.registerAgent("Agent1", "http://localhost:3000", capabilities);
        
        registry.deactivateAgent();
        
        // Try to deactivate again
        vm.expectRevert("Agent already inactive");
        registry.deactivateAgent();
        
        vm.stopPrank();
    }
}