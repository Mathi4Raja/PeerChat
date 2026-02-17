# Peers List UI - Connected vs Discovered

## New UI Layout

The peers list now separates peers into two sections:

### 1. Connected Peers (Active Connections)
- Peers with active Bluetooth/WiFi connections
- Can send/receive messages immediately
- Green indicators and "Active" badge
- These are actual mesh hops available right now

### 2. Discovered Peers (Available but Not Connected)
- Peers found via Bluetooth scanning
- Not currently connected
- Grey indicators and "Available" badge
- Can be connected to when needed

## Visual Mockup

```
┌─────────────────────────────────────────┐
│ Peers                          3 total  │
├─────────────────────────────────────────┤
│                                         │
│ 🔗 Connected (2)                        │
│                                         │
│ 📱 John's Phone                [Active] │
│    A4:5E:60:E8:7B:2C                   │
│                                         │
│ 📱 Sarah's Tablet              [Active] │
│    B8:27:EB:12:34:56                   │
│                                         │
│ 🔍 Discovered (1)                       │
│                                         │
│ 📱 Mike's Laptop            [Available] │
│    C9:38:FC:23:45:67                   │
│                                         │
└─────────────────────────────────────────┘
```

## Color Coding

### Connected Peers
- **Icon**: 🔗 Green link icon
- **Device Icon**: 📱 Green phone icon
- **Badge**: Green "Active" badge
- **Meaning**: Ready to relay messages immediately

### Discovered Peers
- **Icon**: 🔍 Blue search icon
- **Device Icon**: 📱 Grey phone icon
- **Badge**: Grey "Available" badge
- **Meaning**: Can be connected when needed

## Benefits

### For Users
✅ **Clear Status**: Instantly see which peers are connected
✅ **Mesh Visibility**: Understand which devices can relay messages
✅ **Network Health**: Monitor connection status at a glance
✅ **Troubleshooting**: Identify connectivity issues easily

### For Mesh Routing
✅ **Active Hops**: Connected peers can relay messages now
✅ **Potential Hops**: Discovered peers can be connected if needed
✅ **Route Planning**: Router knows which peers are immediately available
✅ **Automatic Connection**: Can connect to discovered peers when routing

## Example Scenarios

### Scenario 1: Good Mesh Network
```
Connected (3)
├─ John's Phone      [Active]
├─ Sarah's Tablet    [Active]
└─ Mike's Laptop     [Active]

Discovered (0)

Status: ✅ Strong mesh network
        All discovered peers are connected
        Messages can route through any peer
```

### Scenario 2: Partial Connectivity
```
Connected (1)
└─ John's Phone      [Active]

Discovered (2)
├─ Sarah's Tablet    [Available]
└─ Mike's Laptop     [Available]

Status: ⚠️ Limited mesh network
        Only 1 active connection
        2 peers available but not connected
        May need to connect for routing
```

### Scenario 3: No Connections
```
Connected (0)

Discovered (3)
├─ John's Phone      [Available]
├─ Sarah's Tablet    [Available]
└─ Mike's Laptop     [Available]

Status: ❌ No active connections
        Peers discovered but not connected
        Need to establish connections
        Messages will be queued
```

## Technical Implementation

### Connection Tracking

**Bluetooth Transport:**
```dart
// Tracks active Bluetooth connections
Map<String, BluetoothConnection> _connections = {};

List<String> getConnectedPeerIds() {
  return _connections.keys.where((peerId) {
    final connection = _connections[peerId];
    return connection != null && connection.isConnected;
  }).toList();
}
```

**WiFi Transport:**
```dart
// Tracks active WiFi Direct connections
Map<String, String> _connectedPeers = {}; // endpointId -> peerId

List<String> getConnectedPeerIds() {
  return _connectedPeers.values.toList();
}
```

### AppState Filtering

```dart
// Get connected peers (active connections)
List<Peer> get connectedPeers {
  final connectedIds = meshRouter.getConnectedPeerIds();
  return peers.where((p) => connectedIds.contains(p.id)).toList();
}

// Get discovered but not connected peers
List<Peer> get discoveredPeers {
  final connectedIds = meshRouter.getConnectedPeerIds();
  return peers.where((p) => !connectedIds.contains(p.id)).toList();
}
```

## User Experience Flow

### 1. App Launch
```
1. Bluetooth scan starts
2. Peers discovered → Added to "Discovered" section
3. App attempts connections
4. Successful connections → Moved to "Connected" section
```

### 2. Sending Message
```
1. User selects recipient
2. Router checks "Connected" section first
3. If recipient connected → Send immediately
4. If recipient in "Discovered" → Attempt connection
5. If connection fails → Queue message
```

### 3. Connection Lost
```
1. Bluetooth connection drops
2. Peer moved from "Connected" to "Discovered"
3. UI updates automatically
4. Router finds alternative route
```

### 4. Reconnection
```
1. Peer comes back in range
2. Bluetooth reconnects automatically
3. Peer moved from "Discovered" to "Connected"
4. Queued messages sent
```

## Comparison: Before vs After

### Before (Single List)
```
Peers (3)
├─ John's Phone
├─ Sarah's Tablet
└─ Mike's Laptop

Problem: Can't tell which are connected!
```

### After (Separated Sections)
```
Connected (2)
├─ John's Phone      [Active]
└─ Sarah's Tablet    [Active]

Discovered (1)
└─ Mike's Laptop     [Available]

Benefit: Clear connection status!
```

## Future Enhancements

### Possible Additions

**1. Connection Quality Indicator**
```
Connected (2)
├─ John's Phone      [Active] ●●●●● (Excellent)
└─ Sarah's Tablet    [Active] ●●●○○ (Good)
```

**2. Last Seen Timestamp**
```
Discovered (1)
└─ Mike's Laptop     [Available] (2 min ago)
```

**3. Transport Type**
```
Connected (2)
├─ John's Phone      [Active] 📶 Bluetooth
└─ Sarah's Tablet    [Active] 📡 WiFi Direct
```

**4. Manual Connect Button**
```
Discovered (1)
└─ Mike's Laptop     [Available] [Connect]
```

**5. Hop Count**
```
Connected (2)
├─ John's Phone      [Active] Direct
└─ Sarah's Tablet    [Active] 2 hops away
```

## Summary

The new UI provides clear visibility into mesh network status by separating:

**Connected Peers:**
- ✅ Active connections
- ✅ Can relay messages now
- ✅ Green indicators
- ✅ "Active" badge

**Discovered Peers:**
- ⚠️ Found but not connected
- ⚠️ Available for connection
- ⚠️ Grey indicators
- ⚠️ "Available" badge

This helps users understand:
- Which devices are actively participating in the mesh
- Which devices are available but not yet connected
- The overall health of the mesh network
- Potential routing paths for messages
