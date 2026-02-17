# Bluetooth Discovery Implementation

## Overview

The app now uses **Bluetooth** for peer discovery instead of relying solely on mDNS (which doesn't support service advertisement).

## What Changed

### Discovery Service (`lib/src/services/discovery_service.dart`)

**Added Bluetooth Discovery:**
- Scans for nearby Bluetooth devices
- Automatically adds bonded/paired devices to peers list
- Discovers nearby Bluetooth devices with visible names
- Runs continuous scanning with 30-second intervals
- Auto-restarts scanning after each cycle

**Dual Discovery System:**
- **Bluetooth**: Primary discovery method (fully functional)
- **mDNS**: Secondary method (listening only, no advertisement)

## How It Works

### 1. Bluetooth Scanning
```
App Start → Check Bluetooth → Enable if needed → Scan for devices
   ↓
Get Bonded Devices → Add to Peers List
   ↓
Start Continuous Scan → Discover Nearby Devices → Add to Peers List
   ↓
After 30s → Stop Scan → Wait 10s → Restart Scan
```

### 2. Peer Detection
The app adds devices to the peers list if:
- Device is bonded/paired with your phone
- Device is discoverable and has a visible name
- Device is within Bluetooth range (~10 meters)
- **Device is a valid mesh node** (phone, tablet, or computer)

### Device Filtering
The app automatically filters out devices that cannot act as mesh nodes:

**Excluded Devices:**
- ❌ Headphones and earbuds (AirPods, Beats, Bose, etc.)
- ❌ Bluetooth speakers and soundbars
- ❌ Smartwatches and fitness trackers
- ❌ Car Bluetooth systems
- ❌ TVs, remotes, and controllers
- ❌ Keyboards and mice
- ❌ Other IoT devices

**Included Devices:**
- ✅ Smartphones (Android, iPhone)
- ✅ Tablets (iPad, Galaxy Tab, etc.)
- ✅ Computers (laptops, desktops)
- ✅ Any device capable of running the app

This ensures the peers list only shows devices that can:
- Run the PeerChat app
- Relay messages in the mesh network
- Act as intermediate hops for routing

### 3. Peer Information
Each discovered peer includes:
- **ID**: Bluetooth MAC address
- **Display Name**: Device name (e.g., "John's Phone")
- **Address**: Bluetooth MAC address
- **Last Seen**: Timestamp of discovery

## User Experience

### On App Launch
1. App requests Bluetooth permissions
2. Enables Bluetooth if disabled
3. Scans for bonded devices (instant)
4. Starts scanning for nearby devices
5. Updates peers list in real-time

### Manual Refresh
- Tap the refresh button (🔄) in the app bar
- Restarts discovery service
- Re-scans for all devices
- Updates peers list

### Automatic Updates
- Scanning runs continuously
- New devices appear automatically
- Peers list updates in real-time
- No user interaction needed

## Testing Peer Discovery

### Quick Test (Single Device)
**Note**: This test now requires another phone/tablet/computer, not just any Bluetooth device.

1. Pair your phone with another smartphone, tablet, or computer
2. Open PeerChat app
3. The paired device appears in Peers list

**Why headphones don't appear**: The app filters out audio devices, wearables, and other non-mesh-capable devices to ensure only devices that can run the app and relay messages are shown.

### Full Test (Multiple Devices)
1. Install app on 2+ Android devices
2. Enable Bluetooth on all devices
3. Keep devices within 10 meters
4. Open app on all devices
5. Devices discover each other automatically

### Make Device Discoverable
1. Go to: Settings → Bluetooth
2. Tap your device name at the top
3. Enable "Visible to other devices"
4. Open PeerChat on another device
5. Your device appears in their Peers list

## Permissions Required

### Android Permissions
```xml
<!-- Bluetooth permissions -->
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />

<!-- Android 12+ permissions -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />

<!-- Location (required for Bluetooth scanning) -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

### Runtime Permissions
The app requests these at startup:
- Bluetooth
- Bluetooth Scan
- Bluetooth Connect
- Bluetooth Advertise
- Location (Fine & Coarse)

## Limitations

### Current Limitations
- **Range**: Bluetooth Classic ~10 meters (30 feet)
- **Discovery Time**: 2-5 seconds for nearby devices
- **Device Name**: Only devices with visible names are added
- **Pairing**: Some devices require pairing to be discovered
- **Battery**: Continuous scanning uses moderate battery

### mDNS Limitations
- **No Advertisement**: Can't advertise service on network
- **Listen Only**: Can only listen for services (not functional without advertisement)
- **Future Enhancement**: Needs native plugin for full mDNS support

## Advantages

### Why Bluetooth Discovery?
✅ **Works Immediately**: No network setup required
✅ **No WiFi Needed**: Works without internet or WiFi
✅ **Peer-to-Peer**: True P2P discovery
✅ **Low Latency**: Fast device discovery
✅ **Automatic**: Continuous background scanning
✅ **Reliable**: Bluetooth is ubiquitous on mobile devices

### Use Cases
- **Offline Messaging**: Works without internet
- **Local Networks**: Discover nearby devices
- **Emergency Communication**: No infrastructure needed
- **Privacy**: No central server required
- **Mesh Networking**: Foundation for multi-hop routing

## Future Enhancements

### Planned Improvements
1. **BLE (Bluetooth Low Energy)**: Lower battery consumption
2. **Service UUID Filtering**: Only discover PeerChat devices
3. **Custom Advertisement**: Broadcast app-specific data
4. **WiFi Direct Integration**: Automatic fallback to WiFi
5. **NFC Pairing**: Tap-to-pair functionality
6. **QR Code Pairing**: Scan to add peer

### mDNS Enhancement
- Implement native mDNS service registration
- Use platform channels for iOS/Android
- Enable WiFi-based discovery
- Support local network advertisement

## Troubleshooting

### "No peers discovered"
**Cause**: No Bluetooth devices nearby or paired
**Solution**: 
- Pair with any Bluetooth device
- Install app on another device
- Make device discoverable
- Grant location permission

### Peers not appearing
**Cause**: Bluetooth disabled or permissions denied
**Solution**:
- Enable Bluetooth in Android settings
- Grant all permissions in app settings
- Tap refresh button to rescan
- Restart the app

### Slow discovery
**Cause**: Bluetooth scanning takes time
**Solution**:
- Wait 5-10 seconds for scan to complete
- Tap refresh to trigger immediate scan
- Move devices closer together
- Ensure devices are discoverable

## Technical Details

### Bluetooth Classic vs BLE
**Current Implementation**: Bluetooth Classic
- Longer range (~10m)
- Higher bandwidth
- Better for data transfer
- Higher battery usage

**Future**: Bluetooth Low Energy (BLE)
- Longer battery life
- Faster discovery
- Lower bandwidth
- Better for beaconing

### Discovery Flow
```dart
1. Check Bluetooth support
2. Enable Bluetooth if needed
3. Get bonded devices → Add to peers
4. Start scanning
5. Listen to scan results → Add to peers
6. After 30s: Stop scan
7. Wait 10s
8. Repeat from step 4
```

### Peer Deduplication
- Uses Bluetooth MAC address as unique ID
- Prevents duplicate entries
- Updates last seen timestamp
- Maintains single entry per device

## Summary

The app now has **fully functional peer discovery** using Bluetooth. Users will see nearby Bluetooth devices in the Peers list, including any paired devices. This provides a solid foundation for the mesh networking functionality.

**Key Points:**
- ✅ Bluetooth discovery is working
- ✅ Paired devices appear automatically
- ✅ Nearby devices are discovered
- ✅ Manual refresh available
- ✅ Continuous background scanning
- ⚠️ mDNS discovery is limited (listen-only)
