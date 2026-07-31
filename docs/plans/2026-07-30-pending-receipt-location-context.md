# Feature: Pending-Receipt Location Context

## Overview

Adds a best-effort, human-readable location hint ("📍 Sunway Pyramid") to receipts sitting in the pending-imports inbox — captured at the moment a receipt is shared into Receipt Drop, before OCR has run. It exists purely as a memory aid: today's `PendingImportsScreen` card shows only a thumbnail, timestamp, and optional source-app chip, which is often not enough for a user to recall *where* an unprocessed receipt came from once a few pile up.

## Problem Statement

`PendingImportsScreen`'s `_PendingImportCard` (`lib/features/pending_imports/pending_imports_screen.dart`) currently renders only a thumbnail, `sourceApp` chip (as of the 2026-07-30 post-share-notification work, now actually populated for Maybank/Touch 'n Go — see `docs/plans/2026-07-30-post-share-receipt-notification.md`), a formatted timestamp, and a failed/retry state. A receipt shared hours ago with an unidentified source and a generic thumbnail gives the user nothing to go on when deciding which pending card is which. Location capture already exists elsewhere in the app (`getCurrentPositionOrNull()`, `lib/core/utils/current_location.dart`) but only fires when the user taps **Process** — i.e. at OCR time, not at share time — and only feeds `ReceiptIngestDraft.shareLocationLat/Lng` for the confirm sheet's map preview, never the pending-imports list itself.

## Goals

- Capture device location once, immediately when a receipt is shared in (not deferred to Process time).
- Resolve that raw coordinate into a short, human-readable venue/area name using the existing Places integration, not raw lat/lng.
- Display it on the pending-imports card as a lightweight memory aid.
- Never block, delay, or fail receipt ingestion because of location capture or resolution.

## Non-Goals

- Extending the post-share OS notification (`docs/plans/2026-07-30-post-share-receipt-notification.md`) to include location in its body — not requested here, and the notification is posted synchronously at share time before any GPS fix could realistically resolve; a follow-on, not part of this feature.
- Replacing or deduplicating the *existing* OCR-time `shareLocationLat/Lng` capture in `receipt_ingest_service.dart`'s `_buildDraft()` (used for the confirm sheet's map preview and, eventually, `transactions.share_location_lat/lng`). See Tradeoffs for why consolidating the two capture points is flagged as a recommended follow-up rather than done here.
- A full reverse-geocoding integration (street address, postcode) — only a single nearby-venue *name* is shown, consistent with "avoid overly precise details."
- Any new backend service, third-party geocoding API, or edge function. Reuses `places-proxy`'s existing `nearby_candidates` mode as-is.
- Location history, trails, or any persisted record beyond the single coordinate needed to resolve today's venue label (see Security Considerations on why this still isn't "tracking").
- Requesting location permission for the first time from this flow (see Decision Logic) — first-time permission priming stays wherever it happens today (e.g. the map screen), not stapled onto a share event.

## Proposed Solution

When `ShareIntentListener` saves a shared file to `pending_imports` (already instant, offline-safe, unchanged), it additionally kicks off a fire-and-forget location capture: a **passive** GPS check (never prompting for permission — see Decision Logic) followed by a call to the existing `places-proxy` `nearby_candidates` mode with no merchant/category bias, so it ranks purely by proximity to well-known place types. The top result's name is written back to the `pending_imports` row once resolved. Both steps happen after `saveSharedReceipt()` already returned, so ingestion, the notification, and the toast are all unaffected by however long location resolution takes (or whether it fails). `PendingImportsScreen`'s existing `StreamBuilder` over `pending_imports` picks up the location text automatically once written, the same way it already picks up `sourceApp`.

## User Experience

**Golden path**: user shares a receipt; the pending card appears immediately (as today) with no location line. A few seconds later — once GPS resolves and the nearby-place lookup returns — the same card updates in place to show "📍 Sunway Pyramid" above the timestamp, with no user action and no visible loading state for this specific piece (the card's existing thumbnail/timestamp were already visible; location just appears when ready).

**Location unavailable** (permission not yet granted, denied, services off, no fix within timeout, or the nearby-place call fails/returns nothing usable): the card renders exactly as it does today — no location line, no placeholder, no error indicator. This is the same visual state as before this feature existed, which is the explicit fallback the request asks for.

**Multiple pending receipts**: each row resolves its own location independently and asynchronously; a user with 5 pending receipts might see 3 with a venue name and 2 without, with no indication that resolution is "in progress" for the ones still pending — deliberately quiet, since this is a nice-to-have hint, not a status the user is meant to wait on.

**Processing a receipt before location resolves**: unaffected — Process/Retry behavior, the OCR pipeline, and the confirm sheet are untouched by this feature (see Non-Goals).

## System Impact

- **Client application**: `ShareIntentListener` (triggers the new capture, fire-and-forget), a new small location-resolution helper reusing `getCurrentPositionOrNull` and `PlacesRepository.fetchNearbyCandidates`, `PendingImportsRepository` (new write path for the resolved label), `PendingImportsScreen`'s `_PendingImportCard` (new UI line).
- **Database/storage**: one new nullable column on the local `pending_imports` Drift table (the resolved venue label — see Technical Design on why only the label, not raw coordinates, needs to persist) and its Postgres `pending_receipts` mirror, following the same migration pattern used for `sourceApp`/`note`.
- **AI/ML pipeline**: none — this is independent of OCR/LLM understanding.
- **Infrastructure**: negligible additional load on the existing `places-proxy` Edge Function (already used by the confirm sheet and place picker) — one extra call per share, capped by the same radius/type-search Google Places call it already makes for other callers.
- **External integrations**: Google Places API, via the existing `places-proxy` proxy — no new integration, no new credential.

## Technical Design

**Capture point moves earlier, but stays additive.** Today, `getCurrentPositionOrNull()` is only called from `receipt_ingest_service.dart`'s `_buildDraft()`, i.e. at Process time. This feature adds a *second*, earlier call site — right after `PendingImportService.saveSharedReceipt()` persists the row in `ShareIntentListener._handleSharedFiles` — that captures a position at share time and resolves it to a place name for the pending card. The existing OCR-time capture is left as-is (see Non-Goals); the two are independent for this pass.

**Resolution is a two-step, both-async pipeline, run without blocking anything already awaited:**
1. A passive position check (see Decision Logic for why this must not be the existing `getCurrentPositionOrNull`'s active-request variant unmodified).
2. `PlacesRepository.fetchNearbyCandidates(lat:, lng:, limit: 1)` called with no `merchantName`/`category`/`candidates` — inspecting `supabase/functions/places-proxy/index.ts`'s `handleNearbyMode` confirms this is already a fully supported call shape: without "usable text," it weights almost entirely on distance (`distWeight: 0.85`) against `DEFAULT_NEARBY_TYPES`, which is exactly "what notable place am I closest to" rather than "what matches this merchant" — the right semantic for a pre-OCR hint, and requires zero Edge Function changes.

**Only the resolved label is persisted on the local model** the UI reads (a new `pending_imports.venue_label` column, or similarly named) — not raw latitude/longitude on that row. The Edge Function still receives the coordinate to perform its lookup (over HTTPS, authenticated, same as every other `places-proxy` call), but nothing new is at rest on the device or in Postgres beyond the short place name string once the round trip completes. This is a deliberate minimization consistent with "not a tracking feature."

**Once resolved, write straight to the existing reactive layer.** `PendingImportsRepository` already exposes `watchAll()` as a `Stream<List<PendingImportModel>>` that `PendingImportsScreen` consumes directly — a new `setVenueLabel(id, label)` method (mirroring the note-writing method added in the post-share-notification feature) is all that's needed for the card to update itself; no new state management.

## Decision Logic

- When `ShareIntentListener` finishes saving a shared file (single or each file in a batch) to `pending_imports`, start location resolution for that row **without awaiting it** before returning from `_handleSharedFiles` — ingestion, the notification, and the toast must not wait on any part of this.
- Location resolution reads the device's current permission state passively (`Geolocator.checkPermission()`/`isLocationServiceEnabled()`) and proceeds to fetch a position **only if permission is already `whileInUse`/`always` and location services are on**. If permission is `denied` (not yet decided) or `deniedForever`, skip immediately — do not call `Geolocator.requestPermission()` from this path. Rationale: triggering a first-time OS permission dialog in the middle of a share-sheet handoff (the user is likely still mid-transition out of Maybank/Touch 'n Go) is exactly the kind of surprise-and-intrusive moment the request explicitly warns against; permission priming belongs to an existing, deliberate in-app moment (e.g. the spend map), not this background path.
- If a position is obtained, call `fetchNearbyCandidates` with only `lat`/`lng` (no merchant/category bias) and `limit: 1`.
- If a candidate is returned, write its `name` (not address, not raw coordinates) to the pending import's venue-label column.
- If the candidate list is empty, the call errors, times out, or `fetchNearbyCandidates` returns `[]` for any of the reasons it already swallows internally (no Supabase config, non-200, malformed response): leave the venue label unset — this is identical, from the UI's perspective, to location never having been attempted.
- If the pending import is deleted (receipt already confirmed) before location resolution completes: the write becomes a no-op on a missing row, mirroring the existing `setNote`/`updateStatus` no-op-on-missing-row pattern from the post-share-notification feature.
- `_PendingImportCard` renders the "📍 `<label>`" line only when a non-null/non-empty label is present on the model; otherwise the card layout is byte-for-byte what it is today (no reserved space, no placeholder).
- The timestamp line's format ("Today, 2:34 PM" in the mockup) is a separate, optional cosmetic change from today's `DateFormat('d MMM, h:mm a')` — treat as a nice-to-have alignment with the mockup, not a hard requirement; do not block the location feature on redesigning the timestamp format.

## Edge Cases

- **Permission already granted, but the device's location radio is off** (`isLocationServiceEnabled() == false`): skip silently, same as denied — already handled by the existing `getCurrentPositionOrNull` short-circuit.
- **User shares a receipt indoors deep inside a large mall with a slow/poor GPS fix**: the existing 8-second `timeLimit` on `getCurrentPositionOrNull` already bounds this; if it doesn't resolve in time, the location line simply never appears for that card — no retry loop is introduced.
- **Batch share of multiple files**: each resulting `pending_imports` row gets its own independent location resolution — they'll all likely resolve to the same venue since they're shared in the same moment/place, which is expected and fine; no dedup logic is needed since each row's write is independent and idempotent per-row.
- **Nearby-search returns a low-confidence match** (e.g. a large search radius returns something far away because nothing closer matched `DEFAULT_NEARBY_TYPES`): `fetchNearbyCandidates`'s existing `SEARCH_RADIUS_METERS = 300` constant already bounds the candidate pool to the same tight radius used for merchant enrichment elsewhere — no new confidence threshold is invented here, but if this radius proves too permissive in testing (e.g. shows a venue that's technically within 300m but not where the user actually was), tightening it is a one-line change in `_shared/place_matching.ts`, shared with every other caller — a tradeoff worth watching, not solving preemptively.
- **The user revokes location permission after some pending receipts already have a resolved label**: already-resolved labels are not retroactively cleared — they remain a fine historical hint; only *future* resolutions stop.
- **The receipt is processed (Process tapped) before location resolves**: no conflict — the pending-imports row (and its venue label) is deleted on successful save regardless of whether a label was ever written; the confirm sheet's own location (from the existing, separate OCR-time capture) is unaffected.
- **Race between the note-write path (post-share-notification feature) and the venue-label write path**: both are independent columns on the same `pending_imports` row, written by unrelated async tasks — no shared mutable state, safe to run concurrently exactly like `note` and `status` already are.

## Performance Considerations

- **Latency**: irrelevant to the perceived "instant save" — everything described here happens after the row already exists and the UI has already rendered the (label-less) card; the label just appears whenever it appears, with no user-visible waiting state to optimize.
- **Network/cost**: one additional `places-proxy` call (→ one Google Places Nearby Search, possibly zero Text Search calls since no query text is provided) per shared file. This uses the same Google Places budget as every other caller of this Edge Function; no separate quota or cost concern beyond "one more call per share," which is a materially smaller volume increase than the deferred auto-OCR-trigger idea flagged in the sibling notification spec.
- **Battery/CPU**: one GPS fix per share (already bounded to an 8-second `LocationAccuracy.medium` request by the existing helper) — no continuous location tracking, no background location mode, no geofencing.

## Security Considerations

- **Not a tracking feature, by construction**: only a short venue-name string is persisted (locally and in the `pending_receipts` Postgres mirror) — raw coordinates are used transiently to make the one Places API call and are not written to any table by this feature. This directly satisfies "should be used as a helpful reminder, not as a tracking feature."
- **No new permission escalation**: reuses the location permission already declared and justified in `AndroidManifest.xml` (`ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`) and `Info.plist` (`NSLocationWhenInUseUsageDescription`, already worded generically enough — "uses your location to suggest nearby places for receipts" — to cover this use without an App Store metadata change).
- **Passive-only permission check** (see Decision Logic) also has a security/trust framing, not just a UX one: never surprising the user with a location prompt they didn't expect from a background share action reduces the chance of a user reflexively denying permission out of suspicion, which would then also block the legitimate, deliberate location uses elsewhere in the app (map, place picker).
- **Auth**: the `places-proxy` call already requires the user's Supabase JWT (enforced server-side, per the Edge Function's existing `supabase.auth.getUser()` check) — no change to that boundary.

## Tradeoffs

- **Two independent location-capture points (share-time for the pending card vs. OCR-time for the confirm sheet) instead of one consolidated capture.** Threading the pending-import's share-time coordinate through to `ReceiptIngestDraft` (avoiding a second GPS fix at Process time, and guaranteeing the pending card and the eventual confirm sheet/transaction agree on where the receipt was captured) is the more architecturally clean answer, but requires changing `ReceiptIngestService.ingestPath`'s signature and its one caller (`PendingImportService.processImport`) to pass the pending import's stored coordinate through — a real but modest change. Deferred here to keep this feature additive and independently shippable/revertible; flagged as a recommended immediate follow-up rather than silently left as permanent duplication.
- **Reusing `places-proxy`'s `nearby_candidates` mode with no text bias vs. building a dedicated "reverse geocode to venue name" mode.** The existing mode already does exactly this when called without `query`/`candidates` (confirmed by reading `handleNearbyMode`'s weighting logic) — a new mode/endpoint would duplicate the scoring, radius, and place-type logic that already lives in `_shared/place_matching.ts` for no behavioral gain.
- **Passive permission check vs. reusing `getCurrentPositionOrNull` unmodified (which actively requests permission).** Reusing it as-is is simpler (zero new code) but risks popping a permission dialog during a share-sheet handoff — a materially worse UX outcome than the explicit "not intrusive" goal in the request. The passive variant needs a small new helper (or a parameter added to the existing one) rather than a second copy of the whole function.
- **Showing only a venue name vs. venue name + distance/address.** A name-only line ("📍 Sunway Pyramid") is closer to how a human would recall the moment ("I was at the mall") than an address string would be, and directly satisfies "avoid overly precise location details that may feel intrusive."

## Implementation Guidance

Suggested order of work:
1. **Schema**: add the nullable venue-label column to the local `pending_imports` Drift table (same migration pattern as the `note`/`sourceApp` columns added in the sibling post-share-notification feature — see `lib/data/local/tables.dart`, `app_database.dart`'s migration branch) and its Postgres `pending_receipts` mirror.
2. **Passive location helper**: add a variant alongside `lib/core/utils/current_location.dart`'s `getCurrentPositionOrNull()` that checks-but-never-requests permission, for use specifically from the share path (the existing function's active-request behavior stays correct and unchanged for its current callers — map recenter, OCR-time capture).
3. **Resolution + write-back**: a small new coordinator (parallel to how the post-share-notification feature added `ReceiptNotificationService`) that, given a `pendingImportId`, does passive-position → `fetchNearbyCandidates(limit: 1)` → `PendingImportsRepository.setVenueLabel(...)`, swallowing every failure silently.
4. **Wire into `ShareIntentListener`**: call the new coordinator, unawaited, once per saved file — right alongside where the sibling feature's notification-posting and referrer-resolution calls already sit in `_handleSharedFiles`.
5. **UI**: add the "📍 `<label>`" line to `_PendingImportCard` in `pending_imports_screen.dart`, conditionally rendered exactly like the existing `sourceApp` chip block.

Areas to inspect closely: `lib/features/share/share_intent_listener.dart` (now doing quite a lot per share — referrer resolution, notification posting, and, with this feature, location resolution; keep each concern in its own small helper rather than growing `_handleSharedFiles` into a monolith), `lib/core/utils/current_location.dart` (confirm the passive-check variant doesn't regress the two existing active-request callers), `lib/data/repositories/places_repository.dart` + `supabase/functions/places-proxy/index.ts` (confirm the no-bias nearby call's real-world result quality — this was verified by reading the scoring logic, not by an actual device test, and is worth a quick manual check against a real Malaysian mall/venue before shipping).

Real risk: nothing here is architecturally novel (it composes three things that already exist — passive geolocation, the existing nearby-places mode, and the reactive Drift-stream-to-UI pattern already used for `sourceApp`/`note`), so the main risk is scope creep in `ShareIntentListener` becoming a dumping ground for every post-share side effect — worth a brief look at whether these three concerns (referrer/source ID, notification, location) should be extracted behind a single small "post-share side effects" coordinator called from one line, rather than three ad hoc unawaited calls accumulating in the same method.

## Testing Strategy

- **Unit**: passive-permission-check helper returns `null` without ever calling `requestPermission()` when permission is undecided/denied (mockable via whatever seam `Geolocator` already offers/is stubbed with elsewhere in this codebase's tests, if any exist for `current_location.dart`); the resolution coordinator writes nothing on any of the "no usable result" paths (no fix, empty candidates, network failure).
- **Integration**: `PendingImportsRepository.setVenueLabel` no-ops safely on a since-deleted row, mirroring the existing test pattern (if any) for `setNote`.
- **Widget**: `_PendingImportCard` renders the location line when the model has a label and omits it entirely (no placeholder space) when null — a straightforward snapshot-style widget test alongside whatever tests already cover `pending_imports_screen.dart`.
- **Manual/device**: share a receipt from a real location with a well-known nearby mall/venue and confirm the resolved label matches user expectation within the existing 300m radius; verify no permission dialog appears when location permission has never been granted (the passive-check contract is the one behavior a unit test can't fully prove without a real OS permission state).
- **User acceptance criteria**: sharing a receipt at a recognizable venue shows that venue's name on the pending card within a few seconds without any additional user action; sharing with location permission denied shows the exact same card as before this feature shipped, with no error state, no permission prompt, and no delay to the receipt appearing.

## Rollout Plan

Fully additive and low-risk relative to the sibling notification feature: no existing behavior is removed or altered (the pending card's current fields are unchanged; the new line only appears when a label resolves). Can ship directly without a flag, but if there's any appetite for caution given it's unverified against a real device/location (see Implementation Guidance), it's trivially gateable behind a single boolean at the coordinator's call site in `ShareIntentListener` — disabling it reverts to today's card with zero data loss (the schema columns stay harmless and unused). No migration ordering concerns beyond the standard additive-column pattern already established for `note`/`sourceApp`.
