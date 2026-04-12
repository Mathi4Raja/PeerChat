# Design Document: Mesh Routing

## Overview

This design specifies a message store-and-forward system with mesh routing capabilities for PeerChat. The system enables multi-hop message delivery through intermediate peers, allowing communication beyond direct connectivity range in disaster scenarios where traditional infrastructure is unavailable.

The design integrates with the existing Flutter application architecture, leveraging:
- **libsodium (sodium package)** for cryptographic operations (signing, encryption)
- **SQLite (sqflite)** for persistent storage of messages, routes, and deduplication cache
- **Provider** for state management and UI updates
- **Existing mDNS peer discovery** for direct peer connectivity detection
- **Existing identity keypairs** stored in FlutterSecureStorage

The mesh routing system operates at the application layer, sitting between the peer discovery layer and the application messaging layer. It provides transparent multi-hop routing while maintaining end-to-end encryption and message authentication.

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                        │
│                  (Chat UI, Message Display)                  │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                   Mesh Router Service                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Message    │  │    Route     │  │   Message    │     │
│  │   Manager    │  │   Manager    │  │    Queue     │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ Deduplication│  │  Signature   │  │   Delivery   │     │
│  │    Cache     │  │  Verifier    │  │     Ack      │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                  Transport Layer                             │
│         (Peer Discovery, Direct Connections)                 │
│              (mDNS, Bluetooth, WiFi Direct)                  │
└─────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

**Message Manager**
- Creates outgoing messages with proper structure and encryption
- Processes incoming messages (decrypt, verify, route)
- Determines if device is final destination or relay
- Coordinates with Route Manager for next hop selection

**Route Manager**
- Maintains routing table with known routes to destinations
- Performs route discovery when no route exists
- Selects optimal routes based on hop count and reliability
- Updates routes based on peer connectivity changes
- Expires stale routing information

**Message Queue**
- Stores messages awaiting transmission (store-and-forward)
- Persists queue to SQLite for durability
- Prioritizes messages by priority level and age
- Manages queue size limits and message expiration
- Triggers transmission when next hop becomes available

**Deduplication Cache**
- Tracks seen message IDs to prevent duplicate processing
- Implements LRU eviction when cache size limit reached
- Persists cache to SQLite for cross-session deduplication
- Maintains entries for minimum 24 hours

**Signature Verifier**
- Verifies message signatures using sender's public key
- Validates route advertisements and acknowledgments
- Detects and blocks peers sending invalid signatures
- Uses libsodium for all cryptographic verification

**Delivery Acknowledgment Handler**
- Generates acknowledgments when messages reach destination
- Routes acknowledgments back to original sender
- Correlates acknowledgments with sent messages
- Notifies application layer of successful delivery

### Integration Points

**With Existing Peer Discovery (DiscoveryService)**
- Listens to `onPeerFound` stream to detect new direct peers
- Updates routing table when peers appear/disappear
- Uses peer connectivity as basis for route selection
- Maintains peer reachability status

**With Existing Database (DBService)**
- Extends database schema with new tables for routing
- Reuses existing peer table for peer information
- Stores messages, routes, and deduplication cache
- Leverages existing SQLite connection

**With Existing State Management (AppState)**
- Integrates MeshRouterService into AppState
- Notifies UI of message delivery status via Provider
- Exposes routing statistics and queue status
- Uses existing identity keypair for signing/encryption

## Components and Interfaces

### MeshRouterService

Primary service class that coordinates all mesh routing operations.

```dart
class MeshRouterService extends ChangeNotifier {
  final Sodium _sodium;
  final KeyPair _identityKeyPair;
  final DBService _db;
  final DiscoveryService _discovery;
  
  final MessageManager _messageManager;
  final RouteManager _routeManager;
  final MessageQueue _messageQueue;
  final DeduplicationCache _deduplicationCache;
  final SignatureVerifier _signatureVerifier;
  final DeliveryAckHandler _deliveryAckHandler;
  
  // Initialize service and start listening to peer discovery
  Future<void> init();
  
  // Send a message to a destination peer
  Future<SendResult> sendMessage({
    required String recipientPeerId,
    required String content,
    MessagePriority priority = MessagePriority.normal,
  });
  
  // Process an incoming message from transport layer
  Future<void> receiveMessage(Uint8List rawMessage, String fromPeerAddress);
  
  // Handle peer connectivity changes from discovery service
  void _onPeerConnected(Peer peer);
  void _onPeerDisconnected(String peerId);
  
  // Expose routing statistics
  RoutingStats get stats;
  
  // Expose message queue status
  QueueStatus get queueStatus;
}

enum SendResult {
  queued,        // Message queued for delivery
  routeFound,    // Route found and message sent to next hop
  noRoute,       // No route available, queued for later
  failed,        // Send failed (validation, encryption, etc.)
}
```

### MessageManager

Handles message creation, encryption, decryption, and routing decisions.

```dart
class MessageManager {
  final Sodium _sodium;
  final KeyPair _identityKeyPair;
  final RouteManager _routeManager;
  final MessageQueue _messageQueue;
  final DeduplicationCache _deduplicationCache;
  final SignatureVerifier _signatureVerifier;
  
  // Create and encrypt a new message
  Future<MeshMessage> createMessage({
    required String recipientPeerId,
    required Uint8List recipientPublicKey,
    required String content,
    required MessagePriority priority,
  });
  
  // Process incoming message (verify, decrypt if destination, or forward)
  Future<ProcessResult> processMessage(MeshMessage message, String fromPeerAddress);
  
  // Forward message to next hop
  Future<bool> forwardMessage(MeshMessage message);
  
  // Decrypt message content (only if we are the recipient)
  Future<String?> decryptContent(MeshMessage message);
}

enum ProcessResult {
  delivered,      // Message delivered to local user
  forwarded,      // Message forwarded to next hop
  queued,         // Message queued (next hop unavailable)
  duplicate,      // Duplicate message discarded
  expired,        // TTL expired, discarded
  invalid,        // Invalid signature or format
}
```

### RouteManager

Manages routing table and performs route discovery.

```dart
class RouteManager {
  final DBService _db;
  final DiscoveryService _discovery;
  final SignatureVerifier _signatureVerifier;
  
  // Find next hop for a destination
  Future<String?> getNextHop(String destinationPeerId);
  
  // Initiate route discovery for a destination
  Future<bool> discoverRoute(String destinationPeerId);
  
  // Update routing table when peer connectivity changes
  Future<void> onPeerConnected(Peer peer);
  Future<void> onPeerDisconnected(String peerId);
  
  // Add or update a route
  Future<void> addRoute(Route route);
  
  // Remove routes through a specific peer
  Future<void> removeRoutesThrough(String peerId);
  
  // Mark route as failed
  Future<void> markRouteFailed(String destinationPeerId, String nextHop);
  
  // Expire stale routes (called periodically)
  Future<void> expireStaleRoutes();
  
  // Process route discovery request
  Future<void> handleRouteRequest(RouteRequest request, String fromPeerAddress);
  
  // Process route discovery response
  Future<void> handleRouteResponse(RouteResponse response);
}
```

### MessageQueue

Manages store-and-forward queue with persistence.

```dart
class MessageQueue {
  final DBService _db;
  
  // Add message to queue
  Future<void> enqueue(QueuedMessage message);
  
  // Get messages ready for transmission to a specific peer
  Future<List<QueuedMessage>> getMessagesForPeer(String peerId);
  
  // Remove message from queue after successful transmission
  Future<void> dequeue(String messageId);
  
  // Get all queued messages sorted by priority and timestamp
  Future<List<QueuedMessage>> getAllQueued();
  
  // Remove expired messages (older than 48 hours)
  Future<void> removeExpired();
  
  // Get queue statistics
  Future<QueueStats> getStats();
}
```

### DeduplicationCache

Tracks seen message IDs to prevent duplicate processing.

```dart
class DeduplicationCache {
  final DBService _db;
  static const int maxCacheSize = 10000;
  static const Duration minRetention = Duration(hours: 24);
  
  // Check if message ID has been seen
  Future<bool> hasSeen(String messageId);
  
  // Mark message ID as seen
  Future<void> markSeen(String messageId);
  
  // Remove oldest entries when cache exceeds size limit
  Future<void> evictOldest();
  
  // Remove entries older than minimum retention period
  Future<void> cleanup();
}
```

### SignatureVerifier

Verifies cryptographic signatures on messages and routing control packets.

```dart
class SignatureVerifier {
  final Sodium _sodium;
  final DBService _db;
  
  // Verify message signature
  Future<bool> verifyMessageSignature(MeshMessage message);
  
  // Verify route advertisement signature
  Future<bool> verifyRouteSignature(RouteResponse response);
  
  // Get public key for a peer ID
  Future<Uint8List?> getPeerPublicKey(String peerId);
  
  // Track invalid signature attempts
  Future<void> recordInvalidSignature(String peerId);
  
  // Check if peer is temporarily blocked
  Future<bool> isPeerBlocked(String peerId);
  
  // Unblock peers after timeout
  Future<void> unblockExpiredPeers();
}
```

### DeliveryAckHandler

Manages delivery acknowledgments.

```dart
class DeliveryAckHandler {
  final MessageManager _messageManager;
  final DBService _db;
  
  // Generate acknowledgment for delivered message
  Future<MeshMessage> createAcknowledgment(MeshMessage originalMessage);
  
  // Process received acknowledgment
  Future<void> handleAcknowledgment(MeshMessage ackMessage);
  
  // Track pending acknowledgments
  Future<void> trackPendingAck(String messageId, String recipientPeerId);
  
  // Notify application layer of delivery confirmation
  void notifyDeliveryConfirmed(String messageId);
}
```

## Data Models

### MeshMessage

Core message structure for all mesh communications.

```dart
class MeshMessage {
  // Unique message identifier (UUID v4)
  final String messageId;
  
  // Message type
  final MessageType type;
  
  // Sender's peer ID (public key fingerprint)
  final String senderPeerId;
  
  // Recipient's peer ID
  final String recipientPeerId;
  
  // Time-to-live (decrements with each hop)
  final int ttl;
  
  // Current hop count (increments with each hop)
  final int hopCount;
  
  // Message priority
  final MessagePriority priority;
  
  // Timestamp (milliseconds since epoch)
  final int timestamp;
  
  // Encrypted message content (only for data messages)
  // Encrypted with recipient's public key using libsodium crypto_box
  final Uint8List? encryptedContent;
  
  // Cryptographic signature of message
  // Signature covers: messageId, type, senderPeerId, recipientPeerId, 
  // ttl, hopCount, priority, timestamp, encryptedContent
  final Uint8List signature;
  
  // Serialize to bytes for transmission
  Uint8List toBytes();
  
  // Deserialize from bytes
  static MeshMessage fromBytes(Uint8List bytes);
  
  // Create a copy with updated TTL and hop count (for forwarding)
  MeshMessage copyForForwarding();
}

enum MessageType {
  data,              // Regular user message
  acknowledgment,    // Delivery acknowledgment
  routeRequest,      // Route discovery request
  routeResponse,     // Route discovery response
}

enum MessagePriority {
  high,    // Critical disaster communications
  normal,  // Regular messages
  low,     // Non-urgent messages
}
```

### Route

Routing table entry.

```dart
class Route {
  // Destination peer ID
  final String destinationPeerId;
  
  // Next hop peer ID (directly connected peer)
  final String nextHopPeerId;
  
  // Number of hops to destination
  final int hopCount;
  
  // Last time this route was used successfully
  final int lastUsedTimestamp;
  
  // Last time this route was updated
  final int lastUpdatedTimestamp;
  
  // Success count for this route
  final int successCount;
  
  // Failure count for this route
  final int failureCount;
  
  // Calculate route preference score
  double get preferenceScore;
  
  // Check if route is stale (not used in 30 minutes)
  bool get isStale;
  
  // Serialize for database storage
  Map<String, Object?> toMap();
  
  // Deserialize from database
  static Route fromMap(Map<String, Object?> map);
}
```

### QueuedMessage

Message waiting in store-and-forward queue.

```dart
class QueuedMessage {
  // The mesh message to be sent
  final MeshMessage message;
  
  // Next hop peer ID
  final String nextHopPeerId;
  
  // Time message was queued
  final int queuedTimestamp;
  
  // Number of transmission attempts
  final int attemptCount;
  
  // Last attempt timestamp
  final int? lastAttemptTimestamp;
  
  // Check if message has expired (queued > 48 hours)
  bool get isExpired;
  
  // Serialize for database storage
  Map<String, Object?> toMap();
  
  // Deserialize from database
  static QueuedMessage fromMap(Map<String, Object?> map);
}
```

### RouteRequest

Route discovery request message.

```dart
class RouteRequest {
  // Request ID (UUID v4)
  final String requestId;
  
  // Peer ID requesting the route
  final String requestorPeerId;
  
  // Destination peer ID being sought
  final String targetPeerId;
  
  // TTL for route request propagation
  final int ttl;
  
  // Timestamp
  final int timestamp;
  
  // Signature by requestor
  final Uint8List signature;
  
  // Serialize to bytes
  Uint8List toBytes();
  
  // Deserialize from bytes
  static RouteRequest fromBytes(Uint8List bytes);
}
```

### RouteResponse

Route discovery response message.

```dart
class RouteResponse {
  // Original request ID
  final String requestId;
  
  // Peer ID responding (has route to target)
  final String responderPeerId;
  
  // Target peer ID
  final String targetPeerId;
  
  // Hop count to target from responder
  final int hopCount;
  
  // Timestamp
  final int timestamp;
  
  // Signature by responder
  final Uint8List signature;
  
  // Serialize to bytes
  Uint8List toBytes();
  
  // Deserialize from bytes
  static RouteResponse fromBytes(Uint8List bytes);
}
```

### Database Schema Extensions

Extend existing SQLite database with new tables:

```sql
-- Messages in store-and-forward queue
CREATE TABLE message_queue (
  message_id TEXT PRIMARY KEY,
  next_hop_peer_id TEXT NOT NULL,
  message_data BLOB NOT NULL,
  priority INTEGER NOT NULL,
  queued_timestamp INTEGER NOT NULL,
  attempt_count INTEGER DEFAULT 0,
  last_attempt_timestamp INTEGER
);

-- Routing table
CREATE TABLE routes (
  destination_peer_id TEXT PRIMARY KEY,
  next_hop_peer_id TEXT NOT NULL,
  hop_count INTEGER NOT NULL,
  last_used_timestamp INTEGER NOT NULL,
  last_updated_timestamp INTEGER NOT NULL,
  success_count INTEGER DEFAULT 0,
  failure_count INTEGER DEFAULT 0
);

-- Deduplication cache
CREATE TABLE deduplication_cache (
  message_id TEXT PRIMARY KEY,
  seen_timestamp INTEGER NOT NULL
);

-- Blocked peers (temporary blocks for invalid signatures)
CREATE TABLE blocked_peers (
  peer_id TEXT PRIMARY KEY,
  blocked_until_timestamp INTEGER NOT NULL,
  invalid_signature_count INTEGER NOT NULL
);

-- Pending acknowledgments
CREATE TABLE pending_acks (
  message_id TEXT PRIMARY KEY,
  recipient_peer_id TEXT NOT NULL,
  sent_timestamp INTEGER NOT NULL
);

-- Create indexes for performance
CREATE INDEX idx_queue_next_hop ON message_queue(next_hop_peer_id);
CREATE INDEX idx_queue_priority ON message_queue(priority DESC, queued_timestamp ASC);
CREATE INDEX idx_routes_next_hop ON routes(next_hop_peer_id);
CREATE INDEX idx_dedup_timestamp ON deduplication_cache(seen_timestamp);
```


## Message Flow

### Sending a Message

1. **Application Layer** calls `MeshRouterService.sendMessage()`
2. **MessageManager** creates `MeshMessage`:
   - Generates unique message ID (UUID v4)
   - Sets initial TTL (8-16 hops)
   - Encrypts content with recipient's public key using `crypto_box`
   - Signs message with sender's private key using `crypto_sign_detached`
3. **RouteManager** looks up next hop for destination
4. **If route exists**:
   - **MessageManager** forwards message to next hop peer
   - Returns `SendResult.routeFound`
5. **If no route exists**:
   - **RouteManager** initiates route discovery
   - **MessageQueue** stores message for later delivery
   - Returns `SendResult.queued`

### Receiving a Message

1. **Transport Layer** receives raw bytes from peer
2. **MeshRouterService** calls `receiveMessage()`
3. **MessageManager** deserializes bytes to `MeshMessage`
4. **SignatureVerifier** validates message signature
   - If invalid: discard message, record invalid signature attempt
5. **DeduplicationCache** checks if message ID seen before
   - If duplicate: discard message
   - If new: mark as seen
6. **MessageManager** checks TTL
   - If TTL = 0: discard message
7. **MessageManager** checks if local device is recipient
8. **If local device is recipient**:
   - Decrypt content with local private key
   - Deliver to application layer
   - **DeliveryAckHandler** generates acknowledgment
   - Route acknowledgment back to sender
9. **If local device is relay**:
   - Decrement TTL, increment hop count
   - **RouteManager** looks up next hop
   - **MessageManager** forwards to next hop (or queue if unavailable)

### Route Discovery

1. **RouteManager** creates `RouteRequest` for destination
2. Broadcast request to all directly connected peers
3. **Each peer receiving request**:
   - Checks if it's the target destination
   - If yes: sends `RouteResponse` back to requestor
   - If no and TTL > 0: forwards request to its peers
4. **Requestor receives RouteResponse**:
   - **SignatureVerifier** validates response signature
   - **RouteManager** adds route to routing table
   - **MessageQueue** checks for pending messages to that destination
   - Sends queued messages using new route

### Delivery Acknowledgment Flow

1. **Recipient** receives message successfully
2. **DeliveryAckHandler** creates acknowledgment message:
   - Type: `MessageType.acknowledgment`
   - Sender: original recipient
   - Recipient: original sender
   - Contains original message ID
3. **Acknowledgment routed back** through mesh (same routing as data messages)
4. **Original sender receives acknowledgment**:
   - **DeliveryAckHandler** correlates with sent message
   - Notifies application layer via Provider
   - Removes from pending acknowledgments

## Cryptographic Operations

### Message Encryption (End-to-End)

Uses libsodium's `crypto_box` (X25519 + XSalsa20 + Poly1305):

```dart
// Encrypt message content
Uint8List encryptContent(String content, Uint8List recipientPublicKey, KeyPair senderKeyPair) {
  final contentBytes = Uint8List.fromList(utf8.encode(content));
  final nonce = _sodium.randombytes.buf(24); // 24-byte nonce
  final ciphertext = _sodium.cryptoBox.easy(
    message: contentBytes,
    nonce: nonce,
    publicKey: recipientPublicKey,
    secretKey: senderKeyPair.secretKey,
  );
  // Prepend nonce to ciphertext for transmission
  return Uint8List.fromList([...nonce, ...ciphertext]);
}

// Decrypt message content
String decryptContent(Uint8List encryptedData, Uint8List senderPublicKey, KeyPair recipientKeyPair) {
  final nonce = encryptedData.sublist(0, 24);
  final ciphertext = encryptedData.sublist(24);
  final plaintext = _sodium.cryptoBox.openEasy(
    ciphertext: ciphertext,
    nonce: nonce,
    publicKey: senderPublicKey,
    secretKey: recipientKeyPair.secretKey,
  );
  return utf8.decode(plaintext);
}
```

### Message Signing (Authentication)

Uses libsodium's `crypto_sign_detached` (Ed25519):

```dart
// Sign message
Uint8List signMessage(MeshMessage message, KeyPair signingKeyPair) {
  final messageBytes = message.toBytesForSigning();
  return _sodium.cryptoSign.detached(
    message: messageBytes,
    secretKey: signingKeyPair.secretKey,
  );
}

// Verify signature
bool verifySignature(MeshMessage message, Uint8List signature, Uint8List senderPublicKey) {
  final messageBytes = message.toBytesForSigning();
  return _sodium.cryptoSign.verifyDetached(
    signature: signature,
    message: messageBytes,
    publicKey: senderPublicKey,
  );
}
```

**Note**: The existing keypair in AppState uses `crypto_box` keypairs (X25519). For signing, we need Ed25519 keypairs. We have two options:

1. **Generate separate signing keypair**: Store additional Ed25519 keypair for signatures
2. **Convert X25519 to Ed25519**: Use libsodium's conversion functions

For simplicity and security, we'll generate a separate Ed25519 signing keypair and store it alongside the encryption keypair in FlutterSecureStorage.

### Peer ID Format

Peer ID is the Base64-encoded Ed25519 public key (signing key), which serves as the unique identifier for each device in the mesh network.

## Route Selection Algorithm

When multiple routes exist to a destination, select based on:

1. **Hop Count** (primary): Prefer routes with fewer hops
2. **Success Rate**: Prefer routes with higher success/failure ratio
3. **Recency**: Prefer recently used routes
4. **Signal Strength**: Prefer routes through peers with stronger connectivity (from discovery service)

```dart
double calculateRouteScore(Route route, Peer nextHopPeer) {
  // Hop count penalty (exponential)
  final hopPenalty = pow(1.5, route.hopCount);
  
  // Success rate bonus
  final totalAttempts = route.successCount + route.failureCount;
  final successRate = totalAttempts > 0 ? route.successCount / totalAttempts : 0.5;
  
  // Recency bonus (routes used in last 5 minutes get bonus)
  final age = DateTime.now().millisecondsSinceEpoch - route.lastUsedTimestamp;
  final recencyBonus = age < 300000 ? 1.2 : 1.0;
  
  // Signal strength bonus (if available from peer)
  final signalBonus = 1.0; // TODO: integrate with peer signal strength when available
  
  return (successRate * recencyBonus * signalBonus) / hopPenalty;
}
```

## Error Handling

### Message Validation Errors

- **Invalid signature**: Discard message, increment invalid signature counter for peer
- **Malformed message**: Discard message, log error
- **Expired timestamp**: Discard message (replay attack prevention)
- **TTL exceeded**: Discard message (normal termination)

### Routing Errors

- **No route available**: Queue message, initiate route discovery
- **Next hop unavailable**: Queue message, wait for peer to reconnect
- **Route discovery timeout**: Retry with exponential backoff (1s, 2s, 4s, 8s, max 8s)
- **All routes failed**: Keep message queued, retry route discovery periodically

### Storage Errors

- **Database write failure**: Log error, notify application layer, retry operation
- **Queue full**: Discard oldest low-priority messages to make space
- **Disk space exhausted**: Notify user, stop accepting new messages until space available

### Cryptographic Errors

- **Decryption failure**: Discard message, log error (wrong recipient or corrupted)
- **Key not found**: Cannot send message, notify application layer
- **Signature generation failure**: Cannot send message, log error

### Peer Blocking

When a peer sends 3 invalid signatures within 5 minutes:
- Block peer for 10 minutes
- Discard all messages from blocked peer
- Remove routes through blocked peer
- After timeout, unblock and allow normal operation

## Testing Strategy

The mesh routing system will be validated through both unit tests and property-based tests to ensure correctness across all scenarios.

### Unit Testing Approach

Unit tests will focus on:
- **Specific examples**: Concrete scenarios like "message with TTL=1 forwarded once then discarded"
- **Edge cases**: Empty queues, single-peer networks, maximum TTL values
- **Error conditions**: Invalid signatures, malformed messages, storage failures
- **Integration points**: Interaction with discovery service, database, state management

### Property-Based Testing Approach

Property-based tests will validate universal correctness properties using a Dart property-based testing library. Each test will run a minimum of 100 iterations with randomized inputs.

**Recommended Library**: Use `test` package with custom property-based testing helpers, or integrate `dart_check` if available.

**Test Configuration**:
- Minimum 100 iterations per property test
- Each test tagged with: `Feature: mesh-routing, Property {N}: {property_text}`
- Tests reference design document property numbers

**Generator Strategy**:
- Generate random peer IDs, message content, TTL values
- Generate random network topologies (peer connectivity graphs)
- Generate random message sequences with varying priorities
- Generate edge cases: empty content, maximum sizes, boundary TTL values


## Correctness Properties

A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.

### Property 1: TTL Decrement Invariant

*For any* message being forwarded through a relay peer, the TTL value in the forwarded message should be exactly one less than the TTL value in the received message.

**Validates: Requirements 1.4, 5.2**

### Property 2: TTL Zero Termination

*For any* message with TTL equal to zero, the message should be discarded and not forwarded to any peer.

**Validates: Requirements 1.5, 5.3**

### Property 3: Message Content Preservation

*For any* message being forwarded through relay peers, the encrypted content, sender peer ID, recipient peer ID, and message ID should remain unchanged from the original message.

**Validates: Requirements 3.3**

### Property 4: Destination Detection

*For any* received message and local peer ID, the router should correctly identify whether the local peer is the final destination (recipient peer ID matches local peer ID) or an intermediate relay.

**Validates: Requirements 1.2**

### Property 5: Queue on Unavailable Next Hop

*For any* message where the next hop peer is not currently connected, the message should be stored in the message queue rather than being discarded.

**Validates: Requirements 3.4, 7.1**

### Property 6: Queue Processing on Peer Available

*For any* queued message, when its designated next hop peer becomes available, the message should be dequeued and forwarded within a reasonable time period.

**Validates: Requirements 3.5, 7.3**

### Property 7: Deduplication Prevents Reprocessing

*For any* message ID that has already been processed, receiving a message with the same message ID should result in the message being discarded without forwarding or delivery.

**Validates: Requirements 4.2**

### Property 8: Deduplication Cache Recording

*For any* message that is successfully processed (delivered or forwarded), the message ID should be recorded in the deduplication cache.

**Validates: Requirements 4.3**

### Property 9: Initial TTL Range

*For any* newly created message, the initial TTL value should be between 8 and 16 hops (inclusive).

**Validates: Requirements 5.1**

### Property 10: Acknowledgment Generation

*For any* message successfully delivered to its final destination, a delivery acknowledgment message should be generated and routed back toward the original sender.

**Validates: Requirements 6.1, 6.2**

### Property 11: Acknowledgment Correlation

*For any* delivery acknowledgment message, it should contain the message ID of the original message it acknowledges, enabling correlation at the sender.

**Validates: Requirements 6.5**

### Property 12: Acknowledgment Routing Rules

*For any* delivery acknowledgment message being forwarded, the same TTL decrement and routing rules should apply as for regular data messages.

**Validates: Requirements 6.4**

### Property 13: Queue Persistence

*For any* message added to the message queue, the message should be persisted to SQLite storage before the enqueue operation completes.

**Validates: Requirements 7.2**

### Property 14: Queue Age-Based Expiration

*For any* message that has been in the queue for more than 48 hours, the message should be removed from the queue and discarded.

**Validates: Requirements 7.5**

### Property 15: Encryption Round-Trip

*For any* valid message content and recipient keypair, encrypting the content with the recipient's public key and then decrypting with the recipient's private key should produce the original content.

**Validates: Requirements 8.1, 8.3**

### Property 16: Relay Cannot Decrypt

*For any* message being forwarded by a relay peer, the relay peer should not be able to decrypt the message content (decryption should fail or produce invalid data).

**Validates: Requirements 8.2**

### Property 17: Routing Metadata Unencrypted

*For any* message, the routing metadata (sender peer ID, recipient peer ID, TTL, hop count, timestamp, message type) should be readable without performing any decryption operations.

**Validates: Requirements 8.5**

### Property 18: Message Structure Completeness

*For any* message created or received, it should contain all required fields: message ID, sender peer ID, recipient peer ID, TTL, hop count, priority, timestamp, message type, and signature.

**Validates: Requirements 9.1, 9.2, 9.3, 9.5, 12.5, 15.5**

### Property 19: Message ID Uniqueness

*For any* set of newly generated message IDs, all IDs should be unique (no collisions).

**Validates: Requirements 9.4**

### Property 20: Route Discovery Initiation

*For any* destination peer ID with no known route in the routing table, attempting to send a message to that destination should trigger a route discovery process.

**Validates: Requirements 2.1, 2.3**

### Property 21: Route Storage Completeness

*For any* successfully discovered route, the route should be stored in the routing table with next hop peer ID, hop count, and timestamp information.

**Validates: Requirements 10.2**

### Property 22: Failed Route Removal

*For any* route that fails during message forwarding, the route should be removed from the routing table or marked as failed.

**Validates: Requirements 10.3**

### Property 23: Route Table Persistence

*For any* update to the routing table (add, remove, or modify route), the change should be persisted to SQLite storage.

**Validates: Requirements 10.4**

### Property 24: Route Expiration

*For any* route that has not been used for more than 30 minutes, the route should be expired and removed from the routing table.

**Validates: Requirements 2.5, 10.5**

### Property 25: Peer Discovery Integration

*For any* peer discovered via mDNS, the peer should be added as a potential next hop in the routing system (either as a direct route or available for route discovery).

**Validates: Requirements 11.1**

### Property 26: Disconnected Peer Route Cleanup

*For any* peer that disconnects, all routes that use that peer as the next hop should be removed from the routing table.

**Validates: Requirements 11.2**

### Property 27: Queue Priority Ordering

*For any* message queue containing messages with different priority levels, when dequeuing messages for transmission, higher priority messages should be processed before lower priority messages.

**Validates: Requirements 12.2**

### Property 28: Same Priority FIFO Ordering

*For any* message queue containing multiple messages with the same priority level, messages should be processed in FIFO order (first queued, first processed).

**Validates: Requirements 12.3**

### Property 29: Message Size Limit

*For any* message, the total message size (including all metadata and encrypted content) should not exceed 64 kilobytes.

**Validates: Requirements 13.3**

### Property 30: Oversized Message Rejection

*For any* message creation attempt where the content would result in a message exceeding 64 kilobytes, the message creation should fail and return an error.

**Validates: Requirements 13.4**

### Property 31: Route Selection Hop Count Preference

*For any* set of available routes to the same destination, the route with the fewest hops should be selected (unless other factors like success rate override).

**Validates: Requirements 14.1**

### Property 32: Route Failure Score Decrease

*For any* route that experiences a forwarding failure, the route's preference score should decrease, making it less likely to be selected in future routing decisions.

**Validates: Requirements 14.3**

### Property 33: Signature Verification on Receipt

*For any* received message, the message signature should be verified using the sender's public key before the message is processed or forwarded.

**Validates: Requirements 15.1, 15.7**

### Property 34: Invalid Signature Discard

*For any* message with an invalid cryptographic signature, the message should be discarded and not forwarded or delivered.

**Validates: Requirements 15.2**

### Property 35: Message Signing on Creation

*For any* newly created message, the message should be signed with the sender's private key, and the signature should be verifiable with the sender's public key.

**Validates: Requirements 15.4**

### Property 36: Timestamp Validity Check

*For any* received message with a timestamp older than 5 minutes or in the future, the message should be discarded to prevent replay attacks.

**Validates: Requirements 15.6**

### Property 37: Repeated Invalid Signature Blocking

*For any* peer that sends 3 or more messages with invalid signatures within a 5-minute window, the peer should be temporarily blocked for 10 minutes.

**Validates: Requirements 15.3**

### Property 38: Alternative Route Retry

*For any* message forwarding failure where alternative routes to the destination exist, the router should attempt to forward the message using an alternative route.

**Validates: Requirements 16.1**

### Property 39: All Routes Failed Queueing

*For any* message where all available routes to the destination have failed, the message should be queued for later retry rather than being discarded.

**Validates: Requirements 16.2**

### Property 40: Malformed Message Discard

*For any* received message that cannot be deserialized or is missing required fields, the message should be discarded without processing.

**Validates: Requirements 16.3**


