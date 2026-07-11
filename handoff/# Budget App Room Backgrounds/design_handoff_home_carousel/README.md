# Handoff: Home Receipt Carousel (auto-rotating, single-card)

## Overview
Redesign of the homepage receipt carousel. Replaces the old manually-swipeable mini slideshow with an auto-rotating, infinitely-looping carousel that still supports manual swipe. Shows one receipt at a time (no adjacent-card peeking). The newest receipt gets a highlighted gold border and a "✨ Latest Spending" badge/sticker breaking its bottom edge.

## About the Design Files
The file in this bundle (`home-receipt-carousel.dc.html`) is an **HTML/CSS/JS design reference** — an interactive prototype showing intended look, layout, and motion. It is not production code to copy directly. Open it in a browser to see/feel the real transitions and timings.

The target codebase is **Flutter/Dart** (see the existing `receipt_cards.dart`, `compact_receipt_card.dart` in the app). Recreate this design as Flutter widgets following the app's existing conventions:
- `google_fonts` package, `GoogleFonts.baloo2(...)` for all type
- Reuse the existing `Category`/`ReceiptItem`-style models and the existing receipt-card layout/content (header row, illustration band, footer band with item icon/name/amount + Total pill) — **do not change what's already inside a card**, only how cards are presented/transitioned and the addition of the newest-receipt treatment.
- A `PageView` (or a custom `AnimatedSwitcher`/`AnimationController`-driven stack) is the natural Flutter fit for the single-card crossfade+scale behavior described below — not a horizontally-scrolling `ListView`/`Row`, which would risk exposing neighboring cards.

## Fidelity
**High-fidelity.** Colors, type, spacing, and interaction/timing behavior below are final — implement pixel-close using Flutter's existing widget primitives, not a WebView embed.

## Screen: Home / "Today's Receipts" carousel

### Purpose
Glanceable dashboard moment: the user opens the app and immediately sees their receipts rotating through automatically, styled like an activity-feed card (Strava-like), with the most recent spend visually called out.

### Layout (top to bottom)
1. Status bar (native, not in scope)
2. Top bar: "✨ {n} drops" pill (white bg, `1.5px solid #EEE3CD` border, 999px radius, `8px 16px` padding) + circular settings button (38×38, white, same border, ⚙️ icon), right-aligned, `gap:10px`
3. Section label: "TODAY'S RECEIPTS", 13px/800, letter-spacing 1.4px, color `#8C857B`
4. **Carousel viewport** — see below
5. Pagination dots, `margin-top:32px`
6. Flexible spacer
7. "Drop Receipt" CTA pill (full width minus 22px side margins, 56px tall, 999px radius, gold `#F6C64B` fill, box-shadow `0 10px 22px rgba(220,170,40,.35)`)
8. Circular "+" FAB (56×56, 18px radius, same gold), centered, overlapping the CTA above it by `margin-top:-24px`
9. Bottom nav: Home (active, gold icon+label) / Feed / Map / Ranks (inactive, `opacity:.55` icon, `#B0A895` label), `justify-content:space-around`, `1.5px solid #EEE3CD` top border

### Carousel viewport
- Container: 296px wide (340px phone width minus 22px side margins ×2), 420px tall, `position:relative`, `overflow:visible` (so the badge and its subtle scale/opacity motion aren't clipped)
- **Exactly one card is visible/interactive at rest.** All non-active cards sit behind it at `opacity:0`, `scale(.92)`, `pointer-events:none`, `z-index:0` — never shown as a peeking neighbor.
- A soft blurred dark blob (`rgba(50,40,15,.16)`, `filter:blur(14px)`, 230×386, centered, `top:16px`) sits behind the active card purely for depth — it is not a neighboring card and carries no content.
- 4 receipt cards in the data set, in display order: **Restaurant (newest, highlighted)**, Grocery, Cafe, Tech. The set loops infinitely in both directions (modulo arithmetic, no cloned DOM nodes needed).

### Receipt card (unchanged content, per existing app conventions)
Each card, 258px wide:
1. Accent bar, 9px tall, category accent color
2. Header row (`16px 16px 12px` padding): 38×38 white circle with emoji + vendor name (16px/800) + timestamp (12px/600, muted) on the left; a small gray pill top-right with a 📄 icon + hashtag category tag (e.g. `#RANT`, `#GROC`, `#CAFE`, `#TECH`), background `#EDE6D6`, text `#3B3527`
3. Illustration band, 180px tall, full-bleed (real photo for the restaurant card; category emoji centered on a tint band as placeholder for the others — swap for real illustrations/photos per receipt)
4. Footer band on the category's "mid" tone: icon tile + vendor name + amount row, `2px dashed` divider, then a "Total" pill (`rgba(255,255,255,.24-.28)` bg, 14px radius)

### Newest-receipt highlight (Restaurant card only)
- The whole card is wrapped in an outer box: `border:3px solid #F6C64B`, `border-radius:27px`, `padding:3px` (so the border surrounds the image and all card content, not just the header)
- Badge: "✨ Latest Spending" pill, content-sized (`padding:8px 15px`), background `#F6C64B` (same gold as the border — a different color from the card's own red/coral palette), text 13px/800 `#23201A`, `border-radius:999px`, `box-shadow:0 6px 14px rgba(220,170,40,.4)`
- Position: `position:absolute; left:50%; bottom:0; transform:translate(-50%, 50%)` — this centers the pill vertically right on top of the border line, visually "breaking" it, rather than sitting fully above or below it
- Older cards (Grocery/Cafe/Tech) use plain card styling — no border, no badge

## Interactions & Behavior

### Auto-rotation
- Advances to the next card automatically every **5 seconds** (tweakable 3–10s)
- Loops infinitely in one direction (index arithmetic mod 4 — no special-casing at the ends)
- **Pauses** the instant the user starts dragging/swiping
- **Resumes** ~400ms after the user releases (drag end, or a dot tap), so it doesn't fight an in-progress read

### Manual swipe
- Pointer/touch drag on the viewport moves only the *active* card: `translateX(dx * 0.6)`, clamped to ±140px, with a proportional scale-down (down to `.92`) and fade (down to `.7` opacity) as the user drags further — this is drag *feedback* on the current card, not a reveal of the next/prev card's content
- Release with `|dx| > 56px` commits a transition to the next (drag left) or previous (drag right) card
- Release under that threshold springs the active card back to rest (`translateX(0) scale(1) opacity(1)`, 0.3s ease-out)

### Card-to-card transition (auto-rotate, swipe-commit, or dot-tap)
A crossfade + scale "flip through a deck" effect — not a horizontal slide-reveal:
- Outgoing card: fades to `opacity:0`, scales down to `.92`, nudges `translateX` 26px in the direction of travel (i.e. moves away)
- Incoming card: starts at `opacity:0`, `scale(.92)`, offset 26px from the opposite direction, then animates in to `opacity:1 scale(1) translateX(0)`
- Both animate together over **~0.68s**, easing `cubic-bezier(.22,.9,.3,1)` for transform / `.6s ease-out` for opacity
- After the transition settles (~690ms), internal state updates to the new active index and all other cards reset to the hidden baseline (no lingering transition state)

### Pagination dots
- One dot per receipt (4 total), active dot elongates to 22px wide and adopts that card's accent color; inactive dots are 7px circles, `#E2DAC6`
- **Tappable**: tapping a dot jumps directly to that card (pauses auto-rotate, chains through intermediate steps at the same transition speed if the jump spans more than one card, then resumes auto-rotate)

### Tap feedback (haptic-style, no navigation)
- Pointer-down on the active card immediately applies a quick press-down: `scale(.965)`, 0.1s ease
- If released without having moved past a 4px drag tolerance (i.e. a tap, not a swipe): springs to `scale(1.02)` over 0.16s with an overshoot easing (`cubic-bezier(.34,1.56,.64,1)`), then settles to `scale(1)` over 0.18s — a quick "bounce" rather than a linear return
- If the pointer moved past the 4px tolerance, it's treated as a drag/swipe instead (see above)

## State Management
```
activeIndex: int (0..3, real index into the receipts list; 0 = newest)
receipts: [{ id, vendor, timestamp, amount, categoryTag, accentColor, palette (top/mid/tile/ink/sub), illustration, isNewest }]
isDragging: bool
isTransitioning: bool  // guards re-entrant transitions while one is animating
dragDx: double          // live pointer delta while dragging
```
Derived: `activeReceipt = receipts[activeIndex]`, dot highlight = `activeIndex`, badge/border visibility = `receipts[i].isNewest` (only ever true for one item — the most-recently-uploaded receipt).

### Edge cases
- **No receipts uploaded**: hide the carousel + dots entirely; show an empty state under "TODAY'S RECEIPTS" instead (not designed in this bundle — ask design for treatment before shipping).
- **Only one receipt**: show it centered with the highlight border/badge if it's the newest (it always is); disable auto-rotation and hide the dots (nothing to rotate to).
- **Missing receipt image**: falls back to the category emoji centered on the palette's tile-tint band (already how Grocery/Cafe/Tech render here) — wire this as the `errorBuilder`/placeholder path, same pattern as `compact_receipt_card.dart`.

## Design Tokens
- Page/phone background: `#FCF6EA`
- Ink (primary text): `#23201A`, `#3E241C` (on warm/red cards), category-specific inks: Grocery `#36482C`, Cafe `#5A4632`, Tech `#2C3A4E`
- Gold accent (CTA / FAB / highlight border / badge): `#F6C64B`
- Category accents: Restaurant `#B4483B`, Grocery `#5E9E51`, Cafe `#E2885C`, Tech `#4F86C6`
- Category "top"/"mid"/"tile" tones — reuse exactly from `receipt_cards.dart`'s existing `Category` palette constants
- Neutral dot: `#E2DAC6`; neutral chip bg: `#EDE6D6`; muted label: `#8C857B` / `#B0A895`
- Font: Baloo 2, weights 500/600/700/800
- Card radius: 24px (27px on the outer highlight wrapper for the newest card, to keep the 3px border's corner concentric)
- Dashed divider: `2px dashed` at ~30% opacity of the card's ink color

## Assets
- Restaurant illustration: real photo (`uploads/restaurant.png` in the reference bundle) — replace with the actual receipt-linked photo/illustration per receipt.
- Grocery/Cafe/Tech illustrations: emoji-on-tint placeholders in the reference — replace with real category illustrations or receipt photos, falling back to the placeholder pattern when none exists (see `compact_receipt_card.dart::_placeholder`).
- No other external assets; all other icons are emoji glyphs, consistent with the rest of the app.

## Files in this bundle
- `home-receipt-carousel.dc.html` — interactive reference (open in a browser; drag/tap the card, watch it auto-rotate, tap a dot)
- `screenshot-home-carousel.png` — resting state, newest (Restaurant) receipt active, showing the gold highlight border
- `screenshot-newest-badge.png` — scrolled view of the same card showing the "✨ Latest Spending" badge breaking the bottom border, the dots, and the Drop Receipt CTA/FAB
- `screenshot-older-card.png` — an older receipt (Grocery) active, showing the plain (non-highlighted) card treatment
