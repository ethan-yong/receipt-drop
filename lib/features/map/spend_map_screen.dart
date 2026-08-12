import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/platform/adaptive_sheet.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/current_location.dart';
import '../../core/utils/place_key.dart';
import '../../data/repositories/map_transactions_repository.dart';
import '../../data/repositories/places_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/map_aggregates.dart';
import '../../domain/logic/map_pin_layout.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/map_filter_chips.dart';
import '../../widgets/profile_photo.dart';
import 'widgets/friend_map_marker.dart';
import 'widgets/friend_pin_sheet.dart';
import 'widgets/overlap_stack_marker.dart';
import 'widgets/receipt_map_sheet.dart';
import 'widgets/spend_cluster_bubble.dart';
import 'widgets/spend_place_marker.dart';

/// Lightweight signature of "everything about the local dataset that could
/// change what pins the map should show" — id + sync status of every
/// location-bearing transaction. Used to detect a locally-relevant change
/// (new receipt, place edit landing, a background sync completing) without
/// comparing full [TransactionView] payloads. Deliberately excludes rows
/// with no location: an edit to an unrelated field on a placeless receipt
/// must not trigger a map refetch.
String mapRelevantFingerprint(List<TransactionView> rows) {
  return rows
      .where((t) => t.placeLat != null && t.placeLng != null)
      .map((t) => '${t.id}:${t.syncStatus}')
      .join(',');
}

/// Screen-pixel positions for the custom-widget pins, isolated in their own
/// `ChangeNotifier` so a reprojection pass (every camera-move frame) only
/// rebuilds the small overlay subtree listening to it, rather than the whole
/// screen's `StreamBuilder` — which would otherwise re-run the full
/// clustering/filtering pipeline on every single animation frame of a drag.
class _MapOverlayPositions extends ChangeNotifier {
  Map<String, Offset> placePos = const {};
  Map<String, Offset> bucketPos = const {};
  Map<String, Offset> friendPos = const {};
  Offset? mePos;

  void update({
    required Map<String, Offset> place,
    required Map<String, Offset> bucket,
    required Map<String, Offset> friend,
    Offset? me,
  }) {
    placePos = place;
    bucketPos = bucket;
    friendPos = friend;
    mePos = me;
    notifyListeners();
  }
}

/// Snap-style spend map: own spend bubbles (or heat overlay) plus friends'
/// avatar pins at their latest receipt place.
class SpendMapScreen extends StatefulWidget {
  const SpendMapScreen({super.key});

  @override
  State<SpendMapScreen> createState() => _SpendMapScreenState();
}

class _SpendMapScreenState extends State<SpendMapScreen>
    with TickerProviderStateMixin {
  static const _malaysiaCenter = LatLng(3.1390, 101.6869);

  GoogleMapController? _controller;
  final _panelController = DraggableScrollableController();
  final _overlayPositions = _MapOverlayPositions();
  String _timeFilter = 'This month';
  String _categoryFilter = 'All categories';
  var _heatmapMode = false;
  var _didAutoFit = false;

  List<FriendMapPin> _friendPins = const [];
  Position? _myPosition;
  String? _myAvatarUrl;
  String? _myDisplayName;
  MapPlaceCluster? _selectedCluster;

  /// Whether we've bumped [AdaptiveSheet.openCount] for the open pin sheet
  /// so MainShell hides the capture FAB + bottom tab bar. Tracked separately
  /// so select/close/dispose never double-increment or leak the count.
  bool _shellChromeHidden = false;

  /// Place keys of the overlap group currently expanded via spiderfy.
  /// `null` means nothing is expanded. Cleared on bare-map tap, when the
  /// live grouping no longer matches, or when zooming out to bucket mode.
  Set<String>? _spiderfiedGroup;

  /// Viewport-fetched rows backing the map's own-place clustering/heat data
  /// (see [MapTransactionsRepository]) — replaces streaming the user's
  /// entire local transaction history into clustering on every rebuild.
  /// Only refetched on `onCameraIdle`, gated by [_maybeFetchViewport]'s
  /// materially-changed-bounds/zoom-bucket guard.
  List<TransactionView> _viewportRows = const [];
  List<MapPlaceCluster> _lastClusters = const [];
  List<GeoBucket> _lastBuckets = const [];
  LatLngBox? _lastFetchedBounds;
  int? _lastZoomBucket;

  /// Bumped only when [_maybeFetchViewport] applies a genuine data refresh
  /// (never during camera movement) — the pin-overlay `AnimatedSwitcher`
  /// keys off this so it crossfades old/new markers instead of a hard cut.
  int _dataVersion = 0;
  List<LatLng> _bootstrapPlacePoints = const [];
  List<LatLng>? _pendingFitPoints;

  bool _reprojectScheduled = false;
  bool _reprojecting = false;
  bool _reprojectPending = false;

  /// Detects locally-relevant changes (new receipt, place edit, a background
  /// sync completing) via [mapRelevantFingerprint] and debounces a forced
  /// viewport refetch — otherwise the map only ever refreshes on camera
  /// movement, so returning to an already-mounted Map tab (kept alive by
  /// `StatefulShellRoute`) after saving elsewhere would show stale pins.
  StreamSubscription<List<TransactionView>>? _localSub;
  String? _lastFingerprint;
  Timer? _refetchDebounce;

  /// Whether the current zoom level is coarse enough that we render
  /// [GeoBucket] cluster bubbles instead of individual [MapPlaceCluster]
  /// pins. Mirrors whichever precision [_maybeFetchViewport] last fetched at.
  bool get _bucketMode =>
      (_lastZoomBucket ?? individualPinPrecision) != individualPinPrecision;

  @override
  void initState() {
    super.initState();
    SocialRepository.getFriendMapPins().then((pins) {
      if (mounted && pins.isNotEmpty) {
        setState(() => _friendPins = pins);
        _scheduleReproject();
      }
      _tryAutoFit();
    });
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      ProfileRepository.fetchProfileHeader(userId).then((header) {
        if (!mounted) return;
        setState(() {
          _myAvatarUrl = header.avatarUrl;
          _myDisplayName = header.displayName;
        });
      });
    }
    getCurrentPositionOrNull().then((pos) {
      if (mounted && pos != null) {
        setState(() => _myPosition = pos);
        _scheduleReproject();
      }
      _tryAutoFit();
    });
    // One-shot local read purely to bootstrap the initial camera auto-fit
    // before any viewport bounds exist yet — not a live subscription, so it
    // doesn't drive the map's ongoing clustering (that's [_viewportRows]).
    AppServices.transactions.watchAll().first.then((rows) {
      if (!mounted) return;
      final clusters = mapClusters(_categoryFiltered(_timeFiltered(rows)));
      _bootstrapPlacePoints = [for (final c in clusters) LatLng(c.lat, c.lng)];
      _tryAutoFit();
    });
    _localSub = AppServices.transactions.watchAll().listen(_onLocalTransactionsChanged);
  }

  /// See [_localSub] — debounces a forced viewport refetch whenever the
  /// local dataset's map-relevant fingerprint changes.
  void _onLocalTransactionsChanged(List<TransactionView> rows) {
    final fingerprint = mapRelevantFingerprint(rows);
    if (fingerprint == _lastFingerprint) return;
    _lastFingerprint = fingerprint;
    _refetchDebounce?.cancel();
    _refetchDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) unawaited(_maybeFetchViewport(force: true));
    });
  }

  @override
  void dispose() {
    _localSub?.cancel();
    _refetchDebounce?.cancel();
    _restoreShellChrome();
    _panelController.dispose();
    _overlayPositions.dispose();
    super.dispose();
  }

  void _hideShellChrome() {
    if (_shellChromeHidden) return;
    _shellChromeHidden = true;
    AdaptiveSheet.openCount.value++;
  }

  void _restoreShellChrome() {
    if (!_shellChromeHidden) return;
    _shellChromeHidden = false;
    AdaptiveSheet.openCount.value--;
  }

  List<TransactionView> _timeFiltered(List<TransactionView> rows) {
    final now = DateTime.now();
    final start = _timeFilter == 'This month'
        ? DateTime(now.year, now.month)
        : DateTime(now.year, now.month - 1);
    final end = _timeFilter == 'This month'
        ? DateTime(now.year, now.month + 1)
        : DateTime(now.year, now.month);

    return rows.where((t) {
      if (!t.includeInCharts) return false;
      if (t.occurredAt.isBefore(start) || !t.occurredAt.isBefore(end)) {
        return false;
      }
      return t.placeLat != null && t.placeLng != null;
    }).toList();
  }

  List<TransactionView> _categoryFiltered(List<TransactionView> rows) {
    if (_categoryFilter == 'All categories') return rows;
    return rows
        .where((t) => t.effectiveCategory == _categoryFilter)
        .toList();
  }

  Future<void> _openPlaceSearch() async {
    final result = await context.pushNamed<PlaceResult>('places-search');
    if (result == null || !mounted) return;
    _controller?.moveCamera(
      CameraUpdate.newLatLngZoom(LatLng(result.lat, result.lng), 15),
    );
  }

  Future<void> _recenterOnMe() async {
    final pos = await getCurrentPositionOrNull();
    if (pos == null || !mounted) return;
    setState(() => _myPosition = pos);
    _scheduleReproject();
    _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 14),
    );
  }

  /// Open the place-detail panel and zoom so the pin is centered on screen.
  void _selectPlace(MapPlaceCluster cluster) {
    setState(() => _selectedCluster = cluster);
    _hideShellChrome();
    const zoom = 16.5;
    final pin = LatLng(cluster.lat, cluster.lng);
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(pin, zoom));
  }

  /// Cluster-bubble tap: single-place buckets open the detail panel
  /// immediately; multi-place buckets fit the camera to the places inside
  /// the bucket (with edge padding) so every pin lands on-screen.
  void _selectBucket(GeoBucket bucket) {
    final precision = _lastZoomBucket ?? zoomBucketPrecision(11);
    final txsInBucket = _viewportRows.where((t) {
      if (!t.includeInCharts) return false;
      final lat = t.placeLat;
      final lng = t.placeLng;
      if (lat == null || lng == null) return false;
      return geohashAt(lat, lng, precision) == bucket.bucketKey;
    }).toList();

    final clusters = mapClusters(txsInBucket);
    if (clusters.length == 1) {
      _selectPlace(clusters.single);
      return;
    }

    var minLat = clusters.first.lat;
    var maxLat = clusters.first.lat;
    var minLng = clusters.first.lng;
    var maxLng = clusters.first.lng;
    for (final c in clusters.skip(1)) {
      if (c.lat < minLat) minLat = c.lat;
      if (c.lat > maxLat) maxLat = c.lat;
      if (c.lng < minLng) minLng = c.lng;
      if (c.lng > maxLng) maxLng = c.lng;
    }
    // newLatLngBounds needs real span; nearly co-located places get a
    // minimum box so the fit doesn't fail, and spiderfy disambiguates
    // once the camera settles at individual-pin zoom.
    const minSpanDeg = 0.0006; // ~65m
    if (maxLat - minLat < minSpanDeg) {
      final pad = minSpanDeg / 2;
      minLat -= pad;
      maxLat += pad;
    }
    if (maxLng - minLng < minSpanDeg) {
      final pad = minSpanDeg / 2;
      minLng -= pad;
      maxLng += pad;
    }
    _controller?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        // Larger than the 64px used for initial auto-fit — custom pill+tail
        // pins are taller than a native marker.
        80,
      ),
    );
  }

  void _closePanel() {
    if (_selectedCluster == null) return;
    setState(() => _selectedCluster = null);
    _restoreShellChrome();
  }

  void _clearSpiderfy() {
    if (_spiderfiedGroup == null) return;
    setState(() => _spiderfiedGroup = null);
  }

  void _onMapBackgroundTap() {
    _closePanel();
    _clearSpiderfy();
  }

  /// One-time camera fit over everything worth seeing (own places, friend
  /// pins, own position) once the first data arrives from whichever async
  /// source resolves first — retried (harmlessly, via [_didAutoFit]) from
  /// each of the three `initState` callbacks that can contribute a point.
  void _tryAutoFit() {
    if (_didAutoFit) return;
    final points = <LatLng>[
      ..._bootstrapPlacePoints,
      for (final p in _friendPins) LatLng(p.lat, p.lng),
      if (_myPosition != null)
        LatLng(_myPosition!.latitude, _myPosition!.longitude),
    ];
    if (points.isEmpty) return;
    _didAutoFit = true;
    _pendingFitPoints = points;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyPendingFitIfReady();
    });
  }

  /// `GoogleMapController` only exists once the platform view finishes
  /// creating, which can race with [_tryAutoFit] - this is called from both
  /// `onMapCreated` and the post-frame callback above, and no-ops until both
  /// the controller and a pending fit are ready.
  void _applyPendingFitIfReady() {
    final controller = _controller;
    final points = _pendingFitPoints;
    if (controller == null || points == null) return;
    _pendingFitPoints = null;
    if (points.length == 1) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(points.single, 13));
      return;
    }
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        64,
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    _applyPendingFitIfReady();
    _scheduleReproject();
    unawaited(_maybeFetchViewport(force: true));
  }

  void _onCameraIdle() {
    _scheduleReproject();
    unawaited(_maybeFetchViewport());
  }

  /// Coalesces however many camera-move ticks land in one frame into a
  /// single reprojection pass, instead of one `getScreenCoordinate`
  /// platform-channel call per pin per tick (which would jank the drag).
  void _scheduleReproject([CameraPosition? _]) {
    if (_reprojectScheduled) return;
    _reprojectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reprojectScheduled = false;
      if (mounted) _reproject();
    });
  }

  /// Fetches the transactions inside the current camera viewport via
  /// [MapTransactionsRepository] and recomputes place/bucket clustering from
  /// them — only called from `onCameraIdle`/`onMapCreated`/filter changes,
  /// never on every camera-move frame. Guarded so tiny settle-jitter near the
  /// idle threshold doesn't refire redundant queries.
  Future<void> _maybeFetchViewport({bool force = false}) async {
    final controller = _controller;
    if (controller == null) return;
    final region = await controller.getVisibleRegion();
    final zoom = await controller.getZoomLevel();
    if (!mounted) return;

    final bounds = (
      minLat: region.southwest.latitude,
      minLng: region.southwest.longitude,
      maxLat: region.northeast.latitude,
      maxLng: region.northeast.longitude,
    );
    final bucket = zoomBucketPrecision(zoom);
    final lastBounds = _lastFetchedBounds;
    final shouldFetch = force ||
        lastBounds == null ||
        bucket != _lastZoomBucket ||
        boundsChangedMaterially(lastBounds, bounds);
    if (!shouldFetch) return;

    final now = DateTime.now();
    final start = _timeFilter == 'This month'
        ? DateTime(now.year, now.month)
        : DateTime(now.year, now.month - 1);
    final end = _timeFilter == 'This month'
        ? DateTime(now.year, now.month + 1)
        : DateTime(now.year, now.month);
    final category =
        _categoryFilter == 'All categories' ? null : _categoryFilter;

    // Fetch a padded margin beyond the visible region so a small pan
    // afterward already has data available — but keep `_lastFetchedBounds`
    // (below) as the raw, unpadded region: comparing padded-vs-raw bounds
    // next time would make `boundsChangedMaterially` misread the size
    // difference itself as camera movement and refetch on almost every idle.
    final paddedBounds = expandBounds(bounds);
    final rows = await MapTransactionsRepository.fetchInBounds(
      minLat: paddedBounds.minLat,
      minLng: paddedBounds.minLng,
      maxLat: paddedBounds.maxLat,
      maxLng: paddedBounds.maxLng,
      startAt: start,
      endAt: end,
      category: category,
    );
    if (!mounted) return;
    // `null` means the fetch failed (e.g. offline) — keep showing the
    // last-known-good clusters rather than clearing the map.
    if (rows == null) return;

    _lastFetchedBounds = bounds;
    _lastZoomBucket = bucket;
    setState(() {
      // Only bumped on a genuine data refresh (never during camera
      // movement) — the pin-overlay AnimatedSwitcher keys off this to
      // crossfade old/new markers instead of hard-cutting between them.
      _dataVersion++;
      _viewportRows = rows;
      _lastClusters = bucket == individualPinPrecision ? mapClusters(rows) : const [];
      _lastBuckets =
          bucket == individualPinPrecision ? const [] : bucketClusters(rows, bucket);
      // Spiderfy only applies in individual-pin mode.
      if (bucket != individualPinPrecision) {
        _spiderfiedGroup = null;
      }
    });
    _scheduleReproject();
  }

  /// Re-derives on-screen positions for every custom-widget pin
  /// (`SpendPlaceMarker`/`SpendClusterBubble`/`FriendMapMarker`/"you are
  /// here") via `GoogleMapController.getScreenCoordinate`, since
  /// `google_maps_flutter`'s native `Marker` can't host arbitrary widgets.
  /// Batches every pin into one `Future.wait` so drag/pinch stays smooth,
  /// and folds in any reproject request that arrives while a batch is
  /// already in flight rather than piling up unbounded work. Writes results
  /// into [_overlayPositions] (a `ChangeNotifier`), never `setState` — so
  /// this never triggers the outer `StreamBuilder`'s expensive rebuild.
  Future<void> _reproject() async {
    final controller = _controller;
    if (controller == null) return;
    if (_reprojecting) {
      _reprojectPending = true;
      return;
    }
    _reprojecting = true;
    try {
      final bucketMode = _bucketMode;
      final placeKeys =
          bucketMode ? const <String>[] : [for (final c in _lastClusters) c.placeKey];
      final bucketKeys =
          bucketMode ? [for (final b in _lastBuckets) b.bucketKey] : const <String>[];
      final friendKeys = [for (final p in _friendPins) p.userId];
      final me = _myPosition;

      final futures = <Future<ScreenCoordinate>>[
        if (bucketMode)
          for (final b in _lastBuckets)
            controller.getScreenCoordinate(LatLng(b.lat, b.lng))
        else
          for (final c in _lastClusters)
            controller.getScreenCoordinate(LatLng(c.lat, c.lng)),
        for (final p in _friendPins)
          controller.getScreenCoordinate(LatLng(p.lat, p.lng)),
        if (me != null)
          controller.getScreenCoordinate(LatLng(me.latitude, me.longitude)),
      ];

      if (futures.isEmpty) {
        if (mounted) {
          _overlayPositions.update(
            place: const {},
            bucket: const {},
            friend: const {},
            me: null,
          );
        }
        return;
      }

      List<ScreenCoordinate> resolved;
      try {
        resolved = await Future.wait(futures);
      } catch (_) {
        // Controller likely disposed mid-flight (screen popped); drop this
        // batch, nothing left to update.
        return;
      }
      if (!mounted) return;

      final dpr = MediaQuery.devicePixelRatioOf(context);
      var i = 0;
      final newPlacePos = <String, Offset>{};
      for (final key in placeKeys) {
        newPlacePos[key] = Offset(resolved[i].x / dpr, resolved[i].y / dpr);
        i++;
      }
      final newBucketPos = <String, Offset>{};
      for (final key in bucketKeys) {
        newBucketPos[key] = Offset(resolved[i].x / dpr, resolved[i].y / dpr);
        i++;
      }
      final newFriendPos = <String, Offset>{};
      for (final key in friendKeys) {
        newFriendPos[key] = Offset(resolved[i].x / dpr, resolved[i].y / dpr);
        i++;
      }
      final newMePos =
          me != null ? Offset(resolved[i].x / dpr, resolved[i].y / dpr) : null;

      _overlayPositions.update(
        place: newPlacePos,
        bucket: newBucketPos,
        friend: newFriendPos,
        me: newMePos,
      );
    } finally {
      _reprojecting = false;
      if (_reprojectPending) {
        _reprojectPending = false;
        unawaited(_reproject());
      }
    }
  }

  List<Widget> _placeOverlays(
    List<MapPlaceCluster> clusters,
    Map<String, Offset> positions,
  ) {
    final byKey = {for (final c in clusters) c.placeKey: c};
    final screenPoints = <String, ScreenPoint>{
      for (final e in positions.entries)
        if (byKey.containsKey(e.key)) e.key: (x: e.value.dx, y: e.value.dy),
    };
    final groups = groupOverlappingKeys(screenPoints);

    // Drop a spiderfy that no longer matches any live overlap group
    // (zoom/pan separated the pins, or a place left the viewport).
    var spiderfied = _spiderfiedGroup;
    if (spiderfied != null) {
      final stillValid = groups.any((g) {
        final set = g.toSet();
        return set.length == spiderfied!.length &&
            set.containsAll(spiderfied);
      });
      if (!stillValid) {
        spiderfied = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _clearSpiderfy();
        });
      }
    }

    final widgets = <Widget>[];
    for (final groupKeys in groups) {
      if (groupKeys.length == 1) {
        final key = groupKeys.single;
        final c = byKey[key];
        final pos = positions[key];
        if (c == null || pos == null) continue;
        widgets.add(Positioned(
          left: pos.dx - 48,
          top: pos.dy - 56,
          child: SpendPlaceMarker(
            cluster: c,
            onTap: () => _selectPlace(c),
          ),
        ));
        continue;
      }

      final members = <MapPlaceCluster>[
        for (final k in groupKeys)
          if (byKey[k] != null) byKey[k]!,
      ];
      if (members.length < 2) continue;

      var cx = 0.0;
      var cy = 0.0;
      for (final k in groupKeys) {
        final p = positions[k]!;
        cx += p.dx;
        cy += p.dy;
      }
      cx /= groupKeys.length;
      cy /= groupKeys.length;

      final groupId = (groupKeys.toList()..sort()).join('|');
      final isExpanded = spiderfied != null &&
          spiderfied.length == groupKeys.length &&
          spiderfied.containsAll(groupKeys);

      // Dominant category ≈ highest-spend place in the group (cheap proxy).
      final dominant = members.reduce(
        (a, b) => a.totalSpend >= b.totalSpend ? a : b,
      );

      final offsets = spiderfyOffsets(members.length);
      // Match spiderfyOffsets radius growth: base 46 + (n-2)*6.
      final radius = 46.0 + (members.length - 2) * 6.0;
      // Room for pill+tail (~56 tall) beyond the fan-out radius.
      final extent = radius + 60.0;

      widgets.add(Positioned(
        left: cx - extent,
        top: cy - extent,
        width: extent * 2,
        height: extent * 2,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: anim, child: child),
          ),
          child: isExpanded
              ? Stack(
                  key: ValueKey('expanded-$groupId'),
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(
                      size: Size(extent * 2, extent * 2),
                      painter: _SpiderfyLegsPainter(
                        center: Offset(extent, extent),
                        offsets: [
                          for (final o in offsets) Offset(o.x, o.y),
                        ],
                        color: AppColors.categoryColor(dominant.dominantCategory)
                            .withValues(alpha: 0.45),
                      ),
                    ),
                    for (var i = 0; i < members.length; i++)
                      Positioned(
                        left: extent + offsets[i].x - 48,
                        top: extent + offsets[i].y - 56,
                        child: SpendPlaceMarker(
                          cluster: members[i],
                          onTap: () => _selectPlace(members[i]),
                        ),
                      ),
                  ],
                )
              : Align(
                  key: ValueKey('collapsed-$groupId'),
                  // Tail tip at the geographic center (box midpoint).
                  alignment: const Alignment(0, 0.15),
                  child: OverlapStackMarker(
                    count: members.length,
                    dominantCategory: dominant.dominantCategory,
                    onTap: () => setState(
                      () => _spiderfiedGroup = groupKeys.toSet(),
                    ),
                  ),
                ),
        ),
      ));
    }
    return widgets;
  }

  List<Widget> _bucketOverlays(
    List<GeoBucket> buckets,
    Map<String, Offset> positions,
  ) {
    final widgets = <Widget>[];
    for (final b in buckets) {
      final pos = positions[b.bucketKey];
      if (pos == null) continue;
      widgets.add(Positioned(
        left: pos.dx - 54,
        top: pos.dy - 60,
        child: SpendClusterBubble(
          bucket: b,
          onTap: () => _selectBucket(b),
        ),
      ));
    }
    return widgets;
  }

  List<Widget> _friendOverlays(Map<String, Offset> positions) {
    final widgets = <Widget>[];
    for (final p in _friendPins) {
      final pos = positions[p.userId];
      if (pos == null) continue;
      widgets.add(Positioned(
        left: pos.dx - 36,
        top: pos.dy - 72,
        child: FriendMapMarker(
          pin: p,
          onTap: () => FriendPinSheet.show(context, p),
        ),
      ));
    }
    return widgets;
  }

  Widget? _myLocationOverlay(Offset? pos) {
    if (pos == null) return null;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return Positioned(
      left: pos.dx - 28,
      top: pos.dy - 28,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.primaryGreen,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ProfilePhoto(
          size: 44,
          avatarUrl: _myAvatarUrl,
          displayName: _myDisplayName,
          userId: userId,
        ),
      ),
    );
  }

  Set<Circle> _heatCircles(List<TransactionView> rows) {
    final circles = <Circle>{};
    var i = 0;
    for (final cell in heatCells(rows)) {
      final color = Color.lerp(
        AppColors.impactLow,
        AppColors.impactHigh,
        cell.intensity,
      )!;
      final center = LatLng(cell.lat, cell.lng);
      // Soft outer glow + stronger core reads like a heat blob instead of
      // the old single flat circle.
      circles.add(
        Circle(
          circleId: CircleId('heat-outer-$i'),
          center: center,
          radius: 3200,
          fillColor: color.withValues(alpha: 0.15),
          strokeWidth: 0,
        ),
      );
      circles.add(
        Circle(
          circleId: CircleId('heat-inner-$i'),
          center: center,
          radius: 1600,
          fillColor: color.withValues(alpha: 0.35),
          strokeWidth: 0,
        ),
      );
      i++;
    }
    return circles;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: StreamBuilder<List<TransactionView>>(
        stream: AppServices.transactions.watchAll(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? [];
          final timeFiltered = _timeFiltered(all);
          final categories = mapCategories(timeFiltered);
          if (!categories.contains(_categoryFilter)) {
            _categoryFilter = 'All categories';
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_maybeFetchViewport(force: true));
            });
          }

          // Re-resolve the selection against the live viewport clusters so
          // the panel always shows fresh data — and closes if its place
          // vanished (filter change, deletion, zoomed out past pin level).
          MapPlaceCluster? selected;
          if (_selectedCluster != null) {
            for (final c in _lastClusters) {
              if (c.placeKey == _selectedCluster!.placeKey) {
                selected = c;
                break;
              }
            }
            if (selected == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _closePanel();
              });
            }
          }

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: _malaysiaCenter,
                  zoom: 11,
                ),
                onMapCreated: _onMapCreated,
                // Tapping bare map dismisses the place panel and any
                // open spiderfy, like Google Maps.
                onTap: (_) => _onMapBackgroundTap(),
                onCameraMove: _scheduleReproject,
                onCameraIdle: _onCameraIdle,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                circles: _heatmapMode ? _heatCircles(_viewportRows) : const {},
              ),
              // Isolated so a reprojection pass (every camera-move frame)
              // only rebuilds this subtree, not the outer StreamBuilder.
              AnimatedBuilder(
                animation: _overlayPositions,
                builder: (context, _) => Stack(
                  children: [
                    // Keyed on `_dataVersion`, which only changes on a
                    // genuine viewport-data refresh (never on a camera-move
                    // frame, since this same AnimatedBuilder rebuild passes
                    // an unchanged key then) — so old/new marker sets
                    // crossfade instead of hard-cutting, without this
                    // transition ever firing mid-drag.
                    if (!_heatmapMode)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 120),
                        child: KeyedSubtree(
                          key: ValueKey(_dataVersion),
                          child: Stack(
                            children: _bucketMode
                                ? _bucketOverlays(
                                    _lastBuckets, _overlayPositions.bucketPos)
                                : _placeOverlays(
                                    _lastClusters, _overlayPositions.placePos),
                          ),
                        ),
                      ),
                    ..._friendOverlays(_overlayPositions.friendPos),
                    ?_myLocationOverlay(_overlayPositions.mePos),
                  ],
                ),
              ),
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              readOnly: true,
                              decoration: InputDecoration(
                                hintText: 'Search places',
                                prefixIcon: const Icon(Icons.search),
                                filled: true,
                                fillColor: AppColors.cardSurface,
                              ),
                              onTap: _openPlaceSearch,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Material(
                            color: AppColors.cardSurface,
                            shape: const CircleBorder(),
                            child: IconButton(
                              icon: Icon(
                                _heatmapMode ? Icons.layers : Icons.layers_outlined,
                                color: _heatmapMode
                                    ? AppColors.primaryGreenDark
                                    : AppColors.textPrimary,
                              ),
                              tooltip: _heatmapMode
                                  ? 'Show personal markers'
                                  : 'Show spend heatmap',
                              onPressed: () =>
                                  setState(() => _heatmapMode = !_heatmapMode),
                            ),
                          ),
                        ],
                      ),
                    ),
                    MapFilterChips(
                      selectedTime: _timeFilter,
                      onTimeChanged: (v) {
                        setState(() => _timeFilter = v);
                        unawaited(_maybeFetchViewport(force: true));
                      },
                      categories: categories,
                      selectedCategory: _categoryFilter,
                      onCategoryChanged: (v) {
                        setState(() => _categoryFilter = v);
                        unawaited(_maybeFetchViewport(force: true));
                      },
                    ),
                  ],
                ),
              ),
              if (selected == null)
                Positioned(
                  right: AppSpacing.md,
                  // Clear the notched bottom bar (MainShell uses extendBody).
                  bottom: MediaQuery.viewPaddingOf(context).bottom + 96,
                  child: Material(
                    color: AppColors.cardSurface,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      icon: const Icon(
                        Icons.my_location,
                        color: AppColors.textPrimary,
                      ),
                      tooltip: 'Recenter on me',
                      onPressed: _recenterOnMe,
                    ),
                  ),
                ),
              if (selected != null)
                ReceiptMapSheet(
                  cluster: selected,
                  controller: _panelController,
                  onClose: _closePanel,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Thin "legs" from a spiderfy group's shared center out to each spread pin,
/// so it's clear which real map point the fanned-out markers came from.
class _SpiderfyLegsPainter extends CustomPainter {
  const _SpiderfyLegsPainter({
    required this.center,
    required this.offsets,
    required this.color,
  });

  final Offset center;
  final List<Offset> offsets;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final o in offsets) {
      canvas.drawLine(center, center + o, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpiderfyLegsPainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.color != color ||
      oldDelegate.offsets.length != offsets.length;
}
