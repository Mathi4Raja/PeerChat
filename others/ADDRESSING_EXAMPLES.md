# Addressing Examples

## Real-World Example

### John's Phone

**Hardware:**
- Device: Samsung Galaxy S21
- Bluetooth chip: Has MAC `A4:5E:60:E8:7B:2C`
- WiFi chip: Has MAC `B8:27:EB:12:34:56`

**When PeerChat Runs:**
```
┌─────────────────────────────────────┐
│      John's Phone (Galaxy S21)      │
├─────────────────────────────────────┤
│ PeerChat App                        │
│ ├─ Public Key (Identity):           │
│ │   DCAIZali206cFn6d3A8e/M7D...    │
│ │                                   │
│ ├─ Bluetooth:                       │
│ │   MAC: A4:5E:60:E8:7B:2C         │
│ │   Name: "John's Phone"            │
│ │                                   │
│ └─ WiFi Direct:                     │
│     Endpoint: endpoint_abc123       │
│     Name: "John's Phone"            │
└─────────────────────────────────────┘
```

## Discovery Scenarios

### Scenario 1: Bluetooth Discovery

**Alice's phone discovers John's phone via Bluetooth:**

```
Alice's Phone                    John's Phone
     │                                │
     │  Bluetooth Scan                │
     ├───────────────────────────────>│
     │                                │
     │  Found: A4:5E:60:E8:7B:2C     │
     │  Name: "John's Phone"          │
     │<───────────────────────────────┤
     │                                │
     │  Add to peers list:            │
     │  id: A4:5E:60:E8:7B:2C        │
     │  name: John's Phone            │
     │  address: A4:5E:60:E8:7B:2C   │
     │                                │
```

**Result in Alice's app:**
```dart
Peer(
  id: "A4:5E:60:E8:7B:2C",        // Bluetooth MAC
  displayName: "John's Phone",
  address: "A4:5E:60:E8:7B:2C",   // Same as ID
  lastSeen: 1234567890,
)
```

### Scenario 2: WiFi Direct Discovery

**Alice's phone discovers John's phone via WiFi Direct:**

```
Alice's Phone                    John's Phone
     │                                │
     │  WiFi Direct Scan              │
     ├───────────────────────────────>│
     │                                │
     │  Found: endpoint_abc123        │
     │  Name: "John's Phone"          │
     │<───────────────────────────────┤
     │                                │
     │  Add to peers list:            │
     │  id: endpoint_abc123           │
     │  name: John's Phone            │
     │  address: endpoint_abc123      │
     │                                │
```

**Result in Alice's app:**
```dart
Peer(
  id: "endpoint_abc123",           // WiFi endpoint ID
  displayName: "John's Phone",
  address: "endpoint_abc123",      // Same as ID
  lastSeen: 1234567890,
)
```

### Scenario 3: Both Transports (Current Problem)

**Alice discovers John via BOTH Bluetooth and WiFi:**

```
Alice's Peers List:
┌────────────────────────────────────┐
│ Peers (2)                          │
├────────────────────────────────────┤
│ 📱 John's Phone                    │
│    ID: A4:5E:60:E8:7B:2C          │
│    Via: Bluetooth                  │
│                                    │
│ 📱 John's Phone                    │
│    ID: endpoint_abc123             │
│    Via: WiFi Direct                │
└────────────────────────────────────┘
```

**Problem:** Same device appears twice!

## Message Routing Example

### Current Implementation

**Alice wants to send message to John:**

```
Alice's Routing Table:
┌─────────────────────────────────────────────┐
│ Destination          Next Hop    Transport  │
├─────────────────────────────────────────────┤
│ A4:5E:60:E8:7B:2C   Direct      Bluetooth   │
│ endpoint_abc123      Direct      WiFi       │
└─────────────────────────────────────────────┘
```

**Alice must choose:**
- Send to `A4:5E:60:E8:7B:2C` via Bluetooth?
- Send to `endpoint_abc123` via WiFi?
- Are these the same person?

### With Public Key (Recommended)

**Alice wants to send message to John:**

```
Alice's Routing Table:
┌──────────────────────────────────────────────────────────┐
│ Destination (Public Key)    Next Hop    Transport        │
├──────────────────────────────────────────────────────────┤
│ DCAIZali206cFn6d3A8e...    Direct      Bluetooth         │
│                                         (A4:5E:60:...)    │
│                                                           │
│ DCAIZali206cFn6d3A8e...    Direct      WiFi              │
│                                         (endpoint_abc...) │
└──────────────────────────────────────────────────────────┘
```

**Alice knows:**
- Both routes go to the same person (same public key)
- Can choose best transport (WiFi faster, Bluetooth more reliable)
- Can failover if one transport fails

## Multi-Hop Routing Example

### Scenario: Alice → Bob → Carol → Dave

**Current Implementation (Bluetooth MACs):**

```
Alice's Phone          Bob's Tablet         Carol's Laptop       Dave's Phone
A4:5E:60:E8:7B:2C     B8:27:EB:12:34:56    C9:38:FC:23:45:67   D0:49:0D:34:56:78
       │                     │                     │                    │
       │  To: D0:49:0D:...  │                     │                    │
       │  Via: B8:27:EB:... │                     │                    │
       ├────────────────────>│  To: D0:49:0D:...  │                    │
       │                     │  Via: C9:38:FC:... │                    │
       │                     ├────────────────────>│  To: D0:49:0D:... │
       │                     │                     │  Direct            │
       │                     │                     ├───────────────────>│
       │                     │                     │                    │
```

**With Public Keys:**

```
Alice's Phone          Bob's Tablet         Carol's Laptop       Dave's Phone
PubKey: AAA...        PubKey: BBB...       PubKey: CCC...       PubKey: DDD...
       │                     │                     │                    │
       │  To: DDD...        │                     │                    │
       │  Via: BBB...       │                     │                    │
       ├────────────────────>│  To: DDD...        │                    │
       │                     │  Via: CCC...       │                    │
       │                     ├────────────────────>│  To: DDD...        │
       │                     │                     │  Direct            │
       │                     │                     ├───────────────────>│
       │                     │                     │                    │
```

**Benefits:**
- Clear identity at each hop
- Can verify signatures
- Transport-agnostic routing
- Same peer ID across all devices

## Address Types Comparison

### Bluetooth MAC Address

```
Format:    XX:XX:XX:XX:XX:XX
Example:   A4:5E:60:E8:7B:2C
Length:    48 bits (6 bytes)
Encoding:  Hexadecimal

Properties:
✅ Globally unique
✅ Permanent (hardware)
✅ Works offline
❌ Privacy concerns (trackable)
```

### WiFi Endpoint ID

```
Format:    Variable string
Example:   endpoint_1234567890abcdef
Length:    Variable
Encoding:  ASCII/UTF-8

Properties:
❌ Not globally unique
❌ Temporary (session-based)
✅ Works offline (P2P)
✅ Privacy-friendly (changes)
```

### Public Key (Recommended)

```
Format:    Base64-encoded Ed25519 public key
Example:   DCAIZali206cFn6d3A8e/M7DPIPi7Fc/iqhhFBxizn0=
Length:    256 bits (32 bytes) → 44 chars base64
Encoding:  Base64

Properties:
✅ Globally unique (cryptographically)
✅ Permanent (user-controlled)
✅ Works offline
✅ Verifiable (signatures)
✅ Transport-agnostic
✅ Privacy-friendly (pseudonymous)
```

### IPv4 Address (Not Used)

```
Format:    XXX.XXX.XXX.XXX
Example:   192.168.1.100
Length:    32 bits (4 bytes)
Encoding:  Decimal

Properties:
❌ Not globally unique (NAT)
❌ Temporary (DHCP)
❌ Requires network infrastructure
❌ Not suitable for P2P mesh
```

## Summary

**Current State:**
```
Bluetooth Discovery → Peer ID = Bluetooth MAC
WiFi Discovery     → Peer ID = Endpoint ID
Same Device        → Appears as 2 different peers
```

**Recommended Future:**
```
Any Discovery      → Peer ID = Public Key
Transport Address  → Stored separately
Same Device        → Single peer, multiple addresses
```

**Answer to "Does it have something unique like IPv4?"**

Yes! Each transport has unique identifiers:

| Transport | Identifier | Like IPv4? | Permanent? |
|-----------|-----------|------------|------------|
| Bluetooth | MAC Address | ✅ Yes | ✅ Yes |
| WiFi | MAC Address | ✅ Yes | ✅ Yes* |
| WiFi Direct | Endpoint ID | ⚠️ Sort of | ❌ No |
| WiFi Network | IPv4 Address | ✅ Yes | ❌ No |
| **Recommended** | **Public Key** | ✅ **Better!** | ✅ **Yes** |

*Can be randomized for privacy

**Best Practice:** Use public key as peer ID, store transport addresses separately.
