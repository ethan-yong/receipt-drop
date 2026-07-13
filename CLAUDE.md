# Receipt Drop

## What this is

A Malaysian receipt-first spend tracker. Users share a receipt image/PDF via the OS share sheet; the app OCRs it, extracts amount/merchant/category/line-items, saves it instantly to a local offline outbox, and syncs to the cloud in the background. Layered on top: gamification (avatar, badges, streaks), a spend map with friend pins, a friends feed, and friends+global leaderboards.

Full v1 product spec (still mostly accurate for the core capture flow, but the app has since grown well past its scope — see `docs/decisions.md` for what changed): `docs/superpowers/specs/2026-05-11-receipt-drop-design.md`.

## Technology stack

- **Client**: Flutter/Dart (Android, iOS, Web, Desktop from one codebase). `go_router` navigation, Drift/SQLite local outbox, `supabase_flutter` client.
- **Backend**: Supabase (Postgres + Row-Level Security + Auth (PKCE) + Storage) plus 3 Deno Edge Functions (BFF layer for Google Places + OCR proxy).
- **OCR**: self-hosted `services/ocr-api` — Python/FastAPI + Tesseract (`pytesseract`). Not on-device, not PaddleOCR — both were tried and replaced (`docs/decisions.md`).
- **Leaderboard**: `services/leaderboard-api` — Python/FastAPI + Redis ZSET, for the global (all-users) leaderboard tier; friends tier is a plain Postgres RPC.
- **Maps**: `google_maps_flutter` (real Google Maps SDK). Briefly on `flutter_map` + free CARTO Voyager tiles due to a GCP billing blocker, reverted once billing was enabled — see `docs/decisions.md` ("Back to `google_maps_flutter`", 2026-07-09). Custom pins (spend places, friends) are Flutter widgets overlaid on the map, not native `Marker`s — see `docs/decisions.md`'s 2026-07-13 entry for the viewport-query/clustering design built on top of that.
- **`Impact Drops/`**: a separate, frozen React/TanStack Start prototype (Lovable-generated) used only as a one-time design/behavior reference for the gamification features. **Not built, imported, or deployed with the product.** See `docs/architecture.md`.

## Important directories

| Path | What's there |
|---|---|
| `lib/` | The Flutter app. `core/` (bootstrap, routing, theme, config), `data/` (Drift local DB + repositories), `domain/` (pure logic + models), `features/` (screens, one dir per feature), `widgets/` (shared UI) |
| `supabase/migrations/` | Postgres schema, chronological — read in filename order, later files alter earlier ones |
| `supabase/functions/` | Deno Edge Functions: `enrich-transaction`, `ocr-proxy`, `places-proxy`, `_shared/place_matching.ts` |
| `services/ocr-api/` | Self-hosted OCR microservice (FastAPI + Tesseract) |
| `services/leaderboard-api/` | Global leaderboard microservice (FastAPI + Redis) |
| `test/` | Dart unit/widget tests — concentrated on the OCR/parse/ingest pipeline |
| `bin/process_receipts.dart`, `scripts/process_receipts.ps1` | Dev batch tool: run OCR+parse against a folder of receipt images, no Supabase needed |
| `Impact Drops/` | Frozen design prototype — historical reference only, ignore for runtime/dependency purposes |
| `docs/superpowers/` | Original planning docs (spec + plan) predating this AI-agent documentation system |

## Architecture summary

Local-first, cloud-enriched: every capture writes to on-device SQLite immediately (works offline, no blocking UI), then a background sync worker uploads to Supabase and triggers server-side enrichment (Google Places lookup for the merchant). A recurring `foo.dart`/`foo_io.dart`/`foo_web.dart` conditional-export pattern handles native-vs-web differences (Drift needs `dart:ffi`, unavailable on web) — see `docs/architecture.md` for the full explanation, don't rediscover it per-file.

Two DB-adjacent services sit beside Supabase, not behind it: the OCR API (called via an Edge Function proxy in production) and the leaderboard API (calls Postgres directly, impersonating the user's JWT so RLS still applies, plus Redis for the global rank cache).

Full diagram, data-flow trace, and design patterns: **`docs/architecture.md`**.

## Which files to read for which task

| Task | Read first |
|---|---|
| Understand the whole system | This file → `docs/architecture.md` → `.claude/context.md` |
| Change the receipt capture/OCR/parse pipeline | `docs/architecture.md` (data flow section) → `memory/feature_graph.md` (Receipt capture feature) → the actual files under `lib/features/share/` and `lib/domain/logic/` |
| Change the DB schema | `docs/database.md` (cumulative schema + RLS) → the latest 2-3 files in `supabase/migrations/` for the current pattern to follow |
| Add/change an API endpoint or Edge Function | `docs/api.md` |
| Understand why something is built the way it is | `docs/decisions.md` |
| Pick up mid-task / check what's in flight | `.claude/context.md` |
| Run/build/test/deploy anything | `.claude/commands.md` |
| Check if a feature has known issues before touching it | `memory/bugs.md` |
| See what depends on a file before changing it | `memory/feature_graph.md` |
| Understand a past technical pivot (OCR engine, maps SDK, leaderboard split) | `memory/experiments.md` and `docs/decisions.md` |
| Anything involving `Impact Drops/` | `docs/architecture.md` "mental model" section first — it's a reference, not live code |
| "What should we improve next?" / check the backlog | `pending-tasks.md` — deliberately-deferred work with a reason and a proposed design; don't re-propose something already recorded there |

## Documentation map (this AI-agent memory system)

```
CLAUDE.md                    ← you are here
docs/
  architecture.md             high-level design, data flow, design patterns
  api.md                      Edge Functions + both Python services: endpoints, auth, integrations
  database.md                 full Postgres schema (cumulative), RLS, storage, RPCs, Drift local schema
  decisions.md                ADR-style log: what changed, why, tradeoffs
.claude/
  context.md                  current in-flight state, incomplete features, things to double-check
  commands.md                 run/build/test/deploy/debug commands
memory/
  feature_graph.md            feature → dependency → file mapping
  bugs.md                     known bugs, workarounds, unresolved issues
  experiments.md               approaches tried and abandoned, and why
```

Keep this system current: when you make an architecturally significant change (new table, new service, a reversed decision), update the relevant `docs/` file and add an entry to `docs/decisions.md` or `memory/experiments.md` rather than letting this fall out of sync with the code.
