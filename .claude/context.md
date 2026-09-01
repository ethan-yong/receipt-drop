# Current project state

For durable architecture/schema/API facts, see `docs/`. This file is for state that changes often: what's in flight, what's incomplete, what to double-check before editing.

## What the project does

Receipt Drop: Malaysian users share receipt images/PDFs via the OS share sheet; the app OCRs them (self-hosted Tesseract), extracts amount/merchant/category/line-items, saves instantly to a local outbox, and syncs to Supabase in the background. Layered on top: gamification (avatar, badges, streaks), a spend map with friend pins, a friends feed, and a friends+global leaderboard. See `docs/architecture.md` for the full data-flow diagram.

## Current development focus (branch: `feat/ethanyong/20260721102508/ui-fixes`)

The share intent flow (OS share sheet → Receipt Drop) has been reworked from **immediate OCR** to an **inbox / pending-import pattern**:

- Sharing a receipt from any app saves it locally first (no OCR, no blocking spinner). The user sees a "Receipt saved — open Receipt Drop to review" toast (pluralized for a multi-file share) and returns to their previous app.
- A home-screen banner ("N receipts waiting") links to a new `PendingImportsScreen` where the user explicitly taps **Process** (or **Retry** on failure) to trigger OCR.
- Drift is the immediate source of truth; Supabase `pending_receipts` syncs asynchronously, best-effort.

**2026-07-21 follow-up** (see `docs/decisions.md` for the full writeup): the OCR-time UI for both the pending-import flow and the in-app Camera/Gallery/file capture flow is now the **same** animated `ReceiptScanProcessingScreen` (`lib/features/share/receipt_scan_processing_screen.dart`) — the plain spinner overlay (`PlatformFeedback.showOcrProgress`) that `PendingImportService.processImport` used to show is gone. Key things to know before touching this area:
- The screen's constructor takes `attemptFactory` (an `OcrAttemptFactory`, re-invoked on Retry) instead of a fixed `stream` — if you add a new call site, build a small local closure that creates a fresh `OcrProgressNotifier` per attempt (see `_startBytesAttempt`/`_startPathAttempt` in `receipt_capture_flow.dart` or the equivalent in `pending_import_service_io.dart`), don't pass a stream directly.
- `processImport` now takes/returns an optional `BatchScanProgress` (`lib/features/share/batch_scan_progress.dart`) so `PendingImportsScreen._processAll`'s sequential "Process all" loop can show a running batch-progress footer. It's an immutable snapshot threaded call-to-call, not a shared mutable notifier.
- `ShareIntentListener._handleSharedFiles` was also fixed to save **every** file from a multi-file OS share, not just the first (`files.firstWhere(...)` was silently dropping the rest before this fix) — a real batch can now actually reach the inbox.

**Key new files (2026-07-12):**
- `supabase/migrations/20260712000000_pending_receipts.sql` — new Supabase table
- `lib/data/local/tables.dart` — `PendingImports` Drift table (schema v8)
- `lib/data/local/app_database.dart` — bumped `schemaVersion` 7→8, added v8 migration branch
- `lib/domain/models/pending_import_model.dart` — pure Dart model (web-safe, no Drift dependency)
- `lib/data/repositories/pending_imports_repository.dart` — Drift + Supabase repo
- `lib/features/pending_imports/pending_import_service.dart` + `_io.dart` + `_web.dart`
- `lib/features/pending_imports/pending_imports_screen.dart`
- `lib/core/bootstrap/app_services_io.dart` + `app_services_web.dart` — extended with `pendingImports`
- `lib/features/share/share_intent_listener.dart` — now calls `PendingImportService.saveSharedReceipt()` instead of launching OCR directly
- `lib/features/home/home_screen.dart` — `_PendingImportsBanner` + stream
- `lib/core/routing/app_router.dart` — `/pending-imports` route

If you're picking this up cold: check `git status`/`git diff` again before assuming this description is still current.

## Payment detection (notification → overlay → transaction), reworked 2026-08-29

Three separately-reproduced bugs were fixed here; see `docs/system/decisions.md` for the evidence. Things to know before touching this area:

- **The floating card is queued, not replaced.** `PaymentOverlayService` holds an `ArrayDeque<Intent>` and shows one card at a time. Don't reintroduce a `removeCurrentView("replaced")` on a new `onStartCommand` — that was the flicker *and* silently dropped every payment but the last in a burst.
- **Anything the user was never asked about goes to the durable queue uncategorized** (`QueuedPaymentEvent.category == null`), and Flutter ingests it with `needsReview: true` so it lands on the existing needs-review banner. That covers a stale notification, queue overflow, a destroyed service, and a missing overlay permission. A *timeout* or "Not now" still discards deliberately — don't "fix" those into saves.
- **`PaymentEventDrainService.drainAndIngest()` must run on resume, not just in `main()`.** The listener keeps the process alive, so returning to the app reuses the existing Flutter engine and `main()` does not re-run. `PaymentEventDrainListener` (wired in `app.dart`) is what makes a category picked on the overlay actually reach the home screen.
- **The dedup cache is written only after the LLM returns a verdict.** Remembering the fingerprint before the network call meant one blip hid that payment for 24h with no retry. There's an in-memory `inFlight` set covering the gap, plus 3 attempts with backoff.
- **Doze is the reason detection ever felt random.** The app now asks for `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, but the user can decline, so the stale-diversion path above has to keep working without it.
- Not verified on a real device this pass — the change set was built and unit-tested, but the phone's installed APK is signed with a key that isn't on the dev machine, so it couldn't be updated in place.

## Incomplete / partially-wired features

- **Pending-receipt location context (2026-07-30)**: `ShareIntentListener` also resolves a best-effort nearby-venue name per shared file (passive-only GPS check + `places-proxy`'s `nearby_candidates` mode with no bias) and writes it to the new `pending_imports.venueLabel` column, shown as a "📍" line on `PendingImportsScreen`'s card. See `docs/plans/2026-07-30-pending-receipt-location-context.md`. Independent of, and not yet consolidated with, the *existing* OCR-time `shareLocationLat/Lng` capture in `receipt_ingest_service.dart` (used for the confirm sheet's map preview) — the two capture points currently coexist; consolidating them is a flagged, not-yet-done follow-up. Not verified against a real device/location this pass.
- **Post-share receipt notification (2026-07-30)**: `ShareIntentListener` now posts an interactive local notification ("🧾 Receipt saved" + inline note action) instead of just a toast — see `docs/plans/2026-07-30-post-share-receipt-notification.md` and the matching `docs/system/decisions.md` entry. Shipped: notification shell, inline note capture (`pending_imports.note` → `transactions.notes`), Android referrer-based source ID (`com.maybank2u.life` → "Maybank", `my.com.tngdigital.ewallet` → "Touch 'n Go"). **Deliberately not shipped**: OCR still only runs when the user taps Process — the notification's "processing" copy is aspirational until a follow-up (behind a flag) actually auto-triggers background OCR; don't assume `pending_imports` rows have a cached parsed draft. Untested on a real device this pass: the Android background-isolate note-write path (`receipt_notification_service_io.dart`'s `@pragma('vm:entry-point')` callback) and iOS's reliability for the inline-reply action when the app is fully terminated — both are called out as open risks in the plan doc, not confirmed working.
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
- **The LLM receipt-understanding call lives in `services/ocr-api` (`POST /understand`), not in `enrich-transaction`.** `enrich-transaction` calls that endpoint (shared-secret auth, `OCR_SERVICE_URL`/`OCR_SERVICE_SECRET`) and re-validates the response; it does not read `VLLM_*` env at all — those belong to `ocr-api`. If you're debugging "the LLM call isn't working," check `ocr-api`'s logs/env first, not the edge function's. See `docs/decisions.md` (2026-07-10 entry) for why it moved there.
- **The edit-location pencil on `ShareSaveSheet`/`ReceiptConfirmSheet` no longer hides when there's no share-time GPS fix.** It now always shows and falls back to `PlacesSearchScreen` (pushed via the root navigator, same pattern as `PlacePickerScreen.push`) — mirrors `transaction_detail_screen.dart`'s `_pickPlace()`. If you see it disappear again, that's a regression, not expected behavior.



- **OCR is no longer on-device.** If you see references to ML Kit in old docs/specs or stale `build/` artifacts, ignore them — the current pipeline is 100% the self-hosted `services/ocr-api` (Tesseract), called via the `ocr-proxy` Edge Function in production.
- **Two confidence fields on `transactions` are easy to conflate**: `ocr_confidence` (amount-extraction confidence) vs. `ocr_service_confidence` (OCR scan-quality confidence). A real bug shipped from conflating these (see `docs/decisions.md` review-queue entry) — don't re-apply a sigmoid to `ocr_service_confidence`, it arrives already calibrated.
- **`profiles` RLS was deliberately widened** (`profiles_select_accepted_friend`) to let the external leaderboard-api service and Flutter's RPC fallback both read friend profiles under plain RLS. If you're reasoning about "can user A read user B's row," check this policy, not just the "own row only" default you'd expect from the social-features migration's stated philosophy.
- **`Env.skipAuth` defaults to `true` in debug builds.** If auth/onboarding seems to "not be gating anything" while developing, this is why — not a bug.
- **`Impact Drops/` is a frozen, one-commit design prototype.** Never edit it expecting it to affect the shipped app; never assume its current code matches what Flutter actually implements (it has already diverged). See `docs/architecture.md` and `docs/decisions.md`.
- **Port convention mismatch**: local dev OCR API defaults to port 8081 (`scripts/run_ocr_api.ps1`, `.env.example`), but the Dockerfile/`bin/process_receipts.dart --help` default to 8080. Don't assume one when debugging "wrong port" issues — check which one the specific script/service you're touching actually defaults to.
- **CARTO map tiles are a free/no-key placeholder**, explicitly flagged in `spend_map_screen.dart` as not safe to ship at production scale.

- **Feedback-learning system landed (2026-07-23)**: `ReceiptConfirmSheet` now captures a `FieldCorrection` for every merchant/amount/category/line-item edit into `OutboxFieldCorrections` → `user_field_corrections`, feeding three surfaces (merchant-alias write-back from `enrich-transaction`, per-user category preference, global anonymized OCR-misread patterns). See `docs/system/decisions.md` and `docs/database/schema.md`. `services/ocr-api` still has no Postgres connectivity — the misread-pattern table is aggregation-only for now, not yet consumed.

## Before modifying code, also check

- `docs/decisions.md` for *why* something is the way it is — several apparent oddities (RLS widening, security-invoker vs definer, dual confidence fields) are deliberate, documented tradeoffs, not bugs.
- `memory/bugs.md` for known issues and workarounds.
- `memory/feature_graph.md` for what depends on what before changing a shared file (e.g. `place_matching.ts`, `transaction_view.dart`, the Drift schema).
