# Network Addressing in PeerChat

## Overview

PeerChat uses different addressing schemes for Bluetooth and WiFi, similar to how devices have unique identifiers like IPv4 addresses.

## Bluetooth Addressing

### Bluetooth MAC Address

**What it is:**
- A globally unique 48-bit identifier (6 bytes)
- Format: `XX:XX:XX:XX:XX:XX` (hexadecimal)
- Example: `A4:5E:60:E8:7B:2C`

**Properties:**
- ✅ **Globally unique** (assigned by manufacturer)
- ✅ **Permanent** (doesn't change)
- ✅ **Hardware-based** (burned into Bluetooth chip)
- ✅ **Works offline** (no network needed)

**In PeerChat:**
```dart
// Discovery Service
final peerId = device.address; // "A4:5E:60:E8:7B:2C"

// Peer Model
Peer(
  id: "A4:5E:60:E8:7B:2C",        // Bluetooth MAC
  displayName: "John's Phone",
  address: "A4:5E:60:E8:7B:2C",   // Same as ID for Bluetooth
  lastSeen: 1234567890,
)
```

**Comparison to IPv4:**
| Feature | Bluetooth MAC | IPv4 Address |
|---------|--------------|--------------|
| Format | `XX:XX:XX:XX:XX:XX` | `XXX.XXX.XXX.XXX` |
| Size | 48 bits (6 bytes) | 32 bits (4 bytes) |
| Uniqueness | Globally unique | Local to network |
| Permanence | Permanent | Temporary (DHCP) |
| Assignment | Manufacturer | DHCP/Static |
| Requires Network | No | Yes |

## WiFi Addressing

### WiFi MAC Address

**What it is:**
- Similar to Bluetooth MAC, but different address
- Format: `XX:XX:XX:XX:XX:XX` (hexadecimal)
- Example: `B8:27:EB:12:34:56`

**Properties:**
- ✅ **Globally unique** (assigned by manufacturer)
- ⚠️ **Can be randomized** (privacy feature on modern devices)
- ✅ **Hardware-based** (burned into WiFi chip)
- ❌ **Different from Bluetooth MAC** (same device has 2 MACs)

### WiFi Direct Endpoint ID

**What it is:**
- A temporary identifier assigned by the Nearby Connections API
- Format: Variable-length string
- Example: `endpoint_1234567890abcdef`

**Properties:**
- ❌ **Not globally unique** (local to connection session)
- ❌ **Temporary** (changes each connection)
- ✅ **Works offline** (no internet needed)
- ✅ **Peer-to-peer** (direct device-to-device)

**In PeerChat:**
```dart
// WiFi Transport
void _onEndpointFound(String endpointId, String endpointName, String serviceId) {
  // endpointId: "endpoint_1234567890abcdef"
  // endpointName: "John's Phone"
  
  _connectedPeers[endpointId] = endpointId; // Use as peer ID
}
```

### IPv4 Address (when on WiFi network)

**What it is:**
- A 32-bit network address
- Format: `XXX.XXX.XXX.XXX` (decimal)
- Example: `192.168.1.100`

**Properties:**
- ❌ **Not globally unique** (local to network)
- ❌ **Temporary** (assigned by DHCP, changes on reconnect)
- ❌ **Requires network** (must be connected to WiFi)
- ❌ **Not used in PeerChat** (we use WiFi Direct, not traditional WiFi)

## Current Implementation

### Peer Identification

```dart
class Peer {
  final String id;          // Unique identifier
  final String displayName; // Human-readable name
  final String address;     // Connection address
  final int lastSeen;       // Timestamp
}
```

### Bluetooth Peers

```dart
// Discovered via Bluetooth
Peer(
  id: "A4:5E:60:E8:7B:2C",        // Bluetooth MAC address
  displayName: "John's Phone",     // Device name
  address: "A4:5E:60:E8:7B:2C",   // Bluetooth MAC (same as ID)
  lastSeen: 1234567890,
)
```

**How it works:**
1. Bluetooth scan discovers device
2. Device has MAC address: `A4:5E:60:E8:7B:2C`
3. Device has name: "John's Phone"
4. We use MAC as both `id` and `address`
5. To send message: Connect to MAC address via Bluetooth

### WiFi Direct Peers

```dart
// Discovered via WiFi Direct
Peer(
  id: "endpoint_abc123",           // Endpoint ID (temporary)
  displayName: "Sarah's Tablet",   // Device name
  address: "endpoint_abc123",      // Endpoint ID (same as ID)
  lastSeen: 1234567890,
)
```

**How it works:**
1. WiFi Direct discovers endpoint
2. Endpoint has ID: `endpoint_abc123`
3. Endpoint has name: "Sarah's Tablet"
4. We use endpoint ID as both `id` and `address`
5. To send message: Send to endpoint ID via Nearby Connections

## Problem: Inconsistent Addressing

### Current Issues

**1. Bluetooth uses permanent MAC, WiFi uses temporary endpoint ID**
```dart
// Same device discovered via different transports
Bluetooth: id = "A4:5E:60:E8:7B:2C"  (permanent)
WiFi:      id = "endpoint_abc123"     (temporary, changes each session)
```

**2. Can't correlate same device across transports**
```dart
// Is this the same device?
Peer 1: id = "A4:5E:60:E8:7B:2C"  (Bluetooth)
Peer 2: id = "endpoint_abc123"     (WiFi)
// We don't know! They appear as 2 different peers.
```

**3. Routing table confusion**
```dart
// Route table might have:
Route to "A4:5E:60:E8:7B:2C" via Bluetooth
Route to "endpoint_abc123" via WiFi
// But they're the same device!
```

## Solution: Use Cryptographic Identity

### Proposed: Use Public Key as Peer ID

Instead of using transport-specific addresses, use the device's **public key** as the peer ID:

```dart
Peer(
  id: "DCAIZali206cFn6d3A8e/M7DPIPi7Fc/iqhhFBxizn0=",  // Base64 public key
  displayName: "John's Phone",
  address: "A4:5E:60:E8:7B:2C",  // Bluetooth MAC or endpoint ID
  lastSeen: 1234567890,
)
```

**Benefits:**
- ✅ **Globally unique** (cryptographically generated)
- ✅ **Permanent** (doesn't change)
- ✅ **Transport-agnostic** (same ID for Bluetooth and WiFi)
- ✅ **Secure** (can verify identity via signatures)
- ✅ **Already generated** (we already have keypairs)

**How it works:**
1. Each device generates keypair on first launch
2. Public key becomes the peer ID
3. Device advertises public key during discovery
4. Other devices use public key as peer ID
5. `address` field stores transport-specific address (MAC or endpoint ID)

### Implementation Changes Needed

**1. Update Discovery Service**
```dart
// Bluetooth Discovery
void _addBluetoothPeer(BluetoothDevice device) {
  // TODO: Get public key from device (via service advertisement)
  final publicKey = _getPublicKeyFromDevice(device);
  
  final peer = Peer(
    id: base64Encode(publicKey),        // Public key as ID
    displayName: device.name ?? 'Unknown',
    address: device.address,             // Bluetooth MAC
    lastSeen: DateTime.now().millisecondsSinceEpoch,
  );
}
```

**2. Update WiFi Discovery**
```dart
// WiFi Discovery
void _onEndpointFound(String endpointId, String endpointName, String serviceId) {
  // TODO: Exchange public keys during connection
  final publicKey = _exchangePublicKey(endpointId);
  
  final peer = Peer(
    id: base64Encode(publicKey),        // Public key as ID
    displayName: endpointName,
    address: endpointId,                 // Endpoint ID
    lastSeen: DateTime.now().millisecondsSinceEpoch,
  );
}
```

**3. Update Routing**
```dart
// Routing now uses public key
Route(
  destinationPeerId: "DCAIZali206cFn6d3A8e...",  // Public key
  nextHopPeerId: "M7DPIPi7Fc/iqhhFBxizn0=...",   // Public key
  transportType: "bluetooth",                     // or "wifi"
  nextHopAddress: "A4:5E:60:E8:7B:2C",           // Transport address
)
```

## Comparison Table

| Identifier Type | Format | Uniqueness | Permanence | Current Use |
|----------------|--------|------------|------------|-------------|
| **Bluetooth MAC** | `XX:XX:XX:XX:XX:XX` | Global | Permanent | ✅ Peer ID (Bluetooth) |
| **WiFi MAC** | `XX:XX:XX:XX:XX:XX` | Global | Permanent* | ❌ Not used |
| **WiFi Endpoint ID** | Variable string | Local | Temporary | ✅ Peer ID (WiFi) |
| **IPv4 Address** | `XXX.XXX.XXX.XXX` | Local | Temporary | ❌ Not used |
| **Public Key** | Base64 string | Global | Permanent | ❌ Should use! |

*Can be randomized on modern devices

## Recommendations

### Short-term (Current Implementation)
✅ Keep using Bluetooth MAC and WiFi endpoint ID
✅ Accept that same device may appear as 2 peers
✅ Document the limitation

### Long-term (Recommended)
🎯 Use public key as peer ID
🎯 Store transport address separately
🎯 Support multiple transports per peer
🎯 Implement key exchange during discovery

## Example: Multi-Transport Peer

**Future implementation:**
```dart
class Peer {
  final String id;                    // Public key (permanent)
  final String displayName;
  final List<PeerAddress> addresses;  // Multiple transport addresses
  final int lastSeen;
}

class PeerAddress {
  final String transport;  // "bluetooth" or "wifi"
  final String address;    // MAC or endpoint ID
  final int lastSeen;
}

// Example peer with both transports
Peer(
  id: "DCAIZali206cFn6d3A8e/M7DPIPi7Fc/iqhhFBxizn0=",  // Public key
  displayName: "John's Phone",
  addresses: [
    PeerAddress(
      transport: "bluetooth",
      address: "A4:5E:60:E8:7B:2C",
      lastSeen: 1234567890,
    ),
    PeerAddress(
      transport: "wifi",
      address: "endpoint_abc123",
      lastSeen: 1234567895,
    ),
  ],
  lastSeen: 1234567895,
)
```

**Benefits:**
- Same peer, multiple ways to reach them
- Can choose best transport for each message
- Automatic failover if one transport fails
- Consistent identity across all transports

## Summary

**Current State:**
- Bluetooth: Uses MAC address as peer ID (permanent, unique)
- WiFi: Uses endpoint ID as peer ID (temporary, session-based)
- Same device can appear as 2 different peers

**Recommended Future:**
- Use public key as peer ID (permanent, unique, transport-agnostic)
- Store transport addresses separately
- Support multiple transports per peer
- Enable intelligent transport selection

**Answer to your question:**
Yes, both Bluetooth and WiFi have unique identifiers:
- **Bluetooth**: MAC address (like `A4:5E:60:E8:7B:2C`) - permanent and unique
- **WiFi**: MAC address (hardware) + endpoint ID (session) + IPv4 (network)
- We currently use these as peer IDs, but should migrate to using public keys for better consistency
