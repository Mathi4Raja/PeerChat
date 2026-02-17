# Mesh Network FAQ

## Do intermediate hops need the app installed?

**YES, absolutely!** Every device in the routing path must have the PeerChat app installed and running.

### Why?

This is a **true mesh network**, not simple Bluetooth packet forwarding. Each hop must:

1. **Parse Messages**: Deserialize the encrypted mesh message structure
2. **Verify Security**: Check Ed25519 signatures to prevent tampering
3. **Check Validity**: Verify TTL, hop count, timestamps
4. **Route Intelligently**: Look up routing tables, make forwarding decisions
5. **Handle Failures**: Store-and-forward when next hop unavailable
6. **Send Acknowledgments**: Route delivery confirmations back to sender
7. **Prevent Attacks**: Maintain deduplication cache, block malicious peers

### Example Routing Path

```
Alice → Bob → Carol → Dave
[App]   [App]  [App]   [App]
```

**What Bob's device does (intermediate hop):**
1. Receives encrypted message from Alice via Bluetooth
2. Deserializes the MeshMessage structure
3. Verifies Alice's signature using Ed25519
4. Checks TTL (time-to-live) hasn't expired
5. Looks up routing table: "Where is Dave?"
6. Finds route: Dave is reachable via Carol
7. Decrements TTL, increments hop count
8. Re-signs the message with Bob's signature
9. Forwards to Carol via Bluetooth/WiFi
10. Waits for acknowledgment from Carol
11. If Carol unreachable, queues message (store-and-forward)

**This requires:**
- Flutter app runtime
- Dart VM
- libsodium cryptographic library
- SQLite database
- Routing algorithms
- Message queue management

### What devices CAN be hops?

✅ **Smartphones** (Android, iPhone)
- Can run Flutter apps
- Have sufficient CPU/memory
- Support background processing
- Have Bluetooth/WiFi

✅ **Tablets** (iPad, Galaxy Tab, etc.)
- Can run Flutter apps
- Larger battery for longer relay time
- Good for stationary relay nodes

✅ **Computers** (Laptops, Desktops)
- Can run Flutter desktop apps
- Always-on capability
- Powerful relay nodes
- Can handle many connections

### What devices CANNOT be hops?

❌ **Bluetooth Headphones/Speakers**
- Proprietary firmware (no app support)
- Audio-only devices
- Cannot run applications
- Cannot process routing logic

❌ **Smartwatches**
- Limited OS (WearOS, watchOS)
- Cannot run full Flutter apps
- Insufficient resources
- Limited battery life

❌ **Car Bluetooth Systems**
- Proprietary OS
- Cannot run Flutter apps
- Not always available
- Limited to car environment

❌ **IoT Devices** (TVs, Keyboards, Mice)
- Embedded systems
- Different architecture
- No Flutter runtime
- Cannot run applications

## Can I use Bluetooth as a "dumb relay"?

**No.** Bluetooth doesn't work that way for application data.

### Why not?

1. **Bluetooth Profiles**: Standard Bluetooth profiles (A2DP for audio, HID for input) don't support arbitrary data relay
2. **No Transparent Forwarding**: Bluetooth devices don't automatically forward packets
3. **Application Layer**: Our mesh protocol operates at the application layer, not the Bluetooth layer
4. **Security**: Each hop must verify signatures and prevent replay attacks
5. **Routing Logic**: Each hop must make intelligent forwarding decisions

### What about Bluetooth Mesh?

**Bluetooth Mesh** (BLE Mesh) is a different technology:
- Uses Bluetooth Low Energy (BLE), not Bluetooth Classic
- Requires special hardware support
- Has its own protocol stack
- Not compatible with standard Bluetooth
- Not supported by flutter_blue_classic

Our implementation uses **Bluetooth Classic** for transport, but the mesh routing logic is implemented in the application layer.

## How does message forwarding work?

### Step-by-Step Example

**Scenario**: Alice sends message to Dave through Bob and Carol

```
Alice's Phone → Bob's Tablet → Carol's Laptop → Dave's Phone
```

**1. Alice's Phone (Sender):**
```dart
1. Encrypt message content with Dave's public key
2. Create MeshMessage structure
3. Sign message with Alice's private key
4. Look up route to Dave → finds Bob as next hop
5. Send to Bob via Bluetooth
```

**2. Bob's Tablet (Intermediate Hop #1):**
```dart
1. Receive message from Alice via Bluetooth
2. Deserialize MeshMessage
3. Verify Alice's signature ✓
4. Check TTL (15 remaining) ✓
5. Check deduplication cache (not seen before) ✓
6. Look up route to Dave → finds Carol as next hop
7. Decrement TTL (14), increment hop count (1)
8. Re-sign message with Bob's signature
9. Forward to Carol via WiFi Direct
10. Add to pending acks list
```

**3. Carol's Laptop (Intermediate Hop #2):**
```dart
1. Receive message from Bob via WiFi
2. Deserialize MeshMessage
3. Verify Bob's signature ✓
4. Check TTL (14 remaining) ✓
5. Check deduplication cache (not seen before) ✓
6. Look up route to Dave → finds Dave directly connected
7. Decrement TTL (13), increment hop count (2)
8. Re-sign message with Carol's signature
9. Forward to Dave via Bluetooth
10. Add to pending acks list
```

**4. Dave's Phone (Receiver):**
```dart
1. Receive message from Carol via Bluetooth
2. Deserialize MeshMessage
3. Verify Carol's signature ✓
4. Check TTL (13 remaining) ✓
5. Recognize self as recipient
6. Decrypt message content with Dave's private key
7. Display message to user
8. Generate acknowledgment
9. Send ack back to Carol (who forwards to Bob, who forwards to Alice)
```

### Key Points

- Each hop **must** verify signatures
- Each hop **must** check TTL and deduplication
- Each hop **must** look up routing tables
- Each hop **must** handle store-and-forward
- Each hop **must** send acknowledgments

**This is impossible without the app installed!**

## What if a hop device turns off?

### Store-and-Forward

If an intermediate hop becomes unavailable:

1. **Previous hop detects failure** (no ack received)
2. **Message queued** in SQLite database
3. **Periodic retry** every 10 seconds
4. **Alternative route** discovered if available
5. **Message expires** after 48 hours if undeliverable

### Example

```
Alice → Bob → [Carol OFFLINE] → Dave
```

**What happens:**
1. Bob tries to forward to Carol
2. Carol doesn't respond (offline)
3. Bob queues message in SQLite
4. Bob initiates route discovery for alternative path
5. If found: Bob → Eve → Dave (new route)
6. If not found: Message stays queued until Carol comes back online
7. When Carol reconnects: Bob forwards queued message

**This requires Bob to have the app running!**

## Can I use WiFi routers as hops?

**No.** WiFi routers operate at the network layer (Layer 3), not the application layer (Layer 7).

### Why not?

1. **Different Layer**: Routers forward IP packets, not application messages
2. **No App Logic**: Routers can't run Flutter apps
3. **No Encryption**: Routers can't decrypt/verify our messages
4. **No Routing Logic**: Routers don't understand our mesh protocol

### What about WiFi Direct?

**WiFi Direct** is used as a **transport layer** in PeerChat, but:
- The mesh routing logic still runs in the app
- Each device must have the app installed
- WiFi Direct just provides faster data transfer than Bluetooth
- The app handles all routing, encryption, and verification

## Summary

### ✅ Required for ALL nodes (sender, receiver, hops):
- PeerChat app installed
- Flutter runtime
- Bluetooth/WiFi enabled
- Sufficient battery/resources
- Background processing capability

### ❌ Cannot be used as hops:
- Bluetooth headphones/speakers
- Smartwatches
- Car Bluetooth systems
- IoT devices
- WiFi routers
- Any device that can't run Flutter apps

### 🎯 Key Takeaway:
**Every device in the mesh network must be a smartphone, tablet, or computer with the PeerChat app installed and running.**

This is a **true peer-to-peer mesh network** where each peer is an intelligent routing node, not a simple packet forwarder.
