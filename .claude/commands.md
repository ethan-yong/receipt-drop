# Commands

Windows-first repo — README.md has detailed troubleshooting for Flutter-on-Windows/OneDrive lock issues; summarized here.

## Run the app

```powershell
flutter pub get
flutter run                 # needs a connected device/emulator, or `-d chrome`/`-d windows`
```

Requires `.env` at repo root (copy `.env.example` → `.env`). Minimum for local dev: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (from `supabase status` after `supabase start`). `SKIP_AUTH=true` (default) bypasses onboarding/auth in debug.

Physical Android device reaching local services on `127.0.0.1`: `.\scripts\android_dev_ports.ps1`.

## Build

```powershell
flutter build apk           # or: appbundle, ios, web, windows
```

`.\scripts\flutter_build_web_windows.ps1` — clears stale `.dart_tool/hooks_runner` locks before building web (OneDrive/lock workaround, see README).

## Test

```powershell
.\scripts\flutter_test_windows.ps1                     # clears hook locks, pub get, flutter test
.\scripts\flutter_test_windows.ps1 -StopDartProcesses  # also kills all dart/flutter processes first
```

Do **not** run `flutter config --no-enable-native-assets` — `sqlite3`/`objective_c` deps need native assets enabled for `flutter test` to work. If previously disabled: `flutter config --enable-native-assets` and `flutter config --enable-dart-data-assets`.

Single test file: `flutter test test/rm_amount_parser_test.dart`.

## Backend: Supabase (local)

```powershell
.\scripts\supabase_start.ps1   # or: supabase start
supabase db reset              # replay all migrations in supabase/migrations/
supabase status                # get local API URL, anon key, JWT secret
```

Edge functions run automatically with `supabase start`; secrets for them go in `supabase/functions/.env` (copy from `.env.example` there — note `GOOGLE_PLACES_API_KEY` is required but **not** listed in that example file, see `docs/database.md`). `enrich-transaction`'s LLM step needs `OCR_SERVICE_URL`/`OCR_SERVICE_SECRET` (already required for `ocr-proxy`, no extra config) — the LLM-specific `LLM_PROVIDER` + `VLLM_*` / `DEEPSEEK_*` vars go on the `services/ocr-api` side instead (root `.env`, see below), not here.

Deploy migrations/functions to a remote project: `supabase db push`, `supabase functions deploy <name>`.

Edge function unit tests (pure logic only, no network/DB — Deno, no CI wiring yet):

```powershell
deno test supabase/functions/_shared/
```

## Backend: OCR API (`services/ocr-api/`)

```powershell
cd services/ocr-api
uv run ocr-api                     # or: .\scripts\run_ocr_api.ps1 from repo root — default port 8081
.\scripts\stop_ocr_api.ps1 -Port 8081   # force-stop (kills uvicorn --reload child too)
```

Requires `OCR_SHARED_SECRET` set (root `.env` or environment) — startup aborts otherwise, and it refuses to start a second instance on an already-listening port. LLM receipt-understanding (`POST /ocr` + `POST /understand`) needs `LLM_PROVIDER=vllm|deepseek` (default `vllm`) plus the matching block: `VLLM_BASE_URL`/`VLLM_MODEL_NAME` (+ optional `VLLM_API_KEY`/`VLLM_REASONING_EFFORT`) or `DEEPSEEK_MODEL_NAME` (+ `DEEPSEEK_API_KEY`, optional `DEEPSEEK_BASE_URL`). Flip `LLM_PROVIDER` and restart ocr-api to switch.

Batch/fixture processing against local receipt images:

```powershell
.\scripts\process_receipts.ps1              # wraps: dart run bin/process_receipts.dart
dart run bin/process_receipts.dart --e2e    # also round-trips through the in-memory outbox
```

Docker (dev, hot reload on port **8081**, reads `OCR_SHARED_SECRET` from root `.env`):

```powershell
docker compose -f docker-compose.dev.yml up --build
```

Docker (one-off, no reload, port **8080**):

```powershell
docker build -t ocr-api services/ocr-api
docker run -p 8080:8080 -e OCR_SHARED_SECRET=<same-as-.env> ocr-api
```

When Supabase runs locally, keep `OCR_SERVICE_URL=http://host.docker.internal:8081` in `supabase/functions/.env`.

Tests: `cd services/ocr-api && pytest` (or via CI: `ruff check .` / `ruff format --check .` / `pytest`).

## Backend: Leaderboard API (`services/leaderboard-api/`)

```powershell
docker compose up --build     # starts redis + leaderboard-api (repo-root docker-compose.yml)
```

Requires `SUPABASE_JWT_SECRET` (from `supabase status`) and `DATABASE_URL` in root `.env`. Flutter picks it up via `LEADERBOARD_API_URL` in `.env` — omit to fall back to the Supabase `get_friend_leaderboard()` RPC directly (Global tab has no fallback and requires this service).

Verify: `curl http://localhost:8080/health`. Full manual verification steps (cache-hit behavior, RLS checks via `psql`, Redis ZSET inspection) are in `README.md`.

Tests: `cd services/leaderboard-api && pip install -e ".[dev]" && pytest`.

## Deploy: production (MicroK8s)

```powershell
.\deploy\scripts\deploy.ps1 1.0.0
.\deploy\scripts\deploy.ps1              # omit the version to auto-generate a timestamp tag
```

Builds `services/ocr-api` and `services/leaderboard-api`, ships them to the MicroK8s VM, imports into containerd, applies `deploy/k8s/`, restarts + verifies the rollout. Redis is a public image, not built. No manual SSH needed — the script handles it. The version arg is optional — every run forces `kubectl rollout restart` regardless of tag, so an auto-generated tag is just as safe as a manual one; pass an explicit version for a real release you want to track by name.

Required env vars: `DEPLOY_HOST`, `DEPLOY_USER`, `SSH_PASSWORD`, `DEPLOY_KNOWN_HOSTS` (path to a pinned `known_hosts` file — host keys are never auto-accepted), `CLOUDFLARE_TUNNEL_ID` (the tunnel ID printed by `cloudflared tunnel create receipt-drop`). Auth is password-only — the script writes the password to a private per-run temp file and drives a generated `SSH_ASKPASS` helper (never on a command line, never read from the env var by a static script). Both artifacts are scrubbed in a `finally` block whether the deploy succeeds or fails. `secrets.yaml` is applied over SSH stdin and is never written under `/tmp` on the VM; the remote deploy directory is deleted at the end of the run.

One-time local setup:

```powershell
Copy-Item deploy\k8s\secrets.yaml.example deploy\k8s\secrets.yaml
# fill in production DATABASE_URL, SUPABASE_JWT_SECRET, OCR_SHARED_SECRET, LLM creds

ssh-keyscan -H $env:DEPLOY_HOST | Out-File -Encoding ascii deploy\known_hosts
$env:DEPLOY_KNOWN_HOSTS = (Resolve-Path deploy\known_hosts).Path

# Cloudflare Tunnel (one-time, needs a browser + the receipt-drop.org zone
# already on Cloudflare): cloudflared tunnel login
#                         cloudflared tunnel create receipt-drop
#                         cloudflared tunnel route dns receipt-drop leaderboard.receipt-drop.org
#                         cloudflared tunnel route dns receipt-drop ocr.receipt-drop.org
# Paste the generated <TUNNEL_ID>.json into secrets.yaml's cloudflared-credentials
# block, and set:
$env:CLOUDFLARE_TUNNEL_ID = "<tunnel-id-printed-above>"
```

One-time server setup (`ubuntu-ethan`): `microk8s enable ingress` (Traefik-backed on MicroK8s ≥1.35, not nginx) and `microk8s enable hostpath-storage` (needed for Redis's PVC — no storage provisioner is enabled by default).

**Ingress / URLs:** a `cloudflared` Deployment tunnels both services to real HTTPS hostnames — `https://leaderboard.receipt-drop.org` and `https://ocr.receipt-drop.org` — dialing out to Cloudflare's edge (no port-forwarding, no router config, TLS terminated at Cloudflare). `ocr-api`'s hostname is additionally gated by **Cloudflare Access** (Zero Trust dashboard → Access → Applications: a Self-hosted app for `ocr.receipt-drop.org`, policy = allow a Service Token) on top of its existing shared-secret auth — generate the token under Access → Service Auth, then `supabase secrets set CF_ACCESS_CLIENT_ID=... CF_ACCESS_CLIENT_SECRET=...` and redeploy `ocr-proxy`/`enrich-transaction` (both attach it as `CF-Access-Client-Id`/`CF-Access-Client-Secret` headers automatically when set — see `docs/decisions.md`). The old Traefik Ingress (`/leaderboard-api/*`, `deploy/k8s/ingress.yaml`) still exists and still works as a LAN-only fallback, but `cloudflared` bypasses it — set Flutter `LEADERBOARD_API_URL` to `https://leaderboard.receipt-drop.org` (root path, no `/leaderboard-api` prefix) for production builds, and `OCR_SERVICE_URL` to `https://ocr.receipt-drop.org` in `supabase/functions/.env`/`supabase secrets set` for production Edge Functions.

`ocr-api`, `leaderboard-api`, `redis`, and `cloudflared` are deployed here. Edge Functions (`enrich-transaction`, `ocr-proxy`, `places-proxy`, `curate-insights`) deploy separately via `supabase functions deploy <name>` (see above) — they're not part of this k8s system. See `docs/architecture.md`'s "Production hosting" section and `docs/decisions.md` for the full design/tradeoffs.

## CI

`.github/workflows/python-ci.yml` — runs `ruff check` + `ruff format --check` + `pytest` for both `ocr-api` and `leaderboard-api` on every push/PR that touches `services/**` (any branch). No Flutter/Dart CI workflow exists yet — Flutter tests are run manually via the scripts above.

## Debugging

- Flutter `flutter test` lock errors on Windows → see README's OneDrive/hooks_runner section; use `flutter_test_windows.ps1`.
- Android build "stuck" on Gradle → likely OneDrive slowness; move the repo to `C:\dev\receipt-drop` (README has the full workaround).
- "No friend pins on map" → check whether `supabase/migrations/20260706000000_friend_map_pins.sql` has actually been pushed to the target Supabase project (`supabase db push`), and whether the user has `share_map_location = true`.
- OCR API "port already in use" refusal → run `scripts/stop_ocr_api.ps1 -Port <port>` (don't just retry; a second instance won't pick up config changes).
- `dart_tool` build cache still referencing `google_mlkit_*`/`google_maps_flutter_android` → stale artifacts from before the OCR/map migrations; not active dependencies, safe to ignore (or `flutter clean` if it's actually causing build errors).
