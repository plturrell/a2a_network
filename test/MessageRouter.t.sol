// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/MessageRouter.sol";
import "../src/AgentRegistry.sol";

contract MessageRouterTest is Test {
    MessageRouter public router;
    AgentRegistry public registry;
    
    address public agent1 = address(0x1);
    address public agent2 = address(0x2);
    address public agent3 = address(0x3);
    address public nonAgent = address(0x4);
    
    bytes32 constant MESSAGE_TYPE_TEXT = keccak256("TEXT");
    bytes32 constant MESSAGE_TYPE_DATA = keccak256("DATA");

    event MessageSent(
        bytes32 indexed messageId,
        address indexed from,
        address indexed to,
        bytes32 messageType
    );
    
    event MessageDelivered(bytes32 indexed messageId);

    function setUp() public {
        registry = new AgentRegistry();
        router = new MessageRouter(address(registry));
        
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

    function testSendMessage() public {
        vm.startPrank(agent1);
        
        string memory content = "Hello Agent2!";
        bytes32 messageId = router.sendMessage(agent2, content, MESSAGE_TYPE_TEXT);
        
        // Verify message was created
        MessageRouter.Message memory message = router.getMessage(messageId);
        assertEq(message.from, agent1);
        assertEq(message.to, agent2);
        assertEq(message.content, content);
        assertEq(message.messageType, MESSAGE_TYPE_TEXT);
        assertFalse(message.delivered);
        
        // Verify message appears in recipient's messages
        bytes32[] memory agent2Messages = router.getMessages(agent2);
        assertEq(agent2Messages.length, 1);
        assertEq(agent2Messages[0], messageId);
        
        vm.stopPrank();
    }

    function testCannotSendMessageAsNonRegisteredAgent() public {
        vm.startPrank(nonAgent);
        
        vm.expectRevert("Agent not registered or inactive");
        router.sendMessage(agent2, "Hello", MESSAGE_TYPE_TEXT);
        
        vm.stopPrank();
    }

    function testCannotSendMessageToInactiveAgent() public {
        // Deactivate agent2
        vm.prank(agent2);
        registry.deactivateAgent();
        
        vm.startPrank(agent1);
        vm.expectRevert("Recipient not active");
        router.sendMessage(agent2, "Hello", MESSAGE_TYPE_TEXT);
        vm.stopPrank();
    }

    function testCannotSendEmptyMessage() public {
        vm.startPrank(agent1);
        
        vm.expectRevert("Content required");
        router.sendMessage(agent2, "", MESSAGE_TYPE_TEXT);
        
        vm.stopPrank();
    }

    function testMarkAsDelivered() public {
        vm.prank(agent1);
        bytes32 messageId = router.sendMessage(agent2, "Hello", MESSAGE_TYPE_TEXT);
        
        // Only recipient can mark as delivered
        vm.prank(agent1);
        vm.expectRevert("Not message recipient");
        router.markAsDelivered(messageId);
        
        // Recipient marks as delivered
        vm.startPrank(agent2);
        
        vm.expectEmit(true, false, false, false);
        emit MessageDelivered(messageId);
        router.markAsDelivered(messageId);
        
        // Verify delivered status
        MessageRouter.Message memory message = router.getMessage(messageId);
        assertTrue(message.delivered);
        
        // Cannot mark as delivered twice
        vm.expectRevert("Already delivered");
        router.markAsDelivered(messageId);
        
        vm.stopPrank();
    }

    function testGetUndeliveredMessages() public {
        vm.startPrank(agent1);
        
        // Send multiple messages with proper delays
        bytes32 messageId1 = router.sendMessage(agent2, "Message 1", MESSAGE_TYPE_TEXT);
        vm.warp(block.timestamp + router.messageDelay());
        bytes32 messageId2 = router.sendMessage(agent2, "Message 2", MESSAGE_TYPE_DATA);
        vm.warp(block.timestamp + router.messageDelay());
        bytes32 messageId3 = router.sendMessage(agent2, "Message 3", MESSAGE_TYPE_TEXT);
        
        vm.stopPrank();
        
        // Mark one as delivered
        vm.prank(agent2);
        router.markAsDelivered(messageId2);
        
        // Check undelivered messages
        bytes32[] memory undelivered = router.getUndeliveredMessages(agent2);
        assertEq(undelivered.length, 2);
        assertEq(undelivered[0], messageId1);
        assertEq(undelivered[1], messageId3);
    }

    function testRateLimiting() public {
        vm.startPrank(agent1);
        
        // First message should succeed
        router.sendMessage(agent2, "Message 1", MESSAGE_TYPE_TEXT);
        
        // Second message too soon should fail
        vm.expectRevert("MessageRouter: rate limit - too frequent");
        router.sendMessage(agent2, "Message 2", MESSAGE_TYPE_TEXT);
        
        // Wait for delay and try again
        vm.warp(block.timestamp + router.messageDelay());
        router.sendMessage(agent2, "Message 2", MESSAGE_TYPE_TEXT);
        
        vm.stopPrank();
    }

    function testRateLimitWindow() public {
        vm.startPrank(agent1);
        
        // Send messages up to the limit
        for (uint i = 0; i < router.MAX_MESSAGES_PER_WINDOW(); i++) {
            router.sendMessage(agent2, "Message", MESSAGE_TYPE_TEXT);
            vm.warp(block.timestamp + router.messageDelay());
        }
        
        // Next message should fail
        vm.expectRevert("MessageRouter: rate limit - too many messages");
        router.sendMessage(agent2, "Too many", MESSAGE_TYPE_TEXT);
        
        // Wait for window to reset
        vm.warp(block.timestamp + router.RATE_LIMIT_WINDOW());
        
        // Should be able to send again
        router.sendMessage(agent2, "New window", MESSAGE_TYPE_TEXT);
        
        vm.stopPrank();
    }

    function testPauseFunction() public {
        // Only pauser can pause
        vm.prank(agent1);
        vm.expectRevert("Pausable: caller is not the pauser");
        router.pause();
        
        // Pause the contract
        router.pause();
        assertTrue(router.paused());
        
        // Cannot send messages when paused
        vm.prank(agent1);
        vm.expectRevert("Pausable: paused");
        router.sendMessage(agent2, "Hello", MESSAGE_TYPE_TEXT);
        
        // Unpause
        router.unpause();
        assertFalse(router.paused());
        
        // Can send messages again
        vm.prank(agent1);
        router.sendMessage(agent2, "Hello", MESSAGE_TYPE_TEXT);
    }

    function testUpdateMessageDelay() public {
        // Only pauser can update
        vm.prank(agent1);
        vm.expectRevert("Pausable: caller is not the pauser");
        router.updateMessageDelay(10 seconds);
        
        // Update delay
        router.updateMessageDelay(10 seconds);
        assertEq(router.messageDelay(), 10 seconds);
        
        // Test bounds
        vm.expectRevert("Invalid delay");
        router.updateMessageDelay(0);
        
        vm.expectRevert("Invalid delay");
        router.updateMessageDelay(2 hours);
    }

    function testMessageIdUniqueness() public {
        vm.startPrank(agent1);
        
        string memory content = "Unique message";
        bytes32 messageId1 = router.sendMessage(agent2, content, MESSAGE_TYPE_TEXT);
        
        // Wait and send same content again
        vm.warp(block.timestamp + router.messageDelay());
        bytes32 messageId2 = router.sendMessage(agent2, content, MESSAGE_TYPE_TEXT);
        
        // Message IDs should be different
        assertTrue(messageId1 != messageId2);
        
        vm.stopPrank();
    }

    function testMultipleRecipients() public {
        vm.startPrank(agent3);
        bytes32[] memory capabilities = new bytes32[](1);
        capabilities[0] = keccak256("messaging");
        registry.registerAgent("Agent3", "http://agent3.com", capabilities);
        vm.stopPrank();
        
        vm.startPrank(agent1);
        
        // Send to multiple agents
        bytes32 messageId1 = router.sendMessage(agent2, "Hello Agent2", MESSAGE_TYPE_TEXT);
        vm.warp(block.timestamp + router.messageDelay());
        bytes32 messageId2 = router.sendMessage(agent3, "Hello Agent3", MESSAGE_TYPE_TEXT);
        
        // Verify each agent has their own messages
        bytes32[] memory agent2Messages = router.getMessages(agent2);
        bytes32[] memory agent3Messages = router.getMessages(agent3);
        
        assertEq(agent2Messages.length, 1);
        assertEq(agent3Messages.length, 1);
        assertEq(agent2Messages[0], messageId1);
        assertEq(agent3Messages[0], messageId2);
        
        vm.stopPrank();
    }
}