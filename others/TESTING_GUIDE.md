# PeerChat - Testing Guide

## Setup Requirements

### Hardware
- 2 Physical Android devices (minimum)
- Bluetooth enabled on all devices
- WiFi enabled (optional, for WiFi Direct)
- Devices should be within Bluetooth range (~10m)

### Software
- Flutter SDK installed
- Android SDK configured
- USB debugging enabled on physical devices

### Permissions Required
- Bluetooth (for device discovery)
- Bluetooth Scan (Android 12+)
- Bluetooth Connect (Android 12+)
- Location (required for Bluetooth scanning on Android)
- WiFi (for WiFi Direct transport)

## How Peer Discovery Works

The app uses **Bluetooth** for peer discovery with intelligent device filtering:

1. **Bluetooth Scanning**: The app continuously scans for nearby Bluetooth devices
2. **Device Filtering**: Only phones, tablets, and computers are added (excludes headphones, speakers, watches, etc.)
3. **Bonded Devices**: Paired devices that match the filter are automatically added
4. **Nearby Devices**: Discoverable mesh-capable devices are added as peers
5. **Auto-Refresh**: Scanning restarts every 30 seconds automatically
6. **Manual Refresh**: Tap the refresh button (🔄) in the app bar to trigger immediate scan

### Device Filtering

The app intelligently filters Bluetooth devices to show only those capable of acting as mesh nodes:

**✅ Included (Valid Mesh Nodes):**
- Smartphones (Android, iPhone)
- Tablets (iPad, Galaxy Tab, etc.)
- Computers (laptops, desktops, MacBooks)

**❌ Excluded (Cannot Relay Messages):**
- Headphones and earbuds
- Bluetooth speakers
- Smartwatches and fitness bands
- Car Bluetooth systems
- TVs and remotes
- Keyboards and mice
- Other IoT devices

This ensures your peers list only shows devices that can:
- Run the PeerChat app
- Relay messages through the mesh network
- Act as intermediate hops for routing

### Why You See "No Peers Discovered"

You'll see this message if:
- No other **phones, tablets, or computers** are running the app nearby
- Bluetooth is disabled on your device
- No compatible devices are paired/bonded (headphones don't count!)
- Location permission not granted (required for Bluetooth scanning)
- Other devices are out of Bluetooth range

**Note**: The app filters out headphones, speakers, watches, and other devices that cannot run the app or relay messages.

### To Test Peer Discovery

**Option 1: Use Another Phone/Tablet**
1. Install the app on 2+ Android devices (phones or tablets)
2. Make sure Bluetooth is enabled on all devices
3. Keep devices within 10 meters of each other
4. Open the app on all devices
5. Devices should discover each other via Bluetooth scanning

**Option 2: Pair with Another Phone/Computer**
1. Pair your phone with another smartphone, tablet, or computer
2. Open the app
3. The paired device should appear in the Peers list

**Option 3: Make Device Discoverable**
1. Go to Android Settings → Bluetooth
2. Make your device discoverable
3. Open the app on another phone/tablet
4. The discoverable device should appear in Peers list

**Important**: Pairing with headphones, speakers, or smartwatches will NOT add them to the peers list, as they cannot run the app or relay messages.

## Building and Installing

### For Physical Devices
```bash
# Build APK
flutter build apk --release

# Install on connected device
flutter install

# Or build and run directly
flutter run --release
```

### For Emulator
```bash
# List available emulators
flutter emulators

# Launch emulator
flutter emulators --launch <emulator_id>

# Run app on emulator
flutter run
```

## Test Scenarios

### 1. Direct Messaging Test
**Goal**: Verify basic message sending between two directly connected devices

**Steps**:
1. Open app on Device A and Device B
2. Wait for devices to discover each other (check Peers list)
3. On Device A, tap chat icon → select Device B → send message
4. Verify message appears on Device B
5. Check Mesh Status Card shows 1 active route

**Expected Result**: Message delivered directly, status shows "Message sent successfully"

### 2. Multi-Hop Routing Test
**Goal**: Verify messages route through intermediate device

**Setup**:
- Device A and Device C out of direct range
- Device B in range of both A and C

**Steps**:
1. Open app on all 3 devices
2. Verify Device B can see both A and C in peers list
3. On Device A, send message to Device C
4. Message should route: A → B → C
5. Check Mesh Status Card on Device B shows forwarding activity

**Expected Result**: Message reaches Device C through Device B relay

### 3. Store-and-Forward Test
**Goal**: Verify messages queue when recipient unavailable

**Steps**:
1. Close app on Device B (recipient)
2. On Device A, send message to Device B
3. Check status shows "Message queued (no route available)"
4. Check Mesh Status Card shows 1 queued message
5. Open app on Device B
6. Verify message delivers within 10 seconds

**Expected Result**: Message queues and delivers when recipient reconnects

### 4. Priority Handling Test
**Goal**: Verify high priority messages sent first

**Steps**:
1. Close app on Device B
2. On Device A, send 3 messages to Device B:
   - Message 1: Low priority
   - Message 2: Normal priority
   - Message 3: High priority
3. Open app on Device B
4. Verify messages arrive in order: High → Normal → Low

**Expected Result**: High priority message delivers first

### 5. Delivery Acknowledgment Test
**Goal**: Verify sender receives delivery confirmation

**Steps**:
1. On Device A, send message to Device B
2. Wait for delivery
3. Check Mesh Status Card on Device A
4. Pending Acks should increment then decrement
5. Check logs for "Message delivered successfully"

**Expected Result**: Acknowledgment routes back to sender

### 6. Route Discovery Test
**Goal**: Verify automatic route discovery

**Steps**:
1. Start with all devices connected
2. Note active routes in Mesh Status Card
3. Move Device C out of range
4. Wait 30 minutes (or manually trigger route expiration)
5. Move Device C back in range
6. Send message from A to C
7. Verify route rediscovered automatically

**Expected Result**: New route discovered and message delivered

### 7. Bluetooth vs WiFi Fallback Test
**Goal**: Verify transport layer fallback

**Steps**:
1. Disable WiFi on all devices
2. Send message (should use Bluetooth)
3. Enable WiFi, disable Bluetooth
4. Send message (should use WiFi Direct)
5. Enable both
6. Send message (uses whichever connects first)

**Expected Result**: Messages send regardless of transport availability

## Monitoring and Debugging

### Mesh Status Card
Monitor real-time statistics:
- **Active Routes**: Should increase as peers connect
- **Queued Messages**: Should be 0 in normal operation
- **Pending Acks**: Temporary, should clear quickly
- **Blocked Peers**: Should be 0 (indicates security issues)

### Flutter Logs
```bash
# View logs from connected device
flutter logs

# Filter for mesh routing logs
flutter logs | grep "Mesh\|Route\|Message"
```

### Key Log Messages
- "WiFi Direct advertising started" - WiFi transport active
- "Bluetooth server mode" - Bluetooth transport active
- "Message received from..." - Message delivered
- "Message sent successfully" - Message transmitted
- "Route discovery initiated" - Looking for path

## Troubleshooting

### Devices Not Discovering Each Other
**Bluetooth Discovery Issues:**
- ✅ Check Bluetooth is enabled on all devices
- ✅ Grant Location permission (Settings → Apps → PeerChat → Permissions)
- ✅ Make sure devices are within 10 meters (Bluetooth range)
- ✅ Try pairing devices first (Settings → Bluetooth → Pair new device)
- ✅ Tap the refresh button (🔄) in the app to trigger manual scan
- ✅ Check if device name is visible (some devices hide their name)
- ✅ Restart the app if Bluetooth was just enabled

**WiFi Discovery Issues (mDNS - currently limited):**
- ⚠️ WiFi-based discovery (mDNS) is not fully implemented
- ⚠️ The app relies primarily on Bluetooth for peer discovery
- ✅ Ensure devices are on same WiFi network (for future WiFi Direct transport)
- ✅ Check Android network is set to "Private"

**Quick Test:**
1. Pair your phone with another smartphone, tablet, or computer
2. Open the app
3. The paired device should appear in Peers list immediately

**Note**: Headphones, speakers, and other audio devices are filtered out as they cannot act as mesh nodes.

### Messages Not Sending
- Check recipient peer ID is correct
- Verify active routes exist (Mesh Status Card)
- Check queued messages count
- Review logs for errors

### High Queued Message Count
- Indicates connectivity issues
- Check transport layer status
- Verify peers are in range
- Wait for automatic retry (every 10 seconds)

### Blocked Peers
- Indicates invalid signatures detected
- May indicate compromised device
- Peers auto-unblock after 10 minutes
- Check crypto service initialization

## Performance Metrics

### Expected Behavior
- **Route Discovery**: < 5 seconds
- **Direct Message**: < 1 second
- **Multi-Hop Message**: < 3 seconds
- **Queue Processing**: Every 10 seconds
- **Route Expiration**: 30 minutes
- **Maintenance Tasks**: Every 5 minutes

### Resource Usage
- **Battery**: Moderate (Bluetooth/WiFi scanning)
- **Storage**: Minimal (SQLite database)
- **Network**: Low (only mesh traffic)

## Security Testing

### Encryption Verification
- Messages should be unreadable in transit
- Only sender and recipient can decrypt
- Relay nodes cannot read content

### Signature Verification
- Invalid signatures rejected
- Malicious peers blocked after 3 attempts
- Auto-unblock after 10 minutes

### Replay Attack Prevention
- Old messages (>5 minutes) rejected
- Future-dated messages rejected
- Duplicate messages discarded

## Success Criteria

✅ All 3 devices discover each other
✅ Direct messages deliver in < 1 second
✅ Multi-hop routing works correctly
✅ Store-and-forward queues and delivers
✅ Priority handling works as expected
✅ Delivery acknowledgments received
✅ Route discovery automatic
✅ Transport fallback functional
✅ No blocked peers (security working)
✅ Mesh Status Card updates in real-time

## Known Limitations

- Bluetooth Classic has limited range (~10m)
- WiFi Direct requires same network
- Route discovery takes a few seconds
- Maximum message size: 64 KB
- Maximum TTL: 16 hops
- Queue expires after 48 hours

## Next Steps After Testing

1. Optimize route selection algorithm
2. Add message history/chat UI
3. Implement group messaging
4. Add file transfer support
5. Optimize battery usage
6. Add network topology visualization
7. Implement CRDT for offline editing
8. Add voice message support

Happy Testing! 🚀

