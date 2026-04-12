PeerChat - System Architecture (Current)

Last updated: February 25, 2026
Source of truth: current implementation in lib/src/** and Android host glue.

This document uses the original style: plain text and ASCII flow diagrams.
No Mermaid blocks are used.


1) High-Level Architecture

App UI Layer
  |
  |-- MainShell (global dialogs/toasts + tabs)
  |-- Home / Chats / Chat / Peers / Emergency / Debug screens
  |
  v
AppState (composition root + runtime orchestration)
  |
  |-- DBService (SQLite schema v13)
  |-- DiscoveryService (mDNS + BT scan policy)
  |-- MeshRouterService (mode selection + routing)
  |-- ConnectionManager (transport <-> crypto identity + capability cache)
  |-- MultiTransportService (WiFi + Bluetooth coordinator)
  |-- FileTransferService (0xFE protocol)
  |-- EmergencyBroadcastService
  |-- BatteryStatusService

Transport stack (both active concurrently)
  |
  |-- WiFiTransport (Nearby Connections)
  |-- BluetoothTransport (Classic BT)

Routing stack
  |
  |-- MessageManager
  |-- MessageQueue (backoff + caps)
  |-- RouteManager (route discovery/pruning)
  |-- DeliveryAckHandler
  |-- DeduplicationCache (seen/fingerprint/forwardedTo)


2) Runtime Profiles and Session Classification

Runtime profiles:
- normalDirect
- normalMesh
- emergencyBattery

Direct session requires ALL conditions:
- local profile == normalDirect
- remote profile (from handshake) == normalDirect
- direct connection currently exists

If any condition is false, session is treated as mesh.

Decision flow:

Peer selected
  |
  v
local profile == normalDirect ?
  |-- no --> Mesh session
  '-- yes --> remote profile == normalDirect ?
                 |-- no --> Mesh session
                 '-- yes --> direct connection exists ?
                                |-- no --> Mesh session
                                '-- yes --> Direct session

File transfer availability:
- Allowed only when session is Direct AND remote supportsFileTransfer == true


3) Startup and Composition Flow

App start
  |
  v
AppState.init()
  |
  |-- Initialize Sodium libs
  |-- Open DB + load peers + load runtime profile
  |-- Compose core services:
  |     CryptoService
  |     DeduplicationCache
  |     SignatureVerifier
  |     MessageQueue
  |     MultiTransportService
  |     DeliveryAckHandler
  |     ConnectionManager
  |
  |-- Compose higher layers:
  |     FileTransferService
  |     EmergencyBroadcastService
  |     RouteManager
  |     MessageManager
  |     MeshRouterService
  |
  |-- meshRouter.setRuntimeProfile(...)
  |-- meshRouter.init()
  |-- fileTransferService.init() (resume incomplete transfers + temp cleanup)
  |-- start battery monitoring + adaptive discovery policy
  |-- start discovery service
  '-- attach listeners (router changes, incoming messages, transfer updates)


4) Transport and Handshake Model

Transport behavior:
- MultiTransportService sends by trying registered transports sequentially.
- Success on any transport = send success.

Handshake payload includes:
- stable crypto peerId
- signing public key
- encryption public key
- displayName
- runtimeProfile
- supportsFileTransfer

Connection identity behavior:
- transport IDs are unstable (endpoint/mac).
- peer identity is stable crypto peerId.
- ConnectionManager merges sessions by peerId on reconnect/transport switch.

Capability propagation behavior:
- local profile change rebroadcasts handshake capabilities immediately
- a second rebroadcast occurs after ~700ms
- remote caches update runtime profile + file transfer support quickly


5) Message Send Flow (Direct / Mesh / Broadcast)

User taps Send in Chat/Emergency UI
  |
  v
MeshRouterService.sendMessage(recipient, content)
  |
  v
selectMode(destination, connectedPeerIds)
  |
  |-- destination == BROADCAST_EMERGENCY
  |     |
  |     '-- EmergencyBroadcastService.broadcastMessage(...)
  |
  |-- mode == direct
  |     |
  |     '-- _sendDirect(message, recipient)
  |            |
  |            |-- transportId exists?
  |            |     |-- yes --> transport.sendMessage(...)
  |            |     |             |-- success --> SendResult.direct
  |            |     |             '-- fail --> fallback mesh forward
  |            |     '-- no --> fallback mesh forward
  |            '-- on success: track pending ACK
  |
  '-- mode == mesh
        |
        '-- _forwardMessageViaTransport(message)
               |
               |-- route exists?
               |     |-- yes --> resolve next hop transport + send
               |     |             |-- success --> routed/direct result + track pending ACK
               |     |             '-- fail --> queue + mark route failed
               |     '-- no --> queue + route discovery
               '-- notify stats/listeners


6) Queue Processing Flow

Timer every 10s OR route/handshake events trigger debounced processing
  |
  v
MeshRouterService._processQueue()
  |
  v
MessageQueue.getReadyMessages()  (next_retry_time <= now)
  |
  v
for each queued message:
  |
  |-- if expired or over max retries -> dequeue
  |-- get current next hop from RouteManager
  |-- get transport id from ConnectionManager
  |-- try transport send
       |-- success:
       |     |-- dequeue
       |     |-- mark route success
       |     '-- track ACK/status for local outgoing DATA
       '-- fail:
             |-- update attempt count + exponential backoff
             '-- mark route failed

Queue policy highlights:
- base retry interval: 30s
- backoff: base * 2^min(attempt, 10)
- max retries: 50
- per-destination cap: 50 messages
- global cap: 5000 messages
- duration-based expiry via MeshMessage.expiryDuration / isExpired


7) Message Receive Flow

Incoming bytes from transport
  |
  |-- keepalive packet (0xFF 0xFF)?
  |     '-- yes -> update activity and return
  |
  '-- no
        |
        |-- parse handshake?
        |     |-- yes:
        |     |     |-- ConnectionManager.handleHandshake(...)
        |     |     |-- map transport <-> crypto peer id
        |     |     |-- store peer keys/capabilities
        |     |     '-- add/update direct route
        |     '-- no:
        |           |-- file-transfer marker (0xFE)?
        |           |     '-- yes -> FileTransferService.dispatchRawMessage(...)
        |           '-- no -> parse MeshMessage
        |
        '-- MeshMessage path:
              |-- broadcast destination?
              |     '-- yes -> EmergencyBroadcastService.handleIncomingBroadcast(...)
              '-- regular message:
                    |-- fingerprint dedup check
                    |-- learn reverse route to sender via immediate neighbor
                    |-- routeRequest/routeResponse handling via RouteManager
                    '-- MessageManager.processMessage(...)
                          |-- delivered -> decrypt + persist chat + emit stream
                          |-- forwarded -> forwarded by manager/router path
                          '-- queued -> opportunistic forward (2-3 peers) or queue


8) Controlled Mesh Forwarding (No Route Case)

When route is missing or relay returns queued:
- opportunistic forward to random 2-3 connected peers (not flood-all)
- skip sender/immediate source
- skip peers already forwarded to for that message
- max 3 opportunistic forwards per message per node
- fingerprint key: messageId-senderId-hopCount

This reduces collisions/loop amplification while still improving delivery chance.


9) File Transfer Architecture (Direct Only)

Protocol marker:
- 0xFE at transport payload start

Core behavior:
- direct session + remote support required
- 64KB chunks
- sliding window max in-flight = 5
- cumulative ACK model
- sender-only pause/resume controls
- receiver sees sender pause/resume status, can cancel
- resume supported
- SHA-256 integrity verification before final save
- persisted state for crash recovery

Flow:

Sender picks file
  |
  |-- verify direct connection + remote supportsFileTransfer
  |-- compute SHA-256
  |-- split into chunks
  '-- send FILE_META

Receiver gets FILE_META
  |
  |-- global incoming request dialog (MainShell)
  |-- reject -> FILE_REJECT
  '-- accept -> FILE_ACCEPT

After accept:
  |
  |-- sender streams CHUNK messages (window=5)
  |-- receiver sends CHUNK_ACK(highestContiguous)
  |-- retries on ACK timeout
  '-- sender sends FILE_COMPLETE when done

Receiver finalization:
- verify SHA-256
- move from temp to final path
- cleanup partial artifacts on cancel/failure paths


10) Emergency Broadcast Architecture

Broadcast rules:
- destination sentinel: BROADCAST_EMERGENCY
- signed, not encrypted
- initial TTL = 5
- per-sender rate limit: 5 messages per minute
- forward fanout: random 2-3 peers
- probabilistic decay after hop > 2
- 24h retention window in broadcast_messages table

Send flow:

User sends emergency text
  |
  |-- create signed MeshMessage (recipient=BROADCAST_EMERGENCY, ttl=5)
  |-- enforce local sender rate limit
  |-- persist local broadcast
  '-- forward to random 2-3 connected peers

Receive flow:

Incoming broadcast
  |
  |-- dedup + signature verify + ttl check
  |-- enforce sender rate limit
  |-- persist and publish to Emergency UI
  '-- if hopCount > 2 then probabilistic decay gate
         |-- skip forwarding OR
         '-- forward to random 2-3 peers (excluding source/already-forwarded)


11) Discovery, Energy, and Health Loops

DiscoveryService adaptive policy uses:
- runtime profile
- connected peer count
- file transfer active state
- battery low flag
- jitter (0-3s)

WiFiTransport health/reconnect loop:
- keepalive interval: 8s
- timeout threshold: 24s
- health checks: every 10s
- reconnect checks: every 8s
- known endpoint persistence for auto-reconnect
- location-related discovery failures surfaced to UI with settings shortcut


12) Persistence Model (Schema v13)

Core tables:
- peers
- chat_messages
- message_queue (next_retry_time, expiry_time)
- routes
- deduplication_cache
- blocked_peers
- pending_acks
- peer_keys
- known_wifi_endpoints
- file_transfers
- broadcast_messages


13) Current Gaps (Implemented Partially / Pending)

- connectionUpgradeRequest/Response enums exist, but no full upgrade orchestration yet
- abstract TransportService does not expose onConnectionLost/onConnectionRestored callbacks
- routing stats exist, but adaptive TTL/queue tuning based on stats is not wired yet
- ACK batching + explicit 5/15/45 minute retry hardening not fully implemented
- dedicated Android foreground service module not implemented yet


14) Design Principles in Current Code

- Stable cryptographic identity over unstable transport IDs
- Profile/capability-gated direct/mesh/file-transfer UX
- Delay-tolerant delivery via persistent queue + route learning
- Opportunistic multi-transport sending
- Signed emergency broadcast channel
- Recovery-first behavior for reconnects and interrupted transfers

