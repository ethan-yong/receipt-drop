# Current project state

For durable architecture/schema/API facts, see `docs/`. This file is for state that changes often: what's in flight, what's incomplete, what to double-check before editing.

## What the project does

Receipt Drop: Malaysian users share receipt images/PDFs via the OS share sheet; the app OCRs them (self-hosted Tesseract), extracts amount/merchant/category/line-items, saves instantly to a local outbox, and syncs to Supabase in the background. Layered on top: gamification (avatar, badges, streaks), a spend map with friend pins, a friends feed, and a friends+global leaderboard. See `docs/architecture.md` for the full data-flow diagram.

## Current development focus (branch: `feat/ethanyong/20260702134010/receipt-finetuning`)

Recent commits (newest first) show active work tightening the receipt-parsing/review pipeline and the map:
- Handheld/thermal receipt parsing improvements + showing line items on the receipt card (`f2b366b`).
- OCR API startup hardening — refuses to start if the port is already in use (`90e26b0`).
- Routing OCR exclusively through the API (dropped remaining on-device paths) + parser improvements (`527a5bb`).
- Mobile OAuth callback + sign-in polish (`8b65379`).
- Map rebuilt on `flutter_map`/CARTO after Google Maps SDK never had a billing key (`ac17253`, `428ea10`).

**Uncommitted working-tree changes at last check**:
- `lib/data/repositories/demo_transactions.dart` — demo seed data's `sync` field changed from `pending`/`stuck` to `synced` (cosmetic demo-data tweak, not a behavior change).
- `supabase/functions/enrich-transaction/index.ts` — reworked to run `searchText` + `searchNearby` concurrently and score/merge candidates via `_shared/place_matching.ts` (dice coefficient + distance decay), replacing the old "take the first text-search result" logic.
- `supabase/functions/_shared/place_matching.ts` — new file, untracked, backing the above.

If you're picking this up cold: check `git status`/`git diff` again before assuming this description is still current.

## Incomplete / partially-wired features

- **`CategoryConfigCache` Drift table** exists and the v1 spec describes a remote-refresh mechanism for `categories-v1.json`, but no code path actually fetches/writes it — categories are loaded only from the bundled asset. Don't assume remote category refresh works; it's scaffolding.
- **Two badges are honest stubs**: `budget_buddy` and `smart_spender` (`lib/domain/logic/badge_progress.dart`) always return 0 progress — budgets and price-comparison features don't exist yet.
- **`impact_level.dart` thresholds** (RM15/RM60 cutoffs for low/med/high) are explicitly placeholder, not derived from real usage data.
- **Diorama category themes** are coarser than the "Impact Drops" prototype implies — most receipts currently land on idle/grocery/transport/fast_food themes until the bundled category config gains more granular rules (`lib/domain/logic/diorama_theme.dart`).
- CSV export (mentioned in Settings) is still v1.1-scoped, not built.

## Important recent changes an agent should know before modifying code

- **`TransactionView` now exposes `shareLocationLat/Lng`** (optional, null on old rows). `_mapRow()` in `transaction_repository_native.dart` populates them; the web stub does not. The tx-detail screen uses them to decide whether to open `PlacePickerScreen` or fall back to text search.
- **`TransactionRepository.updateTransactionPlace(String id, PlaceResult)` is the correct write path for user-corrected place.** It sets `placeStatus='user_locked'`, `syncStatus='pending'`, and triggers `SyncWorker.run()`. The existing `updateTransaction(TransactionView)` intentionally does NOT set placeStatus or trigger sync — don't add place-status logic there.
- **`PlacePickerScreen.push(context, ...)` uses `Navigator.of(context, rootNavigator: true)`.** This is intentional — it must work from inside a modal bottom sheet (AdaptiveSheet). Do NOT change it to `context.pushNamed(...)` or the route will fail when called from the save sheet.
- **`places-proxy` now has a `nearby_candidates` mode** (see `docs/api.md`). The text-search mode is unchanged; the new mode is a separate code path that branches on `bodyJson["mode"] === "nearby_candidates"`.



- **OCR is no longer on-device.** If you see references to ML Kit in old docs/specs or stale `build/` artifacts, ignore them — the current pipeline is 100% the self-hosted `services/ocr-api` (Tesseract), called via the `ocr-proxy` Edge Function in production.
- **Two confidence fields on `transactions` are easy to conflate**: `ocr_confidence` (amount-extraction confidence) vs. `ocr_service_confidence` (OCR scan-quality confidence). A real bug shipped from conflating these (see `docs/decisions.md` review-queue entry) — don't re-apply a sigmoid to `ocr_service_confidence`, it arrives already calibrated.
- **`profiles` RLS was deliberately widened** (`profiles_select_accepted_friend`) to let the external leaderboard-api service and Flutter's RPC fallback both read friend profiles under plain RLS. If you're reasoning about "can user A read user B's row," check this policy, not just the "own row only" default you'd expect from the social-features migration's stated philosophy.
- **`Env.skipAuth` defaults to `true` in debug builds.** If auth/onboarding seems to "not be gating anything" while developing, this is why — not a bug.
- **`Impact Drops/` is a frozen, one-commit design prototype.** Never edit it expecting it to affect the shipped app; never assume its current code matches what Flutter actually implements (it has already diverged). See `docs/architecture.md` and `docs/decisions.md`.
- **Port convention mismatch**: local dev OCR API defaults to port 8081 (`scripts/run_ocr_api.ps1`, `.env.example`), but the Dockerfile/`bin/process_receipts.dart --help` default to 8080. Don't assume one when debugging "wrong port" issues — check which one the specific script/service you're touching actually defaults to.
- **CARTO map tiles are a free/no-key placeholder**, explicitly flagged in `spend_map_screen.dart` as not safe to ship at production scale.

## Before modifying code, also check

- `docs/decisions.md` for *why* something is the way it is — several apparent oddities (RLS widening, security-invoker vs definer, dual confidence fields) are deliberate, documented tradeoffs, not bugs.
- `memory/bugs.md` for known issues and workarounds.
- `memory/feature_graph.md` for what depends on what before changing a shared file (e.g. `place_matching.ts`, `transaction_view.dart`, the Drift schema).
