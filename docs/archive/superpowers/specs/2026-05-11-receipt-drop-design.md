# Receipt Drop — v1 Design Spec

- **Date:** 2026-05-11
- **Status:** Approved for planning (pending user spec review)
- **Repo:** `receipt-drop` (display name: **Receipt Drop**)
- **Scope:** Version 1 (MVP) only. Friends, shared goals, and location-frequency feeds are **explicitly out of scope** for v1 except as a single teaser surface.

---

## 1. Problem and audience

Malaysians pay via QR across multiple, fragmented rails: Maybank QR, Touch 'n Go eWallet, CIMB Pay, DuitNow QR, etc. Each app has its own dashboard, most are weak, and many QR codes are bank-specific — so spend done outside a given app is invisible inside that app's dashboard. The result is that users have **no single, honest view of where their money goes**, and they don't trust or look at any of the existing dashboards.

Receipt Drop's wedge: **the receipt is the universal artifact**. Every QR payment produces a digital receipt the user already has. If we make it trivial to feed receipts into one app via the OS share sheet, we get a unified spend ledger across rails without any bank integration.

## 2. Product principles

1. **Capture must feel free.** Sharing a receipt should be one tap, save immediately, no blocking screens.
2. **Honest defaults, easy corrections.** Auto-extract amount, auto-suggest place and category, but always let the user fix any of it later. Never silently zero an amount.
3. **No anxiety UI.** We do not surface low-confidence amount warnings to the user. Internal confidence scores tune our parser, not the user's mood.
4. **Cloud is the source of truth, but never the gatekeeper.** Capture works offline; sync happens in the background.
5. **Forward-compatible, not over-built.** v1 ships solo + map. Schema and one teaser screen are friend-ready, but no social code paths exist yet.

## 3. v1 feature scope

**In scope (v1):**

- OS Share → Receipt Drop intake of **images and PDFs** (best-effort: anything we can decode as those).
- On-device OCR-driven extraction of **MYR amount** + **merchant text**.
- Immediate **provisional save** of every shared receipt.
- **Hybrid place auto-suggest**: receipt text + share-time device location + Google Places candidates → best guess saved automatically; user can change later.
- **Auto-categorization** via a versioned keyword map (bundled at build time, refreshable from a remote JSON config).
- **Personal dashboard:** monthly total + delta, by-category breakdown, weekly trend, top places.
- **Personal map:** spend bubbles aggregated by place identity, with time and category filters.
- **Auth-from-day-one** (Supabase Auth: email + Google + Apple).
- **Local outbox** for offline-tolerant capture with background sync.
- **Friends teaser** (single read-only surface; no social backend).

**Out of scope (v1):**

- Friends, follows, shared goals, leaderboards, location-frequency feeds.
- Direct bank API or screen-scraping integrations.
- Budget caps, spend alerts, recurring-payment detection.
- Multi-currency. Non-MYR receipts are saved with `amount_myr = null` and flagged via `needs_amount`.
- Visual "low confidence" warnings for amounts.
- CSV export (target v1.1 unless trivially cheap during build).

## 4. Stack

- **Client:** Flutter (Dart), targeting Android and iOS from one codebase. Chosen for tighter native-share / camera / maps integration story than React Native for this specific feature mix.
- **Auth + DB + Storage:** Supabase (Postgres + Row-Level Security + Auth + Storage).
- **Maps + Places:** Google Maps SDK on the client; Places API calls **proxied through a Supabase Edge Function** so the API key is never shipped in the app binary.
- **OCR:** On-device text recognition (Google ML Kit Text Recognition v2 via the official Flutter plugin). Server-side re-OCR is **not** in v1.
- **Local persistence (outbox + cache):** SQLite via Drift.

## 5. Architecture (hybrid: device-first, cloud-enriched)

1. Share intent arrives at the app (foreground app or share extension UI).
2. App immediately writes a **provisional transaction** to the **local outbox** (SQLite), including OCR-extracted amount and merchant text plus share-time location if permission is granted.
3. The artifact (image/PDF bytes) is staged in the local outbox alongside the row.
4. The **sync worker** (background isolate / periodic task) uploads the artifact to Supabase Storage, inserts the `transactions` row with the same client-generated UUID (idempotent), creates the `receipt_artifacts` row, and triggers async enrichment.
5. **Enrichment** runs in a Supabase Edge Function: normalizes merchant text, calls Places to confirm/refine the venue, and updates `pipeline_status` to `enriched` (or `failed_enrichment`).
6. The UI reads from a **unified view** of `outbox` rows + cloud `transactions` so users see their expense the moment they share, regardless of network state. A small **"pending sync"** badge clears when the row lands in cloud.

## 6. Data model

All tables enforce Row-Level Security: a user can read/write only rows where `user_id = auth.uid()`.

### 6.1 `profiles`

- `id` uuid primary key, references `auth.users`.
- `display_name` text.
- `avatar_url` text nullable.
- `wants_friends_beta` boolean default false. *(Set when user taps the teaser CTA.)*
- `created_at` timestamptz default now().

### 6.2 `transactions`

- `id` uuid primary key (client-generated).
- `user_id` uuid not null, references `profiles.id`.
- `created_at` timestamptz default now().
- `occurred_at` timestamptz not null default now(). Editable.
- `amount_myr` numeric(12,2) nullable. Null means "needs amount".
- `amount_source` text check in (`ocr`, `user`, `blended`). Null when `amount_myr` is null.
- `needs_amount` boolean default false. True when amount could not be extracted at save time and user has not yet supplied one.
- `merchant_raw` text nullable. Raw OCR-derived merchant string.
- `merchant_normalized` text nullable. Filled by enrichment.
- `category_guess` text nullable.
- `category_confidence` real nullable. Stored for tuning; not surfaced in UI.
- `category_user` text nullable. User override; takes precedence in all aggregations.
- `place_status` text check in (`guess`, `user_locked`, `none`) default `none`.
- `place_google_place_id` text nullable.
- `place_name` text nullable.
- `place_lat` double precision nullable.
- `place_lng` double precision nullable.
- `place_confidence` real nullable.
- `share_location_lat` double precision nullable.
- `share_location_lng` double precision nullable.
- `share_location_captured_at` timestamptz nullable.
- `ocr_confidence` real nullable.
- `pipeline_status` text check in (`provisional`, `enriched`, `failed_enrichment`) default `provisional`.

### 6.3 `receipt_artifacts`

- `id` uuid primary key.
- `user_id` uuid not null.
- `transaction_id` uuid not null, references `transactions.id` on delete cascade.
- `storage_path` text not null. Path inside the private `receipts` bucket.
- `mime_type` text not null.
- `created_at` timestamptz default now().

### 6.4 Storage bucket: `receipts`

- Private. Access via signed URLs only, generated server-side per request.
- Object key pattern: `<user_id>/<transaction_id>/<artifact_id>.<ext>`.

### 6.5 Local-only tables (SQLite, on device)

- `outbox_transactions` mirrors `transactions` with extra fields: `sync_status` in (`pending`, `syncing`, `synced`, `stuck`), `last_error` text nullable, `retry_count` int default 0.
- `outbox_artifacts` mirrors `receipt_artifacts` with `local_file_path`.
- `category_config_cache` stores the latest fetched remote categories JSON plus its etag/version.

## 7. Categories config

- v1 ships a **bundled** `categories-v1.json` inside the app (works on first launch, no network).
- On launch and once per day thereafter, the client fetches `config/categories-v1.json` from a **public** Supabase Storage object and replaces the in-memory map if a newer `version` is present.
- File shape (illustrative):
  ```json
  {
    "version": "2026-05-11.1",
    "default_category": "Others",
    "rules": [
      { "category": "Food & Drink", "any_of": ["mcdonald", "starbucks", "kopitiam", "kfc", "tealive"] },
      { "category": "Groceries",   "any_of": ["aeon", "village grocer", "jaya grocer", "lotus", "mydin"] },
      { "category": "Transport",   "any_of": ["touch n go", "tng", "grab", "petron", "shell", "petronas"] }
    ]
  }
  ```
- Matching is case-insensitive substring matching against `merchant_normalized` (or `merchant_raw` if normalization hasn't happened yet). First rule wins; otherwise `default_category`.

## 8. Capture flows

### 8.1 Happy path — image/PDF share

1. User shares a receipt to Receipt Drop.
2. Share extension reads the file, runs ML Kit OCR, picks the best MYR amount candidate, and writes a provisional row to the local outbox.
3. The extension shows a **brief confirmation toast** ("Saved — RM 8.90 at 7-Eleven Sunway"). It does **not** require user input on the happy path.
4. Sync worker uploads when network returns; enrichment fills in normalized merchant + place candidates.

### 8.2 Unsupported share type

If the OS hands us a payload we cannot decode as image or PDF:

- Share extension shows a **minimal inline sheet**: title "Couldn't read this — enter amount?", a single MYR amount field, optional note, **Save** / **Cancel**.
- On Save, we still write a transaction with `amount_source = 'user'`, `needs_amount = false`, `merchant_raw` set to whatever shared text was available. If the original shared payload was a file, we retain it in the outbox so we can reprocess later.

### 8.3 OCR finds no amount

- Preferred path: same **inline sheet** as 8.2 appears, prefilled with the OCR'd text so the user can copy/correct quickly. Save writes the transaction with the user-entered amount and `amount_source = 'user'`.
- Fallback path (if the host platform/version forbids extra UI in the share extension): save the transaction with `amount_myr = null` and `needs_amount = true`, then schedule a **local notification**: "Receipt saved — tap to add amount." Tapping deep-links to transaction detail.
- Either way, we never silently store `0` for an unknown amount.

### 8.4 Place auto-suggest ranking

For each shared receipt, the client computes ranked place candidates:

1. Build a query string from `merchant_raw` (cleaned).
2. If location permission is granted, bias toward `share_location_lat/lng` with a small radius (default 250m, expanding to 1km if no candidates).
3. Send `(query, lat, lng)` to the Places-proxy Edge Function; receive top N candidates with `place_id`, name, address, lat/lng, distance, and a relevance score.
4. The top candidate is saved as `place_status = 'guess'`. Alternates are not stored in v1; a re-search happens if the user opens the place picker.

### 8.5 Correction (amount, place, category)

- Tap a transaction → Transaction Detail.
- Edit amount → `amount_source` becomes `user`.
- Change place → opens Places search (Edge Function call), selecting any result sets `place_status = 'user_locked'` and updates `place_*` fields.
- Override category → `category_user` is set; aggregations immediately use the new value.

## 9. Aggregations

- **Effective category** = `category_user` if not null, else `category_guess`, else `Unclassified` bucket.
- **Effective place key** = `place_google_place_id` if not null, else a geohash of `place_lat/lng` at precision 8 (~38m × 19m cell).
- **Month total** = sum of `amount_myr` where `occurred_at` falls within the calendar month and `amount_myr is not null`.
- **Delta vs previous month** is shown as a percentage. If the previous month total is zero, the delta is hidden rather than displayed as infinity.
- **By category** groups by effective category. The `Unclassified` bucket is shown explicitly so users can see how much is unlabeled.
- **Top places** groups by effective place key with sum + visit count.
- Charts ignore rows where `pipeline_status = 'failed_enrichment'` **and** `amount_myr is null`. Any row with a non-null amount is real spend regardless of enrichment state.

## 10. Screens

Visual reference: `assets/c__Users_USER_AppData_Roaming_Cursor_User_workspaceStorage_empty-window_images_image-3fd6e86f-ec37-4d57-a2ef-ff421f7ce0a5.png` (Receipt Drop mock — green primary, pug mascot, four-tab nav with centered + action). This mock is the visual source of truth for v1.

1. **Onboarding (3 slides)** — "Share any RM receipt", "We guess place + category, you can fix", "Your data, your map." Then sign-in.
2. **Sign-in** — Continue with Google, Continue with Apple, or email + password. "Sign up" link below.
3. **Home / Feed** — reverse-chronological list grouped by day ("Today", "Yesterday", then dated). Each row: amount, place name (or "No place"), category chip. Badges: `pending sync`, `needs amount`. **No** low-confidence badge.
4. **Transaction Detail** — receipt thumbnail, editable amount, place block with map preview + "Change place", category dropdown, occurred-at, Delete.
5. **Dashboard** — month picker, "This Month" total + delta vs previous month, By Category donut with `Unclassified` slice, By Week line, Top Places list with visit count + total spend, **Friends teaser card** pinned near the bottom.
6. **Map** — Malaysia-default; bubbles per effective place key sized by spend. Tap → bottom sheet with that place's transactions and visit count for the active filter range. Filter chips: time range, categories. Empty state encourages enabling location.
7. **Places search (Change place)** — search field + ranked results (driven by Edge Function proxy), plus a "Choose on map" entry that lets the user drop a pin manually.
8. **Inline share sheet (Save)** — minimal modal hosted by the share extension: receipt thumbnail, amount field (auto-filled when OCR succeeded), Save / Cancel. Used for happy path and for 8.2 / 8.3 fallback.
9. **Settings** — Account, Sign out, Export (CSV — v1.1 unless cheap), Privacy & Legal, Clear local cache (does not delete cloud data), App version, **Friends (coming soon)** row.
10. **Friends teaser** — read-only screen reachable from the Dashboard card and Settings row. Headline "Save together, soon." Three preview tiles showing what's coming: anonymized friends-on-map, location-frequency-without-amounts ("Nathan spent here 5 times this week"), shared goals ("Nathan is 50% through his challenge — week 5 of 10"). Single CTA "Notify me when this launches" flips `profiles.wants_friends_beta = true`.

## 11. Permissions, security, privacy

- **Location:** "While using the app" only. Used solely for place ranking; never written to the server except as `share_location_*` columns on the user's own transactions.
- **Photos / Files:** requested only when the user invokes the share flow from inside the app or from the OS share sheet.
- **Notifications:** requested before scheduling the "add amount" reminder in 8.3's fallback path.
- **Storage:** the `receipts` bucket is private. The app fetches signed URLs on demand for in-app viewing.
- **RLS:** every user-owned table policy is `user_id = auth.uid()`.
- **Secrets:** Google Places API keys live only in the Supabase Edge Function's environment, never in the client.
- **Copy:** onboarding and Settings clearly state Receipt Drop is not a bank, not financial advice, and that data is the user's.

## 12. Error handling matrix

| Situation | Behavior |
|-----------|----------|
| Unsupported share payload | Inline sheet (8.2) |
| OCR can't find amount | Inline sheet (8.3) preferred; local notification fallback |
| Multiple plausible totals | Pick best per heuristic; no UI warning. Tunable via fixtures. |
| Location permission denied | Save with place fields null; map shows "enable location" empty state; ranking falls back to text-only Places search |
| Places proxy fails / over quota | `pipeline_status = 'failed_enrichment'`; no user-facing error |
| Offline at share time | Outbox stores everything; UI shows transaction immediately with `pending sync` badge |
| Sync stuck after N retries (default 5) | Banner on Home: "1 receipt couldn't sync — tap to retry"; row marked `sync_status = 'stuck'` |
| Password-protected PDF | Treated as unsupported (8.2) |
| Non-MYR receipt detected | Save with `amount_myr = null` and `needs_amount = true`; v1 does not multi-currency |

## 13. Testing strategy

- **Golden fixtures** of receipts (synthetic + anonymized real samples from Maybank QR, TNG eWallet, CIMB Pay, generic merchant printouts). Each asserts extracted amount, expected category under the current keyword config, and a substring of `merchant_raw`.
- **Heuristic regression tests** for the "largest plausible total vs change/discount line" failure mode, including Malay-language receipt vocabulary (`Tunai`, `Baki`, `Diskaun`, `Cukai`).
- **Outbox tests:** enqueue → kill network → relaunch → assert the row syncs exactly once.
- **Map aggregation tests:** three transactions with the same `place_google_place_id` collapse into one bubble with the correct sum and count.
- **RLS tests:** user A cannot read or write user B's rows via direct API calls.
- **Manual QA matrix:** Android share from Chrome, Gallery, Maybank/TNG/CIMB; iOS share from Photos and Files. At least one airplane-mode capture per platform.

## 14. v1 risks and mitigations

- **OCR variance across OEMs/languages.** Mitigated by golden fixtures + remotely-tunable categories config and (post-v1) optional server-side re-OCR.
- **Places key abuse.** Mitigated by routing all Places calls through a Supabase Edge Function with rate limits and request signing.
- **User trust around financial data.** Mitigated by clear copy, RLS, private bucket, signed URLs, and the absence of any social surface in v1.
- **Scope creep into friends/goals.** Mitigated by a single forward-compatible field (`wants_friends_beta`) and a read-only teaser screen — no friend code paths in v1.

## 15. Roadmap signals (post-v1, informational only)

- v1.1: CSV export, refined OCR fixtures, polish.
- v2: Friends, location-frequency feed (counts only, not amounts), shared goals — gated on demand from `wants_friends_beta` and direct user feedback.
