# Start local Supabase with Google OAuth env vars from root .env.
#
# Usage:
#   .\scripts\supabase_start.ps1
#   .\scripts\supabase_start.ps1 -Restart

param(
    [switch]$Restart
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$EnvFile = Join-Path $ProjectRoot ".env"

function Import-DotEnvLine {
    param([string]$Line)
    if ($Line -match '^\s*GOOGLE_OAUTH_CLIENT_ID\s*=\s*(.+)\s*$') {
        $script:GoogleClientId = $Matches[1].Trim().Trim('"').Trim("'")
    }
    if ($Line -match '^\s*GOOGLE_OAUTH_CLIENT_SECRET\s*=\s*(.+)\s*$') {
        $script:GoogleClientSecret = $Matches[1].Trim().Trim('"').Trim("'")
    }
}

$GoogleClientId = ""
$GoogleClientSecret = ""
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object { Import-DotEnvLine $_ }
}

if (-not $GoogleClientId -or $GoogleClientId -like "PASTE_*" -or $GoogleClientId -like "your-*") {
    Write-Warning @"
GOOGLE_OAUTH_CLIENT_ID is not set in .env.
Google Sign-In will fail until you paste your Web application client ID from Google Cloud Console.
"@
} else {
    $env:GOOGLE_OAUTH_CLIENT_ID = $GoogleClientId
}

if (-not $GoogleClientSecret -or $GoogleClientSecret -like "PASTE_*" -or $GoogleClientSecret -like "GOCSPX-your-*") {
    Write-Warning @"
GOOGLE_OAUTH_CLIENT_SECRET is not set in .env.
Google Sign-In will fail until you paste your Web application client secret.
"@
} else {
    $env:GOOGLE_OAUTH_CLIENT_SECRET = $GoogleClientSecret
}

Push-Location $ProjectRoot
try {
    if ($Restart) {
        supabase stop
    }
    supabase start
} finally {
    Pop-Location
}
