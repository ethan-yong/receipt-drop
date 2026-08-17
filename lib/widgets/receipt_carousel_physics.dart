/// Pure math for the home-screen receipt carousel's velocity-based paging.
///
/// Kept free of Flutter widgets so unit tests can exercise target-page and
/// blend logic without a widget pump. The carousel widget drives simulations
/// using these helpers as the source of truth for "where should we land" and
/// "which two cards are visible during a fling".

/// Minimum horizontal drag (px) needed to leave the current page when release
/// velocity is negligible. Matches the design-handoff commit threshold.
const kDragCommitThresholdPx = 56.0;

/// Velocities below this (px/s) are treated as zero noise.
const kMinFlingVelocityPxPerSec = 200.0;

/// How much release velocity (in viewport-widths / second) contributes to the
/// projected page delta. Tunable on device.
const kVelocityWeight = 0.42;

/// How much finger displacement (in viewport-widths) contributes to the
/// projected page delta. Tunable on device.
const kDragWeight = 0.85;

/// Cap on how many pages a single fling can skip (avoids accidental overshoot
/// when the user has many receipts today).
const kMaxSkipPages = 4;

/// Spring parameters for the final snap onto an integer page.
/// Used with Flutter's [SpringDescription] / [SpringSimulation].
const kSnapSpringMass = 1.0;
const kSnapSpringStiffness = 400.0;
const kSnapSpringDamping = 22.0;

/// Result of [pageBlend] / [pageBlendDirected]: the two cards visible during
/// a fractional fling and the blend progress between them.
class PageBlend {
  const PageBlend({
    required this.from,
    required this.to,
    required this.t,
    required this.direction,
  });

  /// Outgoing (leaving) card index.
  final int from;

  /// Incoming (arriving) card index.
  final int to;

  /// 0 = fully on [from], 1 = fully on [to].
  final double t;

  /// +1 when advancing (newer → older / left swipe), −1 when going back.
  final int direction;
}

/// Returns the integer page index to settle on after a finger release.
///
/// [dragDeltaPx] is finger displacement (positive = dragged right = go to
/// previous / lower index). [velocityPxPerSec] is release velocity along the
/// same axis (positive = flinging right).
///
/// Sign convention matches Flutter drag: left swipe → negative dx/velocity →
/// advance to higher index (newer-first list, next older receipt).
int computeTargetPage({
  required double currentPage,
  required double dragDeltaPx,
  required double velocityPxPerSec,
  required double viewportWidthPx,
  required int pageCount,
}) {
  if (pageCount <= 1) return 0;
  final width = viewportWidthPx <= 0 ? 1.0 : viewportWidthPx;

  final absDx = dragDeltaPx.abs();
  final absV = velocityPxPerSec.abs();
  final underThreshold =
      absDx < kDragCommitThresholdPx && absV < kMinFlingVelocityPxPerSec;
  if (underThreshold) {
    return _wrapIndex(currentPage.round(), pageCount);
  }

  // Left swipe (negative) advances; right swipe goes back. Flip sign so
  // positive deltaPages means "advance toward higher indices".
  final dragPages = (-dragDeltaPx / width) * kDragWeight;
  final velocityPages = absV < kMinFlingVelocityPxPerSec
      ? 0.0
      : (-velocityPxPerSec / width) * kVelocityWeight;

  var delta = dragPages + velocityPages;

  // Always move at least one page when past the commit threshold (or when
  // fling velocity alone is strong enough), matching the old one-step swipe.
  if (delta.abs() < 0.5) {
    if (absV >= kMinFlingVelocityPxPerSec) {
      delta = velocityPxPerSec < 0 ? 1.0 : -1.0;
    } else {
      delta = dragDeltaPx < 0 ? 1.0 : -1.0;
    }
  }

  if (delta > kMaxSkipPages) delta = kMaxSkipPages.toDouble();
  if (delta < -kMaxSkipPages) delta = -kMaxSkipPages.toDouble();

  final projected = currentPage + delta;
  final target = projected.round();
  return _wrapIndex(target, pageCount);
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

/// Maps a fractional page offset to the two visible card indices + blend t.
///
/// [pageOffset] may be any real number; it is wrapped into `[0, pageCount)`.
/// When exactly on an integer page, [from] == [to] and [t] == 0.
/// Assumes forward travel (increasing offset).
PageBlend pageBlend({
  required double pageOffset,
  required int pageCount,
}) {
  if (pageCount <= 0) {
    return const PageBlend(from: 0, to: 0, t: 0, direction: 1);
  }
  if (pageCount == 1) {
    return const PageBlend(from: 0, to: 0, t: 0, direction: 1);
  }

  // Normalize into [0, pageCount).
  var offset = pageOffset % pageCount;
  if (offset < 0) offset += pageCount;

  final from = offset.floor() % pageCount;
  final frac = offset - offset.floor();

  if (frac < 1e-6) {
    return PageBlend(from: from, to: from, t: 0, direction: 1);
  }

  final to = (from + 1) % pageCount;
  return PageBlend(from: from, to: to, t: frac, direction: 1);
}

/// Like [pageBlend], but accounts for travel direction so a backward fling
/// (decreasing offset) blends from the higher index toward the lower one
/// with the correct outgoing/incoming assignment.
///
/// [direction] is the fling direction: +1 advancing, −1 going back.
PageBlend pageBlendDirected({
  required double pageOffset,
  required int pageCount,
  required int direction,
}) {
  if (pageCount <= 1 || direction >= 0) {
    return pageBlend(pageOffset: pageOffset, pageCount: pageCount);
  }

  // Traveling backward: floor is the destination, ceil is the source.
  var offset = pageOffset % pageCount;
  if (offset < 0) offset += pageCount;

  final floor = offset.floor() % pageCount;
  final frac = offset - offset.floor();

  if (frac < 1e-6 || frac > 1 - 1e-6) {
    final idx = frac > 0.5 ? (floor + 1) % pageCount : floor;
    return PageBlend(from: idx, to: idx, t: 0, direction: -1);
  }

  final ceil = (floor + 1) % pageCount;
  // t=0 at the start of the segment (on ceil), t=1 at the end (on floor).
  return PageBlend(from: ceil, to: floor, t: 1.0 - frac, direction: -1);
}

int _wrapIndex(int index, int pageCount) {
  if (pageCount <= 0) return 0;
  return ((index % pageCount) + pageCount) % pageCount;
}
