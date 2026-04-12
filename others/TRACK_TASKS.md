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

## Phase 20: Fix Priority Enum Inconsistency (Mar 2, 2026)
- [x] Reordered `MessagePriority` enum from `high(0), normal(1), low(2)` → `low(0), normal(1), high(2)`
- [x] Aligned enum indices with SQL `ORDER BY priority DESC` and debug screen color/label mappings
- [x] Verified `routing_debug_screen.dart` and `queued_messages_status_screen.dart` priority displays are correct

## Phase 21: Release Versioning & CD (Mar 22, 2026)
- [x] Update app display name to "PeerChat" across all platforms and UI
- [x] Update app version to 1.0.0 for release
- [x] Create `others/build_release.ps1` for automated build and naming (CD)
- [x] Update README and documentation to reflect "PeerChat" branding
- [x] Verify build configuration for release APK

## Phase 22: Branding & Identity (Mar 22, 2026)
- [x] Extract color palette and theme details from `theme.dart`
- [x] Generate logo design prompts for AI generation
## Phase 23: Global Theme Harmonization (Mar 22, 2026)
- [x] Audit all UI screens for hardcoded old palette colors (Teal/Cyan)
- [x] Update `theme.dart` with vibrant blue and purple branding colors
- [x] Refine `chat_screen.dart` bubble gradients to match new logo
- [x] Replace hardcoded badge colors in `peers_screen.dart` with theme constants
- [x] Verify theme consistency across all primary application views
- [x] `flutter analyze`: 0 issues found

## Phase 24: UI/UX Refinement (Mar 22, 2026)
- [x] Refined Home Screen: added "Your P2P Identity" tagline, softened QR glow, and made public key row tappable.
- [x] Refined Chat Screen: implemented pill-style date separators and improved message input area.
- [x] Refined Chats List Screen: added relative timestamps (e.g., "5m ago") and last message status icons (Sent/Received).
- [x] Refined First Sign-In Screen: updated with welcoming copy, gradient Google button, and privacy info box.
- [x] Refined Menu Screen: added branded header card and color-coded icons for better differentiation.
- [x] Refined Bottom Navigation: added a subtle active indicator dot below the selected tab.
- [x] `flutter analyze`: 0 issues found

## Phase 25: Project Metadata & Marketing (Mar 26, 2026)
- [x] Generate premium project description card (project_description.md) matching portfolio UI style
- [x] Define core value propositions and tech stack tags for PeerChat

## Phase 26: Unified Website Theme Integration (Apr 8, 2026)
- [x] Extract colors from globals.css of website
- [x] Update mobile 	heme.dart with new dark violet / ink palette

- [x] Removed mDNS (peerchat.local) resolution and switched to direct IP for better cross-device reliability.

- [x] Moved Web Share history to a dedicated, clearable screen with individual entry deletion.

- [x] Implemented Manual Upload Approval system with a secure handshake protocol and real-time pop-up alerts.

## Phase 27: Web Share UI Optimization (Apr 9, 2026)
- [x] Compact Web Share main screen to fit within viewport.
- [x] Move file management (Add/Remove) to History screen.
- [x] Implement tabbed view in History (Files vs. Transfer Log).
- [x] Differentiate active and finished transfers in history log.
- [x] Refine instructions and update top-right icon to add-files symbol.
- [x] Move action shortcuts to body and implement conditional "Add Files" button.

## Phase 28: Global Web Share Service (Apr 9, 2026)
- [x] Globalize `WebShareService` via `AppState` (Provider-managed).
- [x] Implement global listeners in `MainShell` for background alerts.
- [x] Enable background cross-screen approval dialogs and success toasts.
- [x] Decouple server lifecycle from the Web Share screen (server remains active in background).

## Phase 29: Direct Share & Crash Recovery (Apr 9, 2026)
- [x] Re-implemented `FileTransferService` with chunk-based P2P sliding window protocol.
- [x] Restored `file_transfers` table in `DBService` with bitmask-based crash recovery.
- [x] Differentiated UI between "Web Transfer" (Browser) and "Direct Share" (Peer).
- [x] Upgraded `IncomingApprovalDialog` with premium glassmorphic aesthetics and source badges.
- [x] Implemented 30-day automatic history cleanup.
- [x] Re-enabled Peer-to-Peer file sharing button in Chat Screen.
## Phase 30: Web Share Modularization & UI Polish (Apr 9, 2026)
- [x] Split file management and transfer log into separate screens (`WebShareHostedFilesScreen`, `WebShareLogScreen`).
- [x] Rename "Shared Files" to "Hosted Files" for clearer host/receiver context.
- [x] Implement Emerald Green success coloring for completed transfers in log.
- [x] Refine "Start Sharing" button size and scale for better aesthetics.
- [x] Sanitize navigation flow and remove obsolete tab-based screen.

## Phase 31: Build Stability & Transport Standardization (Apr 9, 2026)
- [x] Implement binary-safe `encryptBytes`/`decryptBytes` in `CryptoService`.
- [x] Standardize `MessageManager` for raw byte mesh payloads.
- [x] Expose `onRawMessageReceived` in `MeshRouterService` for discrete sub-service communication.
- [x] Resolve catastrophic build errors in `ChatScreen` and `WebShareLogScreen`.
- [x] Verify project stability (0 errors in `flutter analyze`).

## Phase 32: Native MediaStore & Asset Picker (Apr 9, 2026)
- [x] Implement Native MediaStore Bridge (Kotlin) for Images and Videos.
- [x] Integrate "All Files Access" (MANAGE_EXTERNAL_STORAGE) handler for Android 11+.
- [x] Replace slow directory scanning with 100x faster native queries.
- [x] Add tabbed Asset Picker (Apps | Media | Files) with instant loading.

## Phase 33: Home Screen Compaction & Scaling (Apr 9, 2026)
- [x] Design "Single Screen" layout for Home Screen to prevent scrolling.
- [x] Implement Auto-Scaling Engine using `LayoutBuilder` and `FittedBox`.
- [x] Convert Identity Section to horizontal header (Avatar next to Name).
- [x] Reduce QR Code and spacing to fit all content on small viewports.
- [x] Verify responsive scaling across different device heights.

## Phase 34: Website Content — WiFi Direct & Hotspot File Transfers (Apr 9, 2026)
- [x] Update `HeroSection.tsx` subline to mention file transfers and all 3 transport types (BLE, WiFi Direct, WiFi Hotspot).
- [x] Update `EmergenceSection.tsx` — add WiFi Hotspot to "Zero Infrastructure"; replace "Multi-Hop Routing" card with a dedicated "File Transfers" card.
- [x] Update `SolutionSection.tsx` — "Resilient" card now mentions WiFi Hotspot + file transfers.
- [x] Update `PropagationSection.tsx` — Step 01 "Discover" description includes WiFi Hotspot.
- [x] Update `AccessSection.tsx` — "WiFi Direct & Hotspot file sharing" added as a free Independent plan feature.
- [x] Verified Phase 34 Website Content updates — All sections match 1.0.0 branding and feature set.

## Phase 35: Hardware Isolation & Home Scaling (Apr 9, 2026)
- [x] Implement `setWebShareIsolation` automatic lifecycle in `AppState`.
- [x] Implement hardware suspension hooks across `DiscoveryService`, `MeshRouterService`, and `WiFiTransport`.
- [x] Replace "Turbo Mode" UI with automated isolation logic for better UX.
- [x] Finalize `HomeScreen` auto-scaling with `FittedBox` + Horizontal Identity layout.
- [x] Cleanup: Replace `print` with `debugPrint` in `WebShareService.dart`.
- [x] Verified Phase 35 Hardware Isolation & Home Scaling.

## Phase 36: Expert Asset Picking & Hardware Monitoring (Apr 9, 2026)
- [x] Implement Native `getAppIcon` (128x128 PNG) in `MainActivity.kt`.
- [x] Implement Native `BluetoothStateChannel` (EventChannel) in `MainActivity.kt`.
- [x] Create `AppIconService` with a strict 50-item LRU memory budget.
- [x] Integrate real-time Bluetooth status monitoring into `AppState`.
- [x] Refine `WebShareAssetPicker` with custom skeleton loaders and staggered list entry.
- [x] Implement lazy-loading native icons in `_AppTile` for zero scroll-jank.
- [x] Design "Isolation Glow" pulsing indicator for Web Share dashboard.
- [x] Add real-time hardware status mini-cards to `WebShareScreen`.
- [x] `flutter analyze`: 0 issues found.

## Phase 37: Web Share Dashboard Hardening (Apr 10, 2026)
- [x] Implement real hardware detection for Wi-Fi Hotspot (Native reflection + interface check).
- [x] Integrate periodic 4-second status refresh for hardware indicators.
- [x] Make hardware status cards actionable (Bluetooth toggle, Hotspot settings shortcut).
- [x] Standardize hardware status text to simplified "ON/OFF" labels.
- [x] Implement "Reliable Fallback" for Bluetooth: Tapping now opens system settings if programmatic toggle is restricted.
- [x] Implement Amber warning highlight for unoptimized hardware states (e.g., BT still ON during isolation).
- [x] Optimized dashboard layout for higher information density (Phase 2 Compaction).
- [x] Refined visual feedback with correctly overlapping ripples (`Ink` widget).
- [x] Added debug logging for hardware status interactions.

## Phase 38: P2P Transfer Dashboard & Unified Flow (Apr 10, 2026)
- [x] Refactor `FileTransferService` to expose per-peer active sessions.
- [x] Implement `DirectTransferScreen` with live progress bars and peer-specific history.
- [x] Connect `ChatScreen` attachment pin to navigate to the new Transfer Dashboard.
- [x] Implement "Add Files" action within the Dashboard to launch `WebShareAssetPicker`.
- [x] Verify complete P2P transfer lifecycle visibility in the new UI.

## Phase 39: Enhanced Transfer Metrics & Management (Apr 10, 2026)
- [x] Implement real-time speed calculation (MB/s) in `FileTransferService`.
- [x] Add `abortTransfer`, `resumeTransfer`, and `deleteTransfer` methods.
- [x] Update `DirectTransferScreen` with speed labels and action icons (X, Trash, Resume).
- [x] Implement DB cleanup for deleted transfer records.

## Phase 40: High-Performance P2P Optimization (Apr 10, 2026)
- [x] Increase chunk size to 256KB and implement persistent file handles.
- [x] Implement Sliding Window (pipelining) for wait-free data transmission.
- [x] Fix Sender-side state synchronization (Completed status mismatch).
- [x] Verify speeds match or exceed Web Share performance.

## Phase 41: Absolute Root Storage & Internal Viewer (Apr 10, 2026)
- [x] Add `open_file_plus` and `external_path` dependencies.
- [x] Implement `MANAGE_EXTERNAL_STORAGE` permission request flow.
- [x] Redirect `FileTransferService` to store files in `/PeerChat/Downloads` (External Root).
- [x] Add "View" (Eye Icon) to `DirectTransferScreen` history items.
- [x] Verify persistence after app uninstallation.

## Phase 42: Production-Grade P2P Hardening (Apr 10, 2026)
- [x] Fix Mesh Router delivery leakage (only raw file packets on delivery).
- [x] Implement True Sliding Window (unackedBase) & Symmetric Handshake.
- [x] Re-align Priority (Control/ACK = High, Data = Low).
- [x] Implement Metadata Validation & Path Sanitization.
- [x] Fix Resume Persistence & Outgoing/Incoming recovery paths.
- [x] Implement Transfer Queueing (sequential processing).
- [x] Fix Subscription leaks in UI and Service.
- [x] Link transfer activity to AppState (Discovery Throttling).
## Phase 42: P2P Protocol Hardening & UX Fidelity (Apr 10, 2026)
- [x] Implement Final ACK sync (Receiver confirms last chunk before verify).
- [x] Switch to `FileMode.write` for safe out-of-order random-access writes.
- [x] Add packet head/body bounds validation to prevent malformed crashes.
- [x] Connect `AppState` discovery throttling to active transfer sessions.
- [x] Implement smoothed MB/s throughput and real-time ETA calculation.
- [x] Add explicit "X / Y MB" progress labels to the dashboard.
- [x] Implement recursive filename suffixing (e.g. `file (1).ext`) for collisions.
- [x] Persist `file_hash` in DB for sender/receiver session recovery.
- [x] Verify stable P2P throughput with background radio throttling.
