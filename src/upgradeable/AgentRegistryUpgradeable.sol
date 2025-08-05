// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title AgentRegistryUpgradeable
 * @dev Upgradeable version of the AgentRegistry contract using UUPS proxy pattern
 * This contract manages agent registration, discovery, and lifecycle in the A2A Network
 */
contract AgentRegistryUpgradeable is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    /// @custom:storage-location erc7201:a2a.storage.AgentRegistry
    struct AgentRegistryStorage {
        // Agent data structure
        mapping(address => Agent) agents;
        mapping(bytes32 => address[]) capabilityToAgents;
        address[] allAgents;
        uint256 activeAgentsCount;
        // Pausable functionality
        bool paused;
        address pauser;
    }

    struct Agent {
        address owner;
        string name;
        string endpoint;
        bytes32[] capabilities;
        uint256 reputation;
        bool active;
        uint256 registeredAt;
    }

    // keccak256(abi.encode(uint256(keccak256("a2a.storage.AgentRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AgentRegistryStorageLocation =
        0xa2a0000000000000000000000000000000000000000000000000000000000001;

    function _getAgentRegistryStorage() private pure returns (AgentRegistryStorage storage $) {
        assembly {
            $.slot := AgentRegistryStorageLocation
        }
    }

    event AgentRegistered(address indexed agent, string name, string endpoint);
    event AgentUpdated(address indexed agent, string endpoint);
    event AgentDeactivated(address indexed agent);
    event Paused(address account);
    event Unpaused(address account);
    event PauserChanged(address indexed previousPauser, address indexed newPauser);

    modifier whenNotPaused() {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        require(!$.paused, "AgentRegistry: paused");
        _;
    }

    modifier whenPaused() {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        require($.paused, "AgentRegistry: not paused");
        _;
    }

    modifier onlyPauser() {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        require(msg.sender == $.pauser, "AgentRegistry: caller is not the pauser");
        _;
    }

    modifier onlyAgentOwner(address agentAddress) {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        require($.agents[agentAddress].owner == msg.sender, "Not agent owner");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract (replaces constructor for upgradeable contracts)
     * @param initialOwner The address that will own the contract
     */
    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        $.paused = false;
        $.pauser = initialOwner;
    }

    /**
     * @notice Register a new agent in the network
     * @param name The display name of the agent
     * @param endpoint The API endpoint URL for the agent
     * @param capabilities Array of capability identifiers the agent supports
     */
    function registerAgent(string memory name, string memory endpoint, bytes32[] memory capabilities)
        external
        whenNotPaused
    {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();

        require(bytes(name).length > 0, "Name required");
        require(bytes(endpoint).length > 0, "Endpoint required");
        require($.agents[msg.sender].owner == address(0), "Agent already registered");

        $.agents[msg.sender] = Agent({
            owner: msg.sender,
            name: name,
            endpoint: endpoint,
            capabilities: capabilities,
            reputation: 100,
            active: true,
            registeredAt: block.timestamp
        });

        $.allAgents.push(msg.sender);
        $.activeAgentsCount++;

        for (uint256 i = 0; i < capabilities.length; i++) {
            $.capabilityToAgents[capabilities[i]].push(msg.sender);
        }

        emit AgentRegistered(msg.sender, name, endpoint);
    }

    /**
     * @notice Update the endpoint URL for an existing agent
     * @param newEndpoint The new endpoint URL
     */
    function updateEndpoint(string memory newEndpoint) external onlyAgentOwner(msg.sender) whenNotPaused {
        require(bytes(newEndpoint).length > 0, "Endpoint required");

        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        $.agents[msg.sender].endpoint = newEndpoint;
        emit AgentUpdated(msg.sender, newEndpoint);
    }

    /**
     * @notice Deactivate an agent, preventing it from sending or receiving messages
     */
    function deactivateAgent() external onlyAgentOwner(msg.sender) whenNotPaused {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        require($.agents[msg.sender].active, "Agent already inactive");

        $.agents[msg.sender].active = false;
        $.activeAgentsCount--;
        emit AgentDeactivated(msg.sender);
    }

    /**
     * @notice Reactivate a previously deactivated agent
     */
    function reactivateAgent() external onlyAgentOwner(msg.sender) whenNotPaused {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        require(!$.agents[msg.sender].active, "Agent already active");
        require($.agents[msg.sender].owner != address(0), "Agent not registered");

        $.agents[msg.sender].active = true;
        $.activeAgentsCount++;
        emit AgentUpdated(msg.sender, $.agents[msg.sender].endpoint);
    }

    /**
     * @notice Find all agents that have a specific capability
     * @param capability The capability identifier to search for
     * @return Array of agent addresses with the specified capability
     */
    function findAgentsByCapability(bytes32 capability) external view returns (address[] memory) {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        return $.capabilityToAgents[capability];
    }

    /**
     * @notice Get detailed information about a specific agent
     * @param agentAddress The address of the agent
     * @return The agent's data structure
     */
    function getAgent(address agentAddress) external view returns (Agent memory) {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        return $.agents[agentAddress];
    }

    /**
     * @notice Get all registered agent addresses
     * @return Array of all agent addresses (including inactive ones)
     */
    function getAllAgents() external view returns (address[] memory) {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        return $.allAgents;
    }

    /**
     * @notice Get the count of currently active agents
     * @return The number of active agents
     */
    function getActiveAgentsCount() external view returns (uint256) {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        return $.activeAgentsCount;
    }

    /**
     * @notice Get the count of currently active agents (external access)
     */
    function activeAgentsCount() external view returns (uint256) {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        return $.activeAgentsCount;
    }

    // Pausable functionality
    function paused() public view returns (bool) {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        return $.paused;
    }

    function pause() external onlyPauser whenNotPaused {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        $.paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyPauser whenPaused {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        $.paused = false;
        emit Unpaused(msg.sender);
    }

    function changePauser(address newPauser) external onlyPauser {
        require(newPauser != address(0), "AgentRegistry: new pauser is the zero address");

        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
        address oldPauser = $.pauser;
        $.pauser = newPauser;
        emit PauserChanged(oldPauser, newPauser);
    }

    function pauser() external view returns (address) {
        AgentRegistryStorage storage $ = _getAgentRegistryStorage();
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
