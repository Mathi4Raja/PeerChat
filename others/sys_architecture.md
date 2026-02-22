Transport Layer Architecture
Primary vs Fallback Connections
There is NO primary/fallback hierarchy - instead, you have a multi-transport system that operates simultaneously:

WiFi Direct (Nearby Connections) - High bandwidth, peer-to-peer
Bluetooth Classic - Lower bandwidth, reliable for close range
Both transports run concurrently. When sending a message, the MultiTransportService tries both transports and succeeds if either one works:

// From transport_service.dart
Future<bool> sendMessage(String peerId, Uint8List data) async {
  for (final transport in _transports) {
    if (await transport.sendMessage(peerId, data)) {
      return true; // Success on ANY transport
    }
  }
  return false; // Failed on ALL transports
}
This means:

If WiFi Direct works → message sent via WiFi Direct
If WiFi Direct fails but Bluetooth works → message sent via Bluetooth
If both fail → message queued for retry
Complete Application Flow
1. App Initialization
App Start
  ↓
AppState.init()
  ↓
├─ Initialize Sodium (crypto library)
├─ Open SQLite Database
├─ Initialize MeshRouterService
│   ↓
│   ├─ CryptoService.init() → Generate/load keypairs
│   ├─ Initialize core services (dedup, queue, routes, etc.)
│   ├─ Initialize BluetoothTransport
│   │   ↓
│   │   ├─ Start Bluetooth discovery
│   │   └─ Connect to bonded devices
│   ├─ Initialize WiFiTransport
│   │   ↓
│   │   ├─ Load known endpoints from DB
│   │   ├─ Start WiFi Direct advertising
│   │   ├─ Start WiFi Direct discovery
│   │   ├─ Start keepalive timer (15s)
│   │   └─ Start health check timer (10s)
│   └─ Start maintenance timers
├─ Start DiscoveryService (mDNS)
└─ Start peer refresh timer (10s)
2. Peer Discovery Flow
First-Time Discovery
Step 1: Transport-Level Discovery

Device A                          Device B
   |                                 |
   |-- WiFi Direct Advertising ---->|
   |<--- WiFi Direct Discovery ------|
   |                                 |
   |-- Bluetooth Discovery --------->|
   |<--- Bluetooth Advertising ------|
   |                                 |
   |-- mDNS Broadcast -------------->|
   |<--- mDNS Response ---------------|
Step 2: Connection Establishment

When WiFi Direct discovers a peer:

Device A discovers endpoint "KZXX"
  ↓
onEndpointFound("KZXX", "Arctic Warrior 816")
  ↓
Check if known peer (from database)
  ↓
├─ If known → Auto-reconnect
└─ If new → Request connection
  ↓
onConnectionInitiated("KZXX")
  ↓
Auto-accept connection
  ↓
onConnectionResult(Status.CONNECTED)
  ↓
├─ Add to _connectedPeers map
├─ Save to known_wifi_endpoints table
├─ Start keepalive exchange
└─ Trigger onConnectionEstablished callback
Step 3: Cryptographic Handshake

Device A (Transport ID: KZXX)     Device B (Transport ID: EWDI)
   |                                      |
   |-- Connection Established ---------->|
   |                                      |
   |-- Handshake Message ---------------->|
   |   {                                  |
   |     peerId: "crypto_public_key_A",  |
   |     displayName: "Cloud Tiger 343", |
   |     publicKey: signing_key,         |
   |     encryptionKey: encryption_key   |
   |   }                                  |
   |                                      |
   |<----- Handshake Message -------------|
   |   {                                  |
   |     peerId: "crypto_public_key_B",  |
   |     displayName: "Arctic Warrior",  |
   |     publicKey: signing_key,         |
   |     encryptionKey: encryption_key   |
   |   }                                  |
   |                                      |
   |-- Handshake Complete --------------->|
   |                                      |
   |-- Create Mapping ------------------->|
   |   Transport ID → Crypto ID          |
   |   KZXX → crypto_public_key_B        |
   |                                      |
   |-- Add Direct Route ----------------->|
   |   Destination: crypto_public_key_B  |
   |   NextHop: crypto_public_key_B      |
   |   HopCount: 1                        |
   |                                      |
   |-- Save Peer to Database ------------>|
   |   ID: crypto_public_key_B           |
   |   Name: "Arctic Warrior 816"        |
   |   Keys: signing + encryption        |
3. Message Sending Flow
Direct Message (Peer Connected)
User sends "Hello" to Arctic Warrior
  ↓
ChatScreen → AppState.meshRouter.sendMessage()
  ↓
MeshRouterService.sendMessage()
  ↓
├─ Get recipient's public key from DB
├─ Encrypt content with recipient's encryption key
├─ Create MeshMessage with encrypted content
├─ Sign message with sender's signing key
├─ Track pending ACK in DeliveryAckHandler
└─ Forward message
  ↓
_forwardMessageViaTransport()
  ↓
├─ RouteManager.getNextHop(recipientPeerId)
│   ↓
│   └─ Query routes table → Find direct route
│       NextHop: crypto_public_key_B (1 hop)
│
├─ ConnectionManager.getTransportId(crypto_public_key_B)
│   ↓
│   └─ Return: "KZXX" (WiFi Direct endpoint)
│
└─ MultiTransportService.sendMessage("KZXX", messageBytes)
    ↓
    ├─ Try BluetoothTransport.sendMessage("KZXX")
    │   └─ FAILED (no Bluetooth connection to KZXX)
    │
    └─ Try WiFiTransport.sendMessage("KZXX")
        ↓
        └─ nearby.sendBytesPayload("KZXX", messageBytes)
            └─ SUCCESS ✓
Queued Message (Peer Not Connected)
User sends "Hello" to offline peer
  ↓
MeshRouterService.sendMessage()
  ↓
├─ Create and sign message
└─ _forwardMessageViaTransport()
  ↓
RouteManager.getNextHop(recipientPeerId)
  ↓
  └─ No route found → return null
  ↓
Queue message
  ↓
MessageQueue.enqueue(QueuedMessage)
  ↓
├─ Insert into message_queue table
│   {
│     message_id,
│     next_hop_peer_id,
│     message_data (encrypted),
│     priority,
│     queued_timestamp,
│     attempt_count: 0
│   }
│
└─ Initiate route discovery
    ↓
    RouteManager.discoverRoute(recipientPeerId)
      ↓
      Broadcast ROUTE_REQUEST to all connected peers
4. Message Receiving Flow
WiFi Direct receives bytes from endpoint "KZXX"
  ↓
WiFiTransport._handleIncomingPayload()
  ↓
├─ Check if keepalive (0xFF 0xFF)
│   ↓
│   ├─ Update activity timestamp
│   └─ Forward to ConnectionManager.updatePeerActivity()
│
└─ Try parse as HandshakeMessage
    ↓
    ├─ If handshake → ConnectionManager.handleHandshake()
    │   ↓
    │   ├─ Store peer's crypto keys
    │   ├─ Create transport→crypto mapping
    │   ├─ Add direct route
    │   └─ Save peer to database
    │
    └─ If mesh message → MeshRouterService.receiveMessage()
        ↓
        MeshMessage.fromBytes(rawMessage)
          ↓
        ├─ Learn reverse route (sender → immediate neighbor)
        │
        ├─ MessageManager.processMessage()
        │   ↓
        │   ├─ Check deduplication cache
        │   ├─ Verify signature
        │   ├─ Check if for me
        │   │   ↓
        │   │   ├─ If for me → ProcessResult.delivered
        │   │   └─ If not for me → ProcessResult.forwarded
        │   │
        │   └─ Handle based on message type
        │       ↓
        │       ├─ DATA → Decrypt and deliver
        │       ├─ ACK → Update message status
        │       ├─ ROUTE_REQUEST → Send ROUTE_REPLY
        │       └─ ROUTE_REPLY → Update routing table
        │
        └─ If delivered
            ↓
            _deliverToApplication()
              ↓
              ├─ Decrypt content
              ├─ Save to chat_messages table
              ├─ Publish to onMessageReceived stream
              └─ ChatScreen updates UI
5. Queue Processing Flow
Timer fires every 10 seconds
  ↓
MeshRouterService._processQueue()
  ↓
MessageQueue.getAllQueued()
  ↓
For each queued message:
  ↓
  ├─ Check if expired (TTL)
  │   └─ If expired → dequeue and discard
  │
  ├─ Re-evaluate route
  │   ↓
  │   RouteManager.getNextHop(recipientPeerId)
  │     ↓
  │     ├─ If still no route → skip (wait for discovery)
  │     └─ If route found → proceed
  │
  ├─ Get transport ID for next hop
  │   ↓
  │   ConnectionManager.getTransportId(nextHopCryptoId)
  │     ↓
  │     ├─ If no transport → skip (connection not ready)
  │     └─ If transport found → proceed
  │
  └─ Try to send
      ↓
      MultiTransportService.sendMessage(transportId, messageBytes)
        ↓
        ├─ If SUCCESS
        │   ↓
        │   ├─ Dequeue message
        │   └─ Mark route success
        │
        └─ If FAILED
            ↓
            ├─ Increment attempt_count
            └─ Mark route failed
6. Keepalive & Health Monitoring
Every 15 seconds (keepalive timer):
  ↓
WiFiTransport._sendKeepalives()
  ↓
For each connected endpoint:
  ↓
  nearby.sendBytesPayload(endpointId, [0xFF, 0xFF])
    ↓
    Update local activity timestamp

Every 10 seconds (health check timer):
  ↓
WiFiTransport._checkConnectionHealth()
  ↓
For each connection:
  ↓
  Check time since last activity
    ↓
    ├─ If > 60 seconds → TIMEOUT
    │   ↓
    │   ├─ Remove from _connectedPeers
    │   ├─ Call onConnectionLost()
    │   └─ Disconnect endpoint
    │
    └─ If < 60 seconds → HEALTHY
7. Auto-Reconnection Flow
WiFi turned off → Connection lost
  ↓
onDisconnected("KZXX")
  ↓
├─ Remove from _connectedPeers
├─ Reset reconnect attempts in DB
└─ Call onConnectionLost()

WiFi turned back on
  ↓
User pulls to refresh
  ↓
AppState.refreshDiscovery()
  ↓
MeshRouter.restartWiFiDirect()
  ↓
WiFiTransport.restartWiFiDirect()
  ↓
├─ Stop advertising/discovery
├─ Wait 500ms
└─ Restart advertising/discovery
  ↓
onEndpointFound("KZXX", "Arctic Warrior 816")
  ↓
_shouldAttemptReconnect("KZXX")
  ↓
├─ Check if in _knownPeers (from DB) → YES
├─ Check if already connected → NO
├─ Check reconnect attempts < 5 → YES
└─ Check cooldown period → OK
  ↓
Auto-reconnect: Request connection
  ↓
onConnectionResult(Status.CONNECTED)
  ↓
├─ Save to known_wifi_endpoints
├─ Reset reconnect attempts
└─ Exchange handshakes again
  ↓
Connection restored!
Key Design Principles
Transport Agnostic: Messages don't care which transport they use
Opportunistic Routing: Use whatever transport works
Persistent Queuing: Messages survive app restarts
Cryptographic Identity: Peers identified by public keys, not transport addresses
Automatic Failover: If one transport fails, try another
Route Learning: Build routing table from received messages
Health Monitoring: Detect and handle stale connections
Auto-Reconnection: Remember known peers and reconnect automatically
This architecture provides resilience, security, and seamless multi-hop mesh networking!