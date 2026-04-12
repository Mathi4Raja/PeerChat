# Two-Device Automation (Direct + File Focus)

Use this for repeatable smoke runs on your two phones without manual log copy/paste.

## 1) Run dual-device smoke capture

```powershell
powershell -ExecutionPolicy Bypass -File tools/two_device_smoke.ps1 `
  -DeviceA 1207031462120918 `
  -DeviceB 9T19545LA1222404340 `
  -DurationSec 180
```

If `adb` is not on PATH:

```powershell
powershell -ExecutionPolicy Bypass -File tools/two_device_smoke.ps1 `
  -DeviceA 1207031462120918 `
  -DeviceB 9T19545LA1222404340 `
  -DurationSec 180 `
  -AdbPath ".\platform-tools\adb.exe"
```

What it does:
- validates both ADB device serials
- clears `logcat` on both devices
- launches app on both devices
- captures `logcat` from both devices in parallel
- prints a quick summary (errors, connect/disconnect, keepalive TX/RX)

Optional visible relaunch mode:

```powershell
powershell -ExecutionPolicy Bypass -File tools/two_device_smoke.ps1 `
  -DeviceA 1207031462120918 `
  -DeviceB 9T19545LA1222404340 `
  -DurationSec 120 `
  -VisibleRelaunch `
  -RelaunchEverySec 30 `
  -AdbPath ".\platform-tools\adb.exe"
```

Output:
- `automation_logs/run-<timestamp>/device-<serial>.log`

## 2) Manual actions during capture (recommended)

During the capture window:
1. Send a direct text message both ways.
2. Send one file both ways.
3. Background/foreground one app once.
4. Force-close and reopen one app once.

This gives enough signal to debug:
- reconnect latency
- queue vs pending ACK state transitions
- file transfer resume/recovery behavior

## 3) What to check in logs

Search for:
- `WiFi Direct connected`
- `Handshake complete`
- `Received keepalive`
- `Error starting WiFi Direct discovery`
- `STATUS_OUT_OF_ORDER_API_CALL`
- `couldNotConnect`
- `RenderFlex overflowed`

