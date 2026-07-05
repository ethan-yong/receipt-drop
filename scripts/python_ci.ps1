# Mirror .github/workflows/python-ci.yml locally (ruff + pytest per Python service).
#
# Usage:
#   .\scripts\python_ci.ps1
#   .\scripts\python_ci.ps1 -Service ocr-api

param(
    [ValidateSet("ocr-api", "leaderboard-api", "all")]
    [string]$Service = "all"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

$services = if ($Service -eq "all") {
    @("ocr-api", "leaderboard-api")
} else {
    @($Service)
}

foreach ($name in $services) {
    $dir = Join-Path $ProjectRoot "services\$name"
    Write-Host ""
    Write-Host "==> $name" -ForegroundColor Cyan
    Push-Location $dir
    try {
        python -m pip install -e ".[dev]" -q
        python -m ruff check .
        python -m ruff format --check .
        python -m pytest
    } finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "Python CI passed." -ForegroundColor Green
