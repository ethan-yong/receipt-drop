# Batch-process receipt images via the self-hosted OCR API + Dart parse pipeline.
#
# Requires: Dart SDK, OCR API running locally (services/ocr-api).
#
# Usage:
#   .\scripts\process_receipts.ps1
#   .\scripts\process_receipts.ps1 -IncludeOcrText
#   .\scripts\process_receipts.ps1 -OcrUrl http://127.0.0.1:8080/ocr
#   .\scripts\process_receipts.ps1 -SkipHealthCheck
#   .\scripts\process_receipts.ps1 -v                    # extra progress + live dart output

param(
    [string]$ReceiptsDir = "",
    [string]$OcrUrl = "http://127.0.0.1:8080/ocr",
    [string]$OcrSecret = "",
    [switch]$IncludeOcrText,
    [switch]$SkipHealthCheck,
    [Alias("v")]
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if ($ReceiptsDir -eq "") {
    $ReceiptsDir = Join-Path $ProjectRoot "receipts"
}

if (-not (Test-Path $ReceiptsDir)) {
    Write-Error "Receipts folder not found: $ReceiptsDir"
}

if ($OcrSecret -eq "") {
    $OcrSecret = $env:OCR_SHARED_SECRET
}
if (-not $OcrSecret) {
    Write-Error "Set OCR_SHARED_SECRET or pass -OcrSecret (must match services/ocr-api)."
}

$healthUrl = $OcrUrl -replace "/ocr/?$", "/health"
if (-not $SkipHealthCheck) {
    Write-Host "Checking OCR API at $healthUrl ..."
    try {
        $health = Invoke-RestMethod -Uri $healthUrl -Method Get -TimeoutSec 5
        if ($health.status -ne "ok") {
            Write-Error "OCR API health check failed: $($health | ConvertTo-Json -Compress)"
        }
    } catch {
        Write-Error @"
OCR API not reachable at $healthUrl
Start it first:
  cd services/ocr-api
  `$env:OCR_SHARED_SECRET = '$OcrSecret'
  uvicorn app.main:app --host 127.0.0.1 --port 8080
"@
    }
    Write-Host "OCR API is up."
}

Push-Location $ProjectRoot
try {
    $dartArgs = @(
        "run", "bin/process_receipts.dart",
        "--receipts-dir", $ReceiptsDir,
        "--ocr-url", $OcrUrl,
        "--ocr-secret", $OcrSecret
    )
    if ($IncludeOcrText) {
        $dartArgs += "--include-ocr-text"
    }
    if ($SkipHealthCheck) {
        $dartArgs += "--skip-health-check"
    }

    Write-Host "Running batch processor ..."
    Write-Host "  (first dart run compiles the CLI; each image waits on PaddleOCR - can take a few min)"
    if ($Verbose) {
        Write-Host "  Command: dart $($dartArgs -join ' ')"
    }

    $dartExit = 0
    & dart @dartArgs 2>&1 | ForEach-Object {
        $line = if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $_.ToString()
        } else {
            "$_"
        }
        Write-Host $line
    }
    if ($null -ne $LASTEXITCODE) {
        $dartExit = $LASTEXITCODE
    }

    $resultsFile = Join-Path $ReceiptsDir "_results.json"
    Write-Host ""
    Write-Host "Summary:"
    Write-Host "--------"

    if (Test-Path $resultsFile) {
        $rows = Get-Content $resultsFile -Raw | ConvertFrom-Json
        foreach ($row in $rows) {
            if ($row.error) {
                Write-Host ("  {0,-40} ERROR: {1}" -f $row.file, $row.error)
                continue
            }
            $amount = if ($null -ne $row.amountMyr) { "RM $($row.amountMyr)" } else { "(needs amount)" }
            $merchant = if ($row.merchantRaw) { $row.merchantRaw } else { "(unknown)" }
            $svc = if ($null -ne $row.ocrServiceConfidence) {
                " ocr=$([math]::Round($row.ocrServiceConfidence, 2))"
            } else { "" }
            Write-Host ("  {0,-40} {1,12}  {2}{3}" -f $row.file, $amount, $merchant, $svc)
        }
        Write-Host ""
        Write-Host "Full results: $resultsFile"
    } else {
        Write-Host "  (no _results.json written)"
    }

    if ($dartExit -ne 0) {
        exit $dartExit
    }
} finally {
    Pop-Location
}
