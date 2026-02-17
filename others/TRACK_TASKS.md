# Mesh Routing Implementation Phases

## Phase 1: Dependencies and Infrastructure
- [x] Fix `pubspec.yaml` formatting issues
- [x] Add required dependencies (`sodium_libs`, `uuid`)
- [x] Verify dependency installation

## Phase 2: Data Layer Implementation
- [x] Create Database Schema Extensions (Message Queue, Routes, Dedup Cache, Blocked Peers, Pending Acks)
- [x] Implement `DBService` extensions
- [x] Create Data Models (`MeshMessage`, `Route`, `QueuedMessage`, `RouteRequest`, `RouteResponse`)

## Phase 3: Cryptography and Core Services
- [x] Implement/Verify `SignatureVerifier` (Sodium crypto_sign)
- [x] Implement/Verify `MessageManager` (Encryption/Decryption/Signing)
- [x] Implement/Verify `DeduplicationCache`

## Phase 4: Routing Logic
- [x] Implement `RouteManager` (Route discovery, table management)
- [x] Implement `MessageQueue` (Store-and-forward logic)
- [x] Implement `MeshRouterService` main coordinator

## Phase 5: UI Integration & Testing
- [x] Create routing debug UI
- [x] Integrate with existing Chat UI (real-time incoming messages)
- [ ] Test multi-hop scenarios (requires 3+ Android devices)

## Phase 6: Project Cleanup
- [x] Move documentation files to `others/`
- [x] Update `.gitignore`
- [x] Fix lint errors (flutter analyze)
- [x] Verify project build (flutter build apk)

## Phase 7: Critical Bug Fixes (Feb 17, 2026)
- [x] Fix `MeshRouterService.init()` — 7 `late final` services were never initialized (crash on any connection)
- [x] Add real-time incoming message stream (`StreamController<ChatMessage>`)
- [x] Wire `ChatScreen` to subscribe to incoming message stream for live updates
- [x] Wire `DeliveryAckHandler.notifyDeliveryConfirmed()` to update message status in DB
- [x] Fix `DeliveryAckHandler._getPublicKeyFromPeerId()` — fetch correct key type from DB
- [x] Remove duplicate `dispose` in `ChatScreen`
- [x] Update README to honest status

## Phase 8: Fix Duplicate Discovery & Message Delivery (Feb 17, 2026)
- [x] Stop persisting raw Bluetooth peers to DB — only handshake-confirmed peers appear
- [x] Add direct route in `RouteManager` after handshake completes (using crypto ID, not MAC)
- [x] Delete old MAC-based peer entry from DB on handshake to prevent duplicates
- [x] Fix missing `Peer` import in `peers_list.dart`
- [x] Remove duplicate `addRoute` method in `route_manager.dart`

## Phase 9: Exchange Encryption Keys via Handshake (Feb 17, 2026)
- [x] Update `HandshakeMessage` to include `encryptionPublicKey`
- [x] Update `DBService` to store both key types
- [x] Update `ConnectionManager` to exchange and save both keys
- [x] Update `MessageManager` and `SignatureVerifier` to use correct key types

## Phase 10: Chat List & Unread Badges (Feb 17, 2026)
- [x] Upgrade DB to version 7 (isRead status)
- [x] Implement `getUnreadMessageCounts` and `markMessagesAsRead`
- [x] Add real-time unread tracking to `AppState`
- [x] Create `ChatsListScreen` with unread badges
- [x] Refactor `HomeScreen` navigation and `ChatScreen` auto-read logic

## Phase 11: Identity Synchronization (Feb 17, 2026)
- [x] Unify name generation to use Signing Key (Peer ID)
- [x] Ensure `PeersList` and `ChatsListScreen` prioritize handshake-provided names
- [x] Clean up redundant key management in `AppState`
- [x] Fix: Sent messages incorrecty triggering unread badges

## Phase 12: Debugging Infinix Startup Crash (Feb 17, 2026)
- [x] Unified fatal error trapping in `main.dart`
- [x] Defensive `try-catch` blocks in `AppState` initialization
- [x] Hardened `NameGenerator` sublist operations
- [x] Reinstalled debug APK on Infinix device

## Phase 13: Received & Seen Indicators (Feb 17, 2026)
- [x] Implemented message acknowledgments for "Received" (double grey check)
- [x] Implemented "Read Receipts" for "Seen" (double blue check)
- [x] Real-time mesh transmission of receipts
- [x] UI status icons for all message stages

## Phase 14: UI Audit (Persistence & Privacy) (Feb 17, 2026)
- [x] Update UI to communicate local-only storage
- [x] Add privacy indicators for P2P/E2EE encryption
- [x] Clarify that data is lost if app is uninstalled

## Phase 15: Mesh Reliability Debugging (Feb 17, 2026)
- [x] Debug "Pending ACKs / Queued Messages" synchronization issue
- [x] Fix reverse routing logic (ensure recipient can find sender)
- [x] Optimize ACK transmission reliability
