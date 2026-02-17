# Testing Instructions

## What I've Done

I've added comprehensive debug logging throughout the messaging system to help identify exactly where messages are getting stuck. The debug APK has been built successfully.

## Files to Install

The debug APK is located at:
```
build\app\outputs\flutter-apk\app-debug.apk
```

## How to Test

### 1. Install on Both Devices

```bash
adb install build\app\outputs\flutter-apk\app-debug.apk
```

Or transfer the APK file to both devices and install manually.

### 2. Enable Developer Options & USB Debugging

On both devices:
1. Go to Settings → About Phone
2. Tap "Build Number" 7 times to enable Developer Options
3. Go to Settings → Developer Options
4. Enable "USB Debugging"

### 3. Connect and View Logs

**Option A: Using ADB (Recommended)**

Connect one device via USB:
```bash
adb logcat | findstr "peerchat"
```

For the second device, use wireless ADB or check logs in Android Studio.

**Option B: Using Android Studio**

1. Open Android Studio
2. Go to View → Tool Windows → Logcat
3. Select your device
4. Filter by "peerchat" or look for the log markers

### 4. Test Messaging

1. Open app on both devices
2. Wait for peer discovery (check home screen)
3. Note which section peers appear in:
   - "Connected" (green) = good
   - "Discovered" (grey) = not connected yet
4. Tap a peer to open chat
5. Type a message and tap send
6. Watch the logs on both devices

### 5. What to Look For in Logs

**Key Log Markers:**
- `=== SEND MESSAGE START ===` - Message sending initiated
- `=== GET NEXT HOP ===` - Looking for route
- `=== FORWARD MESSAGE ===` - Attempting to forward
- `=== TRANSPORT SEND ===` - Sending via transport layer
- `BluetoothTransport.sendMessage` - Bluetooth attempt
- `WiFiTransport.sendMessage` - WiFi Direct attempt

**Success Indicators:**
- "Public key found for recipient"
- "Direct connection found!"
- "Data sent successfully"
- "✓ SUCCESS via [transport]"
- "Message forwarded: true"

**Failure Indicators:**
- "ERROR: No public key found"
- "No active connection"
- "No route in routing table"
- "✗ FAILED via [transport]"
- "All transports failed"

## Expected Issues & What They Mean

### Issue 1: "No public key found for recipient"

**What it means:** The peer was discovered but we don't have their public key for encryption.

**Why:** No key exchange protocol is implemented yet.

**Fix needed:** Implement handshake or skip encryption temporarily.

### Issue 2: "No active connection to [peer_id]"

**What it means:** The transport layer doesn't have an active connection to that peer.

**Why:** Either:
- Connection was never established
- Connection was lost
- Peer ID mismatch (discovered ID ≠ connection ID)

**Fix needed:** Verify connection establishment or fix ID mapping.

### Issue 3: "No direct connection, checking routing table... No route"

**What it means:** The peer ID in the chat doesn't match any peer in the database.

**Why:** Peer ID mismatch between discovery and chat.

**Fix needed:** Use consistent peer IDs throughout the app.

## What to Send Me

Please capture and send:

1. **Logs from Device A (sender)** - from app start until after sending message
2. **Logs from Device B (receiver)** - from app start until message should arrive
3. **Screenshots** showing:
   - Home screen with peer list
   - Which section the peer appears in (Connected/Discovered)
   - Chat screen after sending message
   - Message status (timer icon = sending)

## Quick Diagnosis

Based on the logs, I can immediately tell:

- **If logs show "No public key"** → Need to implement key exchange
- **If logs show "No active connection"** → Need to fix transport layer
- **If logs show "No route"** → Need to fix peer ID consistency

Once I see the actual logs, I'll provide a targeted fix for the specific issue.

## Alternative: Quick Test Without Logs

If you can't capture logs, just tell me:

1. Do peers appear in "Connected" (green) or "Discovered" (grey)?
2. What happens when you tap send? (Does icon change? Any error message?)
3. Does the message appear on the receiving device?

This will give me enough info to narrow down the issue.
