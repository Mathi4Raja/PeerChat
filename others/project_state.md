# PeerChat Secure — Project State Snapshot (Migration Handoff)

Last updated: February 25, 2026  
Primary scope: current code in `lib/src/**` and Android host glue in `android/app/src/main/**`  
Companion target plan: `others/implementation_plan.md`

This document is intentionally explicit for LLM handoff/migration. It records:
- what is implemented now,
- what behavior was intentionally changed,
- what remains partially done or not done.

## 1) Current Architecture (As Implemented)

### 1.1 App Composition Root
- `lib/src/app_state.dart` is the composition root and runtime orchestrator.
- It wires and owns:
  - `DBService`
  - `DiscoveryService`
  - `MeshRouterService`
  - `ConnectionManager`
  - `FileTransferService`
  - `EmergencyBroadcastService`
  - battery/location policy glue through `BatteryStatusService`
- It also owns runtime profile state (`RuntimeProfile`) and profile persistence via `FlutterSecureStorage`.

### 1.2 Runtime Profiles and Session Classification
- Model: `lib/src/models/runtime_profile.dart`
  - `normalDirect`
  - `normalMesh`
  - `emergencyBattery`
- Mode selector for message pathing: `lib/src/models/communication_mode.dart`
  - `direct`
  - `mesh`
  - `emergencyBroadcast`
- Critical session gate in `AppState`:
  - `isDirectSessionWithPeer(peerId)` requires:
    - local profile = `normalDirect`
    - remote profile = `normalDirect`
    - direct connection currently present
  - otherwise session is treated as mesh.

### 1.3 Transport + Handshake Layer
- Multi-transport coordinator: `lib/src/services/transport_service.dart`
  - Registers transports and tries sends sequentially until one succeeds.
- WiFi Direct / Nearby transport: `lib/src/services/wifi_transport.dart`
  - Discovery, advertising, connection maintenance, keepalives, reconnect loops.
  - Emits location-related discovery failures.
- Bluetooth transport: `lib/src/services/bluetooth_transport.dart`
  - Classic Bluetooth send/receive with reconnect attempts.
- Session identity + capability merge: `lib/src/services/connection_manager.dart`
  - Maps transport IDs to stable crypto peer IDs.
  - Merges reconnect sessions by peer ID (`_mergeSessionsByPeerId`).
  - Tracks remote capabilities from handshake.
- Handshake payload: `lib/src/models/handshake_message.dart`
  - includes `runtimeProfile` and `supportsFileTransfer`.

### 1.4 Message Routing Layer
- Core router: `lib/src/services/mesh_router_service.dart`
  - Selects direct/mesh/broadcast mode.
  - Direct path uses immediate transport send (`_sendDirect`).
  - Mesh path uses route lookup + queue fallback.
  - Broadcast path delegates to `EmergencyBroadcastService`.
  - Subscribes to route updates and queue processes with debounce.
- Queue: `lib/src/services/message_queue.dart`
  - Exponential backoff using `next_retry_time`.
  - Per-peer cap (`maxMessagesPerPeer = 50`).
  - Global cap (`maxQueueSize = 5000`).
- Route manager: `lib/src/services/route_manager.dart`
  - Maintains route table, route discovery wrappers, stale/failure pruning.
  - Emits `onRouteUpdated`.
- Dedup + forwarding fingerprints: `lib/src/services/deduplication_cache.dart`
  - seen cache
  - forwarding fingerprint cache
  - per-message forwarded-to tracking.
- Message model: `lib/src/models/mesh_message.dart`
  - duration-based expiry support (`expiryDuration`, `isExpired`).
  - message types include route request/response and connection upgrade enums.

### 1.5 File Transfer Layer
- Protocol/state models: `lib/src/models/file_transfer.dart`
  - states: pending/transferring/verifying/completed/failed/paused/cancelled
  - direction: sending/receiving
  - message types: metadata, accept/reject, chunk, ack, resume, cancel, transferPaused, transferResumed
- Engine: `lib/src/services/file_transfer_service.dart`
  - 64KB chunks, sliding window, cumulative ACK.
  - resume support with persisted transfer state.
  - receiver chunk storage in per-transfer temp directory.
  - integrity verification (SHA-256) before final save.
  - cleanup behavior on cancel/failure.
  - sender-only pause/resume enforced in service logic.

### 1.6 Emergency Broadcast Layer
- Service: `lib/src/services/emergency_broadcast_service.dart`
  - destination sentinel: `BROADCAST_EMERGENCY`.
  - signed, not encrypted.
  - TTL and probabilistic forwarding decay.
  - per-sender rate limit (5/minute).
- UI: `lib/src/screens/emergency_broadcast_screen.dart`.

### 1.7 UI Structure
- Shell: `lib/src/screens/main_shell.dart`
  - tabs: Home, Messages, Peers, Emergency, Debug.
  - global location-failure popup.
  - global incoming-file request popup (works outside chat screen).
  - transfer state toasts (reject, cancel-by-peer, completed, sender paused/resumed notifications).
- Home: `lib/src/screens/home_screen.dart`
  - top-right battery-saver icon toggles emergency battery profile.
  - network profile chips now show direct/mesh.
- Chat list: `lib/src/screens/chats_list_screen.dart`
  - explicit split into Direct tab vs Mesh tab.
- Chat: `lib/src/screens/chat_screen.dart`
  - session badge (Direct or Mesh).
  - file attach button only when file transfer is allowed.
  - transfer strip for active transfers.
- File transfer screen: `lib/src/screens/file_transfer_screen.dart`
  - sender-only pause/resume controls.
  - receiver sees “Sender paused sending”.
- Received files history: `lib/src/screens/received_files_history_screen.dart`.

### 1.8 Persistence Layer
- Database: `lib/src/services/db_service.dart`, schema version `13`.
- Core tables:
  - `peers`
  - `chat_messages`
  - `message_queue` (includes `next_retry_time`, `expiry_time`)
  - `routes`
  - `deduplication_cache`
  - `blocked_peers`
  - `pending_acks`
  - `peer_keys`
  - `known_wifi_endpoints`
  - `file_transfers`
  - `broadcast_messages`

## 2) Intentional Changes Already Applied

These are the key behavior changes intentionally made in this branch:

- Added runtime-profile capability exchange in handshake.
  - File transfer availability is now profile/capability-aware per peer.
- Enforced chat/session split semantics:
  - Direct chat list contains only peers where both sides are in direct profile and directly connected.
  - Others appear in mesh list.
- Kept emergency broadcast as dedicated channel and UI tab.
- Added battery saver quick toggle as icon near “PeerChat Secure” title.
  - Removed battery mode from network-profile chip list.
- Added global runtime location-failure UX:
  - popup + “Open Settings” path when discovery/reconnect fails due to location constraints.
- Added global incoming-file request popup in shell:
  - appears from any screen, includes sender identity and file size.
- Added file-size formatter for user-facing displays:
  - exact boundary behavior:
    - `< 1 MB` displays as `KB` (effectively up to `1024.00 KB`)
    - `>= 1 MB` and `< 1 GB` displays as `MB` (effectively up to `1024.00 MB`)
    - `>= 1 GB` displays as `GB` (effectively up to `1024.00 GB` and beyond in same unit scale)
  - utility: `lib/src/utils/file_size_formatter.dart`.
- Added fast profile-state reflection path across peers:
  - local profile change in `AppState.setRuntimeProfile(...)` updates router immediately,
  - `ConnectionManager.setRuntimeProfile(...)` rebroadcasts handshake capabilities immediately and again after ~700ms,
  - remote side updates `peerRuntimeProfile` and `supportsFileTransfer` from handshake,
  - chat/file-transfer UI gating updates from these runtime values.
- File transfer controls refined:
  - sender-only pause/resume.
  - receiver gets status (“Sender paused sending”), no pause/resume controls.
  - pause takes effect faster in send loop.
- Cancellation behavior normalized:
  - receiver partial chunk artifacts are removed on cancel paths.
  - sender source file is not deleted.
- Sender toasts now include:
  - receiver rejected file,
  - receiver canceled transfer,
  - successful file send completion.
- Incoming request cancel-before-response behavior:
  - active incoming dialog auto-dismisses when sender cancels.

## 3) Current Behavioral Rules (Important for Migration)

### 3.1 Chat Classification Rule
- Direct chat visibility requires all:
  - local profile is `normalDirect`,
  - remote profile is `normalDirect`,
  - direct connectivity exists.
- Otherwise chat is considered mesh.
- If one side switches profile mid-conversation, classification is expected to shift quickly after capability handshake refresh (not only on app restart).

### 3.2 File Transfer Availability Rule
- Transfer is allowed only when:
  - direct session is valid (rule above),
  - remote handshake reports `supportsFileTransfer = true`.
- If either side is mesh/emergency profile, transfer actions are disabled.

### 3.3 Pause/Resume Rule
- Only sender may pause/resume.
- Receiver reflects paused/resumed sender state and can still cancel.
- Resume uses explicit control signaling (`transferResumed`) and receiver sends `resumeFrom`.
- Receiver never gets pause/resume action buttons in transfer UI; receiver sees status text and notifications only.

### 3.4 Cancel Rule
- If sender cancels:
  - receiver receives cancel event,
  - receiver partial chunks/temp artifacts are removed.
- If receiver cancels:
  - receiver local partial chunks/temp artifacts are removed,
  - sender is notified via toast.
- In either case transfer DB state for that transfer is removed.

### 3.5 Emergency Broadcast Rule
- Signed, not encrypted.
- 5 messages/minute per sender limit.
- Probabilistic decay after hop 2 to avoid amplification.

## 4) Data and Protocol Notes (LLM Critical)

- Mesh message IDs are kept within fixed-width wire constraints.
- File transfer IDs are compacted to fit protocol fixed-width constraints.
- `MeshMessage` expiry is duration-based (`expiryDuration`) with `isExpired`.
- `message_queue` also stores an `expiry_time` column for DB-level filtering.
- `file_transfers.received_chunks` persists highest contiguous chunk + 1.
- Transfer protocol marker is custom (`0xFE`) in `FileTransferService`.

## 5) What Is Done vs Pending (Against `implementation_plan.md`)

Status legend:
- `DONE`: behavior exists in code now.
- `PARTIAL`: some pieces exist, plan intent not fully implemented.
- `PENDING`: not implemented.

### Phase 1 (Mode separation and direct messaging)
- Status: `DONE` (core behavior implemented).
- Notes:
  - `CommunicationMode` model exists.
  - direct/mesh/broadcast routing is active in `MeshRouterService`.
  - queue trigger on route updates and peer events exists.
  - peer merge by stable `peerId` is implemented.

### Phase 2 (Queue improvements)
- Status: `DONE` for backoff/per-peer limits and retry gating.
- Notes:
  - exponential backoff + `next_retry_time` exists.
  - per-peer limit exists.
  - route stale/failure pruning exists.

### Phase 3 (Controlled lazy flooding)
- Status: `DONE` (opportunistic forwarding + dedup fingerprints present).

### Phase 4 (File transfer system direct-only)
- Status: `DONE` for main engine + UI.
- Notes:
  - chunking, cumulative ACK, resume, crash recovery, disk checks implemented.
  - sender-only pause/resume behavior implemented.
  - global incoming transfer UX implemented.

### Phase 5 (Emergency broadcast)
- Status: `DONE` (service + UI + DB + rate limiting + decay).

### Phase 6 (Transport upgrades)
- Status: `PARTIAL`.
- Done:
  - `MessageType.connectionUpgradeRequest/Response` enums exist.
- Pending:
  - no active connection upgrade workflow in router/service.
  - no dedicated transport interface callbacks `onConnectionLost/onConnectionRestored` as abstract API design requirement.

### Phase 7 (Network-awareness adaptive stats usage)
- Status: `PARTIAL`.
- Done:
  - send/deliver/fail counters and `deliverySuccessRate` exist.
- Pending:
  - adaptive TTL/queue behavior driven by stats is not implemented.

### Phase 8 (Edge hardening)
- Status: `PARTIAL`.
- Done:
  - queue limits, stale transfer abort, crash recovery, broadcast spam controls.
- Pending:
  - ACK storm batching and specified ACK retry schedule (5/15/45 min style) are not implemented in current code.

### Phase 9 (Energy + Android constraints)
- Status: `PARTIAL`.
- Done:
  - adaptive discovery policy with battery and runtime profile.
  - battery polling and location-settings recovery flow.
  - battery optimization exemption request attempt.
- Pending:
  - no dedicated `foreground_service.dart` implementation.
  - no explicit foreground-service notification channel behavior.
  - explicit WiFi-primary + BT fallback orchestration for file transfer performance policy remains basic (transport tries available transports sequentially).

## 6) Migration Risks / Gotchas

- Worktree has many changes across files; treat `git status` as active/in-progress state.
- Several plan items are reflected as comments/intents but not complete runtime behavior.
- `RouteManager` discovery flow exists but should be reviewed carefully for large-scale mesh behavior.
- Transport layer is multi-transport but not a full policy engine (no throughput-based path optimizer yet).
- Broadcast, file-transfer, and mesh message paths coexist; maintain protocol markers and ID-length assumptions during refactor.

## 7) Suggested Immediate Next Steps After Migration

- Re-run baseline checks:
  - `flutter analyze`
  - `flutter test`
  - device-to-device smoke tests for direct + mesh + transfer + emergency
- Implement missing Phase 6/7/8/9 items in this order:
  1. connection-upgrade workflow and transport resume callbacks
  2. adaptive runtime tuning from delivery stats
  3. ACK batching/retry policy hardening
  4. Android foreground service implementation
- Add integration tests for:
  - profile transitions mid-conversation,
  - sender/receiver cancel races,
  - pause/resume correctness and UI reflection timing.

## 8) Requirement Coverage Checklist (Conversation-Specific)

This checklist maps the user-requested behavior changes to current implementation state.

- Direct chat appears only when both peers are in direct profile and directly connected.
  - Covered by `AppState.isDirectSessionWithPeer(...)` and direct/mesh split in `lib/src/screens/chats_list_screen.dart`.
- If one peer is direct and the other is mesh, chat is treated as mesh; switching profile mid-conversation reflects quickly.
  - Covered by handshake capability updates in `ConnectionManager` and profile propagation via `AppState.setRuntimeProfile(...)`.
- File transfer availability must be disabled when remote peer is not direct-capable.
  - Covered by remote `runtimeProfile` + `supportsFileTransfer` gating in `ConnectionManager`/`AppState`.
- Direct<->mesh state reflection should be near-instant in both UIs.
  - Covered by immediate + delayed capability rebroadcast path (`ConnectionManager.setRuntimeProfile(...)`).
- Incoming file requests should appear on almost any screen and show sender identity.
  - Covered by global shell-level incoming popup in `lib/src/screens/main_shell.dart`.
- File size display boundaries should follow 1024-based unit transitions.
  - Covered by `lib/src/utils/file_size_formatter.dart` and documented as KB/MB/GB threshold behavior.
- Sender should receive toast when receiver rejects transfer.
  - Covered by transfer-state toast handling in `lib/src/screens/main_shell.dart`.
- If sender cancels before receiver accepts/rejects, pending incoming request UI should disappear.
  - Covered by cancel handling in `FileTransferService` + global incoming dialog dismissal in shell UI.
- Pause/resume should be sender-only; receiver should not have those controls and should see paused status.
  - Covered by sender-side control gating and receiver status UX in `lib/src/screens/file_transfer_screen.dart` + `FileTransferService`.
- Cancel behavior should remove partial chunks (sender/receiver cancel paths) and notify sender on receiver cancel.
  - Covered by receiver temp cleanup + sender toast in `FileTransferService` and shell toast handlers.
- Sender should receive completion toast when file send succeeds.
  - Covered by completed transfer toast in `lib/src/screens/main_shell.dart`.
