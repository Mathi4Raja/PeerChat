# Debugging Guide: Why Messages Aren't Sending

## How to Debug

### Step 1: Check if devices discover each other

**Expected logs:**
```
Bluetooth: "Bluetooth device found: [device_name] ([MAC_address])"
WiFi Direct: "WiFi Direct endpoint found: [endpoint_id] ([endpoint_name])"
```

**What to check:**
- Do both devices show discovery logs?
- Are the discovered peer IDs showing up in the UI?

### Step 2: Check if connections are established

**Expected logs:**
```
Bluetooth: "Bluetooth connected: [MAC_address]"
WiFi Direct: "WiFi Direct connected: [endpoint_id]"
```

**What to check:**
- Do you see "connected" logs after discovery?
- Do peers move from "Discovered" to "Connected" section in UI?

### Step 3: Check message sending

**Expected logs:**
```
"Sending message to [peer_id]: [content]"
"Message sent successfully" OR "Failed to send message"
```

**What to check:**
- Does the send button trigger the log?
- Does it say "sent successfully" or "failed"?

### Step 4: Check message receiving

**Expected logs:**
```
"Received message from [peer_id]"
"Chat message: [content]"
```

**What to check:**
- Does the receiving device show these logs?
- Does the message appear in the chat UI?

## Common Issues

### Issue 1: Peers discovered but not connected

**Symptoms:**
- Peers appear in "Discovered" section
- Never move to "Connected" section
- Messages stuck in "sending" status

**Causes:**
- Bluetooth pairing required but not done
- WiFi Direct connection request not accepted
- Permissions not granted

**Fix:**
- Check Bluetooth permissions
- Check location permissions (required for WiFi Direct)
- Try manual Bluetooth pairing in Android settings

### Issue 2: Connections established but messages not sending

**Symptoms:**
- Peers in "Connected" section
- Send button works but messages stuck
- No "Message sent successfully" log

**Causes:**
- Peer ID mismatch (discovered ID ≠ routing ID)
- No route found to peer
- Transport layer not actually connected

**Fix:**
- Check if `getConnectedPeerIds()` returns the peer
- Verify peer ID in database matches transport ID
- Add more logging to transport layer

### Issue 3: Messages sent but not received

**Symptoms:**
- "Message sent successfully" log on sender
- No "Received message" log on receiver
- Message shows as "sent" but never "delivered"

**Causes:**
- Data not actually transmitted
- Receiver not listening
- Message format incompatible

**Fix:**
- Add logging in transport layer `sendMessage()`
- Add logging in transport layer message listener
- Verify message format (JSON vs binary)

## Quick Test Commands

### Check Bluetooth status
```dart
final isSupported = await FlutterBlueClassic().isSupported;
final isEnabled = await FlutterBlueClassic().isEnabled;
print('BT supported: $isSupported, enabled: $isEnabled');
```

### Check WiFi Direct status
```dart
// WiFi Direct requires location permission
final status = await Permission.location.status;
print('Location permission: $status');
```

### List connected peers
```dart
final connectedIds = meshRouter.getConnectedPeerIds();
print('Connected peers: $connectedIds');
```

### Check peer in database
```dart
final peers = await db.allPeers();
for (final peer in peers) {
  print('Peer: ${peer.id} (${peer.address})');
}
```

## Next Steps

Based on the logs, we can identify exactly where the flow breaks and fix that specific issue.

**Most likely issue:** Peer ID mismatch between discovery and routing.

**Quick fix:** Use transport IDs consistently everywhere, skip cryptographic IDs for now.
