# Messaging Debug Analysis

## Problem Identified

Messages are stuck in "sending" status because of multiple architectural issues:

### Issue 1: No Automatic Connection Establishment

**Discovery vs Connection:**
- `DiscoveryService` finds peers via Bluetooth/WiFi Direct
- Peers are added to database with transport-layer IDs
- **BUT**: No actual connection is established!
- `BluetoothTransport._connectToPeer()` is called during discovery, but connections may fail silently
- `WiFiTransport` only connects when `_onEndpointFound` is triggered

**Result:** When trying to send a message, the transport layer has no active connection to send through.

### Issue 2: Peer ID Mismatch

**Two ID Systems:**
1. **Transport IDs**: Bluetooth MAC addresses (AA:BB:CC:DD:EE:FF) or WiFi Direct endpoint IDs
2. **Cryptographic IDs**: Public key hashes used for encryption/signing

**Current Flow:**
- Peers discovered with transport IDs
- Messages sent to transport IDs
- But encryption expects cryptographic IDs
- No mapping between the two!

### Issue 3: Missing Public Keys

**Encryption Requirement:**
- `MessageManager.createMessage()` requires recipient's public key
- `_signatureVerifier.getPeerPublicKey(recipientPeerId)` is called
- **BUT**: Discovered peers don't have public keys in database!
- Only manually added peers (via QR code) have public keys

**Result:** Message creation likely fails or uses wrong keys.

### Issue 4: Route Discovery Not Working

**Route Manager Issues:**
- `RouteManager.getNextHop()` checks if peer exists in database
- Returns peer ID as next hop for direct connections
- **BUT**: Doesn't verify if connection actually exists
- Route discovery (`discoverRoute()`) is incomplete (marked with TODO)

## Root Cause

The app was designed for a mesh network with:
- Cryptographic peer IDs
- Public key exchange
- Route discovery protocol

But the current implementation uses:
- Transport-layer discovery (Bluetooth/WiFi Direct)
- No key exchange mechanism
- No connection establishment

**These two approaches are incompatible!**

## Solution Options

### Option A: Simplified Direct Messaging (Recommended)

For disaster relief use case, simplify to direct peer-to-peer:

1. **Remove cryptographic peer IDs** - use transport IDs only
2. **Establish connections on discovery** - auto-connect to discovered peers
3. **Exchange public keys over connection** - first message after connection
4. **Direct messaging only** - no multi-hop routing initially
5. **Add routing later** - once direct messaging works

### Option B: Fix Current Architecture

Keep mesh routing but fix the issues:

1. **Add peer ID mapping** - map transport IDs to crypto IDs
2. **Implement key exchange protocol** - exchange keys on first connection
3. **Fix connection establishment** - ensure connections are active
4. **Complete route discovery** - implement TODO sections
5. **Add connection monitoring** - track active connections

## Recommended Immediate Fix

Implement Option A (Simplified Direct Messaging):

1. Modify peer discovery to establish connections immediately
2. Exchange public keys as first message after connection
3. Store public keys in database
4. Send messages directly to connected peers only
5. Show only connected peers in chat peer selector

This will get messaging working quickly, then routing can be added incrementally.
