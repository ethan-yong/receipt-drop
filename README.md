# Receipt Drop

Malaysian receipt-first spend tracker. Share a receipt image or PDF via the OS share sheet; the app OCRs it, extracts amount / merchant / category / line items, saves instantly to a local offline outbox, and syncs to the cloud in the background.

Layered on top: gamification (avatar, badges, streaks), AI spending insights, receipt history, a spend map with friend pins, a friends feed, and friends + global leaderboards.

## Resources

| Doc | What |
|---|---|
| [`docs/README.md`](docs/README.md) | Full documentation index |
| [`docs/system/architecture.md`](docs/system/architecture.md) | Data flow, platform splits, hosting |
| [`docs/system/decisions.md`](docs/system/decisions.md) | Why things are built this way |
| [`setup.md`](setup.md) | Remote Supabase (OAuth, secrets) checklist |
| [`.claude/commands.md`](.claude/commands.md) | Run / build / test / deploy command reference |
| [`pending-tasks.md`](pending-tasks.md) | Deliberately deferred backlog |

## Architecture

| Layer | Stack |
|---|---|
| Client | Flutter / Dart (`go_router`, Drift/SQLite outbox, `supabase_flutter`) |
| Backend | Supabase (Postgres + RLS + Auth + Storage) + 3 Deno Edge Functions |
| OCR | Self-hosted FastAPI + Tesseract (`services/ocr-api`) |
| Leaderboard | FastAPI + Redis (`services/leaderboard-api`) for Global ranks |
| Maps | `google_maps_flutter` with Flutter widget overlays for pins |

**App shell tabs:** Home, Feed, Map, Ranks. Detail routes include receipt history, insights, settings, avatar, badges, friends, and transaction detail.

Local-first: every capture writes to on-device SQLite immediately, then a background sync worker uploads to Supabase and triggers place enrichment. Full diagram and patterns: [`docs/system/architecture.md`](docs/system/architecture.md).

```
Share / capture → local outbox (Drift)
                 → SyncWorker → Supabase Storage + Postgres
                 → enrich-transaction (Places)
OCR path:        Flutter → ocr-proxy (prod) or OCR API direct (dev)
```

## Local development

Windows-first repo. Prefer a clone **outside OneDrive** (e.g. `C:\dev\receipt-drop`) — OneDrive under `.dart_tool` causes Flutter hook lock stalls (see [Troubleshooting](#troubleshooting)).

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) (stable)
- [Supabase CLI](https://supabase.com/docs/guides/cli)
- Docker Desktop (leaderboard Redis + optional OCR container)
- [uv](https://docs.astral.sh/uv/) (OCR API)
- A connected device, emulator, or `-d chrome` / `-d windows`

### 1. Environment

```powershell
Copy-Item .env.example .env
```

Minimum for Flutter debug with local Supabase:

| Variable | Source |
|---|---|
| `SUPABASE_URL` | `supabase status` after `supabase start` |
| `SUPABASE_ANON_KEY` | same |
| `SKIP_AUTH` | `true` (default) bypasses onboarding/auth in debug |

Also set `OCR_SHARED_SECRET` (and matching `OCR_SERVICE_SECRET` in `supabase/functions/.env`) if you run OCR locally. See `.env.example` for the full list.

### 2. Supabase (local)

```powershell
.\scripts\supabase_start.ps1   # or: supabase start
supabase db reset               # apply all migrations
supabase status                 # copy URL, anon key, JWT secret into .env
```

Edge Functions start with the local stack. Secrets for them go in `supabase/functions/.env` (copy from the example there; `GOOGLE_PLACES_API_KEY` is required for place enrichment).

Remote project checklist (OAuth, secrets): [`setup.md`](setup.md).

### 3. Flutter app

```powershell
flutter pub get
flutter run                     # device/emulator, or -d chrome / -d windows
```

Physical Android reaching services on your PC: `.\scripts\android_dev_ports.ps1`.

### 4. OCR API (optional for capture)

Needed for real receipt OCR in debug (otherwise amounts are manual / skipped on web).

```powershell
# From repo root — default port 8081
.\scripts\run_ocr_api.ps1
# or: cd services/ocr-api; uv run ocr-api
```

Requires `OCR_SHARED_SECRET` in root `.env`. LLM receipt understanding needs `LLM_PROVIDER` + the matching `VLLM_*` or `DEEPSEEK_*` block (see `.env.example`).

For local Edge Functions calling OCR: keep `OCR_SERVICE_URL=http://host.docker.internal:8081` in `supabase/functions/.env`.

### 5. Leaderboard API (optional for Ranks → Global)

```powershell
# Needs SUPABASE_JWT_SECRET + DATABASE_URL in .env (from supabase status)
docker compose up --build
```

Then set `LEADERBOARD_API_URL=http://localhost:8080` in `.env`. Omit it to fall back to the Supabase friends RPC (Global tab still needs this service).

Verify: `curl http://localhost:8080/health`.

## Testing

```powershell
.\scripts\flutter_test_windows.ps1                     # clears hook locks, pub get, flutter test
.\scripts\flutter_test_windows.ps1 -StopDartProcesses  # also kills stray dart/flutter processes

cd services/ocr-api; pytest
cd services/leaderboard-api; pip install -e ".[dev]"; pytest
deno test supabase/functions/_shared/
```

Do **not** run `flutter config --no-enable-native-assets` — `sqlite3` / `objective_c` need native assets enabled for `flutter test`.

## Deployment

Production OCR + leaderboard services run on MicroK8s behind Cloudflare Tunnel:

```powershell
.\deploy\scripts\deploy.ps1 1.0.0
```

Details: [`.claude/commands.md`](.claude/commands.md) (Deploy section) and [`docs/system/architecture.md`](docs/system/architecture.md).

Supabase migrations / Edge Functions: `supabase db push`, `supabase functions deploy <name>`.

---

## Leaderboard API details

Optional Redis-backed service for the **Ranks** tab (Friends + Global). When `LEADERBOARD_API_URL` is unset, Friends uses the Supabase `get_friend_leaderboard()` RPC directly; Global requires the API.

### Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/friends-leaderboard?fresh=false` | Friends ranks (JSON cache-aside, 10s TTL) |
| GET | `/leaderboard/global` | Global top 100 (`ZREVRANGE leaderboard:global 0 99`) |
| POST | `/leaderboard/score` | Upsert caller's score from Postgres into Redis ZSET |

### Local setup

1. Copy `.env.example` → `.env` and set `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
2. Start Supabase and apply migrations:

   ```powershell
   supabase start
   supabase db reset
   ```

3. Copy the **JWT secret** from `supabase status` into `.env` as `SUPABASE_JWT_SECRET`.
4. Start Redis + API:

   ```powershell
   docker compose up --build
   ```

5. Add to `.env` for Flutter debug:

   ```
   LEADERBOARD_API_URL=http://localhost:8080
   ```

   On a physical device, use your machine's LAN IP instead of `localhost`. For a release build talking to production, use `LEADERBOARD_API_URL=https://leaderboard.receipt-drop.org` (Cloudflare Tunnel).

### Manual verification

**Friends tab**

1. Open **Ranks → Friends** — first load hits Postgres (`cached: false` if you curl with a valid JWT).
2. Reload within 10 seconds — Redis cache hit (`cached: true`).
3. Pull-to-refresh — bypasses cache (`?fresh=true`).
4. Remove `LEADERBOARD_API_URL` from `.env` — app falls back to Supabase RPC.

**Global tab**

1. Open home once — syncs streak/badge to Postgres and calls `POST /leaderboard/score`.
2. Open **Ranks → Global** — top 100 from Redis, hydrated with profile metadata from Postgres.
3. Inspect Redis: `docker exec -it receipt-drop-redis redis-cli ZREVRANGE leaderboard:global 0 9 WITHSCORES`

### RLS check (psql)

After seeding two accepted friends and one stranger:

```sql
-- As user A (set jwt claim), stranger C must not appear:
select set_config('request.jwt.claim.sub', '<user-a-uuid>', true);
set local role authenticated;
select user_id from public.get_friend_leaderboard();
```

---

## Troubleshooting

### Google Maps API key

Map screens use `google_maps_flutter`, which needs a per-platform API key in native config (not Dart `.env`). Billing must be enabled or the map renders blank.

- **Android**: add to `android/local.properties` (gitignored):

  ```
  MAPS_API_KEY=your-android-key-here
  ```

- **iOS**: copy `ios/Flutter/Secrets.xcconfig.example` → `ios/Flutter/Secrets.xcconfig` (gitignored):

  ```
  MAPS_API_KEY = your-ios-key-here
  ```

Create keys in Google Cloud Console with **Maps SDK for Android** / **Maps SDK for iOS** enabled, restricted to this app's package name + SHA-1 (Android) or bundle ID (iOS).

### `flutter test` fails with hooks_runner lock

Flutter’s native-assets / hooks step (often `sqlite3`, `jni`, `objective_c`) fails when another `dart`/`flutter` process holds the lock, or OneDrive delays file access under `.dart_tool`.

1. Close other terminals running `flutter` / `dart`.
2. From the repo root:

   ```powershell
   .\scripts\flutter_test_windows.ps1
   ```

   If locks are still in use:

   ```powershell
   .\scripts\flutter_test_windows.ps1 -StopDartProcesses
   ```

   (`-StopDartProcesses` kills **all** `dart`/`flutter` processes on the machine.)

3. Do **not** run `flutter config --no-enable-native-assets`. If previously disabled:

   ```powershell
   flutter config --enable-native-assets
   flutter config --enable-dart-data-assets
   ```

4. Long-term: keep the repo outside OneDrive (e.g. `C:\dev\receipt-drop`).

### Android `flutter run` stuck on Gradle

First debug builds download SDK components and compile native deps. Under OneDrive, `assembleDebug` can appear hung for an hour+.

1. Stop the run (`Ctrl+C`) and use a copy off OneDrive.
2. From that copy: `flutter pub get` then `flutter run`.
3. A successful first build produces `build\app\outputs\flutter-apk\app-debug.apk` in ~2–5 minutes off OneDrive; later runs are much faster.
