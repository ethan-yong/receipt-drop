import 'dart:math' as math;

/// Screen-space point kept as a plain record (not `dart:ui Offset`) so this
/// file stays free of Flutter dependencies and is unit-testable without a
/// map platform view.
typedef ScreenPoint = ({double x, double y});

/// Groups place keys whose screen positions are within [thresholdPx] of each
/// other (transitively — union-find, so A-B-C close in a chain group
/// together even if A and C alone are far apart). Singletons come back as
/// their own one-element group.
///
/// [thresholdPx] defaults to ~half a typical spend-pill width so visually
/// stacked markers collapse into one overlap indicator.
List<List<String>> groupOverlappingKeys(
  Map<String, ScreenPoint> positions, {
  double thresholdPx = 56,
}) {
  final keys = positions.keys.toList();
  if (keys.isEmpty) return const [];

  final parent = List<int>.generate(keys.length, (i) => i);
  final rank = List<int>.filled(keys.length, 0);

  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra == rb) return;
    if (rank[ra] < rank[rb]) {
      parent[ra] = rb;
    } else if (rank[ra] > rank[rb]) {
      parent[rb] = ra;
    } else {
      parent[rb] = ra;
      rank[ra]++;
    }
  }

  final thresholdSq = thresholdPx * thresholdPx;
  for (var i = 0; i < keys.length; i++) {
    final a = positions[keys[i]]!;
    for (var j = i + 1; j < keys.length; j++) {
      final b = positions[keys[j]]!;
      final dx = a.x - b.x;
      final dy = a.y - b.y;
      if (dx * dx + dy * dy <= thresholdSq) {
        union(i, j);
      }
    }
  }

  final groups = <int, List<String>>{};
  for (var i = 0; i < keys.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(keys[i]);
  }
  return groups.values.toList();
}

/// Evenly spaced points on a circle of [radius] around (0, 0), starting at
/// the top and going clockwise — the spiderfy fan-out offsets for [count]
/// pins. Radius grows slightly with [count] so more pins don't crowd.
List<ScreenPoint> spiderfyOffsets(int count, {double baseRadius = 46}) {
  if (count <= 0) return const [];
  if (count == 1) return const [(x: 0.0, y: 0.0)];

  final radius = baseRadius + (count - 2) * 6.0;
  final out = <ScreenPoint>[];
  for (var i = 0; i < count; i++) {
    // Start at the top (−π/2) and go clockwise.
    final angle = -math.pi / 2 + (2 * math.pi * i) / count;
    out.add((x: radius * math.cos(angle), y: radius * math.sin(angle)));
  }
  return out;
}
