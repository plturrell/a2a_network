// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title AgentRegistry
 * @dev Registry contract for managing autonomous agents in the A2A Network.
 * Allows agents to register, update their endpoints, manage capabilities,
 * and be discovered by other agents.
 */
contract AgentRegistry is Pausable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct Agent {
        address owner;
        string name;
        string endpoint;
        bytes32[] capabilities;
        uint256 reputation;
        bool active;
        uint256 registeredAt;
    }

    mapping(address => Agent) public agents;
    mapping(bytes32 => EnumerableSet.AddressSet) private _capabilityToAgents;
    address[] public allAgents;
    uint256 public activeAgentsCount;

    // --- Access Control ---
    

    constructor() {
        
        
    }

    event AgentRegistered(address indexed agent, string name, string endpoint);
    event AgentUpdated(address indexed agent, string endpoint);
    event AgentDeactivated(address indexed agent);

    // Reputation
    event ReputationChanged(address indexed agent, int256 delta, uint256 newReputation);

    modifier onlyAgentOwner(address agentAddress) {
        require(agents[agentAddress].owner == msg.sender, "Not agent owner");
        _;
    }

    /**
     * @notice Register a new agent in the network
     * @param name The display name of the agent
     * @param endpoint The API endpoint URL for the agent
     * @param capabilities Array of capability identifiers the agent supports
     */
    function registerAgent(
        string memory name,
        string memory endpoint,
        bytes32[] memory capabilities
    ) external whenNotPaused nonReentrant {
        require(bytes(name).length > 0, "Name required");
        require(bytes(endpoint).length > 0, "Endpoint required");
        require(agents[msg.sender].owner == address(0), "Agent already registered");

        agents[msg.sender] = Agent({
            owner: msg.sender,
            name: name,
            endpoint: endpoint,
            capabilities: capabilities,
            reputation: 100,
            active: true,
            registeredAt: block.timestamp
        });

        allAgents.push(msg.sender);
        activeAgentsCount++;

        for (uint i = 0; i < capabilities.length; i++) {
            _capabilityToAgents[capabilities[i]].add(msg.sender);
        }

        emit AgentRegistered(msg.sender, name, endpoint);
    }

    /**
     * @notice Update the endpoint URL for an existing agent
     * @param newEndpoint The new endpoint URL
     */
    function updateEndpoint(string memory newEndpoint) external onlyAgentOwner(msg.sender) whenNotPaused nonReentrant {
        require(bytes(newEndpoint).length > 0, "Endpoint required");
        agents[msg.sender].endpoint = newEndpoint;
        emit AgentUpdated(msg.sender, newEndpoint);
    }

    /**
     * @notice Deactivate an agent, preventing it from sending or receiving messages
     */
    function deactivateAgent() external onlyAgentOwner(msg.sender) whenNotPaused nonReentrant {
        require(agents[msg.sender].active, "Agent already inactive");
        agents[msg.sender].active = false;
        activeAgentsCount--;
        emit AgentDeactivated(msg.sender);
    }

    /**
     * @notice Find all agents that have a specific capability
     * @param capability The capability identifier to search for
     * @return Array of agent addresses with the specified capability
     */
    function findAgentsByCapability(bytes32 capability) external view returns (address[] memory) {
        uint256 len = _capabilityToAgents[capability].length();
        address[] memory list = new address[](len);
        for (uint256 i; i < len; ++i) {
            list[i] = _capabilityToAgents[capability].at(i);
        }
        return list;
    }

    /**
     * @notice Internal view helper for tests to fetch set length
     */
    function _capabilitySetLength(bytes32 capability) external view returns (uint256) {
        return _capabilityToAgents[capability].length();
    }

    // Storage gap for future upgrades

    /**
     * @notice Get detailed information about a specific agent
     * @param agentAddress The address of the agent
     * @return The agent's data structure
     */
    function getAgent(address agentAddress) external view returns (Agent memory) {
        return agents[agentAddress];
    }

    /**
     * @notice Get all registered agent addresses
     * @return Array of all agent addresses (including inactive ones)
     */
    function getAllAgents() external view returns (address[] memory) {
        return allAgents;
    }

    /**
     * @notice Get the count of currently active agents
     * @return The number of active agents
     */
    function getActiveAgentsCount() external view returns (uint256) {
        return activeAgentsCount;
    }

    /**
     * @notice Reactivate a previously deactivated agent
     */
    function reactivateAgent() external onlyAgentOwner(msg.sender) whenNotPaused nonReentrant {
        require(!agents[msg.sender].active, "Agent already active");
        require(agents[msg.sender].owner != address(0), "Agent not registered");
        agents[msg.sender].active = true;
        activeAgentsCount++;
        emit AgentUpdated(msg.sender, agents[msg.sender].endpoint);
    }

    // --- Reputation Management (private network) ---
    uint256 private constant _MAX_REPUTATION = 200;

    /**
     * @notice Increase an agent's reputation (admin only)
     * @param agent The agent address
     * @param amount Increment amount
     */
    function increaseReputation(address agent, uint256 amount) external onlyPauser {
        Agent storage a = agents[agent];
        require(a.owner != address(0), "Not registered");
        uint256 old = a.reputation;
        uint256 newVal = old + amount;
        if (newVal > _MAX_REPUTATION) newVal = _MAX_REPUTATION;
        a.reputation = newVal;
        emit ReputationChanged(agent, int256(amount), newVal);
    }

    /**
     * @notice Decrease an agent's reputation (admin only)
     * @param agent The agent address
     * @param amount Decrement amount
     */
    function decreaseReputation(address agent, uint256 amount) external onlyPauser {
        Agent storage a = agents[agent];
        require(a.owner != address(0), "Not registered");
        uint256 old = a.reputation;
        uint256 newVal = old > amount ? old - amount : 0;
        a.reputation = newVal;
        emit ReputationChanged(agent, -int256(amount), newVal);
    }

    
    uint256[49] private __gap;
    // slot reserved for potential future _capabilityToAgents replacement

}