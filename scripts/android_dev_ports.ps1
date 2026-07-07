# Forward phone localhost -> PC for local Supabase (54321) and OCR API (8081).
# Run before `flutter run` when using a USB-connected physical Android device.
#
# Usage:
#   .\scripts\android_dev_ports.ps1

$ErrorActionPreference = "Stop"

$adbCandidates = @(
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    "$env:ANDROID_HOME\platform-tools\adb.exe",
    "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe"
)

$adb = $adbCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $adb) {
    Write-Error @"
adb not found. Install Android SDK platform-tools or set ANDROID_HOME.
Needed so your phone can reach local Supabase and OCR API via 127.0.0.1.
"@
}

$devices = & $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "`tdevice$" }
if (-not $devices) {
    Write-Error "No Android device connected. Enable USB debugging and reconnect."
}

& $adb reverse tcp:54321 tcp:54321
Write-Host "Port reverse: phone 127.0.0.1:54321 -> PC 127.0.0.1:54321 (Supabase)"

& $adb reverse tcp:8081 tcp:8081
Write-Host "Port reverse: phone 127.0.0.1:8081 -> PC 127.0.0.1:8081 (OCR API)"

& $adb reverse --list
