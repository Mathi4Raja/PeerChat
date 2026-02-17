# Immediate Fix Plan for Messaging

## Current Status

Created foundation for proper peer connection management:
- ✅ `HandshakeMessage` model for key exchange
- ✅ `ConnectionManager` for ID mapping
- ✅ Database support for peer public keys
- ✅ Updated `SignatureVerifier` to use database keys

## Remaining Work

### 1. Integrate ConnectionManager into MeshRouter

- Add ConnectionManager instance to MeshRouterService
- Initialize it during init()
- Wire up handshake sending callback

### 2. Update Transport Services

**BluetoothTransport:**
- Notify ConnectionManager when connection established
- Detect and handle handshake messages
- Forward non-handshake messages to mesh router

**WiFiTransport:**
- Same as Bluetooth

### 3. Update Message Sending Flow

**Current broken flow:**
```
ChatScreen → MeshRouter.sendMessage(cryptoPeerId)
→ RouteManager.getNextHop(cryptoPeerId)
→ Returns cryptoPeerId (direct connection)
→ Transport.sendMessage(cryptoPeerId) ❌ FAILS - no such connection
```

**Fixed flow:**
```
ChatScreen → MeshRouter.sendMessage(cryptoPeerId)
→ ConnectionManager.getTransportId(cryptoPeerId)
→ Transport.sendMessage(transportId) ✅ WORKS
```

### 4. Update Peer Discovery

- When peer discovered via Bluetooth/WiFi, store with transport ID
- After handshake, update peer record with crypto ID
- Keep transport ID in address field for routing

### 5. Testing Steps

1. Build and install on both devices
2. Check logs for "Connection established" messages
3. Check logs for "Handshake complete" messages
4. Verify peers appear in "Connected" section
5. Try sending message
6. Check logs for message transmission

## Simplified Alternative (Faster)

If the above is too complex, we can do a quick hack:

1. **Skip handshake for now**
2. **Use transport IDs as peer IDs everywhere**
3. **Skip encryption temporarily** (just for testing)
4. **Get basic messaging working first**
5. **Add security later**

This would involve:
- Remove crypto peer ID requirement
- Use transport IDs in chat
- Send plain text messages
- Verify transport layer works
- Then add encryption back

## Recommendation

Try the simplified alternative first to verify transport layer works, then add security properly.
