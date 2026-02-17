# Implementation Plan: Mesh Routing

## Overview

This implementation plan breaks down the mesh routing system into incremental coding tasks. The approach follows a bottom-up strategy: build core data models and utilities first, then implement individual components, and finally wire everything together. Each task builds on previous work, with testing integrated throughout to catch issues early.

The implementation uses Dart/Flutter with the following key dependencies:
- **libsodium (sodium package)** for cryptographic operations
- **SQLite (sqflite)** for persistent storage
- **Provider** for state management
- **uuid** for unique identifier generation

## Tasks

- [x] 1. Set up project dependencies and database schema
  - Add required packages to `pubspec.yaml`: `sodium`, `sqflite`, `uuid`, `provider`
  - Create database migration script for new tables (message_queue, routes, deduplication_cache, blocked_peers, pending_acks)
  - Add indexes for performance optimization
  - Extend DBService to include schema migration
  - _Requirements: 7.2, 10.4, 4.3_

- [x] 2. Implement core data models
  - [x] 2.1 Create MeshMessage model with serialization
    - Implement MeshMessage class with all fields (messageId, type, senderPeerId, recipientPeerId, ttl, hopCount, priority, timestamp, encryptedContent, signature)
    - Implement `toBytes()` and `fromBytes()` for wire format serialization
    - Implement `toBytesForSigning()` for signature generation
    - Implement `copyForForwarding()` to create forwarded message with updated TTL/hopCount
    - _Requirements: 9.1, 9.2, 9.3, 9.5, 1.4_
  
  - [ ]* 2.2 Write property test for MeshMessage serialization round-trip
    - **Property 15: Encryption Round-Trip**
    - **Validates: Requirements 8.1, 8.3**
  
  - [ ]* 2.3 Write property test for message structure completeness
    - **Property 18: Message Structure Completeness**
    - **Validates: Requirements 9.1, 9.2, 9.3, 9.5, 12.5, 15.5**
  
  - [x] 2.4 Create Route model with scoring logic
    - Implement Route class with all fields
    - Implement `preferenceScore` calculation based on hop count, success rate, recency
    - Implement `isStale` check (30 minute threshold)
    - Implement `toMap()` and `fromMap()` for database persistence
    - _Requirements: 10.2, 14.1, 14.3_
  
  - [x] 2.5 Create QueuedMessage model
    - Implement QueuedMessage class with message, nextHopPeerId, timestamps, attemptCount
    - Implement `isExpired` check (48 hour threshold)
    - Implement `toMap()` and `fromMap()` for database persistence
    - _Requirements: 7.1, 7.5_
  
  - [x] 2.6 Create RouteRequest and RouteResponse models
    - Implement RouteRequest with serialization
    - Implement RouteResponse with serialization
    - Include signature fields for authentication
    - _Requirements: 2.3, 2.4, 15.7_

- [x] 3. Implement cryptographic operations
  - [x] 3.1 Create CryptoService for encryption and signing
    - Initialize libsodium (sodium package)
    - Implement message content encryption using `crypto_box` (X25519 + XSalsa20 + Poly1305)
    - Implement message content decryption
    - Implement message signing using `crypto_sign_detached` (Ed25519)
    - Implement signature verification
    - Generate and store Ed25519 signing keypair in FlutterSecureStorage (separate from encryption keypair)
    - _Requirements: 8.1, 8.3, 15.1, 15.4_
  
  - [ ]* 3.2 Write property test for encryption round-trip
    - **Property 15: Encryption Round-Trip**
    - **Validates: Requirements 8.1, 8.3**
  
  - [ ]* 3.3 Write property test for signature verification
    - **Property 35: Message Signing on Creation**
    - **Validates: Requirements 15.4**
  
  - [ ]* 3.4 Write property test for relay cannot decrypt
    - **Property 16: Relay Cannot Decrypt**
    - **Validates: Requirements 8.2**
  
  - [ ]* 3.5 Write property test for routing metadata unencrypted
    - **Property 17: Routing Metadata Unencrypted**
    - **Validates: Requirements 8.5**

- [x] 4. Implement DeduplicationCache component
  - [x] 4.1 Create DeduplicationCache class
    - Implement `hasSeen()` to check if message ID exists in cache
    - Implement `markSeen()` to record message ID with timestamp
    - Implement `evictOldest()` for LRU eviction when cache exceeds 10,000 entries
    - Implement `cleanup()` to remove entries older than 24 hours
    - Use SQLite deduplication_cache table for persistence
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_
  
  - [ ]* 4.2 Write property test for deduplication prevents reprocessing
    - **Property 7: Deduplication Prevents Reprocessing**
    - **Validates: Requirements 4.2**
  
  - [ ]* 4.3 Write property test for deduplication cache recording
    - **Property 8: Deduplication Cache Recording**
    - **Validates: Requirements 4.3**

- [x] 5. Implement SignatureVerifier component
  - [x] 5.1 Create SignatureVerifier class
    - Implement `verifyMessageSignature()` using CryptoService
    - Implement `verifyRouteSignature()` for route discovery messages
    - Implement `getPeerPublicKey()` from database
    - Implement `recordInvalidSignature()` to track malicious peers
    - Implement `isPeerBlocked()` to check blocked_peers table
    - Implement `unblockExpiredPeers()` to remove expired blocks
    - Block peers after 3 invalid signatures within 5 minutes for 10 minutes
    - _Requirements: 15.1, 15.2, 15.3, 15.7_
  
  - [ ]* 5.2 Write property test for signature verification on receipt
    - **Property 33: Signature Verification on Receipt**
    - **Validates: Requirements 15.1, 15.7**
  
  - [ ]* 5.3 Write property test for invalid signature discard
    - **Property 34: Invalid Signature Discard**
    - **Validates: Requirements 15.2**
  
  - [ ]* 5.4 Write property test for repeated invalid signature blocking
    - **Property 37: Repeated Invalid Signature Blocking**
    - **Validates: Requirements 15.3**

- [ ] 6. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Implement MessageQueue component
  - [x] 7.1 Create MessageQueue class
    - Implement `enqueue()` to add message to queue with SQLite persistence
    - Implement `getMessagesForPeer()` to retrieve messages for specific next hop
    - Implement `dequeue()` to remove message after successful transmission
    - Implement `getAllQueued()` sorted by priority (high > normal > low) then timestamp (FIFO)
    - Implement `removeExpired()` to delete messages older than 48 hours
    - Implement `getStats()` for queue monitoring
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 12.2, 12.3_
  
  - [ ]* 7.2 Write property test for queue persistence
    - **Property 13: Queue Persistence**
    - **Validates: Requirements 7.2**
  
  - [ ]* 7.3 Write property test for queue priority ordering
    - **Property 27: Queue Priority Ordering**
    - **Validates: Requirements 12.2**
  
  - [ ]* 7.4 Write property test for FIFO ordering within same priority
    - **Property 28: Same Priority FIFO Ordering**
    - **Validates: Requirements 12.3**
  
  - [ ]* 7.5 Write property test for age-based expiration
    - **Property 14: Queue Age-Based Expiration**
    - **Validates: Requirements 7.5**

- [x] 8. Implement RouteManager component
  - [x] 8.1 Create RouteManager class with routing table management
    - Implement `getNextHop()` to find next hop from routing table
    - Implement `addRoute()` to store route with persistence
    - Implement `removeRoutesThrough()` when peer disconnects
    - Implement `markRouteFailed()` to update failure count
    - Implement `expireStaleRoutes()` to remove routes unused for 30 minutes
    - Implement route selection algorithm using `calculateRouteScore()`
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 14.1, 14.2, 14.3_
  
  - [x] 8.2 Implement route discovery protocol
    - Implement `discoverRoute()` to initiate route discovery
    - Implement `handleRouteRequest()` to process incoming route requests
    - Implement `handleRouteResponse()` to process route responses
    - Broadcast route requests to all connected peers
    - Implement exponential backoff for retries (1s, 2s, 4s, 8s)
    - Verify signatures on route discovery messages
    - _Requirements: 2.1, 2.3, 2.4, 2.5, 13.5, 15.7_
  
  - [x] 8.3 Integrate with peer discovery service
    - Implement `onPeerConnected()` to add peer as potential next hop
    - Implement `onPeerDisconnected()` to remove routes through peer
    - Listen to DiscoveryService peer events
    - _Requirements: 11.1, 11.2, 11.5_
  
  - [ ]* 8.4 Write property test for route discovery initiation
    - **Property 20: Route Discovery Initiation**
    - **Validates: Requirements 2.1, 2.3**
  
  - [ ]* 8.5 Write property test for route storage completeness
    - **Property 21: Route Storage Completeness**
    - **Validates: Requirements 10.2**
  
  - [ ]* 8.6 Write property test for failed route removal
    - **Property 22: Failed Route Removal**
    - **Validates: Requirements 10.3**
  
  - [ ]* 8.7 Write property test for route table persistence
    - **Property 23: Route Table Persistence**
    - **Validates: Requirements 10.4**
  
  - [ ]* 8.8 Write property test for route expiration
    - **Property 24: Route Expiration**
    - **Validates: Requirements 2.5, 10.5**
  
  - [ ]* 8.9 Write property test for peer discovery integration
    - **Property 25: Peer Discovery Integration**
    - **Validates: Requirements 11.1**
  
  - [ ]* 8.10 Write property test for disconnected peer cleanup
    - **Property 26: Disconnected Peer Route Cleanup**
    - **Validates: Requirements 11.2**
  
  - [ ]* 8.11 Write property test for hop count preference
    - **Property 31: Route Selection Hop Count Preference**
    - **Validates: Requirements 14.1**
  
  - [ ]* 8.12 Write property test for route failure score decrease
    - **Property 32: Route Failure Score Decrease**
    - **Validates: Requirements 14.3**

- [x] 9. Implement DeliveryAckHandler component
  - [x] 9.1 Create DeliveryAckHandler class
    - Implement `createAcknowledgment()` to generate ack message for delivered message
    - Implement `handleAcknowledgment()` to process received acks
    - Implement `trackPendingAck()` to store pending acks in database
    - Implement `notifyDeliveryConfirmed()` to notify application layer via Provider
    - _Requirements: 6.1, 6.2, 6.3, 6.5_
  
  - [ ]* 9.2 Write property test for acknowledgment generation
    - **Property 10: Acknowledgment Generation**
    - **Validates: Requirements 6.1, 6.2**
  
  - [ ]* 9.3 Write property test for acknowledgment correlation
    - **Property 11: Acknowledgment Correlation**
    - **Validates: Requirements 6.5**
  
  - [ ]* 9.4 Write property test for acknowledgment routing rules
    - **Property 12: Acknowledgment Routing Rules**
    - **Validates: Requirements 6.4**

- [ ] 10. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 11. Implement MessageManager component
  - [x] 11.1 Create MessageManager class and message creation
    - Implement `createMessage()` to create new message with encryption and signing
    - Generate unique message ID using UUID v4
    - Set initial TTL between 8-16 hops randomly
    - Encrypt content with recipient's public key
    - Sign message with sender's private key
    - Validate message size limit (64 KB)
    - _Requirements: 1.1, 5.1, 8.1, 9.4, 13.3, 13.4, 15.4_
  
  - [x] 11.2 Implement message processing and validation
    - Implement `processMessage()` to handle incoming messages
    - Verify signature using SignatureVerifier
    - Check deduplication cache
    - Validate TTL and timestamp
    - Determine if local device is recipient or relay
    - Decrypt content if recipient
    - _Requirements: 1.2, 4.1, 5.3, 15.1, 15.6_
  
  - [x] 11.3 Implement message forwarding logic
    - Implement `forwardMessage()` to relay messages
    - Decrement TTL and increment hop count
    - Preserve original message content and metadata
    - Look up next hop from RouteManager
    - Queue message if next hop unavailable
    - _Requirements: 1.3, 1.4, 3.1, 3.2, 3.3, 3.4_
  
  - [x] 11.4 Implement message decryption
    - Implement `decryptContent()` for recipient
    - Use CryptoService for decryption
    - Handle decryption failures gracefully
    - _Requirements: 8.3, 16.5_
  
  - [ ]* 11.5 Write property test for TTL decrement invariant
    - **Property 1: TTL Decrement Invariant**
    - **Validates: Requirements 1.4, 5.2**
  
  - [ ]* 11.6 Write property test for TTL zero termination
    - **Property 2: TTL Zero Termination**
    - **Validates: Requirements 1.5, 5.3**
  
  - [ ]* 11.7 Write property test for message content preservation
    - **Property 3: Message Content Preservation**
    - **Validates: Requirements 3.3**
  
  - [ ]* 11.8 Write property test for destination detection
    - **Property 4: Destination Detection**
    - **Validates: Requirements 1.2**
  
  - [ ]* 11.9 Write property test for queue on unavailable next hop
    - **Property 5: Queue on Unavailable Next Hop**
    - **Validates: Requirements 3.4, 7.1**
  
  - [ ]* 11.10 Write property test for initial TTL range
    - **Property 9: Initial TTL Range**
    - **Validates: Requirements 5.1**
  
  - [ ]* 11.11 Write property test for message ID uniqueness
    - **Property 19: Message ID Uniqueness**
    - **Validates: Requirements 9.4**
  
  - [ ]* 11.12 Write property test for message size limit
    - **Property 29: Message Size Limit**
    - **Validates: Requirements 13.3**
  
  - [ ]* 11.13 Write property test for oversized message rejection
    - **Property 30: Oversized Message Rejection**
    - **Validates: Requirements 13.4**
  
  - [ ]* 11.14 Write property test for timestamp validity check
    - **Property 36: Timestamp Validity Check**
    - **Validates: Requirements 15.6**

- [x] 12. Implement MeshRouterService (main coordinator)
  - [x] 12.1 Create MeshRouterService class and initialization
    - Initialize all component dependencies (MessageManager, RouteManager, MessageQueue, etc.)
    - Implement `init()` to start service and listen to peer discovery
    - Implement `sendMessage()` as main entry point for sending
    - Implement `receiveMessage()` as main entry point for receiving
    - Implement peer connectivity event handlers
    - Expose routing statistics and queue status
    - Integrate with Provider for state management
    - _Requirements: 1.1, 11.3, 11.4, 11.5_
  
  - [x] 12.2 Implement comprehensive error handling
    - Handle message validation errors (discard and log)
    - Handle routing errors (queue and retry)
    - Handle storage errors (notify application layer)
    - Handle cryptographic errors (discard and log)
    - Implement retry logic with alternative routes
    - _Requirements: 16.1, 16.2, 16.3, 16.4, 16.5_
  
  - [ ]* 12.3 Write property test for alternative route retry
    - **Property 38: Alternative Route Retry**
    - **Validates: Requirements 16.1**
  
  - [ ]* 12.4 Write property test for all routes failed queueing
    - **Property 39: All Routes Failed Queueing**
    - **Validates: Requirements 16.2**
  
  - [ ]* 12.5 Write property test for malformed message discard
    - **Property 40: Malformed Message Discard**
    - **Validates: Requirements 16.3**

- [x] 13. Implement background tasks and maintenance
  - [x] 13.1 Create periodic maintenance tasks
    - Implement periodic route expiration (every 5 minutes)
    - Implement periodic queue cleanup (every 10 minutes)
    - Implement periodic deduplication cache cleanup (every hour)
    - Implement periodic peer unblocking (every minute)
    - Use Dart Timer for scheduling
    - _Requirements: 2.5, 4.4, 7.5, 10.5, 15.3_
  
  - [x] 13.2 Implement queue processing on peer availability
    - Listen to peer connected events
    - Check message queue for pending messages to newly connected peer
    - Attempt to send queued messages
    - _Requirements: 3.5, 7.3_
  
  - [ ]* 13.3 Write property test for queue processing on peer available
    - **Property 6: Queue Processing on Peer Available**
    - **Validates: Requirements 3.5, 7.3**

- [ ] 14. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 15. Integration and wiring
  - [x] 15.1 Integrate MeshRouterService with AppState
    - Add MeshRouterService to AppState Provider
    - Initialize service on app startup
    - Wire up peer discovery events
    - Wire up transport layer for message transmission/reception
    - _Requirements: 11.3, 11.4_
  
  - [x] 15.2 Create transport layer integration
    - Implement message transmission over Bluetooth
    - Implement message transmission over WiFi Direct
    - Implement message reception from transport layer
    - Handle transport errors and retries
    - _Requirements: 1.1, 3.1, 3.2_
  
  - [x] 15.3 Update UI to show mesh routing status
    - Display routing statistics (active routes, queue size)
    - Show delivery acknowledgments in chat UI
    - Indicate when messages are being routed through mesh
    - Show message delivery status (queued, sent, delivered)
    - _Requirements: 6.3_
  
  - [ ]* 15.4 Write integration tests for end-to-end flows
    - Test end-to-end message flow (send → route → deliver → ack)
    - Test multi-hop routing (A → B → C)
    - Test route discovery and failover
    - Test store-and-forward with intermittent connectivity
    - _Requirements: 1.1, 2.1, 3.1, 7.1_

- [ ] 16. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at key milestones
- Property tests validate universal correctness properties (minimum 100 iterations each)
- Unit tests validate specific examples, edge cases, and error conditions
- Integration tests validate end-to-end flows across components
- All cryptographic operations use libsodium (sodium package)
- All persistence uses SQLite (sqflite package)
- State management uses Provider pattern
- Message size limit is 64 KB to conserve bandwidth
- TTL range is 8-16 hops to balance reachability and network load
- The implementation follows a bottom-up approach: data models → components → integration
- Each component is tested independently before integration
- All 40 correctness properties from the design document are mapped to property test tasks
