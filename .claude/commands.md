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

## CI

`.github/workflows/python-ci.yml` — runs `ruff check` + `ruff format --check` + `pytest` for both `ocr-api` and `leaderboard-api` on every push/PR that touches `services/**` (any branch). No Flutter/Dart CI workflow exists yet — Flutter tests are run manually via the scripts above.

## Debugging

- Flutter `flutter test` lock errors on Windows → see README's OneDrive/hooks_runner section; use `flutter_test_windows.ps1`.
- Android build "stuck" on Gradle → likely OneDrive slowness; move the repo to `C:\dev\receipt-drop` (README has the full workaround).
- "No friend pins on map" → check whether `supabase/migrations/20260706000000_friend_map_pins.sql` has actually been pushed to the target Supabase project (`supabase db push`), and whether the user has `share_map_location = true`.
- OCR API "port already in use" refusal → run `scripts/stop_ocr_api.ps1 -Port <port>` (don't just retry; a second instance won't pick up config changes).
- `dart_tool` build cache still referencing `google_mlkit_*`/`google_maps_flutter_android` → stale artifacts from before the OCR/map migrations; not active dependencies, safe to ignore (or `flutter clean` if it's actually causing build errors).
