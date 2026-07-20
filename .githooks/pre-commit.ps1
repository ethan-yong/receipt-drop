# Pre-commit: auto-fix with Ruff, then run pytest for both Python services.
# On Ruff auto-fixes: aborts so you can `git add -A && git commit` again.
# On pytest/lint failure: aborts until fixed.
$ErrorActionPreference = 'Stop'

$Root = git rev-parse --show-toplevel
Set-Location $Root

$Services = @('ocr-api', 'leaderboard-api')

function Get-ServicePython {
    param([string]$ServiceDir)
    $venvPy = Join-Path $ServiceDir '.venv\Scripts\python.exe'
    if (Test-Path $venvPy) { return (Resolve-Path $venvPy).Path }
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $py311 = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe'
    if (Test-Path $py311) { return $py311 }
    throw "python not found for $ServiceDir (create .venv with: python -m venv .venv && .\.venv\Scripts\pip install -e `".[dev]`")"
}

function Invoke-ServiceTool {
    param(
        [string]$ServiceDir,
        [string]$Module,  # ruff | pytest
        [string[]]$ToolArgs
    )
    Push-Location $ServiceDir
    try {
        # Prefer `python -m <tool>` from the service .venv so deps match that package.
        $python = Get-ServicePython (Get-Location)
        # Out-Host keeps tool stdout on the console and out of the function's
        # return pipeline (otherwise exit-code checks break in PowerShell).
        & $python -m $Module @ToolArgs 2>&1 | Out-Host
        return [int]$LASTEXITCODE
    } finally {
        Pop-Location
    }
}

Write-Host ''
Write-Host 'pre-commit: ruff + pytest (services/ocr-api, services/leaderboard-api)'
Write-Host ''

$before = @(git status --porcelain -- services/) -join "`n"

foreach ($svc in $Services) {
    $dir = Join-Path 'services' $svc
    Write-Host "== ${svc}: ruff check --fix =="
    $null = Invoke-ServiceTool -ServiceDir $dir -Module 'ruff' -ToolArgs @('check', '--fix', '.')
    Write-Host "== ${svc}: ruff format =="
    $null = Invoke-ServiceTool -ServiceDir $dir -Module 'ruff' -ToolArgs @('format', '.')
    Write-Host ''
}

$after = @(git status --porcelain -- services/) -join "`n"
if ($before -ne $after) {
    Write-Host ''
    Write-Host 'Ruff auto-fixed files under services/. Stage them and commit again:'
    Write-Host '  git add -A'
    Write-Host '  git commit'
    Write-Host ''
    git status --short -- services/
    exit 1
}

$failed = $false
foreach ($svc in $Services) {
    $dir = Join-Path 'services' $svc
    Write-Host "== ${svc}: ruff check (verify) =="
    if ((Invoke-ServiceTool -ServiceDir $dir -Module 'ruff' -ToolArgs @('check', '.')) -ne 0) {
        $failed = $true
    }
    Write-Host "== ${svc}: ruff format --check =="
    if ((Invoke-ServiceTool -ServiceDir $dir -Module 'ruff' -ToolArgs @('format', '--check', '.')) -ne 0) {
        $failed = $true
    }
    Write-Host "== ${svc}: pytest =="
    if ((Invoke-ServiceTool -ServiceDir $dir -Module 'pytest' -ToolArgs @('-q')) -ne 0) {
        $failed = $true
    }
    Write-Host ''
}

if ($failed) {
    Write-Host 'pre-commit failed: fix the errors above, then:'
    Write-Host '  git add -A'
    Write-Host '  git commit'
    exit 1
}

Write-Host 'pre-commit: all checks passed.'
exit 0
