# Feature dependency graph

Relationships between features/subsystems, not just file lists. Use this before changing a shared file to see who else depends on it.

---

## Feature: Receipt capture & OCR ingest (the core loop)

Depends on:
- Share sheet OS integration (`receive_sharing_intent` plugin) OR in-app capture menu
- Local file persistence (native vs. web split)
- OCR API (`services/ocr-api`) — directly in dev, via `ocr-proxy` Edge Function in production
- Parse pipeline: amount parser + merchant extractor (ranked candidates) + category matcher + line-item extractor
- Drift local outbox (transactions + artifacts + line items tables)
- Sync worker → Supabase Storage + `transactions`/`receipt_artifacts`/`receipt_line_items` tables, plus a local write-back of enrichment results
- `enrich-transaction` Edge Function → global `merchant_aliases` cache fast-path, else Google Places API (multi-candidate text search + nearby search)

Files:
- `lib/features/share/share_intent_listener.dart`, `receipt_capture_flow.dart`, `receipt_capture_menu.dart`
- `lib/features/share/receipt_file_store.dart` (+`_io`/`_web`), `receipt_ingest_service.dart` (+`_io`/`_web`)
- `lib/features/share/ocr_pipeline.dart` (+`_io`/`_web`), `ocr_api_client.dart`, `receipt_parse_file.dart`, `receipt_parse_pipeline.dart`
- `lib/domain/models/ocr_line.dart` (`OcrLine` — per-line text + `heightRatio`, threaded from `services/ocr-api`'s `run_ocr_detailed()` through `OcrApiResult`/`OcrFileResult` into the parse pipeline, used only by the `'largeText'` candidate tier)
- `lib/domain/logic/rm_amount_parser.dart`, `merchant_extractor.dart` (`MerchantCandidate`, `extractMerchantCandidates`, `extractOcrHeaderText` — candidate tiers: `header` > `keyword` > `largeText` > `position` > `fallback`), `category_matcher.dart` (+`_bundled`/`_io`), `receipt_line_item_extractor.dart`
- `lib/features/share/receipt_ingest_draft.dart`, `receipt_summary_card.dart`, `receipt_summary_view_model.dart`, `share_save_sheet.dart`
- `lib/data/repositories/transaction_repository.dart` (+`_native`/`_web`), `ingest_receipt_request.dart`
- `lib/data/repositories/sync_worker.dart` (+`_flutter`/`_stub` — `_flutter.dart` also exposes `buildEnrichmentCompanion()`, the local write-back mapper)
- `lib/data/local/tables.dart`, `app_database.dart`
- `supabase/functions/enrich-transaction/index.ts`, `supabase/functions/ocr-proxy/index.ts`, `supabase/functions/_shared/place_matching.ts` (`geohashEncode`, `buildTextSearchQueries`, `scoreCandidate`)
- `supabase/migrations/20260708000000_merchant_aliases.sql` (`merchant_aliases` table + `lookup_merchant_alias()`/`upsert_merchant_alias()` RPCs)
- `services/ocr-api/app/*.py`
- Downstream consumer: `lib/domain/models/transaction_view.dart` (every other feature reads through this)

**Fan-out**: nearly everything else (dashboard, map, feed, badges, ritual) consumes `TransactionView` rows produced here. Changing `TransactionView`'s shape or `ingestReceipt`'s side effects (feed post creation, sync trigger) has wide blast radius.

---

## Feature: Receipt review queue

Depends on:
- Receipt capture & OCR ingest (produces the `combinedConfidence`/`needs_review` signal)
- `transactions.pipeline_status = 'needs_review'` + `raw_ocr_text`/`ocr_service_confidence`/`line_items_confidence`/`parse_failure_reason` columns
- Sync worker (must skip enrichment while `needs_review`)

Files:
- `lib/features/review/receipt_review_screen.dart`
- `lib/data/repositories/transaction_repository.dart` (`confirmReview()`)
- `supabase/migrations/20260705000000_receipt_review_and_raw_ocr.sql`
- `lib/data/repositories/sync_worker_flutter.dart` (the `needs_review` skip check)

---

## Feature: Dashboard & aggregations

Depends on:
- Receipt capture & OCR ingest (reads `TransactionView` stream)
- `dashboard_aggregates.dart` pure functions (month summary, category breakdown, weekly trend, top places, map clusters/heat cells)

Files:
- `lib/features/dashboard/dashboard_screen.dart`
- `lib/domain/logic/dashboard_aggregates.dart`
- `lib/widgets/category_donut_chart.dart`, `weekly_line_chart.dart`, `top_places_list.dart`, `month_picker_header.dart`

No writes — purely a read/aggregation layer. Safe to extend without touching capture/sync.

---

## Feature: Vendor location picker (post-OCR place correction)

Depends on:
- Receipt capture & OCR ingest (provides `shareLocationLat/Lng` and `merchantCandidates` on `ReceiptIngestDraft` / `TransactionView`)
- `places-proxy` Edge Function — extended with `mode: 'nearby_candidates'` (concurrent searchText + searchNearby, same `scoreCandidate()` scoring as enrichment)
- `flutter_map` + CARTO tiles (reuses same tile URL / `CancellableNetworkTileProvider` as spend map)
- `TransactionRepository.updateTransactionPlace()` — new method that sets `placeStatus='user_locked'` and re-queues sync (distinct from the general `updateTransaction()`)

Files:
- `lib/features/places/place_picker_screen.dart` (new) — full-screen picker, `PlacePickerScreen.push()` static helper
- `lib/data/repositories/places_repository.dart` — `PlaceCandidate`, `PlacesRepository.fetchNearbyCandidates()`
- `lib/features/share/share_save_sheet.dart` — pencil icon next to merchant name, pre-save picker wiring
- `lib/features/tx_detail/transaction_detail_screen.dart` — `_pickPlace()` uses picker when `shareLocationLat/Lng` available
- `lib/data/repositories/transaction_repository_native.dart` — `updateTransactionPlace()` + `ingestReceipt()` place write
- `lib/domain/models/transaction_view.dart` — `shareLocationLat/Lng` fields exposed for tx-detail
- `lib/core/routing/app_router.dart` — `/place-picker` go_router route (fallback for deep-link; primary entry via `PlacePickerScreen.push()`)
- `supabase/functions/places-proxy/index.ts` — `nearby_candidates` mode added

**Fan-out**: `ReceiptIngestDraft`, `IngestReceiptRequest`, and `TransactionView` all gained optional fields — all existing callers use defaults (null/false) and are unaffected. `PlacePickerScreen.push()` uses `rootNavigator` so it works from both a normal screen and from inside a `showModalBottomSheet`.

---

## Feature: Spend map (own + friends)

Depends on:
- Dashboard aggregations (`mapClusters`, `heatCells`, `mapCategories`)
- `flutter_map` + CARTO tiles (own spend bubbles/heat)
- Social repository → `get_friend_map_pins()` RPC (friend pins, place+time only, never amount)
- `profiles.share_map_location` opt-out

Files:
- `lib/features/map/spend_map_screen.dart`, `lib/features/map/widgets/*.dart`
- `lib/widgets/map_filter_chips.dart`
- `lib/domain/logic/dashboard_aggregates.dart` (shared with Dashboard)
- `lib/data/repositories/social_repository.dart`
- `supabase/migrations/20260706000000_friend_map_pins.sql`

---

## Feature: Avatar / mood

Depends on:
- Receipt capture (today's `TransactionView`s drive mood derivation)
- Impact Drops prototype (design/behavior source — historical reference only, see `docs/architecture.md`)
- `avatar_config` denormalized column on `profiles`

Files:
- `lib/domain/logic/avatar_mood.dart`, `impact_level.dart`
- `lib/domain/models/avatar_config.dart`
- `lib/widgets/blob_avatar.dart`, `pixel_avatar.dart`
- `lib/features/avatar/avatar_customizer_screen.dart`, `lib/features/summary/summary_screen.dart` (mood display)
- `lib/data/repositories/avatar_repository.dart` (persistence + `syncCurrentMood`)
- `lib/domain/logic/diorama_theme.dart`, `diorama_props.dart`, `lib/widgets/diorama_scene.dart`, `themed_scene_background.dart` (category-themed scene backdrop, also an Impact Drops port)

---

## Feature: Badges

Depends on:
- Receipt capture (badge progress computed from transaction history)
- Bundled badge catalog (`assets/config/badges-v1.json`, not a DB table)
- `user_badges` table (persisted progress, for cross-device continuity and the leaderboard's `badge_count`)

Files:
- `lib/domain/logic/badge_catalog.dart`, `badge_progress.dart`
- `lib/data/repositories/badge_repository.dart`
- `lib/widgets/badge_hex.dart`, `badge_detail_dialog.dart`, `top_badges_grid.dart`
- `lib/features/badges/badges_screen.dart`
- `supabase/migrations/20260626000001_badges.sql`
- `avatar_repository.dart` (`syncBadgeCount` → denormalizes onto `profiles.badge_count`, feeding the leaderboard)

---

## Feature: Friends & social feed

Depends on:
- `friendships` table (add/accept/decline/block)
- `feed_posts`/`feed_reactions` tables (system-generated flavor text only, never raw amount)
- Receipt capture (each save best-effort posts a feed line via `feed_line_generator.dart`)

Files:
- `lib/features/friends/friends_screen.dart`, `lib/features/feed/feed_screen.dart`
- `lib/domain/logic/feed_line_generator.dart`
- `lib/widgets/reaction_chip.dart`
- `lib/data/repositories/social_repository.dart`
- `supabase/migrations/20260626000002_social.sql`

---

## Feature: Leaderboard (friends + global)

Depends on:
- `profiles.current_streak`/`badge_count` (denormalized by avatar_repository/badge_repository)
- Postgres RPC `get_friend_leaderboard()` (friends tier, always live)
- `services/leaderboard-api` + Redis ZSET (global tier — required; no Postgres fallback)
- `lib/domain/logic/leaderboard_label.dart` (mood+streak → descriptive label, Impact Drops port)

Files:
- `lib/features/leaderboard/leaderboard_screen.dart`
- `lib/data/repositories/social_repository.dart` (leaderboard fetch, chooses API vs RPC based on `Env.hasLeaderboardApiConfig`)
- `lib/domain/logic/leaderboard_label.dart`
- `supabase/migrations/20260626000003_leaderboard.sql`, `20260630000000_leaderboard_api.sql`, `20260630100000_global_leaderboard.sql`
- `services/leaderboard-api/app/*.py`
- `docker-compose.yml`

---

## Feature: Ritual (drop animation)

Depends on:
- Receipt capture & OCR ingest (batches unritualled transactions — `OutboxTransactions.ritualledAt`)
- Impact Drops prototype (`ritual.tsx` was the design source)

Files:
- `lib/features/ritual/ritual_screen.dart`
- `lib/data/local/tables.dart` (`ritualledAt` column)

---

## Feature: Batch/CLI receipt processing (dev tooling, not shipped to users)

Depends on:
- Same parse pipeline as the app (`receipt_parse_pipeline.dart`, domain logic)
- OCR API called directly (never through `ocr-proxy`)
- `receipt_batch_e2e.dart` for optional in-memory outbox round-trip verification

Files:
- `bin/process_receipts.dart`, `scripts/process_receipts.ps1`
- `lib/features/share/receipt_batch_e2e.dart`
- `lib/domain/logic/category_matcher_io.dart` (file-based config loading, vs. the app's bundled-asset loader)

---

## Non-feature, but everything depends on it: platform-split data layer

`lib/core/bootstrap/app_services.dart`, `lib/data/local/app_database.dart`, `lib/data/repositories/transaction_repository.dart`, `lib/data/repositories/sync_worker.dart` — see `docs/architecture.md` "Platform-split pattern." Any change to the Drift schema (`lib/data/local/tables.dart`) needs a `schemaVersion` bump + `onUpgrade` migration, and a corresponding Postgres migration if the field also needs to sync to the cloud.

---

## Isolated, not a dependency of anything: `Impact Drops/`

Referenced *by* several features above as a design/behavior source (see each feature's notes), but nothing in `lib/` imports, builds, or deploys it. Safe to ignore when tracing runtime dependencies; relevant only when researching *why* a UI/behavior choice was made.
