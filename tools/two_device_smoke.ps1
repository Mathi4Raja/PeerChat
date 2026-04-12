param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceA,

    [Parameter(Mandatory = $true)]
    [string]$DeviceB,

    [string]$AppId = "com.example.peerchat_secure",
    [string]$MainActivity = ".MainActivity",
    [int]$DurationSec = 180,
    [string]$OutputRoot = "automation_logs",
    [string]$AdbPath = "adb",
    [switch]$VisibleRelaunch,
    [int]$RelaunchEverySec = 45,
    [switch]$StrongVisualRelaunch
)

$ErrorActionPreference = "Stop"
$adb = $AdbPath

if (-not (Get-Command $adb -ErrorAction SilentlyContinue)) {
    throw "ADB not found. Pass -AdbPath with your adb.exe full path, e.g. -AdbPath `".\platform-tools\adb.exe`"."
}

function Ensure-DeviceConnected {
    param([string]$Serial)
    $devices = & $adb devices
    $matchingLine = $devices | Where-Object { $_ -match "^$([regex]::Escape($Serial))\s+device$" } | Select-Object -First 1
    if (-not $matchingLine) {
        throw "Device '$Serial' is not connected (adb state != device)."
    }
}

function Invoke-Adb {
    param(
        [string]$Serial,
        [Alias('Args')]
        [string[]]$CmdArgs
    )
    & $adb -s $Serial @CmdArgs
}

function Get-FocusLines {
    param([string]$Serial)
    $currentFocus = Invoke-Adb -Serial $Serial -Args @("shell", "dumpsys window | grep -i mCurrentFocus")
    $focusedApp = Invoke-Adb -Serial $Serial -Args @("shell", "dumpsys window | grep -i mFocusedApp")
    return @($currentFocus) + @($focusedApp)
}

function Is-AppForeground {
    param(
        [string]$Serial,
        [string]$AppId
    )
    $focusLines = Get-FocusLines -Serial $Serial
    if (-not $focusLines) { return $false }
    $combined = ($focusLines -join " ")
    return ($combined -match [regex]::Escape($AppId))
}

function Launch-AppForeground {
    param(
        [string]$Serial,
        [string]$AppId,
        [string]$MainActivity,
        [int]$MaxRetries = 3
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        Invoke-Adb -Serial $Serial -Args @("shell", "input", "keyevent", "KEYCODE_WAKEUP") | Out-Null
        Invoke-Adb -Serial $Serial -Args @("shell", "wm", "dismiss-keyguard") | Out-Null

        $startOut = Invoke-Adb -Serial $Serial -Args @("shell", "am", "start", "-W", "-n", "$AppId/$MainActivity")
        $statusLine = ($startOut | Select-String -Pattern "^Status:").Line
        if (-not $statusLine) { $statusLine = "Status: unknown" }
        $launchStateLine = ($startOut | Select-String -Pattern "^LaunchState:").Line
        if (-not $launchStateLine) { $launchStateLine = "LaunchState: unknown" }

        # Poll foreground state to tolerate slow cold starts/OEM launch latency.
        for ($probe = 1; $probe -le 12; $probe++) {
            Start-Sleep -Milliseconds 800
            if (Is-AppForeground -Serial $Serial -AppId $AppId) {
                Write-Host "[$Serial] launch ok ($statusLine, $launchStateLine, probe=$probe)"
                return $true
            }
        }

        # Fallback launcher path (sometimes more reliable on OEM ROMs).
        Invoke-Adb -Serial $Serial -Args @("shell", "monkey", "-p", $AppId, "-c", "android.intent.category.LAUNCHER", "1") | Out-Null
        for ($probe = 1; $probe -le 8; $probe++) {
            Start-Sleep -Milliseconds 800
            if (Is-AppForeground -Serial $Serial -AppId $AppId) {
                Write-Host "[$Serial] launch ok via monkey fallback (probe=$probe)"
                return $true
            }
        }

        if ($attempt -lt $MaxRetries) {
            Start-Sleep -Milliseconds 700
        }
    }

    $focusDebug = (Get-FocusLines -Serial $Serial) -join " || "
    if (-not $focusDebug) { $focusDebug = "<no focus lines>" }
    Write-Host "[$Serial] launch failed: app not in foreground after retries"
    Write-Host "[$Serial] focus debug: $focusDebug"
    return $false
}

function Force-Relaunch {
    param(
        [string]$Serial,
        [string]$AppId,
        [string]$MainActivity,
        [bool]$UseStrongVisualMarker = $false
    )
    # Home key first so relaunch is visually obvious.
    Invoke-Adb -Serial $Serial -Args @("shell", "input", "keyevent", "KEYCODE_HOME") | Out-Null
    Start-Sleep -Milliseconds 400
    Invoke-Adb -Serial $Serial -Args @("shell", "am", "force-stop", $AppId) | Out-Null
    Start-Sleep -Milliseconds 400

    if ($UseStrongVisualMarker) {
        # Open Settings briefly so UI automation is obvious to the user.
        Invoke-Adb -Serial $Serial -Args @("shell", "am", "start", "-a", "android.settings.SETTINGS") | Out-Null
        Start-Sleep -Milliseconds 2000
    }

    [void](Launch-AppForeground -Serial $Serial -AppId $AppId -MainActivity $MainActivity)
}

function Start-DeviceLogcat {
    param(
        [string]$Serial,
        [string]$LogPath
    )
    Start-Process -FilePath $adb `
        -ArgumentList @("-s", $Serial, "logcat", "-v", "time") `
        -NoNewWindow `
        -PassThru `
        -RedirectStandardOutput $LogPath `
        -RedirectStandardError "$LogPath.err"
}

function Stop-IfRunning {
    param($ProcessHandle)
    if ($null -ne $ProcessHandle -and -not $ProcessHandle.HasExited) {
        Stop-Process -Id $ProcessHandle.Id -Force -ErrorAction SilentlyContinue
    }
}

function Write-QuickSummary {
    param(
        [string]$Serial,
        [string]$LogPath
    )

    $content = Get-Content -Path $LogPath -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Write-Host "[$Serial] No log output."
        return
    }

    $exceptionCount = ($content | Select-String -Pattern "Exception|Error|ANR|FATAL EXCEPTION|RenderFlex overflowed").Count
    $connectCount = ($content | Select-String -Pattern "WiFi Direct connected|Handshake complete|Connection established with|Connected peers:\s+[1-9]").Count
    $disconnectCount = ($content | Select-String -Pattern "WiFi Direct disconnected|Connection lost with").Count
    $keepaliveRx = ($content | Select-String -Pattern "Received keepalive").Count
    $keepaliveTx = ($content | Select-String -Pattern "Sent keepalive").Count

    Write-Host ""
    Write-Host "=== $Serial summary ==="
    Write-Host "Exceptions/Errors: $exceptionCount"
    Write-Host "Connections:       $connectCount"
    Write-Host "Disconnects:       $disconnectCount"
    Write-Host "Keepalive TX/RX:   $keepaliveTx / $keepaliveRx"
}

Write-Host "Validating connected devices..."
Ensure-DeviceConnected -Serial $DeviceA
Ensure-DeviceConnected -Serial $DeviceB

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $OutputRoot "run-$timestamp"
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$logA = Join-Path $runDir "device-$DeviceA.log"
$logB = Join-Path $runDir "device-$DeviceB.log"

Write-Host "Clearing logcat buffers..."
Invoke-Adb -Serial $DeviceA -Args @("logcat", "-c") | Out-Null
Invoke-Adb -Serial $DeviceB -Args @("logcat", "-c") | Out-Null

Write-Host "Starting log capture..."
$procA = Start-DeviceLogcat -Serial $DeviceA -LogPath $logA
$procB = Start-DeviceLogcat -Serial $DeviceB -LogPath $logB

try {
Write-Host "Launching app on both devices..."
Invoke-Adb -Serial $DeviceA -Args @("shell", "input", "keyevent", "KEYCODE_WAKEUP") | Out-Null
Invoke-Adb -Serial $DeviceB -Args @("shell", "input", "keyevent", "KEYCODE_WAKEUP") | Out-Null
Force-Relaunch -Serial $DeviceA -AppId $AppId -MainActivity $MainActivity
Force-Relaunch -Serial $DeviceB -AppId $AppId -MainActivity $MainActivity

Write-Host "Collecting logs for $DurationSec seconds..."
$remaining = $DurationSec
$elapsed = 0
$effectiveRelaunchEvery = [Math]::Max(10, $RelaunchEverySec)
$nextRelaunchAt = if ($VisibleRelaunch) { $effectiveRelaunchEvery } else { [int]::MaxValue }
while ($remaining -gt 0) {
    $step = [Math]::Min(10, $remaining)
    Start-Sleep -Seconds $step
    $remaining -= $step
    $elapsed += $step

    if ($VisibleRelaunch -and $elapsed -ge $nextRelaunchAt -and $remaining -gt 0) {
        Write-Host "  ...visible relaunch at t=${elapsed}s"
        Force-Relaunch -Serial $DeviceA -AppId $AppId -MainActivity $MainActivity -UseStrongVisualMarker:$StrongVisualRelaunch
        Force-Relaunch -Serial $DeviceB -AppId $AppId -MainActivity $MainActivity -UseStrongVisualMarker:$StrongVisualRelaunch
        $nextRelaunchAt += $effectiveRelaunchEvery
    }

    Write-Host "  ...$remaining s remaining"
}
}
finally {
    Write-Host "Stopping log capture..."
    Stop-IfRunning -ProcessHandle $procA
    Stop-IfRunning -ProcessHandle $procB
}

Write-Host ""
Write-Host "Saved logs to: $runDir"
Write-QuickSummary -Serial $DeviceA -LogPath $logA
Write-QuickSummary -Serial $DeviceB -LogPath $logB
Write-Host ""
Write-Host "Next step: inspect both logs for reconnect latency and queued/pending ACK transitions."

