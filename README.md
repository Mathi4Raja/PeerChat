# PeerChat 📡
### Decentralized. Infrastructure-Free. Privacy-First.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?logo=Flutter&logoColor=white)](https://flutter.dev)
[![Website](https://img.shields.io/badge/Website-peerchat.mathi.live-violet)](https://peerchat.mathi.live)

**PeerChat** is a production-grade, zero-infrastructure messaging platform. It connects devices using only their local hardware—Bluetooth, WiFi Direct, and Hotspots—to create self-healing mesh networks that survive without cell towers or internet.

---

## 🚀 Key Features

- **🌐 Multi-Transport Mesh Networking**: Intelligent routing that automatically selects the best path using Bluetooth, WiFi Direct, or Hotspot relays.
- **📁 Sliding-Window File Transfers**: High-speed, chunk-based P2P file sharing with native crash recovery and bitmask-guaranteed integrity.
- **🔒 Libsodium E2EE**: Absolute message confidentiality using Ed25519 signatures for identity and X25519 for encryption.
- **📡 Multi-Hop Routing**: Messages find their way through intermediate peers to reach out-of-range devices.
- **🌍 Web Share Proxy**: Share files instantly to any device with a browser via an embedded, secure HTTP service.
- **🎨 Premium UX**: A beautiful, harmonized "Ink & Violet" design system with smooth animations and responsive layouts.

---

## 📦 Distribution & Automation

PeerChat follows a professional **Continuous Delivery** pipeline:

- **Automated Releases**: We use GitHub Actions to build and publish signed APKs automatically upon tag pushes.
- **Dynamic Downloads**: Our [website](https://peerchat.mathi.live) always serves the latest version directly from GitHub via a custom proxy API.
- **Real-time Changelog**: The app's history is fetched dynamically from GitHub, ensuring you always see the latest improvements.

---

## 🛠️ Quick Start

### For Users
1. Download the latest APK from **[peerchat.mathi.live](https://peerchat.mathi.live)**.
2. Grant Bluetooth, Location, and File permissions.
3. Bring two devices close together—they will auto-discover and establish a secure handshake.

### For Developers
```bash
git clone https://github.com/Mathi4Raja/P2P-app.git
cd P2P-app
flutter pub get
flutter run
```

---

## 🛡️ Security & Privacy
- **Zero Metadata Tracking**: No central servers = no metadata collection.
- **Identity Verification**: Secure QR code scanning to verify peer fingerprints.
- **Local-Only Persistence**: All data is encrypted and stored strictly on your device's local SQLite database.

---

## 🤝 Contributing
We welcome contributions! Please see our **[CONTRIBUTING.md](CONTRIBUTING.md)** for our setup guide and **AI-assistance policy**.

---

## 📄 License
PeerChat is licensed under the **GNU General Public License v3.0**. 

*Protecting the decentralized future—commercial use requires a separate license.*

---
Built with ❤️ for the decentralized web. [Star us on GitHub](https://github.com/Mathi4Raja/P2P-app) if you believe in privacy.
