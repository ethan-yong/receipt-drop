<#
.SYNOPSIS
    Builds services/ocr-api and services/leaderboard-api, ships them to the
    MicroK8s VM, and rolls out a verified deployment. Redis is a public
    image, not built here.

.USAGE
    .\deploy.ps1 1.0.0
    .\deploy.ps1              # omit the version to auto-generate a timestamp tag

.ENVIRONMENT
    DEPLOY_HOST          Required. Ubuntu VM hostname/IP (e.g. ubuntu-ethan).
    DEPLOY_USER          Required. SSH user on that VM.
    SSH_PASSWORD         Required. Auth is password-only, via a generated
                         SSH_ASKPASS helper — never placed on a command line or
                         read directly from the env var by a static script.
    DEPLOY_KNOWN_HOSTS   Required. Path to a known_hosts file that already
                         contains DEPLOY_HOST's host key. Host keys are pinned
                         (StrictHostKeyChecking=yes) — never auto-accepted.
                         Generate once, using Git for Windows' ssh-keyscan
                         (System32\OpenSSH's build has a known intermittent
                         bug that can hang or return zero keys against some
                         servers):
                           & "$env:ProgramFiles\Git\usr\bin\ssh-keyscan.exe" -H $env:DEPLOY_HOST | Out-File -Encoding ascii deploy\known_hosts
    CLOUDFLARE_TUNNEL_ID Required. The tunnel ID printed by
                         `cloudflared tunnel create receipt-drop` — substituted
                         into deploy/k8s/cloudflared.yaml's ConfigMap. The
                         matching credentials.json (the tunnel's private key
                         material, not just its ID) goes in secrets.yaml
                         instead, applied the same stdin-only way as the rest
                         of that file.
#>

param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'

# No version given — auto-generate a sortable, always-unique tag. Safe to
# reuse across runs regardless: the rollout below always runs `kubectl
# rollout restart`, so pods are recreated (and pull the freshly-imported
# image) every deploy no matter what the tag is.
if (-not $Version) {
    $Version = Get-Date -Format 'yyyyMMddHHmmss'
    Write-Host "No version given - auto-generated tag: $Version"
}

# $Version becomes part of a remote path, a Docker tag, and text embedded in
# a shell command run on the VM (mkdir -p, bash <path>) — constrain it to a
# safe charset up front rather than escaping at each of those use sites.
if ($Version -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "Version '$Version' is invalid. Allowed: letters, digits, '.', '-', '_', starting with a letter or digit."
}

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$K8sDir = Join-Path $RepoRoot 'deploy\k8s'
$SecretsFile = Join-Path $K8sDir 'secrets.yaml'
$RenderedDir = Join-Path $K8sDir '.rendered'
$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "receipt-drop-deploy-$Version"

$Images = @(
    # USE_TESSDATA_BEST=1: services/ocr-api/Dockerfile documents this as "for
    # production images only" (higher-accuracy LSTM models vs. the faster
    # default apt models) — this script is the production build path.
    @{ Key = 'ocr-api'; Name = 'receipt-drop-ocr-api'; Context = 'services\ocr-api'; BuildArgs = @('--build-arg', 'USE_TESSDATA_BEST=1', '--build-arg', 'TESSDATA_DIR=/tessdata') },
    @{ Key = 'leaderboard-api'; Name = 'receipt-drop-leaderboard-api'; Context = 'services\leaderboard-api'; BuildArgs = @() }
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
if (-not $env:DEPLOY_KNOWN_HOSTS) {
    throw @"
DEPLOY_KNOWN_HOSTS environment variable is not set.

Pin the VM's SSH host key once (never auto-accept). Use Git for Windows'
ssh-keyscan, not System32\OpenSSH's - the latter has a known intermittent
bug that can hang or return zero keys against some servers:
  & "`$env:ProgramFiles\Git\usr\bin\ssh-keyscan.exe" -H `$env:DEPLOY_HOST | Out-File -Encoding ascii deploy\known_hosts
  `$env:DEPLOY_KNOWN_HOSTS = (Resolve-Path deploy\known_hosts).Path
"@
}
if (-not (Test-Path $env:DEPLOY_KNOWN_HOSTS)) {
    throw "DEPLOY_KNOWN_HOSTS file not found: $($env:DEPLOY_KNOWN_HOSTS)"
}
if (-not $env:CLOUDFLARE_TUNNEL_ID) {
    throw @"
CLOUDFLARE_TUNNEL_ID environment variable is not set.

One-time: cloudflared tunnel login
          cloudflared tunnel create receipt-drop
Set `$env:CLOUDFLARE_TUNNEL_ID to the printed tunnel ID, and paste the
generated credentials.json into secrets.yaml's cloudflared-credentials block.
"@
}

# secrets.yaml is gitignored and persists across changes to this repo, so its
# CONTENT can silently drift out of date with secrets.yaml.example (e.g. a
# pre-existing file from before the cloudflared-credentials block was added,
# or an unedited "change-me" placeholder copied verbatim) even though the
# Test-Path check above passes. Catching that here, at deploy time, beats
# discovering it later as a confusing CreateContainerConfigError deep in the
# rollout wait.
if ((Get-Content $SecretsFile -Raw) -match 'change-me') {
    throw "$SecretsFile still contains a 'change-me' placeholder value - fill in every real secret (see deploy\k8s\secrets.yaml.example for the full list, including the cloudflared-credentials block) before deploying."
}

# ocr-api's public hostname (ocr.receipt-drop.org, via cloudflared.yaml) is
# only safe because Cloudflare Access gates it in the Zero Trust dashboard -
# nothing in this repo can verify that policy actually exists or is still
# correct, since it isn't config-as-code. Printed every run as a reminder,
# not a hard gate (there's no API credential here to check it programmatically).
Write-Host "== Reminder: verify the Cloudflare Access Service Token policy for ocr.receipt-drop.org is still in place (Zero Trust dashboard) before this completes - X-OCR-Secret alone is not sufficient for an internet-facing endpoint. See docs/decisions.md. =="

# Everything from here on can create secret-bearing temp files (the SSH
# password file, the generated askpass script) or partially-completed remote
# state, so it all lives inside one try/finally: an error anywhere past this
# point — including inside the SSH-auth-setup code below, before any ssh/scp
# call is even made — still reaches the cleanup in finally.
try {

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
$GeneratedAskPass = Join-Path ([System.IO.Path]::GetTempPath()) "receipt-drop-askpass-$([guid]::NewGuid().ToString('N')).cmd"
[System.IO.File]::WriteAllText($GeneratedAskPass, "@type `"$PwFile`"`r`n", [System.Text.Encoding]::ASCII)
$env:SSH_ASKPASS = $GeneratedAskPass
$env:SSH_ASKPASS_REQUIRE = 'force'
$env:DISPLAY = 'localhost:0'

# Pin host keys — never accept-new (MITM risk on first connect).
$SshOpts = @(
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$($env:DEPLOY_KNOWN_HOSTS)",
    '-o', 'ConnectTimeout=15'
)

$Target = "$($env:DEPLOY_USER)@$($env:DEPLOY_HOST)"

# Windows' bundled OpenSSH client (System32\OpenSSH, typically first on PATH)
# has a known intermittent bug negotiating strict-KEX against some servers -
# it can hang indefinitely or fail with "choose_kex: unsupported KEX method
# sntrup761x25519-sha512@openssh.com" on both ssh and ssh-keyscan. Git for
# Windows ships a newer OpenSSH build that doesn't hit this; prefer it when
# present, falling back to whatever's on PATH otherwise.
function Resolve-SshTool {
    param([Parameter(Mandatory = $true)][string]$Name)
    $gitPath = Join-Path $env:ProgramFiles "Git\usr\bin\$Name.exe"
    if (Test-Path $gitPath) { return $gitPath }
    $cmd = Get-Command "$Name.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Warning "Git for Windows' $Name.exe not found at $gitPath - falling back to $($cmd.Source), which may be the known-buggy Windows OpenSSH build described above."
        return $cmd.Source
    }
    throw "$Name.exe not found (checked Git for Windows and PATH)."
}

$SshExe = Resolve-SshTool -Name 'ssh'
$ScpExe = Resolve-SshTool -Name 'scp'

# This script authenticates with a password (via the askpass helper above),
# so `-o BatchMode=yes` can't be used here — it disables password auth
# entirely. Two things instead prevent ssh/scp from silently hanging forever
# on a stray prompt: (1) stdin is explicitly redirected from a genuinely
# empty file below, so ssh can never treat an inherited console as an
# interactive prompt target; (2) Invoke-NativeViaStartProcess enforces a hard
# timeout (kill + throw) as the actual safety net if ssh or the askpass
# helper itself ever stalls regardless.
$EmptyStdinFile = Join-Path ([System.IO.Path]::GetTempPath()) 'receipt-drop-deploy-empty-stdin'
if (-not (Test-Path $EmptyStdinFile)) {
    New-Item -ItemType File -Path $EmptyStdinFile -Force | Out-Null
}

function Invoke-NativeViaStartProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [string]$RedirectStandardInputPath = $EmptyStdinFile,
        [int]$TimeoutSeconds = 120
    )
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList `
            -RedirectStandardInput $RedirectStandardInputPath -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
            -NoNewWindow -PassThru
        # Touching .Handle before WaitForExit is required here: without it,
        # Start-Process -PassThru (no -Wait) leaves .ExitCode unreadable
        # (silently $null) even after the process has exited and
        # WaitForExit(ms) returns true — a real, reproduced .NET/PowerShell
        # quirk, not a hypothetical. A $null ExitCode would make every
        # "-ne 0" check below true, treating every successful call as a
        # failure.
        $null = $p.Handle
        $timedOut = -not $p.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null
            Start-Sleep -Milliseconds 250
        }
        $stdout = if (Test-Path $outFile) { Get-Content $outFile -Raw -ErrorAction SilentlyContinue } else { '' }
        $stderr = if (Test-Path $errFile) { Get-Content $errFile -Raw -ErrorAction SilentlyContinue } else { '' }
        if ($timedOut) {
            throw "Timed out after ${TimeoutSeconds}s and was killed: $FilePath $($ArgumentList -join ' ')`nPartial stdout:`n$stdout`nPartial stderr:`n$stderr"
        }
        return @{ ExitCode = $p.ExitCode; StdOut = $stdout; StdErr = $stderr }
    } finally {
        Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
    }
}

function Invoke-RemoteCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [switch]$AllowFailure,
        [int]$TimeoutSeconds = 120
    )
    $result = Invoke-NativeViaStartProcess -FilePath $SshExe -ArgumentList (@($SshOpts) + @($Target, $Command)) -TimeoutSeconds $TimeoutSeconds
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
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [int]$TimeoutSeconds = 600
    )
    $result = Invoke-NativeViaStartProcess -FilePath $ScpExe -ArgumentList (@($SshOpts) + @($LocalPath, "${Target}:${RemotePath}")) -TimeoutSeconds $TimeoutSeconds
    if ($result.StdOut) { Write-Host $result.StdOut.TrimEnd() }
    if ($result.StdErr) { Write-Host $result.StdErr.TrimEnd() }
    if ($result.ExitCode -ne 0) {
        throw "scp failed: $LocalPath -> $RemotePath"
    }
}

function Apply-SecretsViaStdin {
    # Never write secrets.yaml onto the VM filesystem. Pipe the local file
    # through ssh stdin into `kubectl apply -f -`. Namespace apply (no secret
    # material, already copied to $RemoteDir) is chained into this same SSH
    # session rather than getting its own connection - it only needs to run
    # before the secrets apply, not in a separate call.
    Write-Host "== Applying namespace + secrets via SSH stdin (not written under /tmp) =="
    $result = Invoke-NativeViaStartProcess -FilePath $SshExe `
        -ArgumentList (@($SshOpts) + @($Target, "microk8s kubectl apply -f $RemoteDir/namespace.yaml && microk8s kubectl apply -n receipt-drop -f -")) `
        -RedirectStandardInputPath $SecretsFile
    if ($result.StdOut) { Write-Host $result.StdOut.TrimEnd() }
    if ($result.StdErr) { Write-Host $result.StdErr.TrimEnd() }
    if ($result.ExitCode -ne 0) {
        throw "kubectl apply secrets via stdin failed (exit $($result.ExitCode))"
    }
}

# ---------------------------------------------------------------------------
# 1. Build + save images locally
# ---------------------------------------------------------------------------

if (Test-Path $TmpDir) { Remove-Item -Recurse -Force $TmpDir }
New-Item -ItemType Directory -Path $TmpDir | Out-Null

foreach ($img in $Images) {
    $tag = "$($img.Name):$Version"
    $buildArgs = $img.BuildArgs
    Write-Host "== Building $tag =="
    & docker build @buildArgs -t $tag (Join-Path $RepoRoot $img.Context)
    if ($LASTEXITCODE -ne 0) { throw "docker build failed for $tag" }

    $tarPath = Join-Path $TmpDir "$($img.Key)-$Version.tar"
    Write-Host "== Saving $tag -> $tarPath =="
    & docker save -o $tarPath $tag
    if ($LASTEXITCODE -ne 0) { throw "docker save failed for $tag" }
}

# ---------------------------------------------------------------------------
# 2. Render manifests (substitute the image-tag placeholder into a temp copy;
#    source files under deploy\k8s stay generic across versions).
#    secrets.yaml is intentionally NOT rendered/copied — applied via stdin only.
# ---------------------------------------------------------------------------

if (Test-Path $RenderedDir) { Remove-Item -Recurse -Force $RenderedDir }
New-Item -ItemType Directory -Path $RenderedDir | Out-Null

Get-ChildItem $K8sDir -Filter '*.yaml' | Where-Object { $_.Name -ne 'secrets.yaml' } | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $content = $content -replace '__IMAGE_TAG__', $Version
    $content = $content -replace '__TUNNEL_ID__', $env:CLOUDFLARE_TUNNEL_ID
    Set-Content -Path (Join-Path $RenderedDir $_.Name) -Value $content -NoNewline
}

# ---------------------------------------------------------------------------
# 3. Ship tarballs + non-secret manifests to the server
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
# 4. Apply secrets (stdin, never on-disk on the VM), then remote apply sequence
# ---------------------------------------------------------------------------

# Namespace must exist before secrets apply - handled inside
# Apply-SecretsViaStdin, chained into the same SSH session.
Apply-SecretsViaStdin

$RemoteScriptTemplate = @'
set -e
cd "__REMOTE_DIR__"

# Remove the previous public ocr-api Ingress if present (shared-secret OCR must
# not be internet-reachable; ClusterIP + private path only).
echo "== Removing public ocr-api ingress (if any) =="
microk8s kubectl delete ingress ocr-api-ingress -n receipt-drop --ignore-not-found
microk8s kubectl delete middleware ocrapi-strip -n receipt-drop --ignore-not-found

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
microk8s kubectl apply -n receipt-drop -f redis.yaml -f ocr-api.yaml -f leaderboard-api.yaml -f ingress.yaml -f cloudflared.yaml

echo "== Restarting deployments =="
microk8s kubectl rollout restart deployment/ocr-api deployment/leaderboard-api deployment/redis deployment/cloudflared -n receipt-drop

echo "== Waiting for rollouts =="
failed=0
set +e
for d in ocr-api leaderboard-api redis cloudflared; do
  microk8s kubectl rollout status deployment/$d -n receipt-drop --timeout=120s
  status=$?
  echo "ROLLOUT_STATUS_${d}=$status"
  if [ "$status" -ne 0 ]; then
    failed=1
  fi
done
set -e

echo "== Summary: pods (all namespaces) =="
microk8s kubectl get pods -A

echo "== Summary: services (receipt-drop) =="
microk8s kubectl get services -n receipt-drop

echo "== Summary: ingress (receipt-drop) =="
microk8s kubectl get ingress -n receipt-drop

echo "== Scrubbing remote deploy directory =="
# Image tarballs + manifests (no secrets.yaml — that never landed on disk).
# cd out first: this script's own cwd is __REMOTE_DIR__ (set at the top), and
# rm -rf-ing your own cwd relies on fragile shell-fd-lifetime behavior rather
# than being structurally safe for whatever runs after it.
cd /tmp
rm -rf "__REMOTE_DIR__"

# Exit nonzero if any rollout failed — this is the authoritative pass/fail
# signal the caller checks (not the ROLLOUT_STATUS_ lines above, which are
# for the human-readable per-deployment breakdown only).
exit $failed
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
$DeployResult = Invoke-NativeViaStartProcess -FilePath $SshExe -ArgumentList (@($SshOpts) + @($Target, "bash $RemoteDir/deploy.sh")) -TimeoutSeconds 900
$CombinedOutput = "$($DeployResult.StdOut)`n$($DeployResult.StdErr)"
$CombinedOutput -split "`n" | ForEach-Object { Write-Host $_ }

# ---------------------------------------------------------------------------
# 5. Pass/fail is $DeployResult.ExitCode, which the remote script sets
#    accurately for every failure mode (rollouts included). The per-deployment
#    ROLLOUT_STATUS_ lines are already visible verbatim in the raw output
#    streamed above — no need to re-parse and reprint them here.
# ---------------------------------------------------------------------------

if ($DeployResult.ExitCode -ne 0) {
    throw "Remote deploy sequence exited with code $($DeployResult.ExitCode) - see output above."
}

Write-Host "== Deploy $Version complete =="

} catch {
    # Best-effort remote scrub on ANY failure past this point, including a
    # local timeout (Invoke-NativeViaStartProcess throws directly, bypassing
    # the exit-code check above entirely) as well as the explicit throw above.
    # $RemoteDir may not exist yet if the failure happened before step 3.
    if ($RemoteDir) {
        Write-Host "== Attempting best-effort remote cleanup of $RemoteDir after failure =="
        try {
            Invoke-RemoteCommand "rm -rf $RemoteDir" -AllowFailure -TimeoutSeconds 30 | Out-Null
        } catch {
            Write-Host "Remote cleanup also failed (leaving $RemoteDir on the VM): $_"
        }
    }
    throw
} finally {
    # Always scrub the password artifacts and local build/render output,
    # whether the deploy succeeded, failed, or was interrupted.
    Remove-Item $PwFile, $GeneratedAskPass -ErrorAction SilentlyContinue
    Remove-Item Env:\SSH_ASKPASS, Env:\SSH_ASKPASS_REQUIRE, Env:\DISPLAY -ErrorAction SilentlyContinue
    if (Test-Path $TmpDir) { Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue }
    if (Test-Path $RenderedDir) { Remove-Item -Recurse -Force $RenderedDir -ErrorAction SilentlyContinue }
}
