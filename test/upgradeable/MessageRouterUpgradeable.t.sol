// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../../src/upgradeable/AgentRegistryUpgradeable.sol";
import "../../src/upgradeable/MessageRouterUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MessageRouterUpgradeableTest is Test {
    AgentRegistryUpgradeable public registryImpl;
    AgentRegistryUpgradeable public registry;
    ERC1967Proxy public registryProxy;

    MessageRouterUpgradeable public routerImpl;
    MessageRouterUpgradeable public router;
    ERC1967Proxy public routerProxy;

    address public owner = address(this);
    address public agent1 = address(0x1);
    address public agent2 = address(0x2);
    address public nonOwner = address(0x3);

    bytes32 constant MESSAGE_TYPE_TEXT = keccak256("TEXT");
    bytes32 constant MESSAGE_TYPE_DATA = keccak256("DATA");

    function setUp() public {
        // Deploy and initialize AgentRegistry
        registryImpl = new AgentRegistryUpgradeable();
        bytes memory registryInitData = abi.encodeWithSelector(AgentRegistryUpgradeable.initialize.selector, owner);
        registryProxy = new ERC1967Proxy(address(registryImpl), registryInitData);
        registry = AgentRegistryUpgradeable(address(registryProxy));

        // Deploy and initialize MessageRouter
        routerImpl = new MessageRouterUpgradeable();
        bytes memory routerInitData =
            abi.encodeWithSelector(MessageRouterUpgradeable.initialize.selector, address(registry), owner);
        routerProxy = new ERC1967Proxy(address(routerImpl), routerInitData);
        router = MessageRouterUpgradeable(address(routerProxy));

        // Register test agents
        vm.startPrank(agent1);
        bytes32[] memory capabilities1 = new bytes32[](1);
        capabilities1[0] = keccak256("messaging");
        registry.registerAgent("Agent1", "http://agent1.com", capabilities1);
        vm.stopPrank();

        vm.startPrank(agent2);
        bytes32[] memory capabilities2 = new bytes32[](1);
        capabilities2[0] = keccak256("messaging");
        registry.registerAgent("Agent2", "http://agent2.com", capabilities2);
        vm.stopPrank();
    }

    function testInitialize() public {
        assertEq(router.owner(), owner);
        assertEq(router.pauser(), owner);
        assertEq(router.registry(), address(registry));
        assertEq(router.messageDelay(), 5 seconds);
        assertFalse(router.paused());
        assertEq(router.version(), "1.0.0");
    }

    function testCannotInitializeTwice() public {
        vm.expectRevert();
        router.initialize(address(registry), owner);
    }

    function testSendMessage() public {
        vm.prank(agent1);
        bytes32 messageId = router.sendMessage(agent2, "Hello Agent2!", MESSAGE_TYPE_TEXT);

        MessageRouterUpgradeable.Message memory message = router.getMessage(messageId);
        assertEq(message.from, agent1);
        assertEq(message.to, agent2);
        assertEq(message.content, "Hello Agent2!");
        assertEq(message.messageType, MESSAGE_TYPE_TEXT);
        assertFalse(message.delivered);
    }

    function testUpgradeAuthorization() public {
        // Deploy new implementation
        MessageRouterUpgradeable newImpl = new MessageRouterUpgradeable();

        // Only owner can upgrade
        vm.prank(nonOwner);
        vm.expectRevert();
        router.upgradeToAndCall(address(newImpl), "");

        // Owner can upgrade
        router.upgradeToAndCall(address(newImpl), "");

        // Verify upgrade
        assertEq(router.version(), "1.0.0");
    }

    function testStoragePersistenceAfterUpgrade() public {
        // Send message before upgrade
        vm.prank(agent1);
        bytes32 messageId = router.sendMessage(agent2, "Test message", MESSAGE_TYPE_TEXT);

        // Store initial state
        MessageRouterUpgradeable.Message memory messageBefore = router.getMessage(messageId);
        bytes32[] memory messagesBefore = router.getMessages(agent2);

        // Deploy new implementation
        MessageRouterUpgradeable newImpl = new MessageRouterUpgradeable();

        // Upgrade
        router.upgradeToAndCall(address(newImpl), "");

        // Verify storage persistence
        MessageRouterUpgradeable.Message memory messageAfter = router.getMessage(messageId);
        assertEq(messageAfter.from, messageBefore.from);
        assertEq(messageAfter.to, messageBefore.to);
        assertEq(messageAfter.content, messageBefore.content);
        assertEq(messageAfter.messageType, messageBefore.messageType);
        assertEq(messageAfter.delivered, messageBefore.delivered);

        bytes32[] memory messagesAfter = router.getMessages(agent2);
        assertEq(messagesAfter.length, messagesBefore.length);
        assertEq(messagesAfter[0], messagesBefore[0]);
    }

    function testRateLimitingPersistsAfterUpgrade() public {
        // Send first message
        vm.prank(agent1);
        router.sendMessage(agent2, "Message 1", MESSAGE_TYPE_TEXT);

        // Upgrade contract
        MessageRouterUpgradeable newImpl = new MessageRouterUpgradeable();
        router.upgradeToAndCall(address(newImpl), "");

        // Rate limiting should still work
        vm.prank(agent1);
        vm.expectRevert("MessageRouter: rate limit - too frequent");
        router.sendMessage(agent2, "Message 2", MESSAGE_TYPE_TEXT);

        // Wait and try again
        vm.warp(block.timestamp + router.messageDelay());
        vm.prank(agent1);
        router.sendMessage(agent2, "Message 2", MESSAGE_TYPE_TEXT);
    }

    function testPauseUpgradeableContract() public {
        // Pause the contract
        router.pause();
        assertTrue(router.paused());

        // Cannot send messages when paused
        vm.prank(agent1);
        vm.expectRevert("MessageRouter: paused");
        router.sendMessage(agent2, "Hello", MESSAGE_TYPE_TEXT);

        // Unpause
        router.unpause();
        assertFalse(router.paused());

        // Can send messages again
        vm.prank(agent1);
        router.sendMessage(agent2, "Hello", MESSAGE_TYPE_TEXT);
    }

    function testMessageDelayUpdatePersists() public {
        // Update message delay
        router.updateMessageDelay(10 seconds);
        assertEq(router.messageDelay(), 10 seconds);

        // Upgrade contract
        MessageRouterUpgradeable newImpl = new MessageRouterUpgradeable();
        router.upgradeToAndCall(address(newImpl), "");

        // Delay setting should persist
        assertEq(router.messageDelay(), 10 seconds);
    }

    function testImplementationIsDisabled() public {
        // Try to initialize the implementation directly (should fail)
        vm.expectRevert();
        routerImpl.initialize(address(registry), owner);
    }

    function testUpgradeWithRegistryChange() public {
        // Deploy new registry
        AgentRegistryUpgradeable newRegistryImpl = new AgentRegistryUpgradeable();
        bytes memory newRegistryInitData = abi.encodeWithSelector(AgentRegistryUpgradeable.initialize.selector, owner);
        ERC1967Proxy newRegistryProxy = new ERC1967Proxy(address(newRegistryImpl), newRegistryInitData);
        AgentRegistryUpgradeable newRegistry = AgentRegistryUpgradeable(address(newRegistryProxy));

        // Register agents in new registry
        vm.prank(agent1);
        bytes32[] memory capabilities = new bytes32[](1);
        capabilities[0] = keccak256("messaging");
        newRegistry.registerAgent("Agent1", "http://agent1.com", capabilities);

        // Create new router implementation that could theoretically point to new registry
        MessageRouterUpgradeable newImpl = new MessageRouterUpgradeable();

        // Upgrade (registry reference should remain the same due to storage layout)
        router.upgradeToAndCall(address(newImpl), "");

        // Verify registry reference hasn't changed
        assertEq(router.registry(), address(registry));
    }

    function testMultipleUpgrades() public {
        // Send initial message
        vm.prank(agent1);
        bytes32 messageId = router.sendMessage(agent2, "Initial message", MESSAGE_TYPE_TEXT);

        // First upgrade
        MessageRouterUpgradeable newImpl1 = new MessageRouterUpgradeable();
        router.upgradeToAndCall(address(newImpl1), "");

        // Verify message persists
        MessageRouterUpgradeable.Message memory message = router.getMessage(messageId);
        assertEq(message.content, "Initial message");

        // Send another message
        vm.warp(block.timestamp + router.messageDelay());
        vm.prank(agent1);
        bytes32 messageId2 = router.sendMessage(agent2, "Second message", MESSAGE_TYPE_TEXT);

        // Second upgrade
        MessageRouterUpgradeable newImpl2 = new MessageRouterUpgradeable();
        router.upgradeToAndCall(address(newImpl2), "");

        // Verify both messages persist
        message = router.getMessage(messageId);
        assertEq(message.content, "Initial message");

        MessageRouterUpgradeable.Message memory message2 = router.getMessage(messageId2);
        assertEq(message2.content, "Second message");

        // Verify message count
        bytes32[] memory messages = router.getMessages(agent2);
        assertEq(messages.length, 2);
    }

    function testOwnershipTransferAffectsUpgrades() public {
        address newOwner = address(0x999);

        // Transfer ownership
        router.transferOwnership(newOwner);
        assertEq(router.owner(), newOwner);

        // Old owner cannot upgrade anymore
        MessageRouterUpgradeable newImpl = new MessageRouterUpgradeable();
        vm.expectRevert();
        router.upgradeToAndCall(address(newImpl), "");

        // New owner can upgrade
        vm.prank(newOwner);
        router.upgradeToAndCall(address(newImpl), "");
    }
}
