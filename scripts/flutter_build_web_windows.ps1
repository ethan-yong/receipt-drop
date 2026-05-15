# Clears stale hooks_runner locks, then builds for Web (same lock issue as tests on Windows).
# Use when you see:
#   Could not acquire the lock ... hooks_runner/shared/objective_c/.lock
#   TimeoutException after 0:05:00
#
# Important: Cursor/VS Code run dart.exe analyzers that can hold those locks.
# Easiest reliable flow: CLOSE the IDE OR run from a standalone PowerShell, then:
#   .\scripts\flutter_build_web_windows.ps1 -StopDartProcesses --no-wasm-dry-run
#
# Prefer keeping the repo outside OneDrive sync (e.g. C:\dev\puggy-bank) — OneDrive worsens locking.

param(
    [switch]$StopDartProcesses,
    [switch]$FlutterCleanFirst,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$BuildArgs
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

if ($StopDartProcesses) {
    Write-Host "==> Stopping dart/flutter processes (IDE analysis will disconnect; Cursor may briefly restart dart)..." -ForegroundColor Yellow
    Get-Process -Name "dart", "flutter" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "    stopping PID $($_.Id) $($_.ProcessName)"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

if ($FlutterCleanFirst) {
    Write-Host "==> flutter clean" -ForegroundColor Cyan
    flutter clean
}

Write-Host "==> Removing stale .lock under .dart_tool/hooks_runner ..." -ForegroundColor Cyan
$hooksRoot = Join-Path $root ".dart_tool/hooks_runner"
if (Test-Path $hooksRoot) {
    Get-ChildItem -LiteralPath $hooksRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq ".lock" } |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                Write-Host "    removed $($_.FullName)"
            }
            catch {
                Write-Warning "Could not remove lock (still held?): $($_.FullName)"
            }
        }
}

Write-Host "==> flutter pub get" -ForegroundColor Cyan
flutter pub get

Write-Host "==> flutter build web ..." -ForegroundColor Cyan
if ($null -eq $BuildArgs -or $BuildArgs.Count -eq 0) {
    flutter build web --no-wasm-dry-run
}
else {
    & flutter build web @BuildArgs
}

exit $LASTEXITCODE
