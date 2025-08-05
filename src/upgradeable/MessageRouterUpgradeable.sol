// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./AgentRegistryUpgradeable.sol";

/**
 * @title MessageRouterUpgradeable
 * @dev Upgradeable version of MessageRouter that handles secure message routing between agents
 * Includes rate limiting to prevent spam and message delivery confirmation
 */
contract MessageRouterUpgradeable is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    /// @custom:storage-location erc7201:a2a.storage.MessageRouter
    struct MessageRouterStorage {
        AgentRegistryUpgradeable registry;
        mapping(bytes32 => Message) messages;
        mapping(address => bytes32[]) agentMessages;
        mapping(address => uint256) messageCounts;
        // Rate limiting
        mapping(address => uint256) lastMessageTime;
        mapping(address => uint256) messagesSentInWindow;
        uint256 messageDelay; // Minimum delay between messages
        // Pausable functionality
        bool paused;
        address pauser;
    }

    struct Message {
        address from;
        address to;
        bytes32 messageId;
        string content;
        uint256 timestamp;
        bool delivered;
        bytes32 messageType;
    }

    // keccak256(abi.encode(uint256(keccak256("a2a.storage.MessageRouter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MessageRouterStorageLocation =
        0xa2a0000000000000000000000000000000000000000000000000000000000002;

    function _getMessageRouterStorage() private pure returns (MessageRouterStorage storage $) {
        assembly {
            $.slot := MessageRouterStorageLocation
        }
    }

    uint256 public constant RATE_LIMIT_WINDOW = 1 hours;
    uint256 public constant MAX_MESSAGES_PER_WINDOW = 100;

    event MessageSent(bytes32 indexed messageId, address indexed from, address indexed to, bytes32 messageType);

    event MessageDelivered(bytes32 indexed messageId);
    event RateLimitUpdated(uint256 newDelay);
    event Paused(address account);
    event Unpaused(address account);
    event PauserChanged(address indexed previousPauser, address indexed newPauser);

    modifier onlyRegisteredAgent() {
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        AgentRegistryUpgradeable.Agent memory agent = $.registry.getAgent(msg.sender);
        require(agent.active, "Agent not registered or inactive");
        _;
    }

    modifier whenNotPaused() {
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        require(!$.paused, "MessageRouter: paused");
        _;
    }

    modifier whenPaused() {
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        require($.paused, "MessageRouter: not paused");
        _;
    }

    modifier onlyPauser() {
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        require(msg.sender == $.pauser, "MessageRouter: caller is not the pauser");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the MessageRouter with a registry address
     * @param _registry Address of the AgentRegistry contract
     * @param initialOwner The address that will own the contract
     */
    function initialize(address _registry, address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        MessageRouterStorage storage $ = _getMessageRouterStorage();
        $.registry = AgentRegistryUpgradeable(_registry);
        $.messageDelay = 5 seconds;
        $.paused = false;
        $.pauser = initialOwner;
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
        returns (bytes32)
    {
        MessageRouterStorage storage $ = _getMessageRouterStorage();

        // Input validation first
        require(bytes(content).length > 0, "Content required");
        AgentRegistryUpgradeable.Agent memory recipient = $.registry.getAgent(to);
        require(recipient.active, "Recipient not active");

        // Rate limiting checks after validation
        _checkRateLimit(msg.sender);

        bytes32 messageId =
            keccak256(abi.encodePacked(msg.sender, to, content, block.timestamp, $.messageCounts[msg.sender]));

        $.messages[messageId] = Message({
            from: msg.sender,
            to: to,
            messageId: messageId,
            content: content,
            timestamp: block.timestamp,
            delivered: false,
            messageType: messageType
        });

        $.agentMessages[to].push(messageId);
        $.messageCounts[msg.sender]++;

        // Update rate limiting
        $.lastMessageTime[msg.sender] = block.timestamp;
        $.messagesSentInWindow[msg.sender]++;

        emit MessageSent(messageId, msg.sender, to, messageType);
        return messageId;
    }

    /**
     * @notice Mark a message as delivered (only callable by recipient)
     * @param messageId The ID of the message to mark as delivered
     */
    function markAsDelivered(bytes32 messageId) external whenNotPaused {
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        Message storage message = $.messages[messageId];
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
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        return $.agentMessages[agent];
    }

    /**
     * @notice Get detailed information about a specific message
     * @param messageId The message ID
     * @return The message data structure
     */
    function getMessage(bytes32 messageId) external view returns (Message memory) {
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        return $.messages[messageId];
    }

    /**
     * @notice Get all undelivered messages for an agent
     * @param agent The agent's address
     * @return Array of undelivered message IDs
     */
    function getUndeliveredMessages(address agent) external view returns (bytes32[] memory) {
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        bytes32[] memory allMessages = $.agentMessages[agent];
        uint256 undeliveredCount = 0;

        for (uint256 i = 0; i < allMessages.length; i++) {
            if (!$.messages[allMessages[i]].delivered) {
                undeliveredCount++;
            }
        }

        bytes32[] memory undelivered = new bytes32[](undeliveredCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allMessages.length; i++) {
            if (!$.messages[allMessages[i]].delivered) {
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
        MessageRouterStorage storage $ = _getMessageRouterStorage();

        // Skip delay check for first message
        if ($.lastMessageTime[sender] > 0) {
            // Check minimum delay between messages
            require(
                block.timestamp >= $.lastMessageTime[sender] + $.messageDelay,
                "MessageRouter: rate limit - too frequent"
            );
        }

        // Reset window if needed
        if ($.lastMessageTime[sender] == 0 || block.timestamp >= $.lastMessageTime[sender] + RATE_LIMIT_WINDOW) {
            $.messagesSentInWindow[sender] = 0;
        }

        // Check messages per window
        require(
            $.messagesSentInWindow[sender] < MAX_MESSAGES_PER_WINDOW, "MessageRouter: rate limit - too many messages"
        );
    }

    /**
     * @notice Update the minimum delay between messages (only pauser)
     * @param newDelay New delay in seconds
     */
    function updateMessageDelay(uint256 newDelay) external onlyPauser {
        require(newDelay >= 1 seconds && newDelay <= 1 hours, "Invalid delay");

        MessageRouterStorage storage $ = _getMessageRouterStorage();
        $.messageDelay = newDelay;
        emit RateLimitUpdated(newDelay);
    }

    // Getter functions for rate limiting parameters
    function messageDelay() external view returns (uint256) {
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        return $.messageDelay;
    }

    function registry() external view returns (address) {
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        return address($.registry);
    }

    // Pausable functionality
    function paused() public view returns (bool) {
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        return $.paused;
    }

    function pause() external onlyPauser whenNotPaused {
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        $.paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyPauser whenPaused {
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        $.paused = false;
        emit Unpaused(msg.sender);
    }

    function changePauser(address newPauser) external onlyPauser {
        require(newPauser != address(0), "MessageRouter: new pauser is the zero address");

        MessageRouterStorage storage $ = _getMessageRouterStorage();
        address oldPauser = $.pauser;
        $.pauser = newPauser;
        emit PauserChanged(oldPauser, newPauser);
    }

    function pauser() external view returns (address) {
        MessageRouterStorage storage $ = _getMessageRouterStorage();
        return $.pauser;
    }

    // UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Get the current implementation version
     * @return Version string
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
