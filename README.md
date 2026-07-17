# receipt-drop

## Development (Windows)

### `flutter test` fails with “Could not acquire the lock … hooks_runner … .lock”

That comes from Flutter’s **native assets / hooks** step (often `sqlite3`, `jni`, `objective_c`) when another `dart`/`flutter` process still holds the lock, or **OneDrive** delays file access under `.dart_tool`.

1. Close other terminals running `flutter` / `dart` (including Cursor’s background tasks).
2. From the repo root, run:

   ```powershell
   .\scripts\flutter_test_windows.ps1
   ```

   It deletes stale `**/.lock` files under `.dart_tool/hooks_runner`, runs `flutter pub get`, then `flutter test`.

   If locks are still **in use**, stop other Flutter/Dart jobs, then:

   ```powershell
   .\scripts\flutter_test_windows.ps1 -StopDartProcesses
   ```

   (`-StopDartProcesses` kills **all** `dart`/`flutter` processes on the machine—only use when nothing else needs them.)

3. **Do not** run `flutter config --no-enable-native-assets` for this app. Dependencies such as **`sqlite3`** and **`objective_c`** need **Dart code/data assets** during `flutter test`. If you previously disabled them, turn them back on (machine-wide Flutter SDK setting):

   ```powershell
   flutter config --enable-native-assets
   flutter config --enable-dart-data-assets
   ```

   Then run `.\scripts\flutter_test_windows.ps1 -StopDartProcesses` again.

4. Long-term: keep the repo **outside OneDrive** (e.g. `C:\dev\receipt-drop`) to reduce hook **lock** friction while keeping native assets **enabled**.

### Google Maps API key setup

The map screens use `google_maps_flutter`, which needs a per-platform API key wired into native config (not the Dart `.env`). A key with a billing account attached is required — without one, the map renders blank.

- **Android**: add a line to `android/local.properties` (gitignored):
  ```
  MAPS_API_KEY=your-android-key-here
  ```
- **iOS**: copy `ios/Flutter/Secrets.xcconfig.example` → `ios/Flutter/Secrets.xcconfig` (gitignored) and fill in:
  ```
  MAPS_API_KEY = your-ios-key-here
  ```

Create keys in the Google Cloud Console with **Maps SDK for Android** / **Maps SDK for iOS** enabled, restricted to this app's package name + SHA-1 (Android) or bundle ID (iOS).

### Android `flutter run` stuck on Gradle for a long time

First debug builds download Android SDK components (CMake, etc.) and compile native deps (ML Kit, SQLite). Under **OneDrive**, `assembleDebug` can appear hung for an hour+.

1. Stop the run (`Ctrl+C`) and use a copy off OneDrive: `C:\dev\receipt-drop` (sync from Desktop with `robocopy` or open that folder in Cursor).
2. From `C:\dev\receipt-drop`: `flutter pub get` then `flutter run` (phone connected with USB debugging).
3. A successful first build produces `build\app\outputs\flutter-apk\app-debug.apk` in ~2–5 minutes off OneDrive; later runs are much faster.

## Leaderboard API (FastAPI + Redis)

Optional Redis-backed leaderboard service for the **Ranks** tab (Friends + Global). When `LEADERBOARD_API_URL` is unset, the Friends tab uses the Supabase `get_friend_leaderboard()` RPC directly; Global requires the API.

### Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/friends-leaderboard?fresh=false` | Friends ranks (JSON cache-aside, 10s TTL) |
| GET | `/leaderboard/global` | Global top 100 (`ZREVRANGE leaderboard:global 0 99`) |
| POST | `/leaderboard/score` | Upsert caller's score from Postgres into Redis ZSET |

### Prerequisites

- [Supabase CLI](https://supabase.com/docs/guides/cli) — local Postgres on port `54322`
- Docker Desktop (Redis + API containers)

### Local setup

1. Copy `.env.example` → `.env` and set `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
2. Start Supabase and apply migrations (includes RLS policy `profiles_select_accepted_friend`):

   ```powershell
   supabase start
   supabase db reset
   ```

3. Copy the **JWT secret** from `supabase status` into `.env` as `SUPABASE_JWT_SECRET` (used by the API container).
4. Start Redis + API:

   ```powershell
   docker compose up --build
   ```

5. Add to `.env` for Flutter debug:

   ```
   LEADERBOARD_API_URL=http://localhost:8080
   ```

   On a physical device, use your machine's LAN IP instead of `localhost`. For
   a release build talking to production, use
   `LEADERBOARD_API_URL=https://leaderboard.receipt-drop.org` (Cloudflare
   Tunnel — see `.claude/commands.md`'s deploy section) instead.

### Verify

```powershell
curl http://localhost:8080/health
```

Signed-in app flow:

**Friends tab**

1. Open **Ranks → Friends** — first load hits Postgres (`cached: false` in API response if you curl with a valid JWT).
2. Reload within 10 seconds — Redis cache hit (`cached: true`).
3. Pull-to-refresh — bypasses cache (`?fresh=true`).
4. Remove `LEADERBOARD_API_URL` from `.env` — app falls back to Supabase RPC.

**Global tab**

1. Open home screen once — syncs streak/badge to Postgres and calls `POST /leaderboard/score`.
2. Open **Ranks → Global** — top 100 from Redis ZSET, hydrated with profile metadata from Postgres.
3. Verify in Redis: `docker exec -it receipt-drop-redis redis-cli ZREVRANGE leaderboard:global 0 9 WITHSCORES`

### RLS checks (psql)

After seeding two accepted friends and one stranger:

```sql
-- As user A (set jwt claim), stranger C must not appear:
select set_config('request.jwt.claim.sub', '<user-a-uuid>', true);
set local role authenticated;
select user_id from public.get_friend_leaderboard();
```

### API tests

```powershell
cd services/leaderboard-api
pip install -e ".[dev]"
pytest
```