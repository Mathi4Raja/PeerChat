# Device Setup Guide for PeerChat Testing

## Physical Android Devices Setup

### Step 1: Enable Developer Options
1. Go to **Settings** → **About Phone**
2. Find **Build Number** (usually at the bottom)
3. Tap **Build Number** 7 times rapidly
4. You'll see "You are now a developer!" message
5. Go back to **Settings** → **System** → **Developer Options** (now visible)

### Step 2: Enable USB Debugging
1. In **Developer Options**, scroll down
2. Enable **USB Debugging**
3. Enable **Install via USB** (if available)
4. Enable **USB debugging (Security settings)** (if available)

### Step 3: Connect Device to PC
1. Connect device via USB cable
2. On device, you'll see "Allow USB debugging?" popup
3. Check "Always allow from this computer"
4. Tap **Allow**

### Step 4: Verify Connection
```bash
# Check if device is detected
flutter devices

# You should see something like:
# Android SDK built for x86 (mobile) • emulator-5554 • android-x86 • Android 11 (API 30)
# SM G973F (mobile) • 1234567890ABCDEF • android-arm64 • Android 12 (API 31)
```

### Step 5: Enable Location Services
1. Go to **Settings** → **Location**
2. Turn **Location** ON
3. Set to **High accuracy** mode
4. This is required for Bluetooth and WiFi Direct discovery

### Step 6: Enable Bluetooth
1. Go to **Settings** → **Bluetooth**
2. Turn **Bluetooth** ON
3. Make device **Visible** (discoverable)
4. Keep Bluetooth screen open during first test

### Step 7: Enable WiFi
1. Go to **Settings** → **WiFi**
2. Turn **WiFi** ON
3. Connect to your home/test WiFi network
4. **Important**: Set network to **Private** (not Public/Guest)

### Step 8: Grant App Permissions (After Installation)
When you first run the app, it will request permissions:
1. **Location** - Tap **Allow all the time** (required for Bluetooth/WiFi)
2. **Bluetooth** - Tap **Allow**
3. **Nearby devices** - Tap **Allow**
4. **Files and media** - Tap **Allow** (if prompted)

## Android Emulator Setup

### Step 1: Create Emulator (if not exists)
```bash
# List available system images
flutter emulators

# Create new emulator (if needed)
# Use Android Studio AVD Manager for easier setup
```

### Step 2: Launch Emulator
```bash
# Launch emulator
flutter emulators --launch <emulator_name>

# Or from Android Studio:
# Tools → Device Manager → Play button on emulator
```

### Step 3: Emulator Network Configuration
1. Emulator automatically connects to host PC's network
2. Can communicate with physical devices on same WiFi
3. Bluetooth support is limited in emulator (use WiFi Direct)

### Step 4: Emulator Permissions
Permissions are auto-granted in debug mode, but you can verify:
1. Settings → Apps → PeerChat → Permissions
2. Ensure all permissions are granted

## Network Configuration

### For Home WiFi Testing
1. **Connect all devices to same WiFi network**
2. **Windows PC only** (for emulator): Set network to "Private" 
   - Windows Settings → Network & Internet → WiFi → Your Network → Network profile → Private
   - This allows local network discovery for the emulator
3. **Android devices**: No special network settings needed - just connect to WiFi normally
4. **Disable PC firewall temporarily** (if blocking discovery)
5. **Use 2.4GHz WiFi** (better range than 5GHz)

### For Bluetooth-Only Testing
1. Turn OFF WiFi on all devices
2. Keep devices within 10 meters
3. Ensure no obstacles between devices
4. Bluetooth works better in open spaces

### For WiFi Direct Testing
1. WiFi must be ON (but doesn't need to be connected)
2. Location must be enabled
3. Devices will create direct P2P connection
4. No router needed for WiFi Direct

## Installation Methods

### Method 1: Direct Install (Recommended for Testing)
```bash
# Connect device via USB
# Run on specific device
flutter run -d <device_id>

# Run on all connected devices
flutter run -d all
```

### Method 2: Build APK and Install Manually
```bash
# Build release APK
flutter build apk --release

# APK location: build/app/outputs/flutter-apk/app-release.apk

# Install on connected device
flutter install -d <device_id>

# Or copy APK to device and install manually
```

### Method 3: Share APK via File Transfer
```bash
# Build APK
flutter build apk --release

# Transfer APK to devices via:
# - USB cable
# - Email
# - Cloud storage (Google Drive, Dropbox)
# - Bluetooth file transfer
# - Nearby Share (Android)

# On device: Open APK file → Install
# May need to enable "Install from unknown sources"
```

## Testing Configuration

### Recommended Setup for 3-Device Test

**Device A (Physical Phone 1):**
- Your primary phone
- USB debugging enabled
- Connected to PC for logs
- Role: Message sender

**Device B (Emulator on PC):**
- Running on your PC
- Automatically connected for logs
- Role: Relay node (middle hop)

**Device C (Physical Phone 2):**
- Your secondary phone or borrowed device
- USB debugging enabled (optional)
- Role: Message recipient

### Alternative Setup (All Physical Devices)

**Device A (Your Phone):**
- Connected to PC via USB
- Developer mode enabled
- Role: Sender

**Device B (Sister's Phone):**
- No USB connection needed
- Install APK via file transfer
- Role: Relay

**Device C (Friend's Phone):**
- No USB connection needed
- Install APK via file transfer
- Role: Recipient

## Troubleshooting Device Setup

### "Device not detected" by Flutter
```bash
# Check USB connection
adb devices

# If "unauthorized", check phone for USB debugging prompt
# If "offline", restart adb:
adb kill-server
adb start-server
```

### "Install failed" Error
1. Uninstall any existing version of the app
2. Enable "Install via USB" in Developer Options
3. Check storage space on device
4. Try different USB cable/port

### Permissions Not Granted
1. Go to Settings → Apps → PeerChat → Permissions
2. Manually grant all permissions
3. Restart the app

### Bluetooth Not Working
1. Unpair all Bluetooth devices
2. Turn Bluetooth OFF then ON
3. Make device discoverable
4. Check Location is enabled

### WiFi Direct Not Working
1. Disconnect from WiFi network (but keep WiFi ON)
2. Enable Location services
3. Grant "Nearby devices" permission
4. Restart app

### Devices Not Discovering Each Other
1. Ensure all devices on same WiFi network
2. Check firewall settings (disable temporarily)
3. Verify Location permission granted
4. Keep devices within 10 meters
5. Wait 30 seconds for discovery

## Quick Setup Checklist

### Physical Device Checklist
- [ ] Developer Options enabled
- [ ] USB Debugging enabled
- [ ] Device connected to PC (optional)
- [ ] Location services ON
- [ ] Bluetooth ON and discoverable
- [ ] WiFi ON and connected to network
- [ ] App installed
- [ ] All permissions granted

### Emulator Checklist
- [ ] Emulator created and launched
- [ ] Connected to host network
- [ ] App installed
- [ ] Permissions granted (auto in debug)

### Network Checklist
- [ ] All devices on same WiFi network
- [ ] Windows PC network set to "Private" (for emulator only)
- [ ] PC firewall not blocking (test by disabling temporarily)
- [ ] Devices within range (10m for Bluetooth, 100m for WiFi)

## First Run Instructions

### 1. Install on All Devices
```bash
# From PC, with all devices connected:
flutter run -d all
```

### 2. Grant Permissions on Each Device
- Tap "Allow" for all permission requests
- Choose "Allow all the time" for Location

### 3. Wait for Discovery
- Open app on all devices
- Wait 30 seconds
- Check "Peers" list on home screen
- Should see other devices appear

### 4. Test Basic Connectivity
- On Device A, tap chat icon
- Select Device B from dropdown
- Send test message: "Hello from A"
- Check Device B receives message

### 5. Monitor Mesh Status
- Check "Mesh Network Status" card
- Should show:
  - Active Routes: 2 (A→B, A→C)
  - Queued Messages: 0
  - Pending Acks: 0
  - Blocked Peers: 0

## Tips for Smooth Testing

1. **Keep devices close** during initial setup (within 5 meters)
2. **Use same WiFi network** for all devices
3. **Disable mobile data** to force local connectivity
4. **Keep screens on** during testing (prevents sleep)
5. **Monitor logs** on PC for debugging
6. **Test one scenario at a time** (don't rush)
7. **Restart app** if discovery fails
8. **Check battery** - Bluetooth/WiFi drain battery quickly

## Ready to Test!

Once all devices show each other in the Peers list, you're ready to follow the TESTING_GUIDE.md for detailed test scenarios.

Good luck! 🚀

