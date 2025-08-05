// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../../src/upgradeable/AgentRegistryUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AgentRegistryUpgradeableTest is Test {
    AgentRegistryUpgradeable public implementation;
    AgentRegistryUpgradeable public registry;
    ERC1967Proxy public proxy;
    
    address public owner = address(this);
    address public agent1 = address(0x1);
    address public agent2 = address(0x2);
    address public nonOwner = address(0x3);

    function setUp() public {
        // Deploy implementation
        implementation = new AgentRegistryUpgradeable();
        
        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            AgentRegistryUpgradeable.initialize.selector,
            owner
        );
        proxy = new ERC1967Proxy(address(implementation), initData);
        
        // Cast proxy to interface
        registry = AgentRegistryUpgradeable(address(proxy));
    }

    function testInitialize() public {
        assertEq(registry.owner(), owner);
        assertEq(registry.pauser(), owner);
        assertFalse(registry.paused());
        assertEq(registry.version(), "1.0.0");
    }

    function testCannotInitializeTwice() public {
        vm.expectRevert();
        registry.initialize(owner);
    }

    function testRegisterAgent() public {
        vm.startPrank(agent1);
        
        bytes32[] memory capabilities = new bytes32[](2);
        capabilities[0] = keccak256("data_analysis");
        capabilities[1] = keccak256("market_research");

        registry.registerAgent("Agent1", "http://localhost:3000", capabilities);

        AgentRegistryUpgradeable.Agent memory agent = registry.getAgent(agent1);
        assertEq(agent.owner, agent1);
        assertEq(agent.name, "Agent1");
        assertEq(agent.endpoint, "http://localhost:3000");
        assertTrue(agent.active);
        assertEq(agent.reputation, 100);
        assertEq(registry.activeAgentsCount(), 1);

        vm.stopPrank();
    }

    function testUpgradeAuthorization() public {
        // Deploy new implementation
        AgentRegistryUpgradeable newImpl = new AgentRegistryUpgradeable();
        
        // Only owner can upgrade
        vm.prank(nonOwner);
        vm.expectRevert();
        registry.upgradeToAndCall(address(newImpl), "");
        
        // Owner can upgrade
        registry.upgradeToAndCall(address(newImpl), "");
        
        // Verify upgrade
        assertEq(registry.version(), "1.0.0");
    }

    function testStoragePersistenceAfterUpgrade() public {
        // Register agent before upgrade
        vm.prank(agent1);
        bytes32[] memory capabilities = new bytes32[](1);
        capabilities[0] = keccak256("test");
        registry.registerAgent("Agent1", "http://localhost:3000", capabilities);
        
        // Store initial state
        AgentRegistryUpgradeable.Agent memory agentBefore = registry.getAgent(agent1);
        uint256 activeCountBefore = registry.activeAgentsCount();
        
        // Deploy new implementation
        AgentRegistryUpgradeable newImpl = new AgentRegistryUpgradeable();
        
        // Upgrade
        registry.upgradeToAndCall(address(newImpl), "");
        
        // Verify storage persistence
        AgentRegistryUpgradeable.Agent memory agentAfter = registry.getAgent(agent1);
        assertEq(agentAfter.owner, agentBefore.owner);
        assertEq(agentAfter.name, agentBefore.name);
        assertEq(agentAfter.endpoint, agentBefore.endpoint);
        assertEq(agentAfter.reputation, agentBefore.reputation);
        assertEq(agentAfter.active, agentBefore.active);
        assertEq(registry.activeAgentsCount(), activeCountBefore);
    }

    function testPauseUpgradeableContract() public {
        // Pause the contract
        registry.pause();
        assertTrue(registry.paused());
        
        // Cannot register when paused
        vm.prank(agent1);
        bytes32[] memory capabilities = new bytes32[](1);
        capabilities[0] = keccak256("test");
        vm.expectRevert("AgentRegistry: paused");
        registry.registerAgent("Agent1", "http://localhost:3000", capabilities);
        
        // Unpause
        registry.unpause();
        assertFalse(registry.paused());
        
        // Can register again
        vm.prank(agent1);
        registry.registerAgent("Agent1", "http://localhost:3000", capabilities);
    }

    function testOwnershipTransfer() public {
        address newOwner = address(0x999);
        
        // Transfer ownership
        registry.transferOwnership(newOwner);
        assertEq(registry.owner(), newOwner);
        
        // Old owner cannot upgrade anymore
        AgentRegistryUpgradeable newImpl = new AgentRegistryUpgradeable();
        vm.expectRevert();
        registry.upgradeToAndCall(address(newImpl), "");
        
        // New owner can upgrade
        vm.prank(newOwner);
        registry.upgradeToAndCall(address(newImpl), "");
    }

    function testImplementationIsDisabled() public {
        // Try to initialize the implementation directly (should fail)
        vm.expectRevert();
        implementation.initialize(owner);
    }

    function testProxyPattern() public {
        // Verify proxy is pointing to implementation
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 storedImpl = vm.load(address(proxy), implementationSlot);
        assertEq(address(uint160(uint256(storedImpl))), address(implementation));
    }

    function testMultipleUpgrades() public {
        // Register initial data
        vm.prank(agent1);
        bytes32[] memory capabilities = new bytes32[](1);
        capabilities[0] = keccak256("test");
        registry.registerAgent("Agent1", "http://localhost:3000", capabilities);
        
        // First upgrade
        AgentRegistryUpgradeable newImpl1 = new AgentRegistryUpgradeable();
        registry.upgradeToAndCall(address(newImpl1), "");
        
        // Verify data persists
        AgentRegistryUpgradeable.Agent memory agent = registry.getAgent(agent1);
        assertEq(agent.name, "Agent1");
        
        // Second upgrade
        AgentRegistryUpgradeable newImpl2 = new AgentRegistryUpgradeable();
        registry.upgradeToAndCall(address(newImpl2), "");
        
        // Verify data still persists
        agent = registry.getAgent(agent1);
        assertEq(agent.name, "Agent1");
        assertEq(registry.activeAgentsCount(), 1);
    }
}