# Quick Reference: Message Debugging

## Install & Test (3 Steps)

### 1. Install APK
```bash
adb install build\app\outputs\flutter-apk\app-debug.apk
```

### 2. Capture Logs
```bash
adb logcat | findstr "==="
```

### 3. Send Message
- Open app on both devices
- Tap a peer → open chat
- Type message → tap send
- Watch the logs

## What the Logs Will Show

### ✅ Success Pattern
```
=== SEND MESSAGE START ===
=== GET NEXT HOP ===
Direct connection found!
=== FORWARD MESSAGE ===
=== TRANSPORT SEND ===
✓ SUCCESS via BluetoothTransport
Message forwarded: true
```

### ❌ Failure Patterns

**Pattern 1: No Key**
```
=== SEND MESSAGE START ===
ERROR: No public key found
```
→ Need key exchange

**Pattern 2: No Connection**
```
=== TRANSPORT SEND ===
BluetoothTransport.sendMessage
  No active connection
  Available connections: []
```
→ Connection not established

**Pattern 3: No Route**
```
=== GET NEXT HOP ===
Total peers in database: 0
No route in routing table
```
→ Peer not in database

## Quick Diagnosis

| What You See | What It Means | Fix Needed |
|--------------|---------------|------------|
| Peers in "Discovered" (grey) | Not connected | Fix connection |
| Peers in "Connected" (green) but message stuck | ID mismatch or no key | Fix IDs or add handshake |
| No peers shown | Discovery not working | Check permissions |
| Message shows timer icon | Stuck in sending | See logs for reason |

## Share With Me

1. **Logs** from both devices (just the parts with `===`)
2. **Screenshot** of home screen showing peer list
3. **Tell me** if peers are in "Connected" or "Discovered" section

That's all I need to fix it!

## Alternative: No Logs Available?

Just answer these:
1. Do peers appear in "Connected" (green) or "Discovered" (grey)?
2. How many peers do you see on each device?
3. What happens when you tap send? (Any change? Error message?)

This is enough to narrow down the issue.
