# WiFi Direct Solution - Keepalive Implementation

## Problem Solved

Bluetooth Classic connections were failing because the `flutter_blue_classic` package doesn't support server mode. Both devices were trying to connect as clients, which doesn't work.

## Solution: WiFi Direct with Keepalive

Re-enabled WiFi Direct (Nearby Connections) and added a keepalive mechanism to maintain persistent connections.

## Changes Made

### 1. Re-enabled WiFi Direct Transport
- Uncommented WiFi transport initialization in `mesh_router_service.dart`
- Both Bluetooth and WiFi Direct now active simultaneously

### 2. Added Keepalive Mechanism
- Sends small keepalive packets every 20 seconds
- Prevents WiFi Direct connections from dropping
- Keepalive packets (0xFF 0xFF) are filtered out and not forwarded to app layer

### 3. Improved Bluetooth Filtering
- Only attempts to connect to phone/tablet devices
- Skips headphones, smartwatches, PCs, etc.
- Reduces connection timeout errors

## How It Works

### WiFi Direct Keepalive
```dart
// Every 20 seconds
Timer.periodic(Duration(seconds: 20), (timer) {
  for (endpoint in connectedPeers) {
    sendBytesPayload(endpoint, [0xFF, 0xFF]); // Keepalive packet
  }
});
```

### Packet Filtering
```dart
// On receive
if (bytes == [0xFF, 0xFF]) {
  return; // Ignore keepalive, don't forward
}
// Otherwise, forward to mesh router
```

## Expected Behavior

1. **Discovery**: Both devices discover each other via WiFi Direct
2. **Connection**: WiFi Direct connections establish
3. **Handshake**: Devices exchange cryptographic keys
4. **Keepalive**: Every 20 seconds, keepalive packets maintain connection
5. **Messaging**: Messages sent over persistent WiFi Direct connection

## Testing

Run on both devices:
```bash
flutter run -d 1207031462120918  # Device 1 (Infinix)
flutter run -d 9T19545LA1222404340  # Device 2 (Nokia)
```

### What to Look For

**Logs should show:**
```
WiFi Direct advertising started
WiFi Direct discovery started
WiFi Direct endpoint found: [ID]
WiFi Direct connected: [ID]
Handshake complete
WiFi Direct keepalive started (every 20s)
Sending keepalive to 1 peers
Received keepalive from [ID]
```

**UI should show:**
- Peers appear in "Connected" section
- Human-readable names (e.g., "Swift Phoenix 742")
- Messages send and receive successfully
- No "timer" icon (messages delivered)

## Advantages Over Bluetooth

1. **No client-server requirement** - Both devices are peers
2. **Faster data transfer** - WiFi is faster than Bluetooth
3. **Better range** - WiFi Direct works up to 200m
4. **Already working** - Just needed keepalive fix

## Bluetooth Role

Bluetooth is still active but only for:
- Backup discovery mechanism
- Future mesh routing (if needed)
- Currently filtered to only attempt phone/tablet connections

## Troubleshooting

### If connections still drop:
- Increase keepalive frequency (reduce from 20s to 10s)
- Check WiFi Direct permissions
- Ensure location services are enabled

### If no peers discovered:
- Check both devices have location enabled
- Check WiFi is enabled (even if not connected to network)
- Check permissions granted

### If handshake fails:
- Check database for peer public keys
- Check connection manager logs
- Verify crypto service initialized

## Next Steps

1. Test messaging on both devices
2. Verify keepalive maintains connections
3. Test with devices further apart
4. Test with screen off/app backgrounded
