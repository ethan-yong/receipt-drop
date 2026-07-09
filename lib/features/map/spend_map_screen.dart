import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/current_location.dart';
import '../../data/repositories/avatar_repository.dart';
import '../../data/repositories/places_repository.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/avatar_mood.dart';
import '../../domain/logic/dashboard_aggregates.dart';
import '../../domain/models/avatar_config.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/blob_avatar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/map_filter_chips.dart';
import 'widgets/friend_map_marker.dart';
import 'widgets/friend_pin_sheet.dart';
import 'widgets/place_detail_panel.dart';
import 'widgets/spend_place_marker.dart';

/// Standard Web Mercator tile-pixel projection (256px tiles, doubling per
/// zoom level) — mirrors the maths `flutter_map`'s `MapCamera.projectAtZoom`
/// used internally. `google_maps_flutter` has no client-side equivalent, so
/// it's reimplemented here purely for the "shift the pin up a quarter
/// viewport" trick in `_selectPlace` — kept as synchronous math rather than
/// an async `getScreenCoordinate` round trip, since that API is tied to the
/// *current* camera/zoom, not the *target* zoom being animated to.
Offset _mercatorProject(LatLng point, double zoom) {
  final scale = 256.0 * math.pow(2, zoom);
  final x = (point.longitude + 180) / 360 * scale;
  final sinLat =
      math.sin(point.latitude * math.pi / 180).clamp(-0.9999, 0.9999);
  final y =
      (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * scale;
  return Offset(x, y);
}

LatLng _mercatorUnproject(Offset point, double zoom) {
  final scale = 256.0 * math.pow(2, zoom);
  final lng = point.dx / scale * 360 - 180;
  final n = math.pi - 2 * math.pi * point.dy / scale;
  final lat = 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  return LatLng(lat, lng);
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
  String _timeFilter = 'This month';
  String _categoryFilter = 'All categories';
  var _heatmapMode = false;
  var _didAutoFit = false;

  List<FriendMapPin> _friendPins = const [];
  Position? _myPosition;
  AvatarConfig? _myAvatarConfig;
  MapPlaceCluster? _selectedCluster;

  /// Latest clusters from the stream, cached so the async reprojection pass
  /// (which runs outside `build`) always has the current pin set.
  List<MapPlaceCluster> _lastClusters = const [];
  List<LatLng>? _pendingFitPoints;

  /// Screen-pixel (logical) positions for the custom-widget pins, since
  /// `google_maps_flutter`'s native `Marker` can only host a static bitmap,
  /// not an arbitrary widget. Recomputed by [_reproject].
  Map<String, Offset> _placeScreenPos = {};
  Map<String, Offset> _friendScreenPos = {};
  Offset? _meScreenPos;
  bool _reprojectScheduled = false;
  bool _reprojecting = false;
  bool _reprojectPending = false;

  @override
  void initState() {
    super.initState();
    SocialRepository.getFriendMapPins().then((pins) {
      if (mounted && pins.isNotEmpty) setState(() => _friendPins = pins);
    });
    AvatarRepository.getAvatarConfig().then((config) {
      if (mounted) setState(() => _myAvatarConfig = config);
    });
    getCurrentPositionOrNull().then((pos) {
      if (mounted && pos != null) setState(() => _myPosition = pos);
    });
  }

  @override
  void dispose() {
    _panelController.dispose();
    super.dispose();
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
    _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 14),
    );
  }

  /// Google-Maps-style pin tap: open the half-screen panel and zoom in with
  /// the pin resting in the upper half (the panel covers the lower half).
  void _selectPlace(MapPlaceCluster cluster) {
    setState(() => _selectedCluster = cluster);
    const zoom = 16.5;
    final pin = LatLng(cluster.lat, cluster.lng);
    // Center the camera a quarter viewport south of the pin so the pin sits
    // ~25% from the top once the panel is up.
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final shifted = _mercatorUnproject(
      _mercatorProject(pin, zoom) + Offset(0, viewportHeight * 0.25),
      zoom,
    );
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(shifted, zoom));
  }

  void _closePanel() {
    if (_selectedCluster == null) return;
    setState(() => _selectedCluster = null);
  }

  /// One-time camera fit over everything worth seeing (own places, friend
  /// pins, own position) once the first data arrives.
  void _autoFitOnce(List<MapPlaceCluster> clusters) {
    if (_didAutoFit) return;
    final points = <LatLng>[
      for (final c in clusters) LatLng(c.lat, c.lng),
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
  /// creating, which can race with the first stream emission — this is
  /// called from both `onMapCreated` and the post-frame callback above, and
  /// no-ops until both the controller and a pending fit are ready.
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

  /// Re-derives on-screen positions for every custom-widget pin
  /// (`SpendPlaceMarker`/`FriendMapMarker`/"you are here") via
  /// `GoogleMapController.getScreenCoordinate`, since `google_maps_flutter`'s
  /// native `Marker` can't host arbitrary widgets. Batches every pin into one
  /// `Future.wait` so drag/pinch stays smooth, and folds in any reproject
  /// request that arrives while a batch is already in flight rather than
  /// piling up unbounded work.
  Future<void> _reproject() async {
    final controller = _controller;
    if (controller == null) return;
    if (_reprojecting) {
      _reprojectPending = true;
      return;
    }
    _reprojecting = true;
    try {
      final placeKeys = [for (final c in _lastClusters) c.placeKey];
      final friendKeys = [for (final p in _friendPins) p.userId];
      final me = _myPosition;

      final futures = <Future<ScreenCoordinate>>[
        for (final c in _lastClusters)
          controller.getScreenCoordinate(LatLng(c.lat, c.lng)),
        for (final p in _friendPins)
          controller.getScreenCoordinate(LatLng(p.lat, p.lng)),
        if (me != null)
          controller.getScreenCoordinate(LatLng(me.latitude, me.longitude)),
      ];

      if (futures.isEmpty) {
        if (mounted) {
          setState(() {
            _placeScreenPos = {};
            _friendScreenPos = {};
            _meScreenPos = null;
          });
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
      final newFriendPos = <String, Offset>{};
      for (final key in friendKeys) {
        newFriendPos[key] = Offset(resolved[i].x / dpr, resolved[i].y / dpr);
        i++;
      }
      final newMePos =
          me != null ? Offset(resolved[i].x / dpr, resolved[i].y / dpr) : null;

      setState(() {
        _placeScreenPos = newPlacePos;
        _friendScreenPos = newFriendPos;
        _meScreenPos = newMePos;
      });
    } finally {
      _reprojecting = false;
      if (_reprojectPending) {
        _reprojectPending = false;
        unawaited(_reproject());
      }
    }
  }

  List<Widget> _placeOverlays(List<MapPlaceCluster> clusters) {
    final widgets = <Widget>[];
    for (final c in clusters) {
      final pos = _placeScreenPos[c.placeKey];
      if (pos == null) continue;
      // Bubble sits above the point; the tail tip is the anchor (96×56 box,
      // point at bottom-center).
      widgets.add(Positioned(
        left: pos.dx - 48,
        top: pos.dy - 56,
        child: SpendPlaceMarker(
          cluster: c,
          onTap: () => _selectPlace(c),
        ),
      ));
    }
    return widgets;
  }

  List<Widget> _friendOverlays() {
    final widgets = <Widget>[];
    for (final p in _friendPins) {
      final pos = _friendScreenPos[p.userId];
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

  Widget? _myLocationOverlay(List<TransactionView> allRows) {
    final pos = _meScreenPos;
    final config = _myAvatarConfig;
    if (pos == null || config == null) return null;
    final mood =
        deriveAvatarMood(todaysTransactions(allRows, DateTime.now()));
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
        child: RepaintBoundary(
          child: BlobAvatar(
            mood: mood,
            config: config,
            size: 44,
            animate: false,
          ),
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
          }
          final filtered = _categoryFiltered(timeFiltered);
          final clusters = mapClusters(filtered);
          _lastClusters = clusters;

          if (filtered.isEmpty && _friendPins.isEmpty) {
            return const EmptyState(
              title: 'No map data yet',
              subtitle:
                  'Share receipts with location or enable location when sharing to see spend bubbles.',
              mascotAsset: 'assets/branding/pug-empty-state.png',
            );
          }

          _autoFitOnce(clusters);
          // Data changed (new stream emission) — pin positions may be stale
          // or missing for newly-appeared pins, not just after camera moves.
          _scheduleReproject();
          final myOverlay = _myLocationOverlay(all);

          // Re-resolve the selection against the live stream so the panel
          // always shows fresh data — and closes if its place vanished
          // (filter change, deletion).
          MapPlaceCluster? selected;
          if (_selectedCluster != null) {
            for (final c in clusters) {
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
                // Tapping bare map dismisses the place panel, like
                // Google Maps.
                onTap: (_) => _closePanel(),
                onCameraMove: _scheduleReproject,
                onCameraIdle: _scheduleReproject,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                circles: _heatmapMode ? _heatCircles(filtered) : const {},
              ),
              if (!_heatmapMode) ..._placeOverlays(clusters),
              ..._friendOverlays(),
              ?myOverlay,
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
                      onTimeChanged: (v) => setState(() => _timeFilter = v),
                      categories: categories,
                      selectedCategory: _categoryFilter,
                      onCategoryChanged: (v) =>
                          setState(() => _categoryFilter = v),
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
                PlaceDetailPanel(
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
