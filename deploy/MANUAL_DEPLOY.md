# Manual production deploy (MicroK8s)

Step-by-step commands equivalent to `.\deploy\scripts\deploy.ps1`. Run from a **Windows dev machine** with Docker Desktop unless noted otherwise. Replace placeholders before running:

| Placeholder | Example | Meaning |
|---|---|---|
| `VERSION` | `1.0.0` or `20260728143000` | Docker image tag for this deploy |
| `DEPLOY_HOST` | `ubuntu-ethan` | MicroK8s VM hostname or IP |
| `DEPLOY_USER` | `ubuntu` | SSH user on the VM |
| `CLOUDFLARE_TUNNEL_ID` | `a1b2c3d4-...` | Tunnel ID from `cloudflared tunnel create receipt-drop` |

The automated script also deploys Supabase Edge Functions separately — that is **not** covered here. After this deploy, run `supabase functions deploy <name>` for `enrich-transaction`, `ocr-proxy`, and `places-proxy` if those changed.

---

## One-time setup

### Create production secrets file

Copy the example secrets file and fill in real values (database URL, JWT secret, OCR shared secret, LLM credentials, Cloudflare tunnel credentials JSON).

```powershell
Copy-Item deploy\k8s\secrets.yaml.example deploy\k8s\secrets.yaml
# Edit deploy\k8s\secrets.yaml — replace every change-me placeholder
```

### Pin the VM SSH host key

Stores the server host key locally so SSH refuses unexpected hosts (no auto-accept on first connect).

```powershell
& "$env:ProgramFiles\Git\usr\bin\ssh-keyscan.exe" -H $env:DEPLOY_HOST | Out-File -Encoding ascii deploy\known_hosts
```

### Set deploy environment variables (each session)

```powershell
$env:DEPLOY_HOST = "ubuntu-ethan"
$env:DEPLOY_USER = "ubuntu"
$env:DEPLOY_KNOWN_HOSTS = (Resolve-Path deploy\known_hosts).Path
$env:CLOUDFLARE_TUNNEL_ID = "<your-tunnel-id>"
```

You will type your SSH password when `ssh` / `scp` prompt for it.

### One-time on the MicroK8s VM

Enable ingress (Traefik) and a default StorageClass so Redis can claim a PVC.

```bash
microk8s enable ingress
microk8s enable hostpath-storage
```

### One-time Cloudflare Tunnel (local machine)

Authenticate with Cloudflare, create the tunnel, and route DNS for both public hostnames.

```powershell
cloudflared tunnel login
cloudflared tunnel create receipt-drop
cloudflared tunnel route dns receipt-drop leaderboard.receipt-drop.org
cloudflared tunnel route dns receipt-drop ocr.receipt-drop.org
```

Paste the generated `credentials.json` into `deploy/k8s/secrets.yaml` under the `cloudflared-credentials` block. Set `$env:CLOUDFLARE_TUNNEL_ID` to the printed tunnel ID.

Verify the Cloudflare Access Service Token policy for `ocr.receipt-drop.org` is configured in the Zero Trust dashboard before exposing OCR to the internet.

---

## Deploy steps

Pick a version tag for this release (letters, digits, `.`, `-`, `_` only).

```powershell
$VERSION = "1.0.0"
```

Create a local temp directory for image tarballs.

```powershell
$TmpDir = Join-Path $env:TEMP "receipt-drop-deploy-$VERSION"
New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null
```

### Build OCR API image

Builds the production OCR container with the higher-accuracy Tesseract data pack.

```powershell
docker build --build-arg USE_TESSDATA_BEST=1 --build-arg TESSDATA_DIR=/tessdata -t "receipt-drop-ocr-api:$VERSION" services\ocr-api
```

### Save OCR API image to a tarball

Exports the built image so it can be copied to the VM and imported into containerd (no container registry).

```powershell
docker save -o "$TmpDir\ocr-api-$VERSION.tar" "receipt-drop-ocr-api:$VERSION"
```

### Build leaderboard API image

Builds the global-leaderboard FastAPI service container.

```powershell
docker build -t "receipt-drop-leaderboard-api:$VERSION" services\leaderboard-api
```

### Save leaderboard API image to a tarball

```powershell
docker save -o "$TmpDir\leaderboard-api-$VERSION.tar" "receipt-drop-leaderboard-api:$VERSION"
```

### Render Kubernetes manifests

Substitutes the image tag and Cloudflare tunnel ID into the YAML files. Source files under `deploy/k8s/` stay generic; rendered copies go to `.rendered/`. `secrets.yaml` is **not** copied — it is applied via SSH stdin later.

```powershell
$RenderedDir = "deploy\k8s\.rendered"
Remove-Item -Recurse -Force $RenderedDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $RenderedDir | Out-Null

Get-ChildItem deploy\k8s -Filter '*.yaml' | Where-Object { $_.Name -ne 'secrets.yaml' } | ForEach-Object {
    (Get-Content $_.FullName -Raw) `
        -replace '__IMAGE_TAG__', $VERSION `
        -replace '__TUNNEL_ID__', $env:CLOUDFLARE_TUNNEL_ID |
    Set-Content -Path (Join-Path $RenderedDir $_.Name) -NoNewline
}
```

### Create remote staging directory on the VM

SSH into the server and make a per-version folder under `/tmp` for tarballs and manifests.

```powershell
ssh -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$env:DEPLOY_KNOWN_HOSTS" "$env:DEPLOY_USER@$env:DEPLOY_HOST" "mkdir -p /tmp/receipt-drop-deploy/$VERSION"
```

### Copy image tarballs to the VM

```powershell
scp -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$env:DEPLOY_KNOWN_HOSTS" "$TmpDir\ocr-api-$VERSION.tar" "$env:DEPLOY_USER@$env:DEPLOY_HOST`:/tmp/receipt-drop-deploy/$VERSION/ocr-api-$VERSION.tar"

scp -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$env:DEPLOY_KNOWN_HOSTS" "$TmpDir\leaderboard-api-$VERSION.tar" "$env:DEPLOY_USER@$env:DEPLOY_HOST`:/tmp/receipt-drop-deploy/$VERSION/leaderboard-api-$VERSION.tar"
```

### Copy rendered manifests to the VM

```powershell
Get-ChildItem $RenderedDir -Filter '*.yaml' | ForEach-Object {
    scp -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$env:DEPLOY_KNOWN_HOSTS" $_.FullName "$env:DEPLOY_USER@$env:DEPLOY_HOST`:/tmp/receipt-drop-deploy/$VERSION/$($_.Name)"
}
```

### Apply namespace and secrets (stdin only)

Creates the `receipt-drop` namespace and applies secrets without writing `secrets.yaml` onto the VM disk. Run from repo root; you will be prompted for your SSH password.

```powershell
Get-Content deploy\k8s\secrets.yaml -Raw | ssh -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$env:DEPLOY_KNOWN_HOSTS" "$env:DEPLOY_USER@$env:DEPLOY_HOST" "microk8s kubectl apply -f /tmp/receipt-drop-deploy/$VERSION/namespace.yaml && microk8s kubectl apply -n receipt-drop -f -"
```

---

## Remote rollout (on the VM)

SSH into the VM for the remaining steps, or run them as one remote script.

```powershell
ssh -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$env:DEPLOY_KNOWN_HOSTS" "$env:DEPLOY_USER@$env:DEPLOY_HOST"
```

Set the same version on the server:

```bash
VERSION=1.0.0
cd /tmp/receipt-drop-deploy/$VERSION
```

### Remove legacy public OCR ingress (if present)

Ensures OCR is not exposed via the old Traefik ingress; production OCR goes through Cloudflare Tunnel + Access only.

```bash
microk8s kubectl delete ingress ocr-api-ingress -n receipt-drop --ignore-not-found
microk8s kubectl delete middleware ocrapi-strip -n receipt-drop --ignore-not-found
```

### Import Docker images into containerd

MicroK8s uses containerd, not Docker — images must be imported from the tarballs you copied.

```bash
microk8s ctr image import ocr-api-$VERSION.tar
microk8s ctr image import leaderboard-api-$VERSION.tar
```

### Verify imported images exist

Fails fast if the import did not register the expected tags.

```bash
microk8s ctr images ls | grep "receipt-drop-ocr-api:$VERSION"
microk8s ctr images ls | grep "receipt-drop-leaderboard-api:$VERSION"
```

### Verify a StorageClass exists

Redis needs a default StorageClass for its persistent volume.

```bash
microk8s kubectl get storageclass
```

If empty, run once: `microk8s enable hostpath-storage`.

### Apply workload manifests

Deploys Redis, OCR API, leaderboard API, LAN fallback ingress, and the Cloudflare tunnel sidecar.

```bash
microk8s kubectl apply -n receipt-drop -f redis.yaml -f ocr-api.yaml -f leaderboard-api.yaml -f ingress.yaml -f cloudflared.yaml
```

### Restart deployments

Forces pods to recreate and pick up the newly imported images (Deployments use `imagePullPolicy: Never`).

```bash
microk8s kubectl rollout restart deployment/ocr-api deployment/leaderboard-api deployment/redis deployment/cloudflared -n receipt-drop
```

### Wait for rollouts to finish

```bash
microk8s kubectl rollout status deployment/ocr-api -n receipt-drop --timeout=120s
microk8s kubectl rollout status deployment/leaderboard-api -n receipt-drop --timeout=120s
microk8s kubectl rollout status deployment/redis -n receipt-drop --timeout=120s
microk8s kubectl rollout status deployment/cloudflared -n receipt-drop --timeout=120s
```

### Check cluster state

```bash
microk8s kubectl get pods -A
microk8s kubectl get services -n receipt-drop
microk8s kubectl get ingress -n receipt-drop
```

### Remove remote staging files

Deletes tarballs and manifests from `/tmp` (secrets were never written to disk).

```bash
cd /tmp
rm -rf /tmp/receipt-drop-deploy/$VERSION
```

---

## Local cleanup (dev machine)

Remove local build artifacts after a successful deploy.

```powershell
Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force deploy\k8s\.rendered -ErrorAction SilentlyContinue
```

---

## Post-deploy checks

- Leaderboard: `curl https://leaderboard.receipt-drop.org/health`
- OCR (requires Cloudflare Access token + `X-OCR-Secret`): hit `https://ocr.receipt-drop.org/health` with the same headers your Edge Functions use
- Flutter production build: set `LEADERBOARD_API_URL=https://leaderboard.receipt-drop.org`
- Supabase Edge Functions: set `OCR_SERVICE_URL=https://ocr.receipt-drop.org` and `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` if using Cloudflare Access

---

## What this deploy does not include

| Component | How to deploy |
|---|---|
| Supabase Postgres / Auth / Storage | Hosted by Supabase — apply migrations with `supabase db push` |
| Edge Functions (`enrich-transaction`, `ocr-proxy`, `places-proxy`) | `supabase functions deploy <name>` |
| Flutter app | `flutter build apk` / `appbundle` / etc. |

See [`.claude/commands.md`](../.claude/commands.md) for full run/build/test/deploy commands.
