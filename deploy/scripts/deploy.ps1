<#
.SYNOPSIS
    Builds services/ocr-api and services/leaderboard-api, ships them to the
    MicroK8s VM, and rolls out a verified deployment. Redis is a public
    image, not built here.

.USAGE
    .\deploy.ps1 1.0.0

.ENVIRONMENT
    DEPLOY_HOST     Required. Ubuntu VM hostname/IP (e.g. ubuntu-ethan).
    DEPLOY_USER     Required. SSH user on that VM.
    SSH_PASSWORD    Required. Auth is password-only, via a generated
                    SSH_ASKPASS helper — never placed on a command line or
                    read directly from the env var by a static script.
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$K8sDir = Join-Path $RepoRoot 'deploy\k8s'
$SecretsFile = Join-Path $K8sDir 'secrets.yaml'
$RenderedDir = Join-Path $K8sDir '.rendered'
$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "receipt-drop-deploy-$Version"

$Images = @(
    @{ Key = 'ocr-api'; Name = 'receipt-drop-ocr-api'; Context = 'services\ocr-api' },
    @{ Key = 'leaderboard-api'; Name = 'receipt-drop-leaderboard-api'; Context = 'services\leaderboard-api' }
)

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

if (-not (Test-Path $SecretsFile)) {
    throw "Missing $SecretsFile`n`nCopy deploy\k8s\secrets.yaml.example -> deploy\k8s\secrets.yaml and fill in real values, then re-run."
}

if (-not $env:DEPLOY_HOST) { throw "DEPLOY_HOST environment variable is not set." }
if (-not $env:DEPLOY_USER) { throw "DEPLOY_USER environment variable is not set." }
if (-not $env:SSH_PASSWORD) { throw "SSH_PASSWORD environment variable is not set." }

# ---------------------------------------------------------------------------
# SSH auth setup (password-only, via a generated SSH_ASKPASS helper)
# ---------------------------------------------------------------------------
#
# The password is never placed on a command line and never read directly
# from an env var by a static askpass script (both are avoidable exposure
# surfaces). Instead: write it to a private per-run temp file, then generate
# a per-run askpass.cmd that just dumps that file's contents. Windows 11's
# OpenSSH client ignores SSH_ASKPASS unless SSH_ASKPASS_REQUIRE=force is also
# set; DISPLAY is a harmless legacy check some builds still make outside X11.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$PwFile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($PwFile, "$($env:SSH_PASSWORD)`n", $Utf8NoBom)
$GeneratedAskPass = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.cmd')
[System.IO.File]::WriteAllText($GeneratedAskPass, "@type `"$PwFile`"`r`n", [System.Text.Encoding]::ASCII)
$env:SSH_ASKPASS = $GeneratedAskPass
$env:SSH_ASKPASS_REQUIRE = 'force'
$env:DISPLAY = 'localhost:0'

$SshOpts = @('-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=15')

$Target = "$($env:DEPLOY_USER)@$($env:DEPLOY_HOST)"

# Plain `& ssh.exe ... 2>&1` lets ssh inherit this process's stdin. In some
# terminal hosts that leaves ssh unsure whether a real interactive console is
# attached and it can stall waiting on it rather than proceeding, even with
# -o BatchMode=yes. Start-Process with stdin explicitly redirected from a
# genuinely empty file removes that ambiguity — ssh can never treat it as an
# interactive prompt target.
$EmptyStdinFile = Join-Path ([System.IO.Path]::GetTempPath()) 'receipt-drop-deploy-empty-stdin'
if (-not (Test-Path $EmptyStdinFile)) {
    New-Item -ItemType File -Path $EmptyStdinFile -Force | Out-Null
}

function Invoke-NativeViaStartProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList
    )
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList `
            -RedirectStandardInput $EmptyStdinFile -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
            -NoNewWindow -Wait -PassThru
        $stdout = if (Test-Path $outFile) { Get-Content $outFile -Raw -ErrorAction SilentlyContinue } else { '' }
        $stderr = if (Test-Path $errFile) { Get-Content $errFile -Raw -ErrorAction SilentlyContinue } else { '' }
        return @{ ExitCode = $p.ExitCode; StdOut = $stdout; StdErr = $stderr }
    } finally {
        Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
    }
}

function Invoke-RemoteCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [switch]$AllowFailure
    )
    $result = Invoke-NativeViaStartProcess -FilePath 'ssh.exe' -ArgumentList (@($SshOpts) + @($Target, $Command))
    if ($result.StdOut) { Write-Host $result.StdOut.TrimEnd() }
    if ($result.StdErr) { Write-Host $result.StdErr.TrimEnd() }
    if ($result.ExitCode -ne 0 -and -not $AllowFailure) {
        throw "Remote command failed (exit $($result.ExitCode)): $Command"
    }
    return $result.ExitCode
}

function Copy-ToRemote {
    param(
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath
    )
    $result = Invoke-NativeViaStartProcess -FilePath 'scp.exe' -ArgumentList (@($SshOpts) + @($LocalPath, "${Target}:${RemotePath}"))
    if ($result.StdOut) { Write-Host $result.StdOut.TrimEnd() }
    if ($result.StdErr) { Write-Host $result.StdErr.TrimEnd() }
    if ($result.ExitCode -ne 0) {
        throw "scp failed: $LocalPath -> $RemotePath"
    }
}

try {

# ---------------------------------------------------------------------------
# 1. Build + save images locally
# ---------------------------------------------------------------------------

if (Test-Path $TmpDir) { Remove-Item -Recurse -Force $TmpDir }
New-Item -ItemType Directory -Path $TmpDir | Out-Null

foreach ($img in $Images) {
    $tag = "$($img.Name):$Version"
    Write-Host "== Building $tag =="
    & docker build -t $tag (Join-Path $RepoRoot $img.Context)
    if ($LASTEXITCODE -ne 0) { throw "docker build failed for $tag" }

    $tarPath = Join-Path $TmpDir "$($img.Key)-$Version.tar"
    Write-Host "== Saving $tag -> $tarPath =="
    & docker save -o $tarPath $tag
    if ($LASTEXITCODE -ne 0) { throw "docker save failed for $tag" }
}

# ---------------------------------------------------------------------------
# 2. Render manifests (substitute the image-tag placeholder into a temp copy;
#    source files under deploy\k8s stay generic across versions)
# ---------------------------------------------------------------------------

if (Test-Path $RenderedDir) { Remove-Item -Recurse -Force $RenderedDir }
New-Item -ItemType Directory -Path $RenderedDir | Out-Null

Get-ChildItem $K8sDir -Filter '*.yaml' | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $content = $content -replace '__IMAGE_TAG__', $Version
    Set-Content -Path (Join-Path $RenderedDir $_.Name) -Value $content -NoNewline
}

# ---------------------------------------------------------------------------
# 3. Ship tarballs + manifests to the server
# ---------------------------------------------------------------------------

$RemoteDir = "/tmp/receipt-drop-deploy/$Version"
Write-Host "== Preparing remote directory $RemoteDir =="
Invoke-RemoteCommand "mkdir -p $RemoteDir"

foreach ($img in $Images) {
    $tarPath = Join-Path $TmpDir "$($img.Key)-$Version.tar"
    Write-Host "== Copying $($img.Key)-$Version.tar =="
    Copy-ToRemote -LocalPath $tarPath -RemotePath "$RemoteDir/$($img.Key)-$Version.tar"
}

Get-ChildItem $RenderedDir -Filter '*.yaml' | ForEach-Object {
    Write-Host "== Copying $($_.Name) =="
    Copy-ToRemote -LocalPath $_.FullName -RemotePath "$RemoteDir/$($_.Name)"
}

# ---------------------------------------------------------------------------
# 4. Remote apply sequence (single SSH session, ordered, fails fast on
#    anything except the final rollout-status loop so one hung deployment
#    doesn't hide the others)
# ---------------------------------------------------------------------------

$RemoteScriptTemplate = @'
set -e
cd "__REMOTE_DIR__"

echo "== Applying namespace =="
microk8s kubectl apply -f namespace.yaml

echo "== Applying secrets =="
microk8s kubectl apply -n receipt-drop -f secrets.yaml

echo "== Importing images into containerd =="
microk8s ctr image import ocr-api-__VERSION__.tar
microk8s ctr image import leaderboard-api-__VERSION__.tar

echo "== Verifying imported images =="
if ! microk8s ctr images ls | grep -q "receipt-drop-ocr-api:__VERSION__"; then
  echo "ERROR: receipt-drop-ocr-api:__VERSION__ not found in containerd after import" >&2
  exit 1
fi
if ! microk8s ctr images ls | grep -q "receipt-drop-leaderboard-api:__VERSION__"; then
  echo "ERROR: receipt-drop-leaderboard-api:__VERSION__ not found in containerd after import" >&2
  exit 1
fi

echo "== Verifying a default StorageClass exists (needed for redis's PVC) =="
if ! microk8s kubectl get storageclass -o name | grep -q .; then
  echo "ERROR: no StorageClass found. Run once on the server: microk8s enable hostpath-storage" >&2
  exit 1
fi

echo "== Applying workload manifests =="
microk8s kubectl apply -n receipt-drop -f redis.yaml -f ocr-api.yaml -f leaderboard-api.yaml -f ingress.yaml

echo "== Restarting deployments =="
microk8s kubectl rollout restart deployment/ocr-api deployment/leaderboard-api deployment/redis -n receipt-drop

echo "== Waiting for rollouts =="
set +e
for d in ocr-api leaderboard-api redis; do
  microk8s kubectl rollout status deployment/$d -n receipt-drop --timeout=120s
  echo "ROLLOUT_STATUS_${d}=$?"
done
set -e

echo "== Summary: pods (all namespaces) =="
microk8s kubectl get pods -A

echo "== Summary: services (receipt-drop) =="
microk8s kubectl get services -n receipt-drop

echo "== Summary: ingress (receipt-drop) =="
microk8s kubectl get ingress -n receipt-drop
'@

$RemoteScript = $RemoteScriptTemplate -replace '__REMOTE_DIR__', $RemoteDir -replace '__VERSION__', $Version
# Force LF line endings and no BOM: this is executed on Linux via `bash`, and
# a stray \r or a leading BOM byte both produce confusing shell syntax errors
# on the first/last line of a script.
$RemoteScript = $RemoteScript -replace "`r`n", "`n"
$LocalScriptPath = Join-Path $TmpDir 'remote-deploy.sh'
[System.IO.File]::WriteAllText($LocalScriptPath, $RemoteScript, (New-Object System.Text.UTF8Encoding($false)))

# Ship the script itself rather than passing it inline as an ssh command-line
# argument: a large multi-line string full of quotes/parens/`$`-expansions
# is fragile to marshal correctly through PowerShell -> Win32 process
# invocation -> ssh.exe -> remote shell (embedded quoting can get mangled
# along the way). A short, quote-free `bash <path>` command has no such risk.
Write-Host "== Copying remote-deploy.sh =="
Copy-ToRemote -LocalPath $LocalScriptPath -RemotePath "$RemoteDir/deploy.sh"

Write-Host "== Running remote deploy sequence =="
$DeployResult = Invoke-NativeViaStartProcess -FilePath 'ssh.exe' -ArgumentList (@($SshOpts) + @($Target, "bash $RemoteDir/deploy.sh"))
$CombinedOutput = "$($DeployResult.StdOut)`n$($DeployResult.StdErr)"
$CombinedOutput -split "`n" | ForEach-Object { Write-Host $_ }

if ($DeployResult.ExitCode -ne 0) {
    throw "Remote deploy sequence exited with code $($DeployResult.ExitCode) - see output above."
}

# ---------------------------------------------------------------------------
# 5. Parse rollout results and set the script's own exit code accordingly
# ---------------------------------------------------------------------------

$RolloutFailed = $false
foreach ($line in ($CombinedOutput -split "`n")) {
    if ($line -match 'ROLLOUT_STATUS_(\S+)=(\d+)') {
        $name = $Matches[1]
        $code = [int]$Matches[2]
        if ($code -eq 0) {
            Write-Host "Rollout OK: $name"
        } else {
            Write-Host "Rollout FAILED: $name (exit $code)"
            $RolloutFailed = $true
        }
    }
}

if ($RolloutFailed) {
    throw "One or more deployments failed to roll out - check the summary output above."
}

Write-Host "== Deploy $Version complete =="

} finally {
    # Always scrub the password artifacts, whether the deploy succeeded,
    # failed, or was interrupted.
    Remove-Item $PwFile, $GeneratedAskPass -ErrorAction SilentlyContinue
    Remove-Item Env:\SSH_ASKPASS, Env:\SSH_ASKPASS_REQUIRE, Env:\DISPLAY -ErrorAction SilentlyContinue
}
