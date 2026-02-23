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

## Phase 16: Java LTS Upgrade (Feb 23, 2026)
- [x] Install Java 21 LTS (Oracle JDK) via `winget`
- [x] Remove Java 8 (Red Hat OpenJDK)
- [x] Update `JAVA_HOME` and `Path` environment variables
- [x] Verify Gradle compatibility (Fix "Dependency requires at least JVM runtime version 11")
- [x] Success: `flutter build apk` completed

## Phase 17: UI/UX Modernization (Feb 23, 2026)
- [x] Create dark-mode-first theme (`theme.dart`) with teal/cyan palette, glassmorphism helpers
- [x] Add `google_fonts` (Inter) dependency, update `main.dart` theme setup
- [x] Redesign `home_screen.dart` — gradient AppBar, glass tiles, privacy panel
- [x] Redesign `identity_card.dart` — avatar with glow, copy-key button, styled QR
- [x] Redesign `mesh_status_card.dart` — stat chips, gradient P2P badge
- [x] Redesign `chats_list_screen.dart` — colored avatars, online dots, teal badges
- [x] Redesign `chat_screen.dart` — gradient bubbles, dark input bar, lock indicator
- [x] Redesign `peers_screen.dart` — modern tabs, initials avatars, status pills
- [x] Redesign `add_peer_screen.dart` — gradient scan button, crosshair overlay, glass cards
- [x] Redesign `peers_list.dart` — consistent dark styling
- [x] `flutter analyze`: No issues found

## Phase 17b: Navigation Restructure (Feb 23, 2026)
- [x] Create `main_shell.dart` — custom bottom nav (Home, Messages, Peers, Debug)
- [x] Simplify `home_screen.dart` — QR identity + mesh status only, popup menu
- [x] Redesign mesh status — stat grid with LIVE/IDLE badge, connected/discovered counts
- [x] Fix chat seen status — bright lime green icon for high contrast on teal gradient
- [x] Reverse peer tabs — Discovered first, Connected second
- [x] Apply dark theme to `routing_debug_screen.dart`
- [x] `flutter analyze`: No issues found

## Phase 19: Message Queue Size Limits & Prioritization (Feb 23, 2026)
- [x] Implemented a strict 5000-message maxQueueSize limit in MessageQueue`n- [x] Added _enforceQueueLimit() to automatically drop the oldest, lowest priority messages when the limit is exceeded
- [x] lutter analyze verified successful implementation

## Phase 18: Full Architecture Implementation (Feb 23, 2026)
### Phase 1: Mode Separation - DONE
- [x] Created communication_mode.dart, added mode check + sendDirect + debounce + sender-prefixed IDs
- [x] Strengthened peer identity persistence, deleted simple_message_service.dart
- [x] flutter analyze: No issues found

### Phase 2: Mesh Queue Improvements - DONE
- [x] Clock-independent expiryDuration on MeshMessage, exponential backoff, per-dest limit (50/peer)
- [x] Route failure-rate pruning (>70%), DB v10 migration, getReadyMessages()
- [x] flutter analyze: No issues found

### Phase 3: Controlled Lazy Flooding - DONE
- [x] Forwarding fingerprint dedup, lazy flood to 2-3 random peers, forwardedTo tracking
- [x] flutter analyze: No issues found

### Phase 4: File Transfer System - DONE
- [x] Model, Service (sliding window, cumulative ACKs, SHA-256), DB v11
- [x] Composition Root injection in AppState
- [x] Protocol wiring (0xFE) in MeshRouterService
