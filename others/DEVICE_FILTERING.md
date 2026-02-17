# Bluetooth Device Filtering

## Overview

The PeerChat app implements intelligent device filtering to ensure only mesh-capable devices appear in the peers list. This prevents non-functional entries like headphones, speakers, and smartwatches from cluttering the interface.

## Why Filter Devices?

### Mesh Network Architecture

**Critical Requirement**: ALL nodes in the mesh network (sender, receiver, AND intermediate hops) must have the PeerChat app installed and running.

**Why?** Each hop must:
1. **Receive & Parse**: Deserialize encrypted mesh messages
2. **Verify**: Check signatures and prevent replay attacks
3. **Route**: Look up routing tables and make forwarding decisions
4. **Forward**: Decrement TTL, increment hop count, forward to next hop
5. **Acknowledge**: Send delivery confirmations back to sender
6. **Store**: Queue messages when next hop unavailable (store-and-forward)

This is NOT simple Bluetooth packet forwarding - it requires:
- Flutter app runtime
- Cryptographic operations (libsodium)
- Database access (SQLite)
- Routing logic
- Message queue management

### Problem
Without filtering, the peers list would include devices that CANNOT run the PeerChat app:
- Bluetooth headphones (proprietary firmware, no app support)
- Speakers and soundbars (audio-only devices)
- Smartwatches (limited OS, can't run full Flutter apps)
- Car Bluetooth systems (proprietary OS, no app support)
- IoT devices (embedded systems, different architecture)

### Solution
Filter devices by name patterns to include only devices capable of running Flutter apps:
- Smartphones (Android, iPhone - can run Flutter apps)
- Tablets (iPad, Galaxy Tab - can run Flutter apps)
- Computers (laptops, desktops - can run Flutter desktop apps)

## Filtering Logic

### Implementation
Located in: `lib/src/services/discovery_service.dart`

```dart
bool _isValidMeshNode(BluetoothDevice device) {
  final name = device.name?.toLowerCase() ?? '';
  
  // Exclude audio devices, wearables, car systems, IoT devices
  // Return true only for phones, tablets, computers
}
```

### Exclusion Patterns

**Audio Devices:**
- headphone, earbuds, airpods, buds
- speaker, soundbar, audio
- beats, bose, sony wh, jbl

**Wearables:**
- watch, band, fit, tracker

**Car Systems:**
- car, auto, vehicle

**IoT Devices:**
- tv, remote, controller, gamepad
- keyboard, mouse

### Inclusion Logic

Devices are included if:
1. They have a visible name
2. Name doesn't match any exclusion pattern
3. Device type is Classic or Dual mode Bluetooth

This catches most:
- Phones: "User's Phone", "Galaxy S21", "iPhone", "Pixel"
- Tablets: "iPad", "Galaxy Tab", "Surface"
- Computers: "User's PC", "MacBook", "ThinkPad"

## Device Types

### Valid Mesh Nodes

**Smartphones:**
- Android phones (all manufacturers)
- iPhones (iOS devices)
- Can run the PeerChat app
- Can relay messages
- Can act as intermediate hops

**Tablets:**
- Android tablets
- iPads
- Can run the PeerChat app
- Can relay messages
- Larger battery for longer relay time

**Computers:**
- Laptops (Windows, Mac, Linux)
- Desktops with Bluetooth
- Can run Flutter desktop apps
- Can act as powerful relay nodes
- Always-on capability

### Invalid Mesh Nodes

**Audio Devices (Headphones, Speakers):**
- ❌ Cannot run Flutter apps (proprietary firmware)
- ❌ No operating system to run applications
- ❌ Cannot process mesh routing logic
- ❌ Cannot verify signatures or handle encryption
- ❌ Single-purpose audio devices only

**Wearables (Smartwatches, Fitness Bands):**
- ❌ Limited OS (WearOS, watchOS) - cannot run full Flutter apps
- ❌ Insufficient resources for mesh routing
- ❌ Limited battery life (would drain quickly)
- ❌ Intermittent connectivity
- ❌ Not designed for background message relay

**Car Systems:**
- ❌ Proprietary OS (cannot run Flutter apps)
- ❌ Not always available (only when in car)
- ❌ Cannot run apps in background
- ❌ Limited to car environment
- ❌ Not portable or reliable for mesh networking

**IoT Devices (TVs, Keyboards, Mice, Remotes):**
- ❌ Embedded systems (cannot run Flutter apps)
- ❌ Different architecture (not ARM/x86 with Flutter support)
- ❌ No application runtime environment
- ❌ Single-purpose functionality
- ❌ Cannot handle mesh routing logic

**Key Point**: These devices lack the ability to run the PeerChat application, which is REQUIRED for every node in the mesh network (including intermediate hops) to:
- Parse and validate mesh messages
- Execute routing algorithms
- Perform cryptographic operations
- Maintain routing tables and message queues
- Forward messages to the next hop

## User Experience

### Before Filtering
```
Peers:
- John's Phone ✓
- AirPods Pro ✗
- Galaxy Buds ✗
- Car Bluetooth ✗
- Smart Watch ✗
- JBL Speaker ✗
```

### After Filtering
```
Peers:
- John's Phone ✓
- Sarah's Tablet ✓
- Mike's Laptop ✓
```

### Benefits
- ✅ Clean, relevant peers list
- ✅ Only shows functional mesh nodes
- ✅ Reduces user confusion
- ✅ Improves mesh reliability
- ✅ Better routing decisions

## Edge Cases

### False Positives
Some devices might pass the filter but can't run the app:
- **Smart TVs**: May appear as "TV" but filtered out
- **Game Consoles**: Usually have "PlayStation" or "Xbox" in name
- **E-readers**: Rare, but might appear

**Solution**: Patterns can be extended to catch these cases

### False Negatives
Some valid devices might be filtered out:
- **Custom Device Names**: "My Beats Phone" (contains "beats")
- **Unusual Names**: User renamed phone to "Speaker Phone"

**Solution**: Users can manually add peers via QR code or address

### Unknown Devices
Devices with generic names:
- "Device-1234"
- "BT-Device"
- "Unknown"

**Current Behavior**: Included (benefit of doubt)
**Future**: Could prompt user to verify

## Testing

### Test Cases

**1. Audio Device (Should be filtered)**
```
Device: "AirPods Pro"
Expected: Not in peers list
Result: ✓ Filtered out
```

**2. Smartphone (Should be included)**
```
Device: "John's iPhone"
Expected: In peers list
Result: ✓ Included
```

**3. Smartwatch (Should be filtered)**
```
Device: "Galaxy Watch 4"
Expected: Not in peers list
Result: ✓ Filtered out
```

**4. Tablet (Should be included)**
```
Device: "iPad Pro"
Expected: In peers list
Result: ✓ Included
```

**5. Computer (Should be included)**
```
Device: "MacBook Pro"
Expected: In peers list
Result: ✓ Included
```

### Manual Testing

1. Pair phone with various Bluetooth devices
2. Open PeerChat app
3. Verify only phones/tablets/computers appear
4. Confirm headphones/speakers are filtered out

## Future Enhancements

### Bluetooth Device Class
Use Bluetooth device class codes for more accurate filtering:
- `0x020C`: Phone
- `0x0108`: Computer
- `0x011C`: Tablet
- `0x0404`: Headphones (exclude)
- `0x0414`: Speaker (exclude)

### Service UUID Detection
Detect PeerChat-specific service UUID:
- Only show devices advertising PeerChat service
- Guarantees device is running the app
- Eliminates false positives

### User Preferences
Allow users to:
- Manually add/remove devices
- Whitelist specific devices
- Blacklist specific devices
- Adjust filtering sensitivity

### Machine Learning
Train model to classify devices:
- Learn from user feedback
- Improve accuracy over time
- Adapt to new device types

## Configuration

### Adjusting Filters

To modify filtering behavior, edit:
```dart
// lib/src/services/discovery_service.dart

bool _isValidMeshNode(BluetoothDevice device) {
  // Add/remove patterns here
}
```

### Adding Exclusions
```dart
// Exclude new device type
if (name.contains('newdevicetype')) {
  return false;
}
```

### Adding Inclusions
```dart
// Force include specific pattern
if (name.contains('peerchat')) {
  return true;
}
```

## Summary

The device filtering system ensures the PeerChat peers list only shows devices capable of:
- Running the application
- Relaying messages in the mesh network
- Acting as intermediate routing hops

This improves user experience and mesh network reliability by excluding non-functional devices like headphones, speakers, and smartwatches.

**Key Points:**
- ✅ Filters out audio devices, wearables, IoT
- ✅ Includes phones, tablets, computers
- ✅ Pattern-based matching
- ✅ Extensible for future device types
- ✅ Improves mesh network quality
