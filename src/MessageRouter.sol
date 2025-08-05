// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./AgentRegistry.sol";
import "./Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MessageRouter
 * @dev Handles secure message routing between registered agents in the A2A Network.
 * Includes rate limiting to prevent spam and message delivery confirmation.
 */
contract MessageRouter is Pausable, ReentrancyGuard {
    AgentRegistry public immutable registry;

    struct Message {
        address from;
        address to;
        bytes32 messageId;
        string content;
        uint256 timestamp;
        bool delivered;
        bytes32 messageType;
    }

    mapping(bytes32 => Message) public messages;
    mapping(address => bytes32[]) public agentMessages;
    mapping(address => uint256) public messageCounts;

    // Rate limiting
    mapping(address => uint256) public lastMessageTime;
    mapping(address => uint256) public messagesSentInWindow;
    uint256 public constant RATE_LIMIT_WINDOW = 1 hours;
    uint256 public constant MAX_MESSAGES_PER_WINDOW = 100;
    uint256 public messageDelay = 5 seconds; // Minimum delay between messages

    event MessageSent(bytes32 indexed messageId, address indexed from, address indexed to, bytes32 messageType);

    event MessageDelivered(bytes32 indexed messageId);
    event RateLimitUpdated(uint256 newDelay);

    /**
     * @notice Initialize the MessageRouter with a registry address
     * @param _registry Address of the AgentRegistry contract
     */
    constructor(address _registry) {
        registry = AgentRegistry(_registry);
    }

    modifier onlyRegisteredAgent() {
        AgentRegistry.Agent memory agent = registry.getAgent(msg.sender);
        require(agent.active, "Agent not registered or inactive");
        _;
    }

    /**
     * @notice Send a message to another agent
     * @param to The recipient agent's address
     * @param content The message content
     * @param messageType Type identifier for the message
     * @return messageId Unique identifier for the sent message
     */
    function sendMessage(address to, string memory content, bytes32 messageType)
        external
        onlyRegisteredAgent
        whenNotPaused
        nonReentrant
        returns (bytes32)
    {
        // Input validation first
        require(bytes(content).length > 0, "Content required");
        AgentRegistry.Agent memory recipient = registry.getAgent(to);
        require(recipient.active, "Recipient not active");

        // Rate limiting checks after validation
        _checkRateLimit(msg.sender);

        bytes32 messageId =
            keccak256(abi.encodePacked(msg.sender, to, content, block.timestamp, messageCounts[msg.sender]));

        messages[messageId] = Message({
            from: msg.sender,
            to: to,
            messageId: messageId,
            content: content,
            timestamp: block.timestamp,
            delivered: false,
            messageType: messageType
        });

        agentMessages[to].push(messageId);
        messageCounts[msg.sender]++;

        // Update rate limiting
        lastMessageTime[msg.sender] = block.timestamp;
        messagesSentInWindow[msg.sender]++;

        emit MessageSent(messageId, msg.sender, to, messageType);
        return messageId;
    }

    /**
     * @notice Mark a message as delivered (only callable by recipient)
     * @param messageId The ID of the message to mark as delivered
     */
    function markAsDelivered(bytes32 messageId) external whenNotPaused nonReentrant {
        Message storage message = messages[messageId];
        require(message.to == msg.sender, "Not message recipient");
        require(!message.delivered, "Already delivered");

        message.delivered = true;
        emit MessageDelivered(messageId);
    }

    /**
     * @notice Get all message IDs for a specific agent
     * @param agent The agent's address
     * @return Array of message IDs
     */
    function getMessages(address agent) external view returns (bytes32[] memory) {
        return agentMessages[agent];
    }

    /**
     * @notice Get detailed information about a specific message
     * @param messageId The message ID
     * @return The message data structure
     */
    function getMessage(bytes32 messageId) external view returns (Message memory) {
        return messages[messageId];
    }

    /**
     * @notice Get all undelivered messages for an agent
     * @param agent The agent's address
     * @return Array of undelivered message IDs
     */
    function getUndeliveredMessages(address agent) external view returns (bytes32[] memory) {
        bytes32[] memory allMessages = agentMessages[agent];
        uint256 undeliveredCount = 0;

        for (uint256 i = 0; i < allMessages.length; i++) {
            if (!messages[allMessages[i]].delivered) {
                undeliveredCount++;
            }
        }

        bytes32[] memory undelivered = new bytes32[](undeliveredCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allMessages.length; i++) {
            if (!messages[allMessages[i]].delivered) {
                undelivered[index] = allMessages[i];
                index++;
            }
        }

        return undelivered;
    }

    /**
     * @dev Check rate limiting for message sending
     * @param sender The address sending the message
     */
    function _checkRateLimit(address sender) private {
        // Skip delay check for first message
        if (lastMessageTime[sender] > 0) {
            // Check minimum delay between messages
            require(
                block.timestamp >= lastMessageTime[sender] + messageDelay, "MessageRouter: rate limit - too frequent"
            );
        }

        // Reset window if needed
        if (lastMessageTime[sender] == 0 || block.timestamp >= lastMessageTime[sender] + RATE_LIMIT_WINDOW) {
            messagesSentInWindow[sender] = 0;
        }

        // Check messages per window
        require(messagesSentInWindow[sender] < MAX_MESSAGES_PER_WINDOW, "MessageRouter: rate limit - too many messages");
    }

    /**
     * @notice Update the minimum delay between messages (only pauser)
     * @param newDelay New delay in seconds
     */
    function updateMessageDelay(uint256 newDelay) external onlyPauser nonReentrant {
        require(newDelay >= 1 seconds && newDelay <= 1 hours, "Invalid delay");
        messageDelay = newDelay;
        emit RateLimitUpdated(newDelay);
    }

    // Storage gap for future upgrades
    uint256[50] private __gap;
}
