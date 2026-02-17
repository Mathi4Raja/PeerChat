# Bluetooth Classic Limitation

## The Problem

Bluetooth Classic connections are **failing** on both devices with this error:
```
Error connecting to [MAC]: PlatformException(couldNotConnect, read failed, socket might closed or timeout, read ret: -1, null, null)
```

## Root Cause

Bluetooth Classic (unlike BLE) requires a **client-server architecture**:
- One device must act as a **SERVER** (listening for connections)
- The other device acts as a **CLIENT** (initiating connection)

Currently, both devices are trying to act as **clients** (calling `connect()`), but neither is acting as a server.

## Why This Happens

The `flutter_blue_classic` package **does not support server mode**. It only provides:
- `connect(address)` - Connect as a client
- No `listen()` or `accept()` method for server mode

## Solutions

### Option 1: Use a Different Bluetooth Package ✅ RECOMMENDED

Switch to `flutter_bluetooth_serial` which supports both client and server modes:

```dart
// Server mode (one device)
BluetoothConnection.toAddress(address).then((connection) {
  // Handle connection
});

// Or listen for incoming connections
BluetoothConnection.listenUsing(RfcommMode.LISTEN).listen((connection) {
  // Handle incoming connection
});
```

### Option 2: Use WiFi Direct Instead

WiFi Direct (Nearby Connections) supports peer-to-peer connections without client-server architecture. We already have this implemented but temporarily disabled it.

### Option 3: Hybrid Approach

- Use WiFi Direct for messaging (already implemented)
- Use Bluetooth only for discovery
- Re-enable WiFi Direct with keepalive mechanism

## Recommendation

**Switch back to WiFi Direct** and implement the keepalive mechanism. Here's why:

1. **WiFi Direct works** - We already tested it successfully
2. **No client-server requirement** - Both devices can connect as peers
3. **Faster data transfer** - WiFi is faster than Bluetooth
4. **Already implemented** - Just need to add keepalive

The only issue with WiFi Direct was connections dropping. This can be fixed with periodic keepalive messages.

## Next Steps

1. Re-enable WiFi Direct in `mesh_router_service.dart`
2. Add keepalive mechanism to `wifi_transport.dart`
3. Test messaging over WiFi Direct
4. Keep Bluetooth for discovery only

## Alternative: Try flutter_bluetooth_serial

If you really want Bluetooth messaging:

1. Replace `flutter_blue_classic` with `flutter_bluetooth_serial`
2. Implement server mode on one device
3. Implement client mode on the other
4. Determine which device should be server (e.g., based on MAC address)

But this is more complex than just fixing WiFi Direct.
