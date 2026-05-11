# PeerChat: System Architecture & Flow

This document outlines the architectural logic, protocol flows, and operational invariants of PeerChat. It is the absolute source of truth for implementation details and design trade-offs.

---

## 1. Core Identity & Persistence Flow

PeerChat uses a **Hardware-Linked Cryptographic Identity** model.

### A. The Identity Seed
1.  **Entropy Source**: Fetches a stable hardware identifier:
    - **Android**: `androidInfo.id`
    - **iOS**: `identifierForVendor`
    - **Windows**: `windowsInfo.deviceId`
2.  **Key Generation**:
    - **Seed**: `SHA-256("PeerChat_${purpose}_v1_$hardwareId")`.
    - **Encryption**: X25519 (`sodium.crypto.box.seedKeyPair`).
    - **Signing**: Ed25519 (`sodium.crypto.sign.seedKeyPair`).
3.  **Justification**: Hardware linking eliminates the need for central registration. The $O(1)$ identity derivation ensures zero-knowledge privacy from the start.

### B. The 2x2 Name Resolution Matrix

| Scenario | State | Visual Result |
| :--- | :--- | :--- |
| **New Discovery** | Peer not in DB | **Generated Name** (Deterministic via `NameGenerator`) |
| **Known (No Alias)**| Peer in DB, no custom name | **Generated Name** (Stable per PeerID) |
| **Known (Named)** | Peer in DB with alias | **Custom Name** (User-defined) |
| **Identity Shift** | PeerID change detected | **System Notification** ("X is now Y") |

---

## 2. Discovery & Connectivity Flow

### A. The Discovery Lifecycle
1.  **Passive Discovery**: Continuous mDNS lookup (WiFi) and BLE advertisement monitoring.
2.  **Active Discovery**: Periodic Bluetooth scans with **Adaptive Jitter** (max 3,000ms) to prevent device synchronization collisions.
3.  **The "Handshake" Invariant**:
    - Every new connection triggers a `HandshakeMessage` exchange containing: `peerId`, `signingPublicKey`, `encryptionPublicKey`, and `runtimeProfile`.
    - **State Transition**: Connection status moves from `connecting` $\rightarrow$ `handshakePending` $\rightarrow$ `connected`.

### B. Adaptive Policy (Battery Logic)
The system thresholds are governed by the OS battery state:
- **Low Battery Threshold**: **20%**.
- **The 2x Rule**: When battery < 20%, all discovery scan intervals are **automatically doubled**.
- **Fast Burst**: On app start/resume, the app enters a 40s "Fast Burst" window with aggressive scanning.

---

## 3. Messaging & Routing Flow

### A. Message Lifecycle
1.  **Encryption**: X25519 Box (Nonce + Ciphertext).
2.  **Dedup Invariant**:
    - **Fingerprint**: `$messageId-$senderId-$hopCount`.
    - **Justification**: Including `hopCount` allows the mesh to replace an existing route if a "better" (lower hop) path for the same message is discovered later.
3.  **Clock-Independent Expiry**:
    - `age = now - sender_timestamp`.
    - If `age > expiry_duration` $\rightarrow$ Drop.
    - **Justification**: Ignores absolute system clocks to handle mesh device drift.

### B. The Priority System

| Priority | Index | Network Behavior |
| :--- | :--- | :--- |
| **High** | 0 | SOS/Routing. Skips buffers; processed first. |
| **Normal** | 1 | Private Chats. Standard reliability. |
| **Low** | 2 | Maintenance/Sync. Lowest priority. |

*   **Eviction**: At `maxQueueSize` (5,000), **Low** and **Normal** messages are pruned first.

### C. Causal "Breadcrumb" Routing
- **The Flow**: Every incoming message (relay or direct) causes the `RouteManager` to learn a route back to the sender via the immediate neighbor.
- **Hop Penalty**: `learned_hop_count = message.hopCount + 1`.
- **Justification**: Dramatically reduces the need for explicit `RouteRequest` floods.

---

## 4. Emergency Broadcast Flow

### A. The Flooding Logic
- **Fanout**: Messages are forwarded to 2 to 3 random peers.
- **Probabilistic Decay**: After **Hop 2**, messages have a **50% drop chance** per relay.
- **Justification**: This "Gossip Pruning" prevents broadcast storms and radio saturation in dense mesh environments.

### B. History Synchronization
- **Catch-up Sync**: On every new connection, peers exchange the **60 most recent** broadcasts.
- **Quota**: Senders are limited to **3 broadcasts per minute** globally to prevent mesh-wide spam.

---

## 5. Web Share Bridge (Radio Isolation)

### A. Operational Flow
- **Port**: 8080 (HTTP).
- **Security**: Approval-based handshake $\rightarrow$ Single-use UUID token $\rightarrow$ Data Stream.

### B. Radio Isolation Invariant
- **The Rule**: When Web Share is active, `MeshRouter` and `DiscoveryService` are **Suspended**.
- **Justification**: WiFi Direct and the HTTP server cannot reliably share the radio on many chipsets without packet collision or hardware hangs.

---

## 6. Offline Map Flow

PeerChat uses a custom, MIT-licensed tile caching system to provide location context without internet.

### A. Connectivity-Aware UI (The "Blind" State)
- **Invariant**: The map screen performs a 3s DNS lookup on entry.
- **Blind State**: If `No Internet` AND `No Offline Cache` for the current area, the UI MUST display an explicit **"Map Unavailable"** overlay with a retry option.
- **Justification**: Prevents the "Blank Map" failure mode, ensuring the user understands exactly why the map is not rendering.

### B. Storage Hard Limit (250 MiB)
- **The Rule**: The `TileCacheService` **blocks new tile saves** once the local cache hits **250 MiB**.
- **Justification**: Protects device storage from being filled by background map browsing while still allowing live viewing (RAM-only) if internet is available.

---

## 7. Durable State Trace (Event Sourcing)

PeerChat uses an ACID-compliant event log to reconstruct system state and provide an audit trail.

### A. Non-Blocking Persistence
- **Write Buffer**: Events are held in a **1000-event** queue to prevent UI jank.
- **Flush Policy**: The buffer flushes to SQLite every **500ms** or at **50 events**.
- **Retention**: Log is capped at **10,000 events** via asynchronous pruning.

---

## 8. Runtime Profiles & Battery Orchestration

### A. Profile Side Effects
- **Emergency Battery**: Triggered at **20% battery**. Disables "Fast Bursts" and doubles heartbeats.
- **Web Share Isolation**: Suspends Bluetooth and Nearby Connections. Toggles hardware Bluetooth off to prevent radio hangs.

---

## 9. App Lifecycle & Recovery

### A. The "Resume Kick"
- **Cooldown**: 12 seconds.
- **Logic**: On resume with 0 peers, forces **`restartWiFiDirect()`** and **`startFastDiscoveryBurst()`**.

---

## 10. Memory & Cache Invariants

- **App Icon Cache**: **50-item** LRU cap.
- **Peer Visibility Window**: **5-minute** TTL for "Discovered" peers without a signal.

---

## 11. System Resilience & Numerical Invariants

| Constant | Value | Reason |
| :--- | :--- | :--- |
| **Mesh Depth** | 16 Hops | Absolute cutoff to prevent infinite loops. |
| **WiFi Peer Cap**| 50 Peers | Hardware limitation of WiFi chips. |
| **Message Limit**| 48 KiB | Stability threshold for Bluetooth/RAM. |
| **Heartbeat** | 15s | Background keep-alive interval. |
| **Resume Kick** | 12s Cooldown| Hard restart of WiFi stack on resume. |
| **Discovery Window**| 5 Minutes | Activity window for "discovered" peers. |
| **Event Buffer** | 1000 Events | RAM budget for non-blocking logging. |
| **Log Retention**| 10k Events | Storage cap for audit trail. |
| **Icon Cache** | 50 Items | Memory cap for app assets. |
| **Map Radius** | 10-50km | Safety range for offline context. |
| **Map Storage** | 250 MiB | **Hard Limit** to prevent disk overflow. |
| **Internet Timeout**| 3s | Threshold for map connectivity check. |

---

## 12. UI Visibility Policies

1.  **Sticky Peers**: Active sockets keep peers in "Connected" indefinitely.
2.  **Discovery Pruning**: Ghost peers removed after **5 minutes**.
3.  **Battery Awareness**: Intervals doubled and bursts disabled < **20%**.
4.  **Blind State Invariant**: Explicit UI error if Internet=Off and Cache=Off. Coordinate acquisition remains priority.
5.  **Identity Trace**: Sequence numbers (AUTOINCREMENT) in `event_log` are used to reconstruct peer history.
6.  **Orientation Safety**: 
    - Full-screen maps must reposition overlays (badges/cards) in Landscape mode.
    - All bottom sheets must use `Flexible` scrollable lists to prevent "Bottom Overflow" on small viewports.
7.  **Tactical Compass**: Real-time North tracking with tap-to-reset (0°) functionality.
