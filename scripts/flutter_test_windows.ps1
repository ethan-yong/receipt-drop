# Clears stale hooks_runner lock files (fixes TimeoutException on .lock under
# .dart_tool/hooks_runner/shared/*) then runs flutter test.
# Usage:
#   .\scripts\flutter_test_windows.ps1
#   .\scripts\flutter_test_windows.ps1 test test/widget_test.dart
#   .\scripts\flutter_test_windows.ps1 test --reporter compact
# If locks stay "in use", close other Flutter/Dart work, then:
#   .\scripts\flutter_test_windows.ps1 -StopDartProcesses

param(
    [switch]$StopDartProcesses,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

if ($StopDartProcesses) {
    Write-Host "==> Stopping dart/flutter processes (may affect other IDEs) ..." -ForegroundColor Yellow
    Get-Process -Name "dart", "flutter" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "    stopping PID $($_.Id) $($_.ProcessName)"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

Write-Host "==> Removing stale .lock files under .dart_tool/hooks_runner ..." -ForegroundColor Cyan
$hooksRoot = Join-Path $root ".dart_tool/hooks_runner"
if (Test-Path $hooksRoot) {
    Get-ChildItem -LiteralPath $hooksRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq ".lock" } |
        ForEach-Object {
            $lockPath = $_.FullName
            try {
                Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop
                Write-Host "    removed $lockPath"
            } catch {
                Write-Warning "Could not remove lock (in use?): $lockPath"
            }
        }
}

Write-Host "==> flutter pub get" -ForegroundColor Cyan
flutter pub get

Write-Host "==> flutter ..." -ForegroundColor Cyan
if ($null -eq $FlutterArgs -or $FlutterArgs.Count -eq 0) {
    flutter test
} else {
    & flutter @FlutterArgs
}

# Propagate Flutter's exit code (otherwise a crash can still report success).
exit $LASTEXITCODE
