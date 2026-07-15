# Architecture

## Mental model

Receipt Drop is a **local-first, cloud-enriched** Flutter app. A shared receipt is saved to on-device SQLite (Drift) instantly — the user sees it immediately, offline or not — then a background sync worker uploads it to Supabase and triggers server-side enrichment (place lookup). The device is the source of truth for "did the user's action succeed"; the cloud is the source of truth for cross-device/social state (friends, leaderboard, feed).

A second, equally important mental model: **most of the gamification UI (avatar, badges, diorama scenes, feed, reactions) was designed first as a throwaway React prototype** (`Impact Drops/`, built with Lovable, frozen after one commit) and then manually re-implemented in Dart against real data. `Impact Drops/` is never built, imported, or deployed as part of the product — treat it as a historical design reference only, not a target to edit. Many Dart files literally say "port of Impact Drops' X" in their doc comments; when in doubt about *intended* visual/behavioral design for these features, check there before guessing, but never assume its exact behavior still matches the shipped Flutter code (it has already diverged — see `docs/decisions.md`).

## High-level components

```
┌─────────────────────────┐
│ Flutter app (lib/)       │  Android / iOS / Web / Desktop, one codebase
│  - go_router shell       │
│  - Drift/SQLite outbox   │◄──── local-first capture, works offline
│  - Supabase client       │
└──────────┬───────────────┘
           │ HTTPS (Supabase client SDK + Edge Function calls)
           ▼
┌─────────────────────────┐      ┌──────────────────────────┐
│ Supabase                │      │ services/ocr-api          │
│  - Postgres + RLS       │◄─────┤  self-hosted Tesseract OCR│
│  - Auth (PKCE)          │ OCR  │  (POST /ocr) +            │
│  - Storage (receipts,   │proxy,│  LLM receipt-understanding├──► LLM gateway
│    config buckets)      │direct│  (POST /understand)       │    (self-hosted,
│  - Edge Functions (Deno):│     │  FastAPI, shared secret   │    OpenAI-compat)
│    enrich-transaction,   │     └──────────────────────────┘
│    ocr-proxy,            │     ┌──────────────────────────┐
│    places-proxy          │     │ services/leaderboard-api  │
└──────────┬───────────────┘◄────┤  FastAPI + Redis ZSET     │
           │ server-side only RPC│  global rank cache/service │
           ▼ (key never in client)└──────────────────────────┘
    Google Places API v1

┌──────────────────────────┐
│ Impact Drops/ (React/     │  standalone design prototype only —
│ TanStack Start, Lovable)  │  NOT built/deployed with the product
└──────────────────────────┘
```

Both edges into `ocr-api` are used: `ocr-proxy` forwards the client's OCR calls (hides the OCR shared secret) to `POST /ocr`, which now runs the LLM receipt-understanding step **synchronously, in the same request**, right after Tesseract — the client's OCR response already contains the interpreted receipt, not just raw text. `enrich-transaction` no longer calls the LLM as its primary path; it reuses the understanding the client already synced (`transactions.llm_understanding`) and only calls `POST /understand` itself as a fallback for rows that reached it without one (legacy app version, or a failed client-side call). `ocr-api` is the only thing that talks to the LLM gateway (`VLLM_*` env) — see `docs/decisions.md`.

## Data flow: receipt capture → dashboard

1. **Trigger**: OS share sheet (`ShareIntentListener`, `lib/features/share/share_intent_listener.dart`) or in-app FAB (`ReceiptCaptureFlow.start`, launched from `MainShell`).
2. **Persist bytes locally**: `receipt_file_store_io.dart` (native) writes to app documents dir; web keeps bytes in memory (no OCR on web — user must enter amount manually).
3. **OCR + LLM understanding (synchronous, one call)**: `ocr_pipeline_io.dart` calls the self-hosted OCR service — directly in dev (`Env.ocrApiUrl` + shared secret) or via the `ocr-proxy` Edge Function in production (so the shared secret never ships client-side). That service's `POST /ocr` runs Tesseract *and then* the LLM receipt-understanding step in the same request/response (see `docs/decisions.md`), so the client gets back raw text/lines/confidence **and** an interpreted `understanding` (cleaned merchant name, address/location clues, vendor category, Google Places types, line items, per-field confidences) in one round trip — a failed LLM call still returns the raw OCR fields, just with `understanding: null`. PDFs are text-extracted via `pdfrx` instead (no OCR, no LLM step). Web never OCRs.
4. **Parse**: `receipt_parse_pipeline.dart` runs the heuristic pass first — line-item extraction → amount parsing (cross-checked against the line-items subtotal) → merchant extraction → category guess — then lets the LLM `understanding` (if any) override what it's confident about: its merchant name is prepended as the top-ranked `MerchantCandidate` (`source: 'llm'`), its `vendor_category` maps to a display category, and its `line_items` fully replace the heuristic line items whenever present. The heuristic pass is always the fallback (LLM found nothing, or the call failed) and still feeds the amount-parsing cross-check regardless. Merchant extraction (`extractMerchantCandidates()`) itself still produces a **ranked list** of candidates (`{text, confidence, source}`) — `merchant_raw` is always the top entry; the full ranked list, top-of-receipt OCR context (`ocr_header_text`), and the LLM `understanding` all sync alongside it. Produces a `combinedConfidence` (blends amount-extraction confidence with OCR scan-quality confidence) and a `lowConfidence`/`needs_review` signal.
5. **Confirm**: user sees `ReceiptConfirmSheet` (exclude line items with a live-recalculating total, rename the vendor inline — hands an edited draft onward; see `docs/design/design_handoff_receipt_flows/`) then `ShareSaveSheet` (edit amount/category, Save / Save-for-later / Cancel). Low-confidence or failed parses route into a **review queue** (`pipeline_status='needs_review'`) instead of being silently dropped or blocking the happy path.
6. **Local commit**: `TransactionRepository.ingestReceipt()` writes the outbox transaction + artifact + line items in one shot, fires a best-effort social feed post, and returns immediately — the UI never waits on the network.
7. **Background sync**: `SyncWorker` (fire-and-forget, retried up to 5x before marking `stuck`) uploads the artifact to the `receipts` Storage bucket, upserts `transactions`/`receipt_artifacts`/`receipt_line_items` (now including `llm_understanding`, synced from the local `llmUnderstandingJson` column populated at capture time), then invokes `enrich-transaction` (skipped while `needs_review`). Afterward it re-fetches the enriched columns (`place_*`, `merchant_normalized`, `pipeline_status`) and writes them back into the local outbox row — without this the UI would keep showing raw OCR text forever even after successful server-side enrichment (a real bug, since fixed; see `memory/bugs.md`).
8. **Enrichment**: the Edge Function now mainly does Google Places matching, not LLM understanding — the LLM step already ran client-side, synchronously with OCR (step 3). It prefers the synced `transactions.llm_understanding` (re-validated as defense-in-depth) and only calls `services/ocr-api`'s `POST /understand` itself as a fallback when that field is missing or invalid (legacy app version, or a failed client-side call — no fallback beyond that: a failed LLM call still fails the whole enrichment, see `docs/decisions.md`). Either way, once it has a structured understanding it checks a **global merchant-alias cache** (`merchant_aliases`, keyed by the LLM's normalized merchant name + a coarse geohash bucket) — a hit resolves the place instantly with no Google call. On a miss, it resolves a Google Place candidate (multi-query text search from the LLM's queries + nearby search using the LLM's place types, Dice-coefficient + distance + type-match scoring) and marks `pipeline_status='enriched'` (or `'failed_enrichment'` — this never blocks the transaction from counting toward totals; only a null `amount_myr` does). A high-confidence fresh resolution is written back into the alias cache so the next scan of the same merchant near the same place skips Places entirely.
9. **Read side**: dashboard/map/home screens read a **unified stream** of outbox rows (`TransactionView`) — the UI doesn't care whether a row has synced yet, only whether it `isPendingSync`/`isStuckSync`.

## Frontend/backend relationship

The Flutter app never talks to Postgres directly except through the Supabase client SDK (table CRUD under RLS) and three narrow Edge Functions (BFF pattern — Google Places key and OCR shared secret both live server-side only). The two Python services are peers to Supabase, not behind it: `ocr-api` is called by an Edge Function (`ocr-proxy` for client OCR — which now returns LLM understanding in the same response, or directly in dev) **and**, as a fallback only, by `enrich-transaction` itself (`POST /understand` — enrich-transaction is already server-side, so no proxy hop is needed there); `leaderboard-api` is called directly by Flutter and itself talks to Postgres (impersonating the user's JWT so RLS still applies) and Redis.

## Platform-split pattern (used pervasively — read this once)

Native capabilities unavailable on web (`dart:ffi`-based SQLite via Drift, `dart:io` file access, direct HTTP OCR calls) force a recurring trio: a neutral interface file re-exporting a platform-specific implementation via conditional import:

```dart
export 'foo_io.dart' if (dart.library.html) 'foo_web.dart';
```

Some files gate on `dart.library.ui` instead (true on *any* Flutter target, false only in pure-Dart CLI contexts like `bin/process_receipts.dart`) when the split is "Flutter vs. headless Dart" rather than "native vs. web": `app_database_connection_{stub,flutter}.dart`, `sync_worker.dart`/`_flutter.dart`/`_stub.dart`.

Every call site imports only the neutral `foo.dart` — never branch on platform at the call site. Instances: `app_services`/`_io`/`_web`, `transaction_repository`/`_native`/`_web`, `sync_worker`/`_flutter`/`_stub`, `app_database_connection`/`_stub`/`_flutter`, `ocr_pipeline`/`_io`/`_web`, `receipt_file_store`/`_io`/`_web`, `receipt_ingest_service`/`_io`/`_web`, `receipt_thumbnail_file`/`_file_web`.

Repositories that only talk to Supabase over HTTP (`avatar_repository.dart`, `badge_repository.dart`, `places_repository.dart`, `social_repository.dart`) deliberately have **no** platform split — several of their doc comments call this out explicitly as a contrast.

## Navigation / app shell

`go_router` (`lib/core/routing/app_router.dart`) with a `StatefulShellRoute.indexedStack` of 4 tab branches (**Home, Feed, Map, Ranks** — rendered in `lib/widgets/main_shell.dart`, which also owns the centered capture FAB and a platform-adaptive bottom bar, Cupertino-blurred on iOS vs. Material notch on Android) plus ~14 root-navigator modal/detail routes (dashboard, settings, avatar, badges, ritual, summary, share-hint, onboarding, auth, friends, tx detail, places search, review). Redirect logic gates on `AppPrefs.onboardingComplete` + Supabase session, unless `Env.skipAuth` (defaults **true** in debug builds) bypasses straight to `/home` — a dev convenience, not a security control.

## External services

- **Google Places API v1** — server-side only (Edge Functions), never in the client.
- **Tesseract OCR** — self-hosted (`services/ocr-api`), not a third-party API.
- **LLM gateway** — self-hosted, OpenAI-compatible (LiteLLM/vLLM), called only from `services/ocr-api` (synchronously from within `POST /ocr` as the primary path; `POST /understand` remains as `enrich-transaction`'s fallback and a manual reprocessing entry point) — never from an Edge Function or the client directly. See `docs/decisions.md`.
- **CARTO Voyager raster tiles** (via `flutter_map`) — free, no key, for the spend map. Explicitly flagged in code (`spend_map_screen.dart`) to swap for a keyed provider before production scale.
- **Redis** — self-hosted/dockerized, for the global leaderboard only.

## Production hosting

`services/ocr-api`, `services/leaderboard-api`, and Redis run on a single-node MicroK8s cluster (Ubuntu 22.04 VM, containerd runtime — no Docker on the server) deployed from a Windows dev machine via `deploy/scripts/deploy.ps1` (`.\deploy.ps1 <version>`): build locally with Docker, `docker save` to a tarball, ship it over SSH, `microk8s ctr image import` into containerd, `kubectl apply` the manifests in `deploy/k8s/`, then verify the rollout. No image registry is involved — Deployments use `imagePullPolicy: Never` and rely on the image already being present in containerd from the import step. See `deploy/k8s/` for manifests and `docs/decisions.md` for why this shape was chosen over alternatives (Kustomize/Helm, a registry, nginx-ingress).

This is the only part of the system deployed this way. The 3 Supabase Edge Functions (`enrich-transaction`, `ocr-proxy`, `places-proxy`) remain deployed via `supabase functions deploy <name>`, on Supabase's own infrastructure — not part of the k8s system. Postgres/Auth/Storage remain fully Supabase-managed, never containerized here (no StatefulSet, no DB PVC). There is no separate "backend API" or "worker" service to deploy: the two Python services above are the entire self-hosted server-side surface; the Flutter app's background sync worker is an on-device task, not a server process.

## Design patterns worth knowing

- **Denormalize onto `profiles` for RLS-friendly fan-out**: `current_mood`/`current_streak`/`badge_count`/`avatar_config` are pushed by the owning user so friends' feed/leaderboard/map queries never need cross-user access to `transactions`.
- **Security-definer RPCs for cross-user reads**, with one deliberate exception (`profiles_select_accepted_friend` RLS policy) added to support the external leaderboard-api service impersonating users — see `docs/decisions.md`.
- **Never silently zero/drop a receipt**: unknown amounts get `amount_myr = null` + `needs_amount = true`, not `0`. Failed/low-confidence parses go to a review queue, not the trash.
- **Confidence scores tune the parser, not the user's mood** — the original v1 principle ("no anxiety UI") persisted even as a review queue was added later; the queue is opt-in-by-quality-threshold, not a warning badge on every row.
