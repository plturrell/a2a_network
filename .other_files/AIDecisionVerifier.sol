// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./Pausable.sol";

/**
 * @title AIDecisionVerifier
 * @dev Smart contract for verifying and recording AI decisions on-chain
 * Provides cryptographic proof and immutable audit trails for AI agent decisions
 */
contract AIDecisionVerifier is Pausable {
    
    struct AIDecision {
        address agentAddress;
        string agentId;
        bytes32 decisionHash;
        string modelVersion;
        string inputDataHash;
        string decisionType;
        string decisionOutput;
        uint256 confidenceScore;  // 0-10000 (basis points for precision)
        uint256 timestamp;
        bytes signature;
        bool verified;
        uint256 blockNumber;
        string metadataUri;  // IPFS or other storage for full decision context
    }
    
    struct VerificationChain {
        bytes32[] previousDecisions;
        bytes32 nextDecision;
        uint256 chainLength;
        bool isChainValid;
    }
    
    // Decision storage
    mapping(bytes32 => AIDecision) public decisions;
    mapping(address => bytes32[]) public agentDecisions;
    mapping(string => bytes32[]) public decisionsByType;
    mapping(bytes32 => VerificationChain) public verificationChains;
    
    // Agent verification keys
    mapping(address => bytes32) public agentPublicKeys;
    mapping(address => bool) public verifiedAgents;
    
    // Decision statistics
    mapping(address => uint256) public agentDecisionCount;
    mapping(string => uint256) public decisionTypeCount;
    
    bytes32[] public allDecisions;
    uint256 public totalDecisions;
    
    // Events
    event AIDecisionRecorded(
        bytes32 indexed decisionId,
        address indexed agentAddress,
        string agentId,
        string decisionType,
        uint256 confidenceScore,
        uint256 timestamp
    );
    
    event DecisionVerified(
        bytes32 indexed decisionId,
        address indexed verifier,
        bool isValid
    );
    
    event AgentRegistered(
        address indexed agentAddress,
        bytes32 publicKeyHash
    );
    
    event VerificationChainCreated(
        bytes32 indexed decisionId,
        bytes32[] previousDecisions,
        uint256 chainLength
    );

    modifier onlyVerifiedAgent() {
        require(verifiedAgents[msg.sender], "Agent not verified");
        _;
    }
    
    modifier validDecision(bytes32 decisionId) {
        require(decisions[decisionId].timestamp > 0, "Decision does not exist");
        _;
    }

    /**
     * @notice Register an agent for AI decision verification
     * @param publicKeyHash Hash of the agent's public key for signature verification
     */
    function registerAgent(bytes32 publicKeyHash) external whenNotPaused {
        require(publicKeyHash != bytes32(0), "Invalid public key hash");
        require(!verifiedAgents[msg.sender], "Agent already registered");
        
        agentPublicKeys[msg.sender] = publicKeyHash;
        verifiedAgents[msg.sender] = true;
        
        emit AgentRegistered(msg.sender, publicKeyHash);
    }

    /**
     * @notice Record an AI decision on the blockchain
     * @param agentId String identifier for the agent
     * @param decisionHash Hash of the complete decision data
     * @param modelVersion Version of the AI model used
     * @param inputDataHash Hash of the input data
     * @param decisionType Type/category of the decision
     * @param decisionOutput The actual decision output (truncated if needed)
     * @param confidenceScore Confidence level (0-10000 basis points)
     * @param signature Cryptographic signature of the decision
     * @param metadataUri URI for additional decision metadata
     * @param previousDecisions Array of previous decision IDs for chaining
     */
    function recordAIDecision(
        string memory agentId,
        bytes32 decisionHash,
        string memory modelVersion,
        string memory inputDataHash,
        string memory decisionType,
        string memory decisionOutput,
        uint256 confidenceScore,
        bytes memory signature,
        string memory metadataUri,
        bytes32[] memory previousDecisions
    ) external onlyVerifiedAgent whenNotPaused returns (bytes32) {
        require(bytes(agentId).length > 0, "Agent ID required");
        require(decisionHash != bytes32(0), "Decision hash required");
        require(confidenceScore <= 10000, "Invalid confidence score");
        require(signature.length > 0, "Signature required");
        
        // Generate unique decision ID
        bytes32 decisionId = keccak256(
            abi.encodePacked(
                msg.sender,
                agentId,
                decisionHash,
                block.timestamp,
                block.number
            )
        );
        
        // Ensure unique decision ID
        require(decisions[decisionId].timestamp == 0, "Decision ID collision");
        
        // Create decision record
        decisions[decisionId] = AIDecision({
            agentAddress: msg.sender,
            agentId: agentId,
            decisionHash: decisionHash,
            modelVersion: modelVersion,
            inputDataHash: inputDataHash,
            decisionType: decisionType,
            decisionOutput: decisionOutput,
            confidenceScore: confidenceScore,
            timestamp: block.timestamp,
            signature: signature,
            verified: false,  // Will be verified separately
            blockNumber: block.number,
            metadataUri: metadataUri
        });
        
        // Create verification chain
        if (previousDecisions.length > 0) {
            verificationChains[decisionId] = VerificationChain({
                previousDecisions: previousDecisions,
                nextDecision: bytes32(0),  // Will be set by future decisions
                chainLength: previousDecisions.length + 1,
                isChainValid: _validateDecisionChain(previousDecisions)
            });
            
            // Update next decision reference in previous decisions
            for (uint i = 0; i < previousDecisions.length; i++) {
                if (verificationChains[previousDecisions[i]].nextDecision == bytes32(0)) {
                    verificationChains[previousDecisions[i]].nextDecision = decisionId;
                }
            }
            
            emit VerificationChainCreated(decisionId, previousDecisions, previousDecisions.length + 1);
        }
        
        // Update mappings and counters
        agentDecisions[msg.sender].push(decisionId);
        decisionsByType[decisionType].push(decisionId);
        allDecisions.push(decisionId);
        
        agentDecisionCount[msg.sender]++;
        decisionTypeCount[decisionType]++;
        totalDecisions++;
        
        emit AIDecisionRecorded(
            decisionId,
            msg.sender,
            agentId,
            decisionType,
            confidenceScore,
            block.timestamp
        );
        
        return decisionId;
    }

    /**
     * @notice Verify the cryptographic signature of an AI decision
     * @param decisionId The decision to verify
     * @param publicKey The public key to verify against
     */
    function verifyDecisionSignature(
        bytes32 decisionId,
        bytes memory publicKey
    ) external validDecision(decisionId) returns (bool) {
        AIDecision storage decision = decisions[decisionId];
        
        // Reconstruct the signed message
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                decision.agentId,
                decision.decisionHash,
                decision.modelVersion,
                decision.inputDataHash,
                decision.decisionType,
                decision.confidenceScore,
                decision.timestamp
            )
        );
        
        // Verify signature (simplified - in production use proper ECDSA verification)
        bytes32 publicKeyHash = keccak256(publicKey);
        bool isValid = (publicKeyHash == agentPublicKeys[decision.agentAddress]);
        
        if (isValid) {
            decision.verified = true;
            emit DecisionVerified(decisionId, msg.sender, true);
        }
        
        return isValid;
    }

    /**
     * @notice Get decision details by ID
     * @param decisionId The decision ID to retrieve
     */
    function getDecision(bytes32 decisionId) external view validDecision(decisionId) 
        returns (AIDecision memory) {
        return decisions[decisionId];
    }

    /**
     * @notice Get all decisions by an agent
     * @param agentAddress The agent's address
     */
    function getAgentDecisions(address agentAddress) external view 
        returns (bytes32[] memory) {
        return agentDecisions[agentAddress];
    }

    /**
     * @notice Get all decisions of a specific type
     * @param decisionType The decision type to filter by
     */
    function getDecisionsByType(string memory decisionType) external view 
        returns (bytes32[] memory) {
        return decisionsByType[decisionType];
    }

    /**
     * @notice Get verification chain for a decision
     * @param decisionId The decision ID
     */
    function getVerificationChain(bytes32 decisionId) external view validDecision(decisionId)
        returns (VerificationChain memory) {
        return verificationChains[decisionId];
    }

    /**
     * @notice Get agent statistics
     * @param agentAddress The agent's address
     */
    function getAgentStats(address agentAddress) external view returns (
        uint256 decisionCount,
        uint256 verifiedDecisions,
        bool isVerified
    ) {
        decisionCount = agentDecisionCount[agentAddress];
        isVerified = verifiedAgents[agentAddress];
        
        // Count verified decisions
        bytes32[] memory agentDecisionsList = agentDecisions[agentAddress];
        for (uint i = 0; i < agentDecisionsList.length; i++) {
            if (decisions[agentDecisionsList[i]].verified) {
                verifiedDecisions++;
            }
        }
    }

    /**
     * @notice Get global statistics
     */
    function getGlobalStats() external view returns (
        uint256 totalDecisionsCount,
        uint256 totalVerifiedAgents,
        uint256 totalVerifiedDecisions
    ) {
        totalDecisionsCount = totalDecisions;
        
        // Count verified agents (simplified - could be optimized)
        uint256 verifiedCount = 0;
        for (uint i = 0; i < allDecisions.length; i++) {
            if (verifiedAgents[decisions[allDecisions[i]].agentAddress]) {
                verifiedCount++;
            }
        }
        totalVerifiedAgents = verifiedCount;
        
        // Count verified decisions
        for (uint i = 0; i < allDecisions.length; i++) {
            if (decisions[allDecisions[i]].verified) {
                totalVerifiedDecisions++;
            }
        }
    }

    /**
     * @notice Query decisions with filters
     * @param agentAddress Filter by agent (address(0) for all)
     * @param decisionType Filter by type (empty string for all)
     * @param minConfidence Minimum confidence score
     * @param maxAge Maximum age in seconds (0 for no limit)
     */
    function queryDecisions(
        address agentAddress,
        string memory decisionType,
        uint256 minConfidence,
        uint256 maxAge
    ) external view returns (bytes32[] memory) {
        bytes32[] memory filteredDecisions = new bytes32[](totalDecisions);
        uint256 count = 0;
        uint256 cutoffTime = maxAge > 0 ? block.timestamp - maxAge : 0;
        
        for (uint i = 0; i < allDecisions.length; i++) {
            bytes32 decisionId = allDecisions[i];
            AIDecision memory decision = decisions[decisionId];
            
            // Apply filters
            if (agentAddress != address(0) && decision.agentAddress != agentAddress) {
                continue;
            }
            
            if (bytes(decisionType).length > 0 && 
                keccak256(bytes(decision.decisionType)) != keccak256(bytes(decisionType))) {
                continue;
            }
            
            if (decision.confidenceScore < minConfidence) {
                continue;
            }
            
            if (maxAge > 0 && decision.timestamp < cutoffTime) {
                continue;
            }
            
            filteredDecisions[count] = decisionId;
            count++;
        }
        
        // Return properly sized array
        bytes32[] memory result = new bytes32[](count);
        for (uint i = 0; i < count; i++) {
            result[i] = filteredDecisions[i];
        }
        
        return result;
    }

    /**
     * @notice Internal function to validate decision chain integrity
     * @param previousDecisions Array of previous decision IDs
     */
    function _validateDecisionChain(bytes32[] memory previousDecisions) 
        internal view returns (bool) {
        for (uint i = 0; i < previousDecisions.length; i++) {
            if (decisions[previousDecisions[i]].timestamp == 0) {
                return false;  // Previous decision doesn't exist
            }
        }
        return true;
    }

    /**
     * @notice Emergency function to update decision verification status (admin only)
     * @param decisionId The decision to update
     * @param verified New verification status
     */
    function updateDecisionVerification(bytes32 decisionId, bool verified) 
        external onlyOwner validDecision(decisionId) {
        decisions[decisionId].verified = verified;
        emit DecisionVerified(decisionId, msg.sender, verified);
    }
}