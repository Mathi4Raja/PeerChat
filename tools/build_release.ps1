# PeerChat Release Build Script
# This script builds the release APK and renames it with the version from pubspec.yaml.

Write-Host "--- PeerChat Release Build Process ---" -ForegroundColor Cyan

# 1. Get version from pubspec.yaml
$pubspec = Get-Content "pubspec.yaml" -Raw
if ($pubspec -match "version:\s*([0-9.]+)") {
    $version = $Matches[1]
    Write-Host "Detected version: $version" -ForegroundColor Green
} else {
    Write-Host "Could not detect version from pubspec.yaml. Using 'unknown'." -ForegroundColor Yellow
    $version = "unknown"
}

# 2. Build APK
Write-Host "Building release APK..." -ForegroundColor Cyan
flutter build apk --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}

# 3. Define paths
$sourceApk = "build\app\outputs\flutter-apk\app-release.apk"
$targetApk = "build\app\outputs\flutter-apk\PeerChat-v$version.apk"

# 4. Rename and move (copy) to root for easy access
if (Test-Path $sourceApk) {
    Copy-Item $sourceApk "PeerChat-v$version.apk"
    Write-Host "Success! Release APK created: PeerChat-v$version.apk" -ForegroundColor Green
    Write-Host "You can now push this version manually." -ForegroundColor Cyan
} else {
    Write-Host "Error: Could not find generated APK at $sourceApk" -ForegroundColor Red
}
