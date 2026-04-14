# PeerChat

**Version:** 1.0.0 (Production Ready)  
**Status:** 🟢 Mission Complete — Fully Decentralized & Feature Rich  

PeerChat is a fully functional, zero-infrastructure peer-to-peer secure messaging and file-sharing application designed for offline communication scenarios. Built intelligently to connect devices without cell towers, it establishes self-healing mesh networks, multi-hop routing, and high-speed direct file transfers using local hardware radios.

---

## 🌟 What's New in v1.0.0

The project has advanced from a core-messaging app to a comprehensive decentralized platform:

- **🚀 P2P Sliding-Window File Transfers:** High-speed, chunk-based direct file transfers with crash-recovery capabilities mapped natively to device external storage.
- **🌐 Web Share Hosted Service:** An isolated HTTP service embedded directly in the app to share files seamlessly over WiFi Hotspots directly to native browsers, featuring Manual Upload Approval protocols.
- **📡 Multi-Transport Engine:** Smart routing leveraging **Bluetooth Classic**, **WiFi Direct**, and **WiFi Hotspots**.
- **🎨 Visual Overhaul & Harmonized Theme:** A beautiful, responsive interface featuring Dark Violet / Ink branding, refined chat bubbles, relative timestamps, and scaling UI. 
- **📁 Native Media Picker:** 100x faster media queries, app icon extraction, and file management linked natively to the OS.
- **🛠️ Automated CI/CD:** Release workflows fully managed via `mobile-ci.yml`.

---

## ⚡ Quick Start (In 5 Minutes)

### 1. Install Securely
Install the latest `PeerChat.apk` on two or more Android devices.
```bash
adb install build/app/outputs/flutter-apk/PeerChat.apk
```

### 2. Grant Device Permissions
Upon launch, PeerChat requires local radio access. Grant permissions when prompted:
- ✅ **Bluetooth** (For persistent background device discovery)
- ✅ **Location** (A hard Android requirement for WiFi Direct/Nearby connections)
- ✅ **Camera** (To scan secure Identity QR codes)
- ✅ **Files / Media** (To enable P2P local file caching and sharing)

### 3. Connect & Transact
- Keep both devices in proximity. Peers will appear under **Discovered** initially.
- Allow 10-30 seconds for the **Automatic Cryptographic Key Exchange** handshake.
- Once handshakes complete, devices turn Green and shift to **Connected**.
- **Send Messages:** Tap a peer, type, and verify receipt via the checkmarks.
- **Send Files:** Trigger transfers right from the Chat Screen or head to the Dashboard.

*Having issues? Check the **[DEBUGGING_GUIDE.md](others/DEBUGGING_GUIDE.md)**.*

---

## ⚙️ Core Architecture & Tech Stack

PeerChat employs a robust, multi-layered architecture focused completely on privacy and zero-trust. 

### Security & Privacy Layer (Libsodium/NaCl)
- **Ed25519 Signatures:** Validates peer identity; prevents tampering.
- **X25519 Encryption:** Absolute message confidentiality from device to device.
- **Local Persistence Only:** The database is strictly on-device (SQLite). 
- **Offline By Design:** Requires exactly 0% internet connectivity. 

### Decentralized Mesh Routing
- **Multi-Hop Relaying:** Out-of-range devices connect automatically via intermediate peers holding the app.
- **Lazy Flooding & Queue Limits:** Intelligent queue pruning (max 5000) prevents cache bloat and eliminates replay attacks.
- **Delivery Confirmations & Read Receipts:** A robust 3-stage validation (`Sent` → `Received` → `Seen`).

### P2P Protocol Engine
- **Hardware Isolation Hooks:** Turbo Mode isolates Web Share from local meshes temporarily to maximize throughput and radio capacity.
- **True Sliding Window / Pipelining:** Enables wait-free data transmission with crash restoration bitmasks guaranteeing complete transfers across interruptions.

---

## 📚 Technical Documentation

Deeper structural details are maintained in the `others/` directory:

- [System Architecture](others/sys_architecture.md): The original design paradigm.
- [Requirements & Specifications](others/req.md): Foundational features outlined.
- [Mesh Networking Details](others/MESH_ROUTING_IMPLEMENTATION.md): How Multi-Hop routing handles paths.
- [Debugging & Logs Guide](others/DEBUGGING_GUIDE.md): What logs look like during direct connections and troubleshooting steps.
- [Tracked Status & Tasks](others/TRACK_TASKS.md): Detailed historic iterations across 40+ phases.

---

## 📱 Use Cases & Deployment

### 🌪️ Disaster Relief & Off-Grid (Primary)
- Operates smoothly without internet or cell tower availability.
- Mesh topologies dramatically extend communications bounds down the street.
- Minimal footprint installs on decade-old, low-resource hardware.

### ⛺ Peer Scenarios
- Tactical operations / Privacy-focused networks.
- Dense convention halls with clogged network pipes (Hotspot direct share).
- Camping, protesting, and localized remote teamwork.

---

## 🏗️ Development & Build Configs

PeerChat natively binds Java 21 LTS limits with advanced Flutter integration.

**Requirements:**
- Android: 6.0+ minimum; fully optimized for Android 11+ scoped storage.
- Storage: ~50MB 

**Create Release APK (Optimized, Split ABIs):**
```bash
./others/build_release.ps1
```
*Alternatively natively by:*
```bash
flutter build apk --release --split-per-abi
```

**Debug Build:**
```bash
flutter build apk --debug
```

---

## ❤️ Open Source & Community Support

PeerChat revolves around the ideology of permanent, decentralized rights to share files and speak without centralized authority observation. 

Consider supporting the project by joining the Patron initiative or leaving a star on GitHub.
