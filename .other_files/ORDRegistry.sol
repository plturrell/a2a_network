// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./Pausable.sol";

/**
 * @title ORDRegistry
 * @dev Decentralized Object Resource Discovery registry on blockchain
 * Stores ORD documents, metadata, and enables discovery on-chain
 */
contract ORDRegistry is Pausable {
    
    struct ORDDocument {
        bytes32 documentId;
        address publisher;
        string title;
        string description;
        string documentURI; // IPFS hash or URI to full document
        bytes32[] capabilities;
        bytes32[] tags;
        uint256 version;
        uint256 publishedAt;
        uint256 updatedAt;
        bool active;
        uint256 reputation;
    }
    
    struct DublinCoreMetadata {
        string creator;
        string subject;
        string contributor;
        string publisher;
        string type_;
        string format;
        string identifier;
        string source;
        string language;
        string relation;
        string coverage;
        string rights;
    }
    
    // Storage mappings
    mapping(bytes32 => ORDDocument) public ordDocuments;
    mapping(bytes32 => DublinCoreMetadata) public dublinCoreMetadata;
    mapping(bytes32 => address[]) public capabilityToDocuments;
    mapping(bytes32 => address[]) public tagToDocuments;
    mapping(address => bytes32[]) public publisherDocuments;
    bytes32[] public allDocuments;
    
    // Events
    event ORDDocumentRegistered(
        bytes32 indexed documentId,
        address indexed publisher,
        string title,
        string documentURI
    );
    
    event ORDDocumentUpdated(
        bytes32 indexed documentId,
        address indexed publisher,
        uint256 version
    );
    
    event ORDDocumentDeactivated(bytes32 indexed documentId);
    
    modifier onlyPublisher(bytes32 documentId) {
        require(ordDocuments[documentId].publisher == msg.sender, "Not document publisher");
        _;
    }
    
    /**
     * @notice Register a new ORD document
     * @param title Document title
     * @param description Document description  
     * @param documentURI URI to full document (IPFS hash recommended)
     * @param capabilities Array of capability identifiers
     * @param tags Array of tag identifiers
     * @param dublinCore Dublin Core metadata
     */
    function registerORDDocument(
        string memory title,
        string memory description,
        string memory documentURI,
        bytes32[] memory capabilities,
        bytes32[] memory tags,
        DublinCoreMetadata memory dublinCore
    ) external whenNotPaused returns (bytes32) {
        require(bytes(title).length > 0, "Title required");
        require(bytes(documentURI).length > 0, "Document URI required");
        
        bytes32 documentId = keccak256(
            abi.encodePacked(msg.sender, title, block.timestamp)
        );
        
        ordDocuments[documentId] = ORDDocument({
            documentId: documentId,
            publisher: msg.sender,
            title: title,
            description: description,
            documentURI: documentURI,
            capabilities: capabilities,
            tags: tags,
            version: 1,
            publishedAt: block.timestamp,
            updatedAt: block.timestamp,
            active: true,
            reputation: 100
        });
        
        dublinCoreMetadata[documentId] = dublinCore;
        allDocuments.push(documentId);
        publisherDocuments[msg.sender].push(documentId);
        
        // Index by capabilities and tags
        for (uint i = 0; i < capabilities.length; i++) {
            capabilityToDocuments[capabilities[i]].push(msg.sender);
        }
        
        for (uint i = 0; i < tags.length; i++) {
            tagToDocuments[tags[i]].push(msg.sender);
        }
        
        emit ORDDocumentRegistered(documentId, msg.sender, title, documentURI);
        return documentId;
    }
    
    /**
     * @notice Update an existing ORD document
     * @param documentId Document to update
     * @param newDocumentURI New document URI
     * @param newDescription New description
     */
    function updateORDDocument(
        bytes32 documentId,
        string memory newDocumentURI,
        string memory newDescription
    ) external onlyPublisher(documentId) whenNotPaused {
        ORDDocument storage doc = ordDocuments[documentId];
        require(doc.active, "Document not active");
        
        doc.documentURI = newDocumentURI;
        doc.description = newDescription;
        doc.version++;
        doc.updatedAt = block.timestamp;
        
        emit ORDDocumentUpdated(documentId, msg.sender, doc.version);
    }
    
    /**
     * @notice Deactivate an ORD document
     * @param documentId Document to deactivate
     */
    function deactivateORDDocument(bytes32 documentId) 
        external onlyPublisher(documentId) whenNotPaused 
    {
        ordDocuments[documentId].active = false;
        emit ORDDocumentDeactivated(documentId);
    }
    
    /**
     * @notice Find ORD documents by capability
     * @param capability Capability identifier to search for
     * @return Array of publisher addresses with matching documents
     */
    function findDocumentsByCapability(bytes32 capability) 
        external view returns (address[] memory) 
    {
        return capabilityToDocuments[capability];
    }
    
    /**
     * @notice Find ORD documents by tag
     * @param tag Tag identifier to search for
     * @return Array of publisher addresses with matching documents
     */
    function findDocumentsByTag(bytes32 tag) 
        external view returns (address[] memory) 
    {
        return tagToDocuments[tag];
    }
    
    /**
     * @notice Get all documents by a publisher
     * @param publisher Publisher address
     * @return Array of document IDs
     */
    function getDocumentsByPublisher(address publisher) 
        external view returns (bytes32[] memory) 
    {
        return publisherDocuments[publisher];
    }
    
    /**
     * @notice Get ORD document details
     * @param documentId Document ID
     * @return ORD document struct
     */
    function getORDDocument(bytes32 documentId) 
        external view returns (ORDDocument memory) 
    {
        return ordDocuments[documentId];
    }
    
    /**
     * @notice Get Dublin Core metadata for document
     * @param documentId Document ID
     * @return Dublin Core metadata struct
     */
    function getDublinCoreMetadata(bytes32 documentId) 
        external view returns (DublinCoreMetadata memory) 
    {
        return dublinCoreMetadata[documentId];
    }
    
    /**
     * @notice Get all document IDs
     * @return Array of all document IDs
     */
    function getAllDocuments() external view returns (bytes32[] memory) {
        return allDocuments;
    }
    
    /**
     * @notice Get total number of documents
     * @return Count of documents
     */
    function getDocumentCount() external view returns (uint256) {
        return allDocuments.length;
    }
    
    /**
     * @notice Update document reputation (only pauser for now)
     * @param documentId Document to update
     * @param newReputation New reputation score
     */
    function updateDocumentReputation(bytes32 documentId, uint256 newReputation) 
        external onlyPauser 
    {
        ordDocuments[documentId].reputation = newReputation;
    }
}