# Home Diorama: 360° Themed Platform

Replace the static pixel-avatar block on `/` with an interactive **square 3D diorama** the user can swipe to rotate 360°. The platform's scene (props, walls, color palette) is driven by the **category of the most recent receipt drop**. The avatar performs a category-specific **idle loop** on top.

Visual reference: Rolife-style miniature room dioramas — soft pastel walls, chunky toy-like props, a small square floor tile, two back walls forming a corner, warm "shelf light." Built entirely with CSS 3D transforms (voxels + flat textured planes) — no three.js, no new heavy deps.

## Behavior

- **Source of truth**: most recent drop in `DropsContext` (`drops[drops.length-1]`).
- **Theme picked from `drop.category`** via a new `getThemeForCategory()` helper.
- **Caption** under the diorama: `"Your last receipt was from {Category}."`
- **If no drops yet OR category is "Other"/unknown**: render the neutral `idle` platform (plain wooden tile + soft walls) with caption `"Update your last receipt's category to set the scene."` + a small `Link` to `/drop` (or the most recent drop's edit, future work).
- **Interaction**: horizontal swipe / drag rotates the diorama around its Y axis. Pointer events only — no buttons, no zoom, no tap. Avatar is non-interactable (pointer-events: none on the avatar layer).
- **Inertia**: light momentum on release, then settles (no snap to faces — free rotation).
- **Vertical tilt**: fixed ~15° downward isometric view; vertical drag is ignored.

## 10 Themes

Each theme = a `DioramaTheme` config with `id`, `label`, `palette` (uses existing tokens + per-theme accent), `props[]` (positioned voxel/plane primitives), `avatarAnim` (idle loop name), and matching `category` keys.

| # | Theme id | Triggered by category | Scene vibe | Avatar idle |
|---|----------|-----------------------|------------|-------------|
| 1 | `cafe` | Coffee / Cafe | Little Bear cafe corner: espresso machine, small table, menu board | Sipping bob — holds tiny cup, slow head-bob |
| 2 | `shopping` | Shopping / Clothes | Pink boutique: clothing rack, mirror, shopping bag | Browse-walk — paces left↔right, peeks at rack |
| 3 | `grocery` | Groceries | Mini market: shelves of cans, basket on floor | Basket-hop — small hops, basket swings |
| 4 | `food` | Food / Restaurant | Panda Hotpot booth: steaming pot, stools | Chopstick wiggle — leans over pot, arms wiggle |
| 5 | `bubble_tea` | Drinks / Bubble tea | Super Bubble Tea counter: blender, cup display | Straw-sway — sways shoulders, sips straw |
| 6 | `bakery` | Bakery / Dessert | Glass cake display, "Cakery" sign | Window-gaze — leans forward, tiny bounce |
| 7 | `petrol` | Transport / Fuel | Pump island: pump, tiny car silhouette | Tap-foot — stands still, foot taps |
| 8 | `pets` | Pets | Furry Home shop: pet carrier, toy wall | Crouch-pet — crouches, head tilts |
| 9 | `home` | Bills / Utilities / Rent | Cozy living room: sofa, lamp, rug | Couch-slump — sits, slow breath |
| 10 | `entertainment` | Entertainment / Cinema / Games | Cha Chaan Teng / arcade booth: neon sign, booth seat | Dance-bob — rhythmic side-step |

Plus the fallback **`idle`** scene (plain wooden tile, soft cream walls, no props) → avatar uses existing generic `pixel-bob`.

Category-to-theme mapping lives in `src/lib/diorama-themes.ts` and is forgiving (lowercased substring match, e.g. `"coffee" | "cafe" | "espresso" → cafe`).

## Files

**New**
- `src/lib/diorama-themes.ts` — `DioramaTheme` type, `themes` registry, `getThemeForCategory(category?: string): DioramaTheme`.
- `src/components/Diorama.tsx` — square 3D stage (`perspective`, `rotateX(-15deg) rotateY(spin)`), renders floor tile + two back walls + theme `props`, mounts `PixelAvatar` centered on the floor with the theme's `avatarAnim`.
- `src/components/diorama/` — small prop primitives composed from existing `Voxel`:
  - `Floor.tsx` (textured tile w/ per-theme color)
  - `BackWalls.tsx` (two perpendicular planes)
  - `props/*.tsx` — one tiny file per recurring prop (`Espresso`, `ClothingRack`, `Shelf`, `Pump`, `Sofa`, `CakeCase`, `Counter`, `Pot`, …). Each is a small composition of `Voxel`s.
- `src/hooks/use-swipe-rotate.ts` — pointer-down/move/up hook returning `rotationY` + bind props; includes inertia (decays over ~600ms).

**Edited**
- `src/routes/index.tsx` — replace the avatar block with `<Diorama theme={theme} state={avatarState} config={avatarConfig} />` + caption + conditional "update category" hint. Keep header, "Drop Receipt" CTA, and badges row unchanged.
- `src/components/PixelAvatar.tsx` — accept new optional `idleAnim?: string` prop that overrides the state-derived animation class (so themes can swap in `cafe-sip`, `shop-walk`, etc.).
- `src/styles.css` — add per-theme keyframes (`@keyframes shop-walk`, `cafe-sip`, `basket-hop`, `chopstick-wiggle`, `straw-sway`, `window-gaze`, `tap-foot`, `crouch-pet`, `couch-slump`, `dance-bob`) and utility classes. All use existing OKLCH tokens + small per-theme accent CSS vars defined in `:root` (e.g. `--theme-cafe-accent`).

**Unchanged**: drops context, mock data, ritual/summary/feed/map/leaderboard routes, MobileShell. The `/avatar` customizer keeps working and its config is passed through to the diorama avatar.

## Technical notes

- **Stage size**: 280×280 CSS px (fits 571px viewport with room for caption + CTA). `transform-style: preserve-3d`, `perspective: 900px` on parent.
- **Swipe math**: `rotationY += deltaX * 0.5` (deg per px). Clamp velocity, decay `v *= 0.92` per frame via `requestAnimationFrame` until `|v| < 0.05`.
- **Avatar pinning**: avatar sits at `translateZ(0)` center of floor; rotates with the stage (so it always faces the camera relative to scene). Idle animations are self-contained transforms on the avatar root — they compose with the stage rotation cleanly because they only affect children inside `preserve-3d`.
- **No persistence**: rotation resets on route change (acceptable for prototype).
- **A11y**: stage has `role="img"` + `aria-label="{theme.label} diorama with your avatar"`. Caption is real text below.
- **Perf**: ~30-50 voxels per scene; well within CSS 3D budget. No re-renders during drag (rotation written to a ref + CSS var, not React state).

## Out of scope

- three.js / WebGL.
- New categories on the drop screen (existing categories are reused; mapping is forgiving).
- Persisting rotation, zoom, tap-to-interact, day/night lighting.
- Unlockable themes, theme picker UI (theme is always derived from last receipt).
- Editing a past drop's category from the home screen (just a hint + link to `/drop`).
