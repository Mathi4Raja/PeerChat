# PeerChat Secure — Implementation Plan v2

Full architecture implementation covering Direct Layer, Mesh Layer, and Emergency Broadcast per the spec documents.

> [!IMPORTANT]
> This plan is **additive** — nothing existing is removed. All current mesh routing, crypto, and transport code stays intact.

---

## Mode Profiles (Updated Rules)

These runtime profiles sit on top of the existing `CommunicationMode` (`direct`, `mesh`, `emergencyBroadcast`).

### 1) Normal Mode

- `normal_direct`:
  - Direct chats stay enabled and prioritized.
  - Mesh remains available/passive (coexistence allowed).
  - Emergency broadcast channel stays available.
  - File transfer follows the existing direct single-path implementation by default.
  - Dual WiFi+Bluetooth transfer is optional and should only be enabled if measured throughput gain is significant in real testing.

- `normal_mesh`:
  - Mesh discovery/routing is primary.
  - Direct chat and file transfer UI/actions are disabled in this profile.
  - Emergency broadcast channel remains available and is prioritized over normal mesh traffic.

### 2) Emergency Mode (Battery Saver Profile)

- Keep the **existing emergency broadcast channel** as-is (no behavioral downgrade).
- Apply aggressive battery-saving policy to discovery/scan cadence in both mesh and emergency broadcast use.
- De-prioritize direct chat/file transfer activity (limited or disabled by profile), while preserving stable peer liveness.

### 3) Android Location Constraint Handling

- Nearby discovery/reconnect depends on Android location permission/services on many devices.
- Add explicit runtime UX when discovery/reconnect fails due to location:
  - show popup explaining failure reason
  - provide one-tap shortcut to Location settings/app settings for immediate recovery

---

## Phase 1: Mode Separation & Direct Messaging

Enforce the 3-mode rule: Direct bypasses mesh; Mesh uses queue+routing; Broadcast uses flooding.

### Core Logic

#### [NEW] [communication_mode.dart](file:///d:/P2P-app/lib/src/models/communication_mode.dart)
- `CommunicationMode` enum: `direct`, `mesh`, `emergencyBroadcast`
- Mode selection function:
```dart
if (destinationId == "BROADCAST_EMERGENCY") → emergencyBroadcast
else if (isDirectlyConnected(destinationId)) → direct
else → mesh
```

#### [MODIFY] [mesh_router_service.dart](file:///d:/P2P-app/lib/src/services/mesh_router_service.dart)
- Add mode check at top of [sendMessage()](file:///d:/P2P-app/lib/src/services/transport_service.dart#49-75):
  - **Direct**: encrypt → sign → send via transport **immediately** (skip queue, skip route lookup)
  - **Mesh**: existing logic (route lookup → queue if needed)
  - **Broadcast**: delegate to new `EmergencyBroadcastService`
- Add `sendDirect()` private method for zero-hop delivery
- Wire retry triggers: call [_processQueue()](file:///d:/P2P-app/lib/src/services/mesh_router_service.dart#540-590) on [onPeerConnected](file:///d:/P2P-app/lib/src/services/route_manager.dart#233-247) and `onRouteUpdated` events
- **Peer churn debounce**: `debounceQueueProcessing(2s)` — prevents burst traffic when many peers connect simultaneously
- **Message ID uniqueness**: `messageId = "${senderPrefix}_${uuid.v4()}"` — globally unique across devices, never reused

> [!NOTE]
> **Message Persistence Rules**: Direct/mesh messages for this user → `chat_messages` DB. Relay messages → `message_queue` only (never stored in chat). Broadcast → `broadcast_messages` with 24h expiry.

#### [DELETE] [simple_message_service.dart](file:///d:/P2P-app/lib/src/services/simple_message_service.dart)
- Legacy testing service, superseded by [MeshRouterService](file:///d:/P2P-app/lib/src/services/mesh_router_service.dart#47-670) with direct mode

#### [MODIFY] [connection_manager.dart](file:///d:/P2P-app/lib/src/services/connection_manager.dart)
- **Peer identity persistence**: on reconnect, always merge by `peerId` (public key hash) — never create duplicate peer entries
- Add explicit guard: `mergeSessionsByPeerId()` in [handleHandshake()](file:///d:/P2P-app/lib/src/services/connection_manager.dart#73-121) — if transport ID changes, update mapping atomically
- Ensure `peerId` survives WiFi ↔ BT transport switches

---

## Phase 2: Mesh Queue Improvements

Add exponential backoff, retry triggers, fairness, per-destination limits, and duration-based expiry.

> [!WARNING]
> **Clock Independence (Critical)**: In disaster scenarios, devices have no NTP. ALL timing must use **duration since creation**, never absolute timestamps:
> ```dart
> final age = now - message.createdAt;
> if (age > expiryDuration) drop(); // ✅ clock-independent
> // NOT: if (now > message.expiryTime) drop(); // ❌ clock-dependent
> ```

#### [MODIFY] [mesh_message.dart](file:///d:/P2P-app/lib/src/models/mesh_message.dart)
- Add `int expiryDuration` field (milliseconds, default: 7 days = `604800000`)
- Compute expiry dynamically: `bool get isExpired => (now - timestamp) > expiryDuration`
- All retry/ACK timers also use duration-based checks, never absolute wall clock

#### [MODIFY] [queued_message.dart](file:///d:/P2P-app/lib/src/models/queued_message.dart)
- Add `int nextRetryTime` field
- Add `static const int maxRetries = 50`
- Add `bool get shouldDrop => attemptCount > maxRetries`
- Update [toMap()](file:///d:/P2P-app/lib/src/models/queued_message.dart#27-38) / [fromMap()](file:///d:/P2P-app/lib/src/models/queued_message.dart#40-52) + DB schema

#### [MODIFY] [message_queue.dart](file:///d:/P2P-app/lib/src/services/message_queue.dart)
- Implement exponential backoff: `nextRetryTime = now + base * 2^min(retryCount, 10)`
- `getReadyMessages()` — only return messages where `now >= nextRetryTime`
- Age-based priority boost: messages queued > 1 hour get priority bumped
- Drop messages exceeding `maxRetries`
- **Per-destination queue limit**: `maxMessagesPerPeer = 50`
  - `dropOldestForPeer(peerId)` when limit exceeded
  - Prevents single unreachable peer from consuming entire queue

#### [MODIFY] [route_manager.dart](file:///d:/P2P-app/lib/src/services/route_manager.dart)
- Add `Stream<String> onRouteUpdated` — emits destination peer ID when route changes
- **Route failure-rate pruning**: `if (route.failureRate > 0.7) removeRoute()` — evict bad routes proactively
- `if (route.lastSeen > staleThreshold) removeRoute()` — clean stale entries
- Fire event in [addRoute()](file:///d:/P2P-app/lib/src/services/route_manager.dart#83-121), [handleRouteResponse()](file:///d:/P2P-app/lib/src/services/route_manager.dart#399-427)

#### [MODIFY] [db_service.dart](file:///d:/P2P-app/lib/src/services/db_service.dart)
- Bump DB version (add `next_retry_time` column to `message_queue`, `expiry_time` to message data)

---

## Phase 3: Controlled Lazy Flooding

When no route exists, spread messages gradually with multi-node collision prevention.

#### [MODIFY] [mesh_router_service.dart](file:///d:/P2P-app/lib/src/services/mesh_router_service.dart)
- In [_forwardMessageViaTransport()](file:///d:/P2P-app/lib/src/services/mesh_router_service.dart#392-456), if no route:
  1. Pick 2-3 random connected peers (not sender)
  2. **Dedup guard**: `if (message.alreadyForwardedTo.contains(peerId)) skip`
  3. Forward to them only (NOT all peers)
  4. Mark message as "opportunistically forwarded"
- Limit: max 3 opportunistic forwards per message per node
- Track `forwardedTo` set per messageId in [DeduplicationCache](file:///d:/P2P-app/lib/src/services/deduplication_cache.dart#4-91)

#### Forwarding Fingerprint (Multi-Node Collision Prevention)
- Use `"$messageId-$senderId-$hopCount"` as forwarding fingerprint
- Check fingerprint before forwarding — prevents duplicate propagation across different nodes that received the same message via different paths:
```dart
final fingerprint = "$messageId-$senderId-$hopCount";
if (seenFingerprints.contains(fingerprint)) return;
seenFingerprints.add(fingerprint);
```

#### [MODIFY] [deduplication_cache.dart](file:///d:/P2P-app/lib/src/services/deduplication_cache.dart)
- Add `Set<String> forwardedTo` tracking per messageId
- Add `hasForwardedTo(messageId, peerId)` / `markForwardedTo(messageId, peerId)`
- Add `hasSeenFingerprint(fingerprint)` / `markFingerprint(fingerprint)` with bounded cache

---

## Phase 4: File Transfer System (DIRECT ONLY)

Chunk-based transfer with resume, sliding window ACKs, integrity validation, per-chunk timeout, and crash recovery.

### Models

#### [NEW] [file_transfer.dart](file:///d:/P2P-app/lib/src/models/file_transfer.dart)
- `FileTransferState` enum: `idle`, `requested`, `accepted`, `transferring`, `paused`, `completed`, `failed`
- `FileMetadata` class: `fileId`, `fileName`, `fileSize`, `totalChunks`, `sha256Hash`
- `FileChunk` class: `fileId`, `chunkIndex`, [data](file:///d:/P2P-app/.metadata) (Uint8List)
- `FileTransferMessage` union type:
  - `FILE_META` — sender → receiver (propose transfer)
  - `FILE_ACCEPT` — receiver → sender
  - `FILE_REJECT` — receiver → sender
  - `CHUNK` — sender → receiver (data chunk)
  - `CHUNK_ACK` — receiver → sender
  - `RESUME_FROM` — receiver → sender (resume from chunkIndex)
  - `FILE_COMPLETE` — sender → receiver (all chunks sent)
  - `FILE_ABORT` — either → either

### Service

#### [NEW] [file_transfer_service.dart](file:///d:/P2P-app/lib/src/services/file_transfer_service.dart)
- Manages active file transfers (`Map<fileId, FileTransferSession>`)
- **Sender flow**: pick file → compute SHA-256 → split into 64KB chunks → send FILE_META → wait for ACCEPT → stream chunks with sliding window (5 in flight) → wait for CHUNK_ACKs → send FILE_COMPLETE
- **Receiver flow**: receive FILE_META → prompt user → send ACCEPT → receive chunks → write to temp file → verify SHA-256 → move to final path
- **Chunk ordering**: use `BitSet receivedChunks` — never assume ordered delivery. Write sequentially only when contiguous chunks are ready
- **Cumulative ACK**: `ACK { highestContiguousChunkIndex }` — one ACK implicitly acknowledges all chunks below it, reduces ACK traffic ~80%
- **Resume**: on reconnect, receiver sends RESUME_FROM(lastReceivedChunk+1)
- **Transport switching**: if WiFi drops, pause → wait for BT → send RESUME_FROM
- Constraints: `assert(isDirectlyConnected(peerId))` — refuse if not direct
- **Chunk ACK timeout (10s WiFi / 15s BT)**:
```dart
if (!ackReceivedWithin(chunkAckTimeout)) {
  resendChunk(chunkIndex);
}
```
  - Max 5 resend attempts per chunk → abort transfer on failure
- **Crash recovery**: persist transfer state to DB. On app start:
```dart
onAppStart() → resumeIncompleteTransfers();
```
- **Stale transfer cleanup**: auto-abort transfers idle > 10 minutes
- **Disk pressure guard**: before accepting a transfer, check available storage:
```dart
if (availableStorage < requiredSpace * 1.2) rejectTransfer();
```
- **Temp file cleanup**: `cleanupTempFiles(olderThan: 24h)` on app start — prevents storage bloat on budget devices

### Database

#### [MODIFY] [db_service.dart](file:///d:/P2P-app/lib/src/services/db_service.dart)
- New table `file_transfers`: fileId, peerId, state, fileName, fileSize, totalChunks, receivedChunks, sha256Hash, tempPath, createdAt, lastActivityAt

### UI

#### [NEW] [file_transfer_screen.dart](file:///d:/P2P-app/lib/src/screens/file_transfer_screen.dart)
- File picker integration
- Progress bar with chunk count
- Pause/Resume/Cancel buttons
- SHA-256 verification status

#### [MODIFY] [chat_screen.dart](file:///d:/P2P-app/lib/src/screens/chat_screen.dart)
- Add file attachment button (📎) in input bar — **only visible for directly connected peers**
- Show file transfer cards in chat (progress, download button)

---

## Phase 5: Emergency Broadcast Mode

Public "town square" channel with controlled spread and probabilistic decay.

### Service

#### [NEW] [emergency_broadcast_service.dart](file:///d:/P2P-app/lib/src/services/emergency_broadcast_service.dart)
- `broadcastMessage(content)`:
  - Create [MeshMessage](file:///d:/P2P-app/lib/src/models/mesh_message.dart#18-250) with `destinationId = "BROADCAST_EMERGENCY"`
  - TTL = 5 (low, limits spread)
  - Sign with Ed25519 but do NOT encrypt
  - Forward to 2-3 random directly connected peers (NOT all)
- `handleBroadcast(message)`:
  - Verify signature (reject tampered)
  - Dedup via existing [DeduplicationCache](file:///d:/P2P-app/lib/src/services/deduplication_cache.dart#4-91)
  - **Forward to 2-3 random connected peers** (NOT all — prevents local congestion), decrement TTL
  - **Probabilistic decay**: after hop 2, 50% chance to skip forwarding — creates natural dampening in dense networks:
```dart
if (hopCount > 2 && Random().nextDouble() > 0.5) return;
```
  - Deliver to UI
- **Rate limiting**: max 5 broadcasts per minute per sender
  - Track `Map<senderId, List<timestamp>>` of recent broadcasts
  - Drop excess silently

### Database

#### [MODIFY] [db_service.dart](file:///d:/P2P-app/lib/src/services/db_service.dart)
- New table `broadcast_messages`: messageId, senderId, senderName, content, timestamp, signature

### UI

#### [NEW] [emergency_broadcast_screen.dart](file:///d:/P2P-app/lib/src/screens/emergency_broadcast_screen.dart)
- Public chat timeline (all messages visible)
- Red/orange "EMERGENCY" visual theme
- Sender display name + verification badge (signature valid)
- Input bar with rate limit warning
- No encryption indicator

#### [MODIFY] [main_shell.dart](file:///d:/P2P-app/lib/src/screens/main_shell.dart)
- Add 5th bottom nav tab: Emergency (🆘 icon, red accent)

---

## Phase 6: Transport Layer Upgrades

### Connection Upgrade (Mesh → Direct for File Transfer)

#### [MODIFY] [mesh_router_service.dart](file:///d:/P2P-app/lib/src/services/mesh_router_service.dart)
- New message type: `connectionUpgradeRequest` — ask remote peer to establish WiFi Direct
- **Deterministic race prevention**: lower peer ID initiates, higher waits:
```dart
if (myPeerId.compareTo(otherPeerId) < 0) {
  initiateConnection();
} else {
  waitForConnection();
}
```
- On accept: initiator starts WiFi Direct → handshake → ready for file transfer

#### [MODIFY] [mesh_message.dart](file:///d:/P2P-app/lib/src/models/mesh_message.dart)
- Add `MessageType.connectionUpgradeRequest` and `MessageType.connectionUpgradeResponse`

### Transport Resume

#### [MODIFY] [transport_service.dart](file:///d:/P2P-app/lib/src/services/transport_service.dart)
- Add [onConnectionLost](file:///d:/P2P-app/lib/src/services/connection_manager.dart#122-135) callback to abstract interface
- Add `onConnectionRestored` callback
- These fire resume logic in `FileTransferService`

---

## Phase 7: Network Awareness (Lightweight Stats)

#### [MODIFY] [mesh_router_service.dart](file:///d:/P2P-app/lib/src/services/mesh_router_service.dart)
- Track lightweight stats:
  - `int messagesSent`, `int messagesDelivered`, `int messagesFailed`
  - `double get deliverySuccessRate`
  - `int get activePeerCount`
- Expose via existing [RoutingStats](file:///d:/P2P-app/lib/src/services/mesh_router_service.dart#33-46) class
- Use stats for adaptive behavior:
  - If deliveryRate < 30%: **clamped** TTL increase: `ttl = clamp(ttl + 2, min: 10, max: 20)`
  - If queue > 80% full: drop low-priority messages faster

---

## Phase 8: Edge Case Hardening

#### [MODIFY] [mesh_router_service.dart](file:///d:/P2P-app/lib/src/services/mesh_router_service.dart)
- **Route disappears mid-delivery**: already handled (markRouteFailed → re-queue)
- **ACK timeout**: exponential retry with hard cap:
  - Retry intervals: 5min → 15min → 45min (`base * 3^attempt`)
  - `maxAckRetries = 3` — give up after 3 attempts
- **ACK storm mitigation**: aggregate ACKs — batch multiple ACK IDs into a single message every 2s instead of sending individually. Reduces ACK-induced congestion.
- **Queue overload**: enforce `maxQueueSize` with priority-weighted eviction + per-destination cap (from Phase 2)

#### [MODIFY] [file_transfer_service.dart](file:///d:/P2P-app/lib/src/services/file_transfer_service.dart)
- **Peer disconnect during transfer**: pause state, auto-resume on reconnect
- **Stale transfers**: auto-abort transfers idle > 10 minutes
- **Crash recovery**: `resumeIncompleteTransfers()` on app startup (from Phase 4)

#### [MODIFY] [emergency_broadcast_service.dart](file:///d:/P2P-app/lib/src/services/emergency_broadcast_service.dart)
- **Broadcast spam**: rate limiter enforced per senderId
- **Broadcast loop amplification**: probabilistic decay after hop 2 (from Phase 5)

---

## Phase 9: Energy Efficiency & Android Constraints

**Golden Rule**: *"Keep links alive, reduce searching when not needed."*

### Adaptive Discovery

#### [MODIFY] [discovery_service.dart](file:///d:/P2P-app/lib/src/services/discovery_service.dart)
- **Adaptive scan intervals** based on connection state:

| Condition | Scan Interval |
|-----------|--------------|
| 0 connections | 5 seconds |
| 1-2 connections | 15 seconds |
| 3+ connections | 30-60 seconds |
| File transfer active | Disable throttling (keep alive) |
| Battery low | Double all intervals |

- **Discovery jitter**: `scanInterval = baseInterval + random(0-3s)` — prevents synchronized WiFi storms when many devices launch simultaneously
- Connections MUST stay alive at all times — only throttle **discovery scanning**
- Battery-aware: detect low battery → increase retry delays, reduce scan frequency

### Android System Constraints

#### [MODIFY] [app_state.dart](file:///d:/P2P-app/lib/src/app_state.dart)
- Request battery optimization exemption on first launch (prompt user with explanation dialog)

#### [NEW] [foreground_service.dart](file:///d:/P2P-app/lib/src/services/foreground_service.dart)
- Android foreground service (MANDATORY for Android 12+):
  - **Minimal, helpful notification**: "Keeping nearby connections alive 📡 · {n} peers"
  - Low priority notification channel (less intrusive)
  - Tap opens app, no dismiss action (Android requirement for foreground services)
  - Keeps WiFi Direct and Bluetooth alive in background
  - Prevents OS from killing the process

#### [MODIFY] [wifi_transport.dart](file:///d:/P2P-app/lib/src/services/wifi_transport.dart)
- Auto-reconnect WiFi Direct on unexpected disconnect
- Fallback to Bluetooth on WiFi failure

#### [MODIFY] [pubspec.yaml](file:///d:/P2P-app/pubspec.yaml)
- Add `flutter_foreground_task` or `flutter_background_service` dependency

### Per-Mode Energy Behavior

| Mode | Discovery | Connections | Battery |
|------|-----------|-------------|---------|
| 🟢 Direct | No throttling | Keep alive | Full power |
| 🟡 Mesh | Adaptive throttle | Maintain | Backoff on low battery |
| 🔵 Broadcast | Short bursts only | Controlled spread | Minimal scanning |

---

## Verification Plan

### Per-Phase Testing
| Phase | Command / Check |
|-------|----------------|
| 1-3 | `flutter analyze` + existing chat works (direct sends instantly, mesh routes correctly) |
| 4 | Manual: send file, disconnect WiFi mid-transfer, verify resume over BT, kill app mid-transfer & relaunch |
| 5 | Manual: broadcast on 2+ phones, test rate limit, verify decay in dense network |
| 6-7 | `flutter analyze` + verify stats in debug screen, test upgrade race condition |
| 8 | Targeted: kill connections mid-transfer, spam queue with messages to offline peer, verify per-dest limits |
| 9 | Manual: run app for 30+ min, compare battery usage with/without adaptive discovery |

### Automated
```
flutter analyze
flutter test
flutter build apk
```

### Manual (on 2+ Android devices)
1. Direct chat works instantly (no queue delay)
2. Mesh chat works when peers are not directly connected
3. File transfer: send image, verify SHA-256 match
4. Resume: kill WiFi mid-transfer, verify it resumes over Bluetooth
5. Crash recovery: kill app during file transfer, relaunch, verify it resumes
6. Emergency broadcast: open on 2 phones, send message, verify both see it
7. Rate limit: spam broadcast, verify after 5th message it's blocked
8. Mode separation: file attachment button only appears for directly connected peers
9. Queue limits: spam 100 messages to offline peer, verify capped at 50
10. Foreground service: app keeps running when screen off
