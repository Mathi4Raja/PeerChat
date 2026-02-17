# Dependency Update Notes

## Successfully Updated Dependencies

All dependencies have been updated to their latest stable versions and all breaking changes have been fixed:

- `cupertino_icons`: ^1.0.2 → ^1.0.8
- `qr_flutter`: ^4.0.0 → ^4.1.0
- `flutter_secure_storage`: ^8.0.0 → ^10.0.0
- `sqflite`: ^2.2.5 → ^2.4.1
- `path_provider`: ^2.0.14 → ^2.1.5
- `sodium`: ^2.3.1+1 → ^3.4.6
- `sodium_libs`: ^2.0.0 → ^3.4.6+4
- `provider`: ^6.0.5 → ^6.1.2
- `multicast_dns`: ^0.3.0 → ^0.3.2+8
- `uuid`: ^4.0.0 → ^4.5.1
- `flutter_bluetooth_serial`: ^0.4.0 → replaced with `flutter_blue_classic`: ^0.0.9
- `nearby_connections`: ^4.3.0 (kept, latest available)
- `permission_handler`: ^12.0.1 (kept, latest available)

## Breaking Changes Fixed

### 1. Sodium Library (v2.x → v3.x) ✅ FIXED

**Changes made**:
- Updated `SodiumInit.init()` to use `sodium_libs.SodiumInit.init()` (no parameters needed)
- Changed `KeyPair` to use `SecureKey.fromList(_sodium, bytes)` instead of `Uint8List`
- Updated `crypto.box.openEasy()` parameter from `ciphertext:` to `cipherText:`
- Used `keypair.secretKey.extractBytes()` to get bytes from SecureKey for storage
- Removed `SignKeyPair` type (now using `KeyPair` for both encryption and signing)

**Files fixed**:
- `lib/src/app_state.dart`
- `lib/src/services/crypto_service.dart`

### 2. QR Flutter (v4.0 → v4.1) ✅ FIXED

**Changes made**:
- Replaced `QrImage()` with `QrImageView()`
- Updated all QR code generation calls

**Files fixed**:
- `lib/src/widgets/identity_card.dart`
- `lib/src/screens/add_peer_screen.dart`

### 3. SelectableText Widget ✅ FIXED

**Changes made**:
- Removed `overflow` parameter from SelectableText

**Files fixed**:
- `lib/src/widgets/identity_card.dart`

### 4. Bluetooth Library Replacement ✅ FIXED

**Changes made**:
- Replaced `flutter_bluetooth_serial` with `flutter_blue_classic`
- Updated all Bluetooth API calls to match flutter_blue_classic
- Fixed null safety issues with connection handling
- Updated method calls (turnOn, startScan, stopScan are now void)

**Files fixed**:
- `lib/src/services/bluetooth_transport.dart`
- `pubspec.yaml`

### 5. Multicast DNS ✅ FIXED

**Changes made**:
- Changed `MDnsClient.stop()` from async to sync (no await needed)
- Fixed TXT record parsing to split by newline

**Files fixed**:
- `lib/src/services/discovery_service.dart`

### 6. MessagePriority Type ✅ FIXED

**Changes made**:
- Added import for `mesh_message.dart` to access MessagePriority enum

**Files fixed**:
- `lib/src/screens/chat_screen.dart`

## Build Status

✅ Android Gradle namespace issue resolved
✅ Dependencies updated successfully
✅ All code compilation errors fixed
✅ Build successful: `app-debug.apk` generated

## Notes

- The app now builds successfully on Android
- All breaking changes from dependency updates have been addressed
- Bluetooth functionality uses `flutter_blue_classic` which has better Android Gradle Plugin compatibility
- Sodium v3.x provides better security with SecureKey for key management
