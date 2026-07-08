# Handoff: Receipt Confirmation & Restaurant Location Picker

## Overview
Two bottom-sheet screens for the receipt-scanning flow:
1. **Receipt Confirmation Sheet** — shown right after a scan finishes. Lets the user review the vendor, total, and itemized breakdown before saving.
2. **Restaurant Location Picker** — a map + bottom-sheet screen for picking which physical branch a receipt belongs to, using the top 3 nearby matches (500m radius) or a manual search.

## About the Design Files
The files in this bundle (`receipt-confirm-sheet.html`, `restaurant-location-picker.html`) are **HTML/CSS/JS design references** built as interactive prototypes — they show intended look, layout, and behavior. They are not production code to copy directly.

The target codebase is **Flutter/Dart** (see the existing `receipt_cards.dart`, `compact_receipt_card.dart` in the app). Recreate these designs as Flutter widgets following the app's existing conventions:
- `google_fonts` package, `GoogleFonts.baloo2(...)` for all type
- `Scaffold` + `showModalBottomSheet` (or a custom `DraggableScrollableSheet`) for the pull-up sheet pattern
- Match the existing `Category`/`ReceiptItem` model shapes already used in `receipt_cards.dart` where practical

## Fidelity
**High-fidelity.** Colors, type, spacing, and interaction behavior below are final — implement pixel-close using Flutter's existing widget primitives, not a WebView embed.

## Design Tokens
- Background (app default): `#FAF3E7`
- Sheet surface: `#FFFDF8`
- Ink (primary text): `#4F2D23` (headline/total) and `#5A4632` (body)
- Sub text (muted): `#9C8A72`, `#B0A48D`
- Tile (icon chip bg): `#F4E8D6`
- Accent / CTA gold: `#F5C242`, CTA text `#5A3E0A`
- Accent link (e.g. "Edit details"): `#D89B1F` / hover `#C4841C`
- Dashed divider: `2px dashed rgba(79,45,35,0.2)`
- Font: Baloo 2, weights 500/600/700/800
- Sheet corner radius: 28px (top corners only)
- Sheet shadow: `0 -18px 40px rgba(60,40,20,.16)`
- Drag handle: 38×5px pill, `#E9DDC8`

---

## Screen 1 — Receipt Confirmation Sheet

### Layout
Bottom sheet, full width, rounded top corners (28px), padding `12px 22px 26px`. Order top-to-bottom:
1. Drag handle (centered)
2. Row: category chip (left, pill `#F4E8D6` bg, emoji + label, muted text) — count label (right, `"{n} of {total} items"`, muted)
3. Row: circular avatar (42px, gold `#F0AA2A` bg, white bold initial letter) + vendor name (20px/800) + pencil icon-button (32px circle, `#F4E8D6` bg) at the far right of that row
4. Total amount, large (38px/800, ink)
5. Dashed divider
6. Item list (see below)
7. Optional undo banner (see Interactions)
8. CTA button "Looks good" — full width, 18px radius, gold `#F5C242` fill, ink-brown text, soft gold shadow
9. Text link "Edit details" (gold-brown, centered)
10. Text link "Cancel" (muted, centered)

### Item row
Each item: 22×22 rounded-square checkbox (7px radius) + item name (15px/700) on the left, price (15px/700) on the right, `justify-content: space-between`.
- **Checked** (included): checkbox filled gold `#F5C242` with a white checkmark, name/price full opacity, no strikethrough.
- **Unchecked** (excluded): checkbox white with a light border (`#E4D8C2`), checkmark hidden, name gets `line-through`, name+price drop to ~40% opacity.

### Vendor rename
Tapping the pencil button swaps the vendor name text for an inline text input (same 20px/800 styling, bottom-border `2px solid #F5C242`, autofocus + select-all on open). Enter or blur commits the new name and reverts to display mode; Escape cancels back to display mode without special-casing the text (kept as typed).

### Interactions & Behavior
- **Toggle item (checkbox tap)**: flips that item's included/excluded state and immediately recalculates the total (sum of checked items' prices only). The item-count label updates to `"{checkedCount} of {totalCount} items"`.
- **Uncheck → show Undo banner**: unchecking an item shows a dismissible banner between the item list and the CTA: `"{Item name} excluded"` with an `Undo` action (gold-brown, right-aligned). Auto-hides after ~4 seconds. Tapping Undo re-checks that specific item and hides the banner immediately. If the same item gets re-checked manually (not via Undo) while its banner is showing, hide the banner.
- Only one undo banner at a time — a new uncheck replaces/reschedules it.
- "Looks good" commits the (possibly edited) item list, vendor name, and total.
- "Edit details" / "Cancel" are placeholder actions — wire to your existing edit-receipt / dismiss-sheet flows.

### State
```
vendorName: string
editingVendor: bool
items: [{ id, name, price, checked }]
undo: { itemId, name } | null   // drives the undo banner + its timer
```
Derived: `total = sum(price for items where checked)`, `includedCount = count(checked)`, `itemCount = items.length`.

---

## Screen 2 — Restaurant Location Picker

### Layout
Full-screen map background (simplified roads/greenery placeholder — replace with your real map integration) with:
- Status bar
- Top bar: back button (circular, white, 42px) + rounded search-style bar reading "Which restaurant was this?" (tapping it opens search mode)
- A dashed 500m radius ring centered on the user's "you are here" blue dot
- 3 pin markers for nearby candidates (nearest pin highlighted gold, others neutral `#C9BB9E`)

Below the map, a bottom sheet (same 28px top radius, `#FFFDF8` surface) with two modes:

**Browse mode (default):**
1. Drag handle
2. Header row: "Choose the location" (18px/800) + "{n} spots found nearby" (13px, muted) — no icon in this row
3. List of 3 candidate rows, each: location-pin icon (38px tile) + name (15px/800) + address (12.5px, muted) + distance badge (top-right, e.g. "120m") + radio circle (bottom-right, filled gold when selected)
   - Selected row gets a soft gold tint background (`#FBF0D7`) and gold border; unselected rows are plain white/cream with a light border.
4. CTA "Confirm location" (same gold pill style as Screen 1)

**Search mode** (entered by tapping the map's search bar):
- Header row swaps for: back/close icon-button + a search input pill (magnifying-glass icon + text field, placeholder "Search for a restaurant or address"), autofocus on open.
- The candidate list is hidden while searching; wire it to your real place-search/autocomplete results.

### Interactions & Behavior
- Tapping a candidate row selects it (single-select/radio) — updates highlight state on all 3 rows.
- Tapping the map search bar switches to Search mode; tapping the back/close icon in Search mode returns to Browse mode.
- **Sheet entrance animation**: the sheet slides up from fully off-screen (translateY ~420px) to resting position on load, using an eased transition (~550ms, `cubic-bezier(.22,.9,.32,1)`). Trigger this whenever the sheet is presented (e.g. on `showModalBottomSheet` open / route push), not just once.
- "Confirm location" commits the selected candidate (or the manually-searched result) as the receipt's location.

### State
```
candidates: [{ id, name, address, distanceMeters }]
selectedId: string
searchOpen: bool
searchQuery: string
```

---

## Assets
No external image assets — all icons are inline vector (checkmark, pencil, pin, back-arrow, search) drawn as simple SVG paths in the reference files; recreate with your icon set or `CustomPainter`/`Icon` equivalents.

## Files in this bundle
- `receipt-confirm-sheet.html` — Screen 1 reference (interactive; open in a browser)
- `restaurant-location-picker.html` — Screen 2 reference (interactive; open in a browser)
- `screenshot-receipt-confirm-sheet.png` — static screenshot of Screen 1
- `screenshot-restaurant-location-picker.png` — static screenshot of Screen 2
