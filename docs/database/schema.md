# Database

Postgres via Supabase. Migrations live in `supabase/migrations/`, applied in filename (timestamp) order — **always read them chronologically**; later migrations alter columns/constraints/RLS added by earlier ones rather than restating the whole table. The schema below is the cumulative *current* state as of `20260708000000_merchant_aliases.sql`.

Local dev: `supabase start` then `supabase db reset` (replays all migrations). JWT secret from `supabase status` feeds `SUPABASE_JWT_SECRET` for `services/leaderboard-api`.

## Tables

### `profiles`
1:1 with `auth.users` (auto-created by trigger `on_auth_user_created` / `handle_new_user()`, `20260511000000_init.sql`). RLS: own row only, **plus** (`20260630000000_leaderboard_api.sql`) `profiles_select_accepted_friend` — any authenticated user can SELECT a profile they share an accepted `friendships` row with. This is an intentional widening from the original "definer-functions-only" cross-user access philosophy stated in `20260626000002_social.sql` — done so the external leaderboard-api service (impersonating users via JWT) and the Flutter RPC fallback can both read friend profiles under plain RLS instead of a bypass function.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | → `auth.users`, cascade delete |
| `display_name` | text | |
| `avatar_url` | text | |
| `wants_friends_beta` | boolean | legacy v1 teaser flag |
| `created_at` | timestamptz | |
| `avatar_config` | jsonb | `{color, eyes, hat}`, default cap/yellow/neutral — added `20260626000000` |
| `top_badge_order` | text[] | added `20260626000000` |
| `current_mood` | text | check `calm\|active\|spiky\|balanced`, nullable — added `20260626000002` |
| `badge_count` | int | default 0, `>=0` — added `20260626000003`, denormalized from `user_badges` |
| `current_streak` | int | default 0, `>=0` — added `20260626000003`, denormalized |
| `share_map_location` | boolean | default true — added `20260706000000`, opt-out for friend map pins |
| `username` | text | nullable, case-insensitive unique (`profiles_username_unique_idx` on `lower(username)`) — added `20260804000000` |
| `profile_setup_complete` | boolean | default false — added `20260804000000`, gates the post-sign-in `/profile-setup` screen |

`badge_count`/`current_streak`/`current_mood`/`avatar_config` are **write-your-own-row-only** denormalizations pushed by `lib/data/repositories/avatar_repository.dart` (`syncCurrentMood`, `syncCurrentStreak`, `syncBadgeCount`) so friend-facing queries (leaderboard, feed, map) never need to read another user's `transactions`.

`username` availability is checked via the `is_username_available(candidate text)` RPC (`security definer`, `20260804000000`) rather than widening `profiles_select_own` — it only exposes an exists-check, not the underlying rows. `avatar_url` is now actually wired up: `lib/data/repositories/profile_repository.dart` uploads a real photo to the `avatars` Storage bucket (public read, own-folder write — same shape as the `receipts`/`config` buckets in `20260511000001_storage.sql`) and stores its public URL here. It's writable from two places — once during `/profile-setup` (`completeProfileSetup`) and again any time after from `SettingsScreen` (`updateAvatarUrl`), since a photo shouldn't be a one-time-only choice.

### `transactions`
Core receipt row. RLS: owner-only for all of select/insert/update/delete (`20260511000000_init.sql`), unchanged since.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | client-generated |
| `user_id` | uuid FK → `profiles.id` | cascade delete |
| `created_at`, `occurred_at` | timestamptz | |
| `amount_myr` | numeric(12,2) | null = "needs amount" |
| `amount_source` | text | `ocr\|user\|blended` |
| `needs_amount` | boolean | |
| `merchant_raw`, `merchant_normalized` | text | |
| `category_guess`, `category_user` | text | effective category = user ?? guess ?? "Unclassified" |
| `category_confidence` | float8 | tuning only, never shown to user |
| `place_status` | text | `guess\|user_locked\|none` |
| `place_google_place_id`, `place_name`, `place_lat/lng`, `place_confidence` | | |
| `share_location_lat/lng`, `share_location_captured_at` | | device location at share time |
| `ocr_confidence` | float8 | **amount-extraction** confidence |
| `pipeline_status` | text | `provisional\|enriched\|failed_enrichment\|needs_review` (4th value added `20260705000000`) |
| `impact_user` | text | `low\|med\|high`, user override — added `20260626000000` |
| `raw_ocr_text` | text | added `20260705000000` — since the LLM receipt-understanding step, always populated (client caps it ~8000 chars) rather than only for failed/low-confidence parses; still doubles as labeled data for fixing parser rules |
| `ocr_service_confidence` | float8 | added `20260705000000` — **scan-quality** confidence from the OCR engine, distinct from `ocr_confidence` (amount-extraction). Don't conflate the two. |
| `line_items_confidence` | float8 | added `20260705000000` |
| `parse_failure_reason` | text | added `20260705000000` |
| `merchant_candidates` | jsonb | added `20260708000000` — ranked `MerchantCandidate[]` (`{text, confidence, source}`) from `extractMerchantCandidates()`; `merchant_raw` is always the top entry's text. No longer read by `enrich-transaction` (superseded by `llm_understanding`), kept for the alias-cache precedent and future heuristic comparisons |
| `ocr_header_text` | text | added `20260708000000` — top-of-receipt OCR lines, always populated; used by `enrich-transaction` as a fallback when `raw_ocr_text` is empty |
| `llm_understanding` | jsonb | added `20260709000000` — structured output of the LLM receipt-understanding step: `merchant_name`, `merchant_search_queries`, `address_text`, `location_clues`, `vendor_category`, `google_place_types`, `line_items`, `confidence`, plus a `_meta` (latency/prompt_source) or `_error`/`_raw` on failure. As of the client-synchronous OCR+LLM pipeline (`docs/decisions.md`), this is normally populated by the **client** at sync time (`SyncWorker`, from the local `llmUnderstandingJson` Drift column produced alongside OCR at capture) — `enrich-transaction` only writes it itself when it had to fall back to calling `services/ocr-api`'s `POST /understand` (missing/invalid precomputed value) |
| `place_geom` | `geometry(Point, 4326)`, generated (stored) | added `20260713000000` — `ST_MakePoint(coalesce(place_lng, share_location_lng), coalesce(place_lat, share_location_lat))`, null when neither lat/lng pair is set. Requires the `postgis` extension (enabled in the same migration). Bounding-box viewport queries only (`&&`/`ST_MakeEnvelope`), not radius/distance search — geometry (not geography) was chosen for that reason |
| `cleaned_ocr_text` | text | added `20260723000000` — LLM OCR-cleanup step's corrected transcript (opt-in via `LLM_CLEANUP_ENABLED`, `services/ocr-api`), additive alongside — never replacing — `raw_ocr_text`. Own column (not folded into `llm_understanding`) mirroring `raw_ocr_text`'s own-column precedent, so both stay independently queryable. Null when cleanup wasn't attempted or produced nothing the per-line edit-distance guard accepted |
| `ocr_corrections` | jsonb | added `20260723000000` — compact per-line correction record (`[{line_index, original, corrected}, ...]`) for lines the cleanup guard actually accepted; empty/null alongside a null `cleaned_ocr_text` |

Indexes: `transactions_user_occurred_idx (user_id, occurred_at desc)`; `transactions_place_geom_gix` — GiST index on `place_geom`, added `20260713000000` for the map's viewport query.

`needs_review` rows are queued in `lib/features/review/receipt_review_screen.dart`; enrichment is deferred until the user confirms (`confirmReview()` flips status back to `provisional` and re-syncs).

### `receipt_artifacts`
Metadata row for a file in the `receipts` storage bucket. `id`, `user_id` FK, `transaction_id` FK (cascade), `storage_path`, `mime_type`, `created_at`. RLS: select/insert/delete own; **no update** (immutable). Unchanged since `20260511000000`.

### `receipt_line_items`
Added `20260703000000_receipt_line_items.sql`. `id`, `user_id` FK, `transaction_id` FK (cascade), `name`, `price_myr`, `quantity`, `confidence`, `sort_order`, `created_at`. Index `(transaction_id, sort_order)`. RLS: select/insert/delete own; no update (immutable, mirrors `receipt_artifacts`). Rows can originate from either the heuristic Dart extractor or the LLM's `line_items` (the client prefers the LLM's whenever it returned any — see `docs/decisions.md`); there's no `source` column to distinguish them, since the choice is made once client-side before the first insert, not reconciled after the fact.

### `user_badges`
Added `20260626000001_badges.sql`. `id`, `user_id` FK (cascade), `badge_id text` (references the **client-bundled** `assets/config/badges-v1.json` catalog, not a DB table), `progress numeric`, `earned boolean`, `earned_at`, `updated_at`. `unique(user_id, badge_id)`. RLS: select/insert/update own; no delete.

### `friendships`
Added `20260626000002_social.sql`. `id`, `requester_id`/`addressee_id` FK → `profiles` (cascade), `status text` (`pending\|accepted\|declined\|blocked`, default `pending`), `created_at`, `responded_at`. `check (requester_id != addressee_id)`, `unique(requester_id, addressee_id)`. Index on `addressee_id`.

RLS is deliberately asymmetric on update: `using auth.uid() in (requester_id, addressee_id)`, `with check ... and (status='blocked' or auth.uid()=addressee_id)` — **only the addressee can accept/decline**, either party can block. This prevents a requester from self-accepting their own request to gain read access to a stranger's profile. No delete policy (block/decline instead of deleting).

### `feed_posts`
Added `20260626000002_social.sql`. `id`, `user_id` FK (cascade), `transaction_id` FK (cascade, nullable), `line text` — **system-generated flavor text only, never raw amount/merchant** (see `lib/domain/logic/feed_line_generator.dart`), `created_at`. Index `(user_id, created_at desc)`. RLS: select/insert/delete own; no update.

### `feed_reactions`
Added `20260626000002_social.sql`. `id`, `post_id` FK → `feed_posts` (cascade), `user_id` FK (cascade), `kind text` (`fire\|laugh\|eyes`), `created_at`. `unique(post_id, user_id, kind)` for idempotent repeat-tap. RLS: **insert-only** own policy — no select policy at all. Reads only ever happen aggregated inside `get_friend_feed()`; a direct `select` from a client is denied by RLS even though a table grant exists.

### `pending_receipts`
Added `20260712000000_pending_receipts.sql`. Supabase mirror of the device inbox — created asynchronously after the local Drift row. The **Drift row is the source of truth**; this table exists only so the cloud has visibility. RLS: owner-only for all operations (`pending_receipts_owner` policy). Index `(user_id, created_at desc)`.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | client-generated, matches Drift `pending_imports.id` |
| `user_id` | uuid FK → `profiles.id` | cascade delete |
| `storage_path` | text | `<user_id>/pending/<id>.<ext>` in the `receipts` bucket |
| `file_type` | text | mime type |
| `status` | text | `pending\|processing\|completed\|failed` (check constraint). `completed` written by client after the transaction is saved; never written by a server process |
| `source_app` | text | optional — app that originated the share (e.g. "Touch 'n Go") |
| `transaction_id` | uuid FK → `transactions.id` | set to null on delete; written when `completed` |
| `created_at` | timestamptz | |

Storage path reuses the existing `receipts` bucket (the folder-level RLS `(storage.foldername(name))[1] = auth.uid()::text` already covers `<user_id>/pending/...`). The client uploads the file and inserts this row in a single best-effort async step after the local Drift save — never blocking the share flow.

### `merchant_aliases`
Added `20260708000000_merchant_aliases.sql`. `id`, `alias_text_normalized text`, `geohash_bucket text` (precision-7, ~150m cells — coarser than the map's precision-8 aggregation key, to tolerate phone GPS drift), `canonical_place_id text`, `canonical_name text`, `canonical_lat/lng double precision`, `confidence double precision` (check 0-1), `hit_count int default 1`, `created_at`, `last_matched_at`. `unique(alias_text_normalized, geohash_bucket, canonical_place_id)`, index on `(alias_text_normalized, geohash_bucket)`.

**Deliberately global, not per-user** — a cache of "this garbled OCR text near this location resolves to this Google Place," shared across all users (business names aren't sensitive; one user's correction should help everyone who later scans a receipt from the same place). RLS enabled with **zero policies** — no `authenticated`/`anon` grant on the table at all, and function `EXECUTE` is explicitly revoked from `PUBLIC` before being granted to `authenticated` (Postgres auto-grants `EXECUTE` to `PUBLIC` on new functions — easy to forget to revoke). The only access path is the two functions below, matching the `list_leaderboard_scores()` precedent of a locked-down table behind narrow definer functions. See `docs/decisions.md`.

### `user_field_corrections`
Added `20260723010000_user_field_corrections.sql` (feedback-learning-system, `docs/plans/2026-07-23-feedback-learning-system.md`). `id`, `user_id` FK → `profiles.id` cascade, `transaction_id` FK → `transactions.id` cascade, `field text` (check `merchant|amount|category|line_item_price`), `predicted_value text`, `confirmed_value text`, `merchant_raw text` (nullable — the merchant this correction is attributed to, regardless of `field`), `confidence double precision` (nullable), `correction_type text` (nullable — `free_text|user_locked`, `field = 'merchant'` only), `line_item_index integer` (nullable, `field = 'line_item_price'` only), `created_at`. Indexes on `user_id` and `transaction_id`.

`alias_writeback_applied_at timestamptz` (nullable) added `20260724010000_feedback_learning_hardening.sql` — set by `upsert_merchant_alias_from_correction` after a successful merchant-alias write-back so retries/re-enrichment cannot re-increment `merchant_aliases.hit_count` for the same logical correction.

Owner-only RLS (`user_id = auth.uid()`), same as `transactions`. This is the single source-of-truth event log every other learning surface below derives from — captured client-side in `ReceiptConfirmSheet._buildFieldCorrections()` at the one point the OCR/LLM prediction and the user's confirmed value are both still in scope, synced alongside the transaction it belongs to.

### `user_category_preferences`
Added `20260723020000_user_category_preferences.sql`. `id`, `user_id` FK → `profiles.id` cascade, `merchant_normalized text`, `category text`, `correction_count int default 1` (corroboration counter — see below), `last_corrected_at`, `created_at`. `unique(user_id, merchant_normalized)`, index on `(user_id, merchant_normalized)`.

Strictly owner-only (RLS `user_id = auth.uid()`, like `transactions`) — a personal signal, not shared cross-user like `merchant_aliases`. `upsert_category_preference()`/`lookup_category_preference()` below are plain `security invoker` functions (RLS still applies to the caller), used only for the atomic corroboration-count increment, not to bypass RLS. A learned preference is only meant to be surfaced once corrected *consistently* at least twice for the same merchant: when a disagreeing correction arrives, the newest category wins (recency) but `correction_count` resets to 1. As of `20260724010000`, the `>= 2` corroboration gate is enforced inside `lookup_category_preference` itself (returns no row for `correction_count < 2`), and the RPC also returns a decayed, corroboration-weighted `confidence` (90-day half-life on `last_corrected_at`). One-time backfill from historical `transactions.category_user`/`category_guess` divergence: `supabase/scripts/20260723_backfill_category_preferences.sql` (not a migration — run manually once).

### `ocr_misread_patterns`
Added `20260723030000_ocr_misread_patterns.sql`. `id`, `from_char text`, `to_char text`, `hit_count int default 1`, `created_at`, `last_seen_at`. `unique(from_char, to_char)`, index on `(from_char, to_char)`.

Global and anonymous by construction — rows are abstracted single-character substitution counts only (e.g. "a predicted `O` was corrected to a confirmed `0`"); the amount/receipt content that produced them never reaches this table at all (the abstraction — `lib/domain/logic/misread_pattern_extractor.dart` — runs client-side before the record is ever constructed, and only proceeds when the predicted/confirmed strings align as a small, localized fix). Locked down exactly like `merchant_aliases`: zero RLS policies, access only via `lookup_misread_patterns()`/`upsert_misread_pattern()`, execute revoked from `public` then granted to `authenticated`. Not yet consumed server-side (`services/ocr-api` has no Postgres connectivity today — see `docs/system/decisions.md`); aggregation only for v1.

### `friend_groups` / `friend_group_members`
Added `20260807000000_friend_groups.sql`. `friend_groups`: `id`, `owner_id` FK → `profiles` (cascade), `name`, `created_at`. `friend_group_members`: `group_id` FK → `friend_groups` (cascade), `friend_user_id` FK → `profiles` (cascade), `added_at`, `primary key (group_id, friend_user_id)`. Owner-only RLS on both; a member row's insert additionally requires `friend_user_id` be an accepted friend of the caller (checked declaratively against `friendships`, no trigger). Named, persisted subsets of a user's friends for one-tap selection in the Bill Split flow — not a general-purpose social feature.

### `bill_splits` / `bill_split_participants` / `bill_split_item_assignments`
Added `20260807010000_bill_splits.sql`. A receipt's payer splits it with a subset of their friends; v1 is payer-created bookkeeping, but **friends can see and self-report their own share as paid** (see below) — there is no push-notification system in this app, so discovery is via `SplitRequestsScreen`/a Home banner, both driven by realtime reads, not a delivered notification.

- `bill_splits`: `id`, `transaction_id` FK → `transactions` (cascade, **unique** — one split per receipt), `owner_id` FK → `profiles` (cascade), `mode text` (`equal|by_item`), `total_myr` snapshotted at creation (not re-derived from `transactions.amount_myr`, so a later amount edit can't invalidate already-collected shares), `created_at`. RLS: select/insert/delete owner-only; **no update policy** — immutable once created, like `receipt_line_items`. No in-place edit UI in v1.
- `bill_split_participants`: `id`, `split_id` FK → `bill_splits` (cascade), `friend_user_id` FK → `profiles` (cascade), `share_myr`, `paid boolean default false`, `paid_at`, `last_reminded_at`, `created_at`, `unique(split_id, friend_user_id)`. RLS is where friend-visibility lives: the payer has full select/insert/update/delete on their split's rows, **and a participant can additionally select/update their own row** (`friend_user_id = auth.uid()`) — two separate permissive update policies, Postgres ORs them. No column-level restriction (no precedent for that anywhere else in this schema); the friend-side client codepath only ever sends `{paid, paid_at}`.
- `bill_split_item_assignments`: `id`, `split_id` FK → `bill_splits` (cascade), `line_item_id` FK → `receipt_line_items` (cascade), `assigned_user_id` FK → `profiles` (cascade), `created_at`, `unique(split_id, line_item_id, assigned_user_id)`. Only populated for `mode='by_item'`; owner-only RLS (never edited by a friend). `assigned_user_id` can be the owner or any friend — no fake `'you'` sentinel row.
- `get_my_split_requests()` — `security definer`, joins `bill_split_participants` (`where friend_user_id = auth.uid()`) → `bill_splits` → `transactions` (for `merchant_raw`) → `profiles` (payer's name/`avatar_config`/`avatar_url`). The only cross-user read in this feature — `transactions`/`profiles` are otherwise owner-only-readable, same reasoning as `get_friend_feed()`. `avatar_url` added in `20260811120000` so Split Requests can show the real profile photo.

## Storage buckets (`20260511000001_storage.sql`)

| Bucket | Public | Policy |
|---|---|---|
| `receipts` | No | `authenticated`-only select/insert/delete where `(storage.foldername(name))[1] = auth.uid()::text`. No update (immutable uploads). Object key: `<user_id>/<transaction_id>/<artifact_id>.<ext>`. |
| `config` | Yes | `select` open to `anon` + `authenticated`, bucket-wide. Intended for public static config/bundled-asset mirrors. |
| `place-photos` | Yes | Public `select` for `anon` + `authenticated` (`place_photos_public_read`). **No client write policies** — only `places-proxy` (service role) uploads. Object key: `<google_place_id>/<index>.jpg`. Added in `20260811180001_place_photos_cache.sql`. |

### `place_photos_cache` (`20260811180001_place_photos_cache.sql`)

Shared, cross-user cache of Google Places venue photos for the map sheet carousel. Keyed by `google_place_id`; `photo_urls` holds **bucket-relative Storage paths** in `place-photos` (e.g. `ChIJ…/0.jpg`), not absolute URLs — the Flutter client rebuilds public URLs against its own Supabase origin. `fetched_at` drives a 30-day TTL inside `places-proxy`. RLS enabled with **zero client policies**; `anon`/`authenticated` revoked; `service_role` has explicit `SELECT/INSERT/UPDATE/DELETE` because the edge function writes this table directly (unlike `merchant_locations`, which is only touched via SECURITY DEFINER RPCs).

## Functions / RPCs

| Function | Mode | Purpose | Migration | Caller |
|---|---|---|---|---|
| `handle_new_user()` (+ trigger `on_auth_user_created`) | `security definer` | Seeds `profiles` row on signup | `20260511000000` | Postgres trigger only |
| `find_user_by_email(lookup_email)` | `security definer` | Resolve email → profile id/name without exposing `auth.users` | `20260626000002` | `social_repository.dart` (add friend) |
| `list_friendships()` | `security definer` | Friendship rows joined with the other party's public profile fields (`other_avatar_config` + `other_avatar_url`) | `20260626000002`, `avatar_url` in `20260811120000` | `social_repository.dart` |
| `list_friend_groups()` | `security definer` | Owner's friend groups + member display name/`avatar_config`/`avatar_url` | `20260807000000`, `avatar_url` in `20260811120000` | `bill_split_repository.dart` |
| `get_my_split_requests()` | `security definer` | Splits the caller is a participant in, with payer name/`avatar_url` + merchant | `20260807010000`, `avatar_url` in `20260811120000` | `bill_split_repository.dart` |
| `get_friend_feed()` | `security definer` | Accepted friends' feed posts + per-post reaction counts, limit 100 | `20260626000002` | `social_repository.dart` |
| `get_friend_leaderboard()` | **`security invoker`** (redefined from definer in `20260630000000`) | Ranks self + accepted friends by `current_streak desc, badge_count desc` — explicitly a placeholder ranking pending product sign-off | `20260626000003`, redefined `20260630000000` | `services/leaderboard-api/app/db.py` (JWT-impersonated) and Flutter's direct RPC fallback when `LEADERBOARD_API_URL` unset |
| `get_leaderboard_profiles_by_ids(uuid[])` | `security definer` | Narrow batch profile hydration for global leaderboard display | `20260630100000` | `leaderboard-api/app/db.py` |
| `list_leaderboard_scores()` | `security definer`, **execute revoked from `public`, granted only to `postgres` role** | Bulk dump of all scorable profiles, for Redis ZSET cold-start rebuild | `20260630100000` | `leaderboard-api` FastAPI startup only (runs as postgres superuser) |
| `get_friend_map_pins()` | `security definer` | Each accepted friend's single most-recent geolocated transaction in last 30 days (place+time only, never amount), gated by `share_map_location`; includes `avatar_url` for the real profile photo on map pins | `20260706000000`, `avatar_url` in `20260811000000` | `social_repository.dart` (spend map friend pins) |
| `get_map_transactions_in_bounds(min_lat, min_lng, max_lat, max_lng, start_at, end_at, category)` | `security definer` | Caller's own geolocated transactions inside a lat/lng bounding box + time/category filter, via the `place_geom` GiST index; explicit `where user_id = auth.uid()` since security definer bypasses RLS; `limit 2000`. Returns per-row `line_items` (jsonb) + `receipt_storage_path` (latest `receipt_artifacts.storage_path`) so the Receipt Map Sheet can render items/photo without a second round-trip — columns added in `20260811180000` (DROP + recreate; `CREATE OR REPLACE` cannot widen OUT params) | `20260713000000`, detail columns in `20260811180000` | `map_transactions_repository.dart` (spend map own-place pins, fetched on `onCameraIdle` only) |
| `lookup_merchant_alias(alias_text, geohash)` | `security definer`, execute revoked from `public`, granted to `authenticated` | Best cached merchant→place match for an alias key + geohash bucket, ranked/returned by confidence decayed with a 90-day half-life on `last_matched_at` | `20260708000000`, decay in `20260724010000` | `enrich-transaction` edge function (alias fast-path, before any Places call) |
| `upsert_merchant_alias(alias_text, geohash, place_id, name, lat, lng, confidence)` | `security definer`, execute revoked from `public`, granted to `authenticated` | Insert-or-bump-confidence/hit-count on conflict | `20260708000000` | `enrich-transaction` edge function (only when a fresh resolution's confidence clears `ALIAS_SAVE_CONFIDENCE_THRESHOLD`, best-effort) |
| `upsert_merchant_alias_from_correction(alias_text, geohash, place_id, name, lat, lng, correction_type, transaction_id, ocr_confidence?)` | `security definer`, execute revoked from `public`, granted to `authenticated` | Second alias write-back trigger keyed on an explicit user correction; idempotent via `user_field_corrections.alias_writeback_applied_at` + row lock; confidence weighted by correction type + OCR confidence (promotion after 3 disagreeing free-text hits uses a hit_count/OCR formula, not a flat constant) | `20260723040000`, redefined `20260724010000` | `enrich-transaction` edge function |
| `upsert_category_preference(merchant_normalized, category)` | `security invoker` (RLS applies) | Atomic upsert-with-corroboration-count for the caller's own `user_category_preferences` row | `20260723020000` | `sync_worker_flutter.dart` (on syncing a `category` field correction) |
| `lookup_category_preference(merchant_normalized)` | `security invoker` (RLS applies) | Caller's learned category + corroboration count + decayed weighted `confidence`, only when `correction_count >= 2` | `20260723020000`, gate+weight in `20260724010000` | `category_preference_repository.dart` (consulted before parsing, keyed on the LLM's merchant read) |
| `upsert_misread_pattern(from_char, to_char)` | `security definer`, execute revoked from `public`, granted to `authenticated` | Insert-or-bump-hit-count for a single abstracted character-substitution pattern | `20260723030000` | `sync_worker_flutter.dart` (on syncing an `amount`/`line_item_price` field correction, after client-side abstraction) |
| `lookup_misread_patterns()` | `security definer`, execute revoked from `public`, granted to `authenticated` | All abstracted misread patterns, ranked by hit count | `20260723030000` | Not yet consumed (see table doc above) |

## Relationships (ER summary)

```
auth.users 1─1 profiles
profiles 1─N transactions (user_id, cascade)
transactions 1─N receipt_artifacts (transaction_id, cascade)
transactions 1─N receipt_line_items (transaction_id, cascade)
transactions 1─0..1 feed_posts (transaction_id, cascade, nullable)
profiles 1─N user_badges (user_id, cascade)
profiles 1─N friendships as requester_id (cascade)
profiles 1─N friendships as addressee_id (cascade)
profiles 1─N feed_posts (user_id, cascade)
feed_posts 1─N feed_reactions (post_id, cascade)
profiles 1─N feed_reactions (user_id, cascade)
profiles 1─N pending_receipts (user_id, cascade)
pending_receipts 0..1─0..1 transactions (transaction_id, set null on delete)
profiles 1─N friend_groups (owner_id, cascade)
friend_groups 1─N friend_group_members (group_id, cascade)
profiles 1─N friend_group_members as friend_user_id (cascade)
transactions 1─0..1 bill_splits (transaction_id, cascade, unique)
bill_splits 1─N bill_split_participants (split_id, cascade)
bill_splits 1─N bill_split_item_assignments (split_id, cascade)
receipt_line_items 1─N bill_split_item_assignments (line_item_id, cascade)
```

`merchant_aliases` has no FK to any other table — it's a standalone global cache keyed by `(alias_text_normalized, geohash_bucket)`, not by user or transaction. `ocr_misread_patterns` likewise has no FK — it's a standalone global, anonymized aggregate keyed by `(from_char, to_char)`. `user_field_corrections` FKs to both `profiles` and `transactions` (cascade both ways); `user_category_preferences` FKs only to `profiles`, keyed by `(user_id, merchant_normalized)`.

## Two leaderboard systems — how they relate

Not competing — layered. **Friend leaderboard** = Postgres-native, RLS-backed `get_friend_leaderboard()` RPC (small friend groups, always fresh). **Global leaderboard** = Redis ZSET (`leaderboard:global`, `services/leaderboard-api`) ranking *all* users, periodically rehydrated from Postgres via the two narrow, superuser-only definer functions. Both read the same denormalized source of truth: `profiles.current_streak` / `profiles.badge_count`. See `docs/api.md` for the sync flow and `docs/decisions.md` for why the split exists.

## Merchant alias cache — how it fits into enrichment

`enrich-transaction` (see `docs/api.md`) checks `lookup_merchant_alias()` **before** calling Google Places at all: if a hit is found for the top-ranked merchant candidate's normalized text + geohash bucket, it writes `place_*`/`pipeline_status='enriched'` directly from the cached row and returns — no Places API call, no cost. A fresh Places resolution that clears a confidence threshold gets written back via `upsert_merchant_alias()` so the *next* scan of the same merchant near the same location skips Places too. Global (see table doc above) — this is the one place in the schema where cross-user data sharing happens by design outside the friends/social system.

## Feedback-learning system — how the three surfaces derive from one capture point

See `docs/plans/2026-07-23-feedback-learning-system.md` for the full design. `ReceiptConfirmSheet` captures a `user_field_corrections` row for every field the user actually changed (merchant/amount/category/line-item price), synced alongside its transaction — nothing downstream captures corrections independently:

- **Merchant identity** — `enrich-transaction` reads any pending `merchant` correction for the transaction it's enriching and calls `upsert_merchant_alias_from_correction()` (passing `transaction_id` + the correction's OCR `confidence`) using the place it already resolved — a second write-back trigger into `merchant_aliases` alongside the existing algorithmic `>=0.85`-confidence path. Idempotent: a second enrich of the same correction is a no-op. Alias *reads* return confidence decayed by a 90-day half-life on `last_matched_at`.
- **Category preference** — `sync_worker_flutter.dart` calls `upsert_category_preference()` for any pending `category` correction as it syncs. `parseReceiptFile()` calls `lookup_category_preference()` ahead of parsing (keyed on the LLM's own merchant read, when available); the RPC only returns rows with `correction_count >= 2` and includes a decayed weighted `confidence`. `parseReceiptOcrText()` uses that as a low-priority tie-breaker (only fills in when the request's own category signal is itself below `categoryPreferenceOverrideConfidenceCeiling`).
- **OCR misread patterns** — `lib/domain/logic/misread_pattern_extractor.dart` runs client-side, before upload, against any pending `amount`/`line_item_price` correction, discarding the actual values and keeping only aligned character-substitution pairs; `sync_worker_flutter.dart` calls `upsert_misread_pattern()` for each one found. Aggregation only for v1 — not yet consumed (`services/ocr-api` has no Postgres connectivity today).

## Local-only tables (Drift/SQLite, on-device — see `lib/data/local/tables.dart`)

Not part of Postgres; the outbox mirrors the cloud schema plus sync bookkeeping. Schema is versioned (`schemaVersion = 11` in `app_database.dart`) with incremental `onUpgrade` migrations.

| Table | Mirrors | Extra fields |
|---|---|---|
| `OutboxTransactions` | `transactions` | `syncStatus` (`pending\|syncing\|synced\|stuck`), `lastError`, `retryCount`, `impactUser` (v2), `rawOcrText`/`ocrServiceConfidence`/`lineItemsConfidence`/`parseFailureReason` (v5, mirrors the Postgres v3 columns), `merchantCandidatesJson`/`ocrHeaderText` (v6, mirrors `transactions.merchant_candidates`/`ocr_header_text`), `llmUnderstandingJson` (v7, mirrors `transactions.llm_understanding` — populated at capture time by the synchronous OCR+LLM call, see `docs/decisions.md`), `cleanedOcrText`/`ocrCorrectionsJson` (v10, LLM OCR-cleanup diffs — unrelated to `OutboxFieldCorrections` below despite the similar name) |
| `OutboxArtifacts` | `receipt_artifacts` | `localFilePath` |
| `OutboxLineItems` (v4) | `receipt_line_items` | — |
| `CategoryConfigCache` | remote categories JSON | etag/version — **scaffolded but not actively fetched at runtime**; categories are loaded only from the bundled asset (`assets/config/categories-v1.json`). Don't assume remote refresh works. |
| `PendingImports` (v8) | `pending_receipts` (async best-effort) | local-only inbox. Rows are the **immediate source of truth** — the Supabase mirror is best-effort. Status: `local\|processing\|failed`. On successful save the Drift row **and** the copied local file are deleted; there is no `completed` status. `localFilePath` points to `<documents>/pending_receipts/<id>.<ext>`. Exposed via `PendingImportsRepository` (`lib/data/repositories/pending_imports_repository.dart`); public API uses pure Dart `PendingImportModel` (not the Drift-generated class) so web compiles without Drift. |
| `OutboxFieldCorrections` (v11) | `user_field_corrections` | local queue for the feedback-learning capture hook (see above) — `syncStatus` (`pending\|synced`) gates both the Postgres upsert and the one-time category-preference/misread-pattern RPC calls that must fire exactly once per correction |

`beforeOpen` sets `PRAGMA foreign_keys = ON` — SQLite disables FK enforcement by default; required for cascade deletes.

## Known gap

`supabase/functions/.env.example` documents `OCR_SERVICE_URL`/`OCR_SERVICE_SECRET` but **not** `GOOGLE_PLACES_API_KEY`, which both `enrich-transaction` and `places-proxy` require at runtime (read from `Deno.env`). Set it manually in the Supabase project's function secrets / local `.env`.
