// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../../src/upgradeable/AgentRegistryUpgradeable.sol";
import "../../src/upgradeable/MessageRouterUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title UpgradeScenarioTest
 * @dev Tests realistic upgrade scenarios for the A2A Network
 */
contract UpgradeScenarioTest is Test {
    AgentRegistryUpgradeable public registry;
    MessageRouterUpgradeable public router;
    ERC1967Proxy public registryProxy;
    ERC1967Proxy public routerProxy;

    address public owner = address(this);
    address public agent1 = address(0x1);
    address public agent2 = address(0x2);
    address public agent3 = address(0x3);

    event MessageSent(bytes32 indexed messageId, address indexed from, address indexed to, bytes32 messageType);

    function setUp() public {
        // Deploy full A2A Network with proxies
        _deployA2ANetwork();
        _registerTestAgents();
    }

    function _deployA2ANetwork() private {
        // Deploy AgentRegistry
        AgentRegistryUpgradeable registryImpl = new AgentRegistryUpgradeable();
        bytes memory registryInitData = abi.encodeWithSelector(AgentRegistryUpgradeable.initialize.selector, owner);
        registryProxy = new ERC1967Proxy(address(registryImpl), registryInitData);
        registry = AgentRegistryUpgradeable(address(registryProxy));

        // Deploy MessageRouter
        MessageRouterUpgradeable routerImpl = new MessageRouterUpgradeable();
        bytes memory routerInitData =
            abi.encodeWithSelector(MessageRouterUpgradeable.initialize.selector, address(registry), owner);
        routerProxy = new ERC1967Proxy(address(routerImpl), routerInitData);
        router = MessageRouterUpgradeable(address(routerProxy));
    }

    function _registerTestAgents() private {
        bytes32[] memory capabilities = new bytes32[](2);
        capabilities[0] = keccak256("data_analysis");
        capabilities[1] = keccak256("messaging");

        vm.prank(agent1);
        registry.registerAgent("DataAnalyzer", "http://analyzer.ai", capabilities);

        vm.prank(agent2);
        registry.registerAgent("TradingBot", "http://trader.ai", capabilities);

        vm.prank(agent3);
        registry.registerAgent("ResearchAgent", "http://research.ai", capabilities);
    }

    function testFullNetworkOperation() public {
        // Test network functionality before any upgrades
        _testBasicNetworkFunctionality();

        // Wait to avoid rate limiting
        vm.warp(block.timestamp + 10 seconds);

        // Simulate network activity
        _simulateNetworkActivity();

        // Perform upgrades
        _performNetworkUpgrades();

        // Wait before testing functionality
        vm.warp(block.timestamp + 10 seconds);

        // Verify functionality after upgrades with different agents to avoid rate limits
        _testBasicNetworkFunctionalityPostUpgrade();

        // Test new functionality persists
        _verifyUpgradeDataPersistence();
    }

    function _testBasicNetworkFunctionality() private {
        // Test agent discovery
        address[] memory dataAgents = registry.findAgentsByCapability(keccak256("data_analysis"));
        assertEq(dataAgents.length, 3);

        // Test messaging
        vm.prank(agent1);
        bytes32 messageId = router.sendMessage(agent2, "Analysis request", keccak256("WORK_REQUEST"));

        MessageRouterUpgradeable.Message memory message = router.getMessage(messageId);
        assertEq(message.from, agent1);
        assertEq(message.to, agent2);
        assertFalse(message.delivered);

        // Test message delivery
        vm.prank(agent2);
        router.markAsDelivered(messageId);

        message = router.getMessage(messageId);
        assertTrue(message.delivered);
    }

    function _simulateNetworkActivity() private {
        // Agent 1 sends multiple messages
        vm.startPrank(agent1);
        router.sendMessage(agent2, "Market analysis request", keccak256("ANALYSIS"));
        vm.warp(block.timestamp + 6 seconds);
        router.sendMessage(agent3, "Research collaboration", keccak256("COLLABORATION"));
        vm.stopPrank();

        // Agent 2 responds
        vm.warp(block.timestamp + 6 seconds);
        vm.prank(agent2);
        router.sendMessage(agent1, "Analysis complete", keccak256("RESPONSE"));

        // Agent updates endpoint
        vm.prank(agent3);
        registry.updateEndpoint("http://research-v2.ai");

        // Add more time to avoid rate limiting issues in subsequent tests
        vm.warp(block.timestamp + 10 seconds);

        // Verify activity
        assertEq(registry.activeAgentsCount(), 3);
        assertTrue(router.getMessages(agent2).length > 0);
        assertTrue(router.getMessages(agent3).length > 0);
    }

    function _performNetworkUpgrades() private {
        console.log("Performing network upgrades...");

        // Upgrade AgentRegistry
        AgentRegistryUpgradeable newRegistryImpl = new AgentRegistryUpgradeable();
        registry.upgradeToAndCall(address(newRegistryImpl), "");
        console.log("AgentRegistry upgraded successfully");

        // Upgrade MessageRouter
        MessageRouterUpgradeable newRouterImpl = new MessageRouterUpgradeable();
        router.upgradeToAndCall(address(newRouterImpl), "");
        console.log("MessageRouter upgraded successfully");

        // Verify versions remain the same (implementation logic unchanged)
        assertEq(registry.version(), "1.0.0");
        assertEq(router.version(), "1.0.0");
    }

    function _testBasicNetworkFunctionalityPostUpgrade() private {
        // Test agent discovery
        address[] memory dataAgents = registry.findAgentsByCapability(keccak256("data_analysis"));
        assertEq(dataAgents.length, 3);

        // Test messaging with agent2 to avoid rate limits on agent1
        vm.prank(agent2);
        bytes32 messageId = router.sendMessage(agent3, "Post-upgrade test", keccak256("POST_UPGRADE"));

        MessageRouterUpgradeable.Message memory message = router.getMessage(messageId);
        assertEq(message.from, agent2);
        assertEq(message.to, agent3);
        assertFalse(message.delivered);
    }

    function _verifyUpgradeDataPersistence() private {
        // Verify all agents are still registered and active
        assertEq(registry.activeAgentsCount(), 3);

        AgentRegistryUpgradeable.Agent memory agent = registry.getAgent(agent1);
        assertEq(agent.name, "DataAnalyzer");
        assertTrue(agent.active);

        agent = registry.getAgent(agent3);
        assertEq(agent.endpoint, "http://research-v2.ai"); // Updated endpoint should persist

        // Verify messages are preserved
        bytes32[] memory agent2Messages = router.getMessages(agent2);
        assertTrue(agent2Messages.length > 0);

        // Verify rate limiting can work for new messages after sufficient time
        vm.warp(block.timestamp + 10 seconds);
        vm.prank(agent3);
        router.sendMessage(agent1, "Rate limit test after upgrade", keccak256("RATE_TEST"));
    }

    function testEmergencyUpgradeScenario() public {
        // Simulate a critical bug discovery that requires emergency upgrade

        // 1. Pause both contracts
        registry.pause();
        router.pause();

        assertTrue(registry.paused());
        assertTrue(router.paused());

        // 2. Verify network is halted
        vm.prank(agent1);
        vm.expectRevert("AgentRegistry: paused");
        registry.registerAgent("EmergencyAgent", "http://emergency.ai", new bytes32[](0));

        vm.prank(agent1);
        vm.expectRevert("MessageRouter: paused");
        router.sendMessage(agent2, "Emergency message", keccak256("EMERGENCY"));

        // 3. Perform emergency upgrades
        AgentRegistryUpgradeable newRegistryImpl = new AgentRegistryUpgradeable();
        registry.upgradeToAndCall(address(newRegistryImpl), "");

        MessageRouterUpgradeable newRouterImpl = new MessageRouterUpgradeable();
        router.upgradeToAndCall(address(newRouterImpl), "");

        // 4. Unpause after upgrade
        registry.unpause();
        router.unpause();

        // 5. Verify network functionality restored
        vm.prank(agent1);
        router.sendMessage(agent2, "Post-upgrade message", keccak256("RECOVERY"));

        assertFalse(registry.paused());
        assertFalse(router.paused());
    }

    function testCrossContractUpgradeCompatibility() public {
        // Ensure that upgrading one contract doesn't break the other

        // Store initial state
        bytes32[] memory initialMessages = router.getMessages(agent2);
        uint256 initialActiveCount = registry.activeAgentsCount();

        // Upgrade only the registry
        AgentRegistryUpgradeable newRegistryImpl = new AgentRegistryUpgradeable();
        registry.upgradeToAndCall(address(newRegistryImpl), "");

        // Verify router still works with upgraded registry
        vm.prank(agent1);
        bytes32 messageId = router.sendMessage(agent2, "Cross-contract test", keccak256("TEST"));

        MessageRouterUpgradeable.Message memory message = router.getMessage(messageId);
        assertEq(message.content, "Cross-contract test");

        // Verify registry upgrade didn't affect router's message storage
        bytes32[] memory newMessages = router.getMessages(agent2);
        assertEq(newMessages.length, initialMessages.length + 1);

        // Now upgrade the router
        MessageRouterUpgradeable newRouterImpl = new MessageRouterUpgradeable();
        router.upgradeToAndCall(address(newRouterImpl), "");

        // Verify registry operations still work
        assertEq(registry.activeAgentsCount(), initialActiveCount);

        // Verify cross-contract functionality
        vm.prank(agent1);
        vm.warp(block.timestamp + 6 seconds); // Avoid rate limit
        router.sendMessage(agent3, "Final test message", keccak256("FINAL"));
    }

    function testUpgradeGasEfficiency() public {
        // Measure gas costs of operations before and after upgrade

        uint256 gasBefore;
        uint256 gasAfter;

        // Measure message sending before upgrade
        vm.prank(agent1);
        gasBefore = gasleft();
        router.sendMessage(agent2, "Gas test message", keccak256("GAS_TEST"));
        gasBefore = gasBefore - gasleft();

        // Perform upgrade
        MessageRouterUpgradeable newRouterImpl = new MessageRouterUpgradeable();
        router.upgradeToAndCall(address(newRouterImpl), "");

        // Measure message sending after upgrade
        vm.warp(block.timestamp + 6 seconds);
        vm.prank(agent1);
        gasAfter = gasleft();
        router.sendMessage(agent2, "Gas test message 2", keccak256("GAS_TEST"));
        gasAfter = gasAfter - gasleft();

        // Gas usage should be similar (within 50% tolerance for test stability)
        uint256 gasDiff = gasBefore > gasAfter ? gasBefore - gasAfter : gasAfter - gasBefore;
        uint256 tolerance = gasBefore / 2; // 50% tolerance for test environment variations

        assertLe(gasDiff, tolerance, "Gas usage changed significantly after upgrade");

        console.log("Gas before upgrade:", gasBefore);
        console.log("Gas after upgrade:", gasAfter);
        console.log("Gas difference:", gasDiff);
        console.log("Tolerance:", tolerance);
    }
}
