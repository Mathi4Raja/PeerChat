# Quick Start Guide

## Install & Test in 5 Minutes

### Step 1: Install (1 minute)

```bash
adb install build\app\outputs\flutter-apk\app-debug.apk
```

Or transfer APK to both devices and install manually.

### Step 2: Grant Permissions (1 minute)

When app opens, grant all permissions:
- ✅ Bluetooth
- ✅ Location (required for WiFi Direct)
- ✅ Camera (for QR scanning)
- ✅ Nearby devices

### Step 3: Wait for Discovery (30 seconds)

- Open app on both devices
- Wait 10-30 seconds
- Peers will appear on home screen

### Step 4: Wait for Connection (30 seconds)

- Peers start in "Discovered" section (grey)
- After handshake, move to "Connected" section (green)
- Look for the green section!

### Step 5: Send Message (1 minute)

1. Tap a peer in "Connected" section
2. Type a message
3. Tap send button
4. Message appears on other device!

## Troubleshooting

### Peers Not Appearing?

**Check:**
- Bluetooth is ON on both devices
- Location permission granted
- Devices are within 10 meters
- Wait at least 30 seconds

**Try:**
- Tap refresh button (🔄) on home screen
- Restart app
- Manually pair Bluetooth in Android settings

### Peers in "Discovered" but Not "Connected"?

**This means handshake hasn't completed yet.**

**Wait:** 10-30 more seconds for handshake

**Check logs:**
```bash
adb logcat | findstr "handshake"
```

Should see:
```
Sending handshake to [peer]
Received handshake from [peer]
Handshake complete
```

### Message Stuck in "Sending"?

**Check:**
- Peer is in "Connected" section (not "Discovered")
- Connection is active

**Check logs:**
```bash
adb logcat | findstr "==="
```

Should see:
```
=== SEND MESSAGE START ===
=== FORWARD MESSAGE ===
=== TRANSPORT SEND ===
✓ SUCCESS
```

### Still Not Working?

**Capture logs and share:**

```bash
adb logcat > device1.log
```

Run on both devices, try to send message, then share the log files.

## Success Indicators

### ✅ Discovery Working
- Peers appear on home screen
- Peer count increases

### ✅ Connection Working
- Peers in "Connected" section (green)
- Logs show "Handshake complete"

### ✅ Messaging Working
- Message changes from timer to checkmark
- Message appears on receiving device
- Logs show "✓ SUCCESS"

## What to Expect

### First Time (Cold Start)
- App opens in 2-3 seconds
- Discovery takes 10-30 seconds
- Handshake takes 5-10 seconds
- First message sends in <1 second

### Subsequent Use (Warm Start)
- App opens in <1 second
- Peers appear immediately (from database)
- New peers discovered in 10-30 seconds
- Messages send instantly

## Tips for Best Results

1. **Keep devices close** - Within 10 meters for first connection
2. **Wait for green** - Only send to peers in "Connected" section
3. **Check logs** - Use `adb logcat` to see what's happening
4. **Be patient** - Discovery and handshake take time
5. **Restart if needed** - Sometimes a fresh start helps

## Advanced Testing

### Test Mesh Routing (3+ Devices)

1. Set up 3 devices: A, B, C
2. Place A and C far apart (out of direct range)
3. Place B in the middle (can reach both)
4. Send message from A to C
5. Message routes through B automatically!

### Test Offline Messaging

1. Send message to peer
2. Turn off peer's device
3. Message queued on sender
4. Turn on peer's device
5. Message delivered automatically!

### Test Encryption

1. Send message between devices
2. Check logs - you'll see encrypted data
3. Message is decrypted only on recipient
4. Intermediate nodes can't read content

## Need Help?

Check these files:
- `COMPLETION_REPORT.md` - Full feature list
- `TESTING_INSTRUCTIONS.md` - Detailed testing
- `DEBUGGING_GUIDE.md` - Troubleshooting
- `QUICK_REFERENCE.md` - Quick diagnosis

Or just ask me!
