/// Pure math for the home-screen receipt carousel's continuous momentum
/// scrolling: the deck tracks the finger 1:1 while dragging, then on
/// release decelerates via friction before spring-snapping to center on the
/// nearest receipt.
///
/// Kept free of Flutter widgets so unit tests can exercise the offset math,
/// windowing, and physics handoff without a widget pump.
library;

/// Each card's width as a fraction of the carousel's viewport width. Leaves
/// room on either side for neighbor cards to peek in, without requiring the
/// carousel to bleed past its parent's padding.
const kCardWidthFraction = 0.84;

/// Horizontal gap between adjacent card slots, in px.
const kCardSpacingPx = 14.0;

/// How many neighbors to render on each side of the centered card. Rendered
/// card count is capped at `2 * kVisibleWindowRadius + 1` regardless of how
/// many receipts exist.
const kVisibleWindowRadius = 2;

/// Scale/opacity floor for cards at or beyond [kPeekFalloffRadius] pages
/// away from center.
const kPeekMinScale = 0.88;
const kPeekMinOpacity = 0.55;

/// Distance (in pages) beyond which a peeking card's scale/opacity stop
/// shrinking further.
const kPeekFalloffRadius = 1.6;

/// [FrictionSimulation] drag coefficient for the post-release deceleration
/// phase, in page-units (not pixels — a "page" is one card's extent, so
/// this needs to be much smaller than a typical pixel-space friction
/// constant). Tunable on device — higher (closer to 1) is "slippier" and
/// travels further before decaying; lower (closer to 0) stops sooner.
const kFrictionDrag = 0.26;

/// Once the friction phase's velocity decays below this (pages/sec), hand
/// off to the settle spring.
const kFrictionToSpringVelocityThreshold = 0.6;

/// Hard cap on how many pages the friction phase can travel from where the
/// gesture started, so an extreme flick can't skip the entire list.
const kMaxFlingPages = 6.0;

/// Spring parameters for the final centering snap after a real flick's
/// friction phase hands off (see `_startSpringPhase`). Programmatic jumps
/// (auto-rotate, dot-tap, tap-to-recenter) have no gesture velocity to stay
/// continuous with, so they use a plain curved tween instead of this spring
/// — this keeps "bounce" exclusive to user flicks.
/// Used with Flutter's [SpringDescription] / [SpringSimulation].
const kSnapSpringMass = 1.0;
const kSnapSpringStiffness = 400.0;

/// ~1.1x critical damping (`2·√(mass·stiffness) = 40`) — no overshoot even
/// with the friction phase's handoff velocity, slightly over rather than
/// exactly-critical for safety margin, still fast given the high stiffness.
const kSnapSpringDamping = 44.0;

/// A single rendered card during the windowed render: [index] is the real
/// (wrapped) transaction index, [delta] is its signed shortest-path distance
/// from the current offset (negative = to the left, positive = to the
/// right).
class CarouselSlot {
  const CarouselSlot({required this.index, required this.delta});

  final int index;
  final double delta;
}

/// The transform to apply to a single card slot, derived from its [delta].
class CardTransform {
  const CardTransform({
    required this.dx,
    required this.scale,
    required this.opacity,
    required this.zOrder,
  });

  /// Horizontal offset from the slot's centered rest position, in px.
  final double dx;

  /// 1.0 when centered, shrinking toward [kPeekMinScale] as it peeks away.
  final double scale;

  /// 1.0 when centered, shrinking toward [kPeekMinOpacity] as it peeks away.
  final double opacity;

  /// Paint-order hint: 0 at center, larger for cards farther away (paint
  /// farthest-first so the centered card stays on top).
  final double zOrder;
}

/// Wraps [index] into `[0, pageCount)`.
int wrapIndex(int index, int pageCount) {
  if (pageCount <= 0) return 0;
  return ((index % pageCount) + pageCount) % pageCount;
}

/// Shortest signed page delta from [from] to [to] on a looping list of
/// [pageCount] pages. Result is in `[-floor(n/2), ceil(n/2)]`.
int shortestPageDelta(int from, int to, int pageCount) {
  if (pageCount <= 0) return 0;
  var diff = to - from;
  if (diff > pageCount / 2) diff -= pageCount;
  if (diff < -pageCount / 2) diff += pageCount;
  return diff;
}

/// The unwrapped integer page nearest [offset]. Spring targets live in this
/// (unwrapped) space, not wrapped-index space, so momentum can keep
/// carrying the offset past a wrap boundary mid-animation.
int roundToNearestPage(double offset) => offset.round();

/// The wrapped real transaction index nearest [offset], for display/lookup.
int nearestRealIndex(double offset, int pageCount) =>
    wrapIndex(roundToNearestPage(offset), pageCount);

/// Each card's rest-position width, in px.
double cardSlotWidth(double viewportWidth) =>
    viewportWidth * kCardWidthFraction;

/// Center-to-center distance between adjacent card slots, in px.
double cardExtentPx(double viewportWidth) =>
    cardSlotWidth(viewportWidth) + kCardSpacingPx;

/// Converts a frame's raw horizontal drag delta (px) into a page delta to
/// add to the live offset. Sign convention matches Flutter drag: a left
/// drag (negative px) advances toward higher indices (positive pages).
double pxDeltaToPages({
  required double deltaPx,
  required double viewportWidth,
}) {
  final extent = cardExtentPx(viewportWidth <= 0 ? 1.0 : viewportWidth);
  return -deltaPx / extent;
}

/// Converts a release velocity (px/s) into pages/sec, same sign convention
/// as [pxDeltaToPages].
double pxVelocityToPagesPerSecond({
  required double velocityPxPerSec,
  required double viewportWidth,
}) {
  final extent = cardExtentPx(viewportWidth <= 0 ? 1.0 : viewportWidth);
  return -velocityPxPerSec / extent;
}

/// The bounded set of cards to render around [offset]. Generates unwrapped
/// candidate page positions in `[offset.round() - windowRadius,
/// offset.round() + windowRadius]`, wraps each to a real index, and dedupes
/// by real index — keeping the candidate with the smallest `|delta|` — so a
/// small [pageCount] (e.g. 2-3) with a wide window doesn't render the same
/// receipt twice.
List<CarouselSlot> visibleSlots({
  required double offset,
  required int pageCount,
  int windowRadius = kVisibleWindowRadius,
}) {
  if (pageCount <= 0) return const [];

  final centerPage = offset.round();
  final byIndex = <int, CarouselSlot>{};
  for (var p = centerPage - windowRadius; p <= centerPage + windowRadius; p++) {
    final delta = p - offset;
    final index = wrapIndex(p, pageCount);
    final existing = byIndex[index];
    if (existing == null || delta.abs() < existing.delta.abs()) {
      byIndex[index] = CarouselSlot(index: index, delta: delta);
    }
  }
  return byIndex.values.toList();
}

/// The transform for a single card slot at signed [delta] pages from
/// center, given the on-screen center-to-center card spacing
/// [cardExtentPx].
CardTransform cardTransformForDelta({
  required double delta,
  required double cardExtentPx,
}) {
  final absDelta = delta.abs();
  final t = (absDelta / kPeekFalloffRadius).clamp(0.0, 1.0);
  return CardTransform(
    dx: delta * cardExtentPx,
    scale: 1.0 - t * (1.0 - kPeekMinScale),
    opacity: 1.0 - t * (1.0 - kPeekMinOpacity),
    zOrder: absDelta,
  );
}

/// Clamps a live friction-phase offset to within [maxPages] of where the
/// gesture began ([flingStart]), so an extreme flick can't skip the entire
/// list before the settle spring takes over.
double clampOffsetTravel({
  required double offset,
  required double flingStart,
  double maxPages = kMaxFlingPages,
}) {
  return offset.clamp(flingStart - maxPages, flingStart + maxPages);
}

/// True when the friction phase should hand off to the settle spring this
/// tick — either the velocity has decayed enough to feel like a snap rather
/// than a scroll, or the travel cap has been reached.
bool frictionShouldHandoffToSpring({
  required double velocityPagesPerSec,
  required double offset,
  required double flingStart,
  double maxPages = kMaxFlingPages,
  double velocityThreshold = kFrictionToSpringVelocityThreshold,
}) {
  if (velocityPagesPerSec.abs() < velocityThreshold) return true;
  final travel = (offset - flingStart).abs();
  return travel >= maxPages;
}
