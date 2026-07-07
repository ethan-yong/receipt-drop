# Kills whatever is listening on the OCR API port, including uvicorn --reload's
# worker child — which survives even after the visible "reloader" process is
# stopped, and silently keeps answering requests with its old config. Stopping
# just the top-level PID (Task Manager, closing the terminal, one Stop-Process
# call) leaves that child running.
#
# Usage:
#   .\scripts\stop_ocr_api.ps1
#   .\scripts\stop_ocr_api.ps1 -Port 8081

param(
    [int]$Port = 8081
)

$ErrorActionPreference = "Stop"

function Get-ProcessTree([int[]]$RootIds) {
    $all = Get-CimInstance Win32_Process
    $ids = [System.Collections.Generic.HashSet[int]]::new([int[]]$RootIds)
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($p in $all) {
            if ($ids.Contains([int]$p.ParentProcessId) -and -not $ids.Contains([int]$p.ProcessId)) {
                [void]$ids.Add([int]$p.ProcessId)
                $changed = $true
            }
        }
    }
    return $ids
}

$killedAny = $false

for ($i = 0; $i -lt 5; $i++) {
    $owners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    if (-not $owners) {
        break
    }

    $tree = Get-ProcessTree -RootIds $owners
    foreach ($procId in $tree) {
        try {
            Stop-Process -Id $procId -Force -ErrorAction Stop
            Write-Host "Killed PID $procId"
            $killedAny = $true
        } catch {
            # Already gone (e.g. a reloader that already exited) — fine.
        }
    }
    Start-Sleep -Milliseconds 500
}

if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
    Write-Warning "Port $Port still has a listener after cleanup attempts. Check manually with:`n  Get-NetTCPConnection -LocalPort $Port"
} elseif ($killedAny) {
    Write-Host "Port $Port is clear."
} else {
    Write-Host "Nothing was listening on port $Port."
}
