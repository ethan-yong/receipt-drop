# Batch-process receipt images via OCR API + Dart parse/save pipeline.
#
# Default folder: receipts/ (drop your receipt images here).
# Requires: Dart SDK, OCR API running locally (services/ocr-api).
#
# Usage:
#   .\scripts\process_receipts.ps1
#   .\scripts\process_receipts.ps1 -E2e
#   .\scripts\process_receipts.ps1 -IncludeOcrText
#   .\scripts\process_receipts.ps1 -ReceiptsDir receipts
#   .\scripts\process_receipts.ps1 -OcrUrl http://127.0.0.1:8080/ocr
#   .\scripts\process_receipts.ps1 -SkipHealthCheck
#   .\scripts\process_receipts.ps1 -v                    # extra progress + live dart output

param(
    [string]$ReceiptsDir = "",
    [string]$OcrUrl = "http://127.0.0.1:8080/ocr",
    [string]$OcrSecret = "",
    [switch]$IncludeOcrText,
    [switch]$E2e,
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
if ($OcrSecret -eq "") {
    $envFile = Join-Path $ProjectRoot ".env"
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^\s*OCR_SHARED_SECRET\s*=\s*(.+)\s*$') {
                $script:OcrSecret = $Matches[1].Trim().Trim('"').Trim("'")
            }
        }
    }
}
if (-not $OcrSecret) {
    Write-Error @"
OCR_SHARED_SECRET is not set.

Option A — add to .env at repo root (copy from .env.example):
  OCR_SHARED_SECRET=your-local-ocr-secret

Option B — set for this shell:
  `$env:OCR_SHARED_SECRET = 'your-local-ocr-secret'

Option C — pass inline:
  .\scripts\process_receipts.ps1 -OcrSecret 'your-local-ocr-secret'

The value must match services/ocr-api (same variable when starting uvicorn).
"@
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
    if ($E2e) {
        $dartArgs += "--e2e"
    }
    if ($SkipHealthCheck) {
        $dartArgs += "--skip-health-check"
    }

    Write-Host "Running batch processor on $ReceiptsDir ..."
    if ($E2e) {
        Write-Host "  E2E: OCR -> parse -> draft -> outbox -> sync payload preview"
    }
    Write-Host "  (first dart run compiles the CLI; each image waits on Tesseract OCR)"
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
                Write-Host ("  {0,-28} ERROR: {1}" -f $row.file, $row.error)
                continue
            }
            $amount = if ($null -ne $row.amountMyr) { "RM $($row.amountMyr)" } else { "(needs amount)" }
            $merchant = if ($row.merchantRaw) { $row.merchantRaw } else { "(unknown)" }
            $itemCount = if ($null -ne $row.lineItems) { $row.lineItems.Count } else { 0 }
            $itemsLabel = if ($itemCount -gt 0) { " items=$itemCount" } else { "" }
            $matchLabel = if ($row.itemsMatchTotal -eq $true) { " subtotal=ok" } elseif ($itemCount -gt 0) { " subtotal=?" } else { "" }
            $svc = if ($null -ne $row.ocrServiceConfidence) {
                " ocr=$([math]::Round($row.ocrServiceConfidence, 2))"
            } else { "" }
            $combined = if ($null -ne $row.combinedConfidence) {
                " combined=$([math]::Round($row.combinedConfidence, 2))"
            } else { "" }
            $reviewLabel = if ($row.needsAmount -or $row.lowConfidence) { " NEEDS-REVIEW" } else { "" }
            $e2eLabel = ""
            if ($E2e -and $row.e2e) {
                if ($row.e2e.roundTripOk) {
                    $e2eLabel = " e2e=ok"
                } else {
                    $e2eLabel = " e2e=fail"
                }
                if ($row.e2e.needsReview) {
                    $e2eLabel += "(review)"
                }
            }
            Write-Host ("  {0,-28} {1,12}  {2}{3}{4}{5}{6}{7}{8}" -f $row.file, $amount, $merchant, $itemsLabel, $matchLabel, $svc, $combined, $e2eLabel, $reviewLabel)
            if ($itemCount -gt 0) {
                foreach ($item in $row.lineItems) {
                    $qty = if ($null -ne $item.quantity) { "$($item.quantity)x " } else { "" }
                    Write-Host ("    - {0}{1} RM {2}" -f $qty, $item.name, $item.priceMyr)
                }
            }
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
