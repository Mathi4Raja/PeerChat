# Requirements Document: Mesh Routing

## Introduction

This document specifies requirements for a message store-and-forward system with mesh routing capabilities for PeerChat, an offline-first disaster communication Flutter application. The system enables messages to travel through multiple devices to reach destinations beyond direct connectivity range, which is critical for disaster scenarios where people are spread out and traditional communication infrastructure is unavailable.

## Glossary

- **Mesh_Router**: The component responsible for routing messages through the peer-to-peer network
- **Message**: A data packet containing encrypted content, routing metadata, and delivery information
- **Hop**: A single transmission of a message from one peer to another peer
- **TTL**: Time-to-live value that decrements with each hop to prevent infinite routing loops
- **Route**: A sequence of peers through which a message travels from sender to recipient
- **Relay_Peer**: An intermediate peer that forwards messages not addressed to itself
- **Message_Queue**: Local storage for messages awaiting transmission to the next hop
- **Delivery_Acknowledgment**: A confirmation message that propagates back through the mesh to notify the sender
- **Route_Discovery**: The process of finding available paths through the mesh network
- **Message_ID**: A unique identifier for each message used for deduplication
- **End_to_End_Encryption**: Encryption where only the original sender and final recipient can decrypt message content
- **Peer_ID**: A unique identifier for each device in the mesh network

## Requirements

### Requirement 1: Multi-Hop Message Routing

**User Story:** As a user in a disaster zone, I want my messages to reach distant recipients through intermediate devices, so that I can communicate beyond my direct connectivity range.

#### Acceptance Criteria

1. WHEN a message destination is not directly reachable, THE Mesh_Router SHALL forward the message through intermediate peers
2. WHEN the Mesh_Router receives a message, THE Mesh_Router SHALL determine if it is the final destination or an intermediate hop
3. WHEN the Mesh_Router is an intermediate hop, THE Mesh_Router SHALL select the next peer in the route and forward the message
4. WHEN forwarding a message, THE Mesh_Router SHALL decrement the TTL value by one
5. WHEN the TTL value reaches zero, THE Mesh_Router SHALL discard the message and SHALL NOT forward it further

### Requirement 2: Route Discovery

**User Story:** As a user, I want the system to automatically find available paths through the network, so that my messages can reach their destination even when the network topology changes.

#### Acceptance Criteria

1. WHEN a message needs to be sent, THE Mesh_Router SHALL discover available routes to the destination peer
2. WHEN multiple routes exist to a destination, THE Mesh_Router SHALL select a route based on hop count and peer availability
3. WHEN no route is known to a destination, THE Mesh_Router SHALL initiate a route discovery process
4. WHEN a route discovery request is received, THE Mesh_Router SHALL respond if it has connectivity to the requested destination
5. WHEN route information becomes stale, THE Mesh_Router SHALL refresh route information through periodic discovery

### Requirement 3: Message Relay and Forwarding

**User Story:** As a device in the mesh network, I want to automatically relay messages for others, so that the community can maintain communication across the disaster area.

#### Acceptance Criteria

1. WHEN a message is received that is not addressed to the local peer, THE Mesh_Router SHALL act as a Relay_Peer
2. WHEN acting as a Relay_Peer, THE Mesh_Router SHALL forward the message toward its destination
3. WHEN forwarding a message, THE Mesh_Router SHALL preserve the original message content and sender information
4. WHEN the next hop peer is unavailable, THE Mesh_Router SHALL store the message in the Message_Queue
5. WHEN a queued message's next hop becomes available, THE Mesh_Router SHALL forward the message from the Message_Queue

### Requirement 4: Message Deduplication

**User Story:** As a user, I want the system to prevent duplicate message delivery, so that I don't receive the same message multiple times and network bandwidth is conserved.

#### Acceptance Criteria

1. WHEN a message is received, THE Mesh_Router SHALL check if the Message_ID has been seen before
2. WHEN a duplicate message is detected, THE Mesh_Router SHALL discard it and SHALL NOT forward it
3. WHEN a message is processed, THE Mesh_Router SHALL record the Message_ID in a deduplication cache
4. WHEN the deduplication cache exceeds a size limit, THE Mesh_Router SHALL remove the oldest entries
5. THE Mesh_Router SHALL maintain deduplication records for a minimum of 24 hours

### Requirement 5: TTL and Hop Limits

**User Story:** As a system administrator, I want messages to have hop limits, so that routing loops and infinite message propagation are prevented.

#### Acceptance Criteria

1. WHEN a message is created, THE Mesh_Router SHALL assign an initial TTL value between 8 and 16 hops
2. WHEN a message is forwarded, THE Mesh_Router SHALL decrement the TTL value by one
3. WHEN a message's TTL reaches zero, THE Mesh_Router SHALL discard the message
4. WHEN a message's TTL reaches zero, THE Mesh_Router SHALL NOT generate a delivery failure notification
5. THE Mesh_Router SHALL include the current TTL value in the message header

### Requirement 6: Delivery Acknowledgments

**User Story:** As a sender, I want to know when my message has been delivered, so that I can confirm communication was successful.

#### Acceptance Criteria

1. WHEN a message is successfully delivered to its final destination, THE Mesh_Router SHALL generate a Delivery_Acknowledgment
2. WHEN a Delivery_Acknowledgment is generated, THE Mesh_Router SHALL route it back to the original sender through the mesh
3. WHEN a Delivery_Acknowledgment is received by the sender, THE Mesh_Router SHALL notify the application layer
4. WHEN a Delivery_Acknowledgment is forwarded, THE Mesh_Router SHALL apply the same routing and TTL rules as regular messages
5. THE Delivery_Acknowledgment SHALL include the original Message_ID for correlation

### Requirement 7: Message Queue and Store-and-Forward

**User Story:** As a user, I want messages to be queued when the next hop is unavailable, so that communication continues when connectivity is intermittent.

#### Acceptance Criteria

1. WHEN the next hop peer is unavailable, THE Mesh_Router SHALL store the message in the Message_Queue
2. WHEN storing a message, THE Mesh_Router SHALL persist it to local storage using SQLite
3. WHEN a peer becomes available, THE Mesh_Router SHALL check the Message_Queue for pending messages to that peer
4. WHEN the Message_Queue exceeds storage limits, THE Mesh_Router SHALL discard the oldest messages first
5. WHEN a message has been queued for more than 48 hours, THE Mesh_Router SHALL discard it

### Requirement 8: End-to-End Encryption

**User Story:** As a user, I want my message content to remain private, so that only the intended recipient can read it even as it travels through intermediate devices.

#### Acceptance Criteria

1. WHEN a message is created, THE Mesh_Router SHALL encrypt the message content using the recipient's public key
2. WHEN a Relay_Peer forwards a message, THE Relay_Peer SHALL NOT be able to decrypt the message content
3. WHEN a message is received at its destination, THE Mesh_Router SHALL decrypt the content using the recipient's private key
4. THE Mesh_Router SHALL use libsodium (sodium package) for all cryptographic operations
5. THE Mesh_Router SHALL keep routing metadata unencrypted to enable forwarding decisions

### Requirement 9: Message Structure and Metadata

**User Story:** As a developer, I want messages to have a well-defined structure, so that routing, encryption, and delivery can be implemented reliably.

#### Acceptance Criteria

1. THE Mesh_Router SHALL include sender Peer_ID, recipient Peer_ID, and Message_ID in every message
2. THE Mesh_Router SHALL include TTL, hop count, and timestamp in message routing metadata
3. THE Mesh_Router SHALL include message type field to distinguish between data messages and acknowledgments
4. WHEN creating a Message_ID, THE Mesh_Router SHALL generate a unique identifier using cryptographically secure random values
5. THE Mesh_Router SHALL store message metadata separately from encrypted content

### Requirement 10: Routing Table Management

**User Story:** As a device in the mesh, I want to maintain current routing information, so that messages can be forwarded efficiently.

#### Acceptance Criteria

1. THE Mesh_Router SHALL maintain a routing table with known routes to peer destinations
2. WHEN a route is discovered, THE Mesh_Router SHALL store the route with next hop information and hop count
3. WHEN a route fails, THE Mesh_Router SHALL remove it from the routing table
4. WHEN the routing table is updated, THE Mesh_Router SHALL persist changes to SQLite storage
5. THE Mesh_Router SHALL expire routing table entries that have not been used for more than 30 minutes

### Requirement 11: Integration with Existing Peer Discovery

**User Story:** As a developer, I want mesh routing to integrate with existing mDNS peer discovery, so that the system works cohesively.

#### Acceptance Criteria

1. WHEN a new peer is discovered via mDNS, THE Mesh_Router SHALL add it as a potential next hop
2. WHEN a peer disconnects, THE Mesh_Router SHALL update routing tables to remove routes through that peer
3. THE Mesh_Router SHALL use the existing peer database for storing routing information
4. THE Mesh_Router SHALL use Provider state management for routing state updates
5. WHEN peer connectivity changes, THE Mesh_Router SHALL notify the routing layer within 5 seconds

### Requirement 12: Message Priority and Ordering

**User Story:** As a user, I want critical messages to be delivered first, so that urgent disaster communications are prioritized.

#### Acceptance Criteria

1. THE Mesh_Router SHALL support message priority levels: high, normal, and low
2. WHEN forwarding messages from the Message_Queue, THE Mesh_Router SHALL process higher priority messages first
3. WHEN multiple messages have the same priority, THE Mesh_Router SHALL process them in FIFO order
4. WHEN a high priority message is queued, THE Mesh_Router SHALL attempt immediate transmission
5. THE Mesh_Router SHALL include priority level in message metadata

### Requirement 13: Network Efficiency and Bandwidth Management

**User Story:** As a user on battery-powered devices with limited bandwidth, I want the system to use network resources efficiently, so that devices remain operational longer.

#### Acceptance Criteria

1. WHEN forwarding messages, THE Mesh_Router SHALL batch multiple messages to the same next hop when possible
2. WHEN the Message_Queue contains more than 10 messages for the same destination, THE Mesh_Router SHALL prioritize establishing a route
3. THE Mesh_Router SHALL limit the maximum message size to 64 kilobytes
4. WHEN a message exceeds size limits, THE Mesh_Router SHALL reject it at creation time
5. THE Mesh_Router SHALL implement exponential backoff for route discovery retries

### Requirement 14: Routing Metrics and Path Selection

**User Story:** As a system, I want to select optimal routes through the mesh, so that messages are delivered reliably and efficiently.

#### Acceptance Criteria

1. WHEN selecting a route, THE Mesh_Router SHALL prefer routes with fewer hops
2. WHEN multiple routes have equal hop counts, THE Mesh_Router SHALL prefer routes through peers with stronger signal strength
3. WHEN a route consistently fails, THE Mesh_Router SHALL decrease its preference score
4. THE Mesh_Router SHALL maintain success/failure statistics for each route
5. WHEN all known routes have failed, THE Mesh_Router SHALL initiate a new route discovery

### Requirement 15: Security and Attack Resistance

**User Story:** As a user in a disaster scenario, I want the mesh network to resist attacks and malicious behavior, so that communication remains trustworthy even with compromised devices in the network.

#### Acceptance Criteria

1. WHEN a message is received, THE Mesh_Router SHALL verify the sender's cryptographic signature using their public key
2. WHEN a message signature is invalid, THE Mesh_Router SHALL discard the message and SHALL NOT forward it
3. WHEN a peer repeatedly sends invalid messages, THE Mesh_Router SHALL temporarily block that peer for 10 minutes
4. WHEN creating a message, THE Mesh_Router SHALL sign the message using the sender's private key from libsodium
5. THE Mesh_Router SHALL include a timestamp in each message to enable replay attack detection
6. WHEN a message timestamp is older than 5 minutes or in the future, THE Mesh_Router SHALL discard it
7. WHEN route discovery responses are received, THE Mesh_Router SHALL verify they are signed by the responding peer
8. THE Mesh_Router SHALL limit the rate of route discovery requests to prevent network flooding
9. WHEN a peer advertises routes, THE Mesh_Router SHALL verify the peer has recent connectivity to claimed destinations
10. THE Mesh_Router SHALL use the existing identity keypair from secure storage for all signing operations

### Requirement 16: Error Handling and Resilience

**User Story:** As a user, I want the system to handle errors gracefully, so that communication continues even when problems occur.

#### Acceptance Criteria

1. WHEN a message forwarding fails, THE Mesh_Router SHALL retry with an alternative route if available
2. WHEN all routes fail, THE Mesh_Router SHALL queue the message for later retry
3. WHEN a malformed message is received, THE Mesh_Router SHALL discard it and log the error
4. WHEN storage operations fail, THE Mesh_Router SHALL notify the application layer
5. WHEN cryptographic operations fail, THE Mesh_Router SHALL discard the message and log the error

