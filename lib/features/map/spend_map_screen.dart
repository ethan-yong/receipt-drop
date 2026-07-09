import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

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

/// Snap-style spend map: own spend bubbles (or heat overlay) plus friends'
/// avatar pins at their latest receipt place. Free CARTO raster basemap —
/// no API key; swap to a keyed provider (MapTiler/Stadia) at production
/// scale, and never ship tile.openstreetmap.org as the default.
class SpendMapScreen extends StatefulWidget {
  const SpendMapScreen({super.key});

  @override
  State<SpendMapScreen> createState() => _SpendMapScreenState();
}

class _SpendMapScreenState extends State<SpendMapScreen>
    with TickerProviderStateMixin {
  static const _malaysiaCenter = LatLng(3.1390, 101.6869);
  static const _tileUrl =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

  final MapController _mapController = MapController();
  final _panelController = DraggableScrollableController();
  String _timeFilter = 'This month';
  String _categoryFilter = 'All categories';
  var _heatmapMode = false;
  var _didAutoFit = false;

  List<FriendMapPin> _friendPins = const [];
  Position? _myPosition;
  AvatarConfig? _myAvatarConfig;
  MapPlaceCluster? _selectedCluster;
  AnimationController? _cameraAnim;

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
    _cameraAnim?.dispose();
    _cameraAnim = null;
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
    _mapController.move(LatLng(result.lat, result.lng), 15);
  }

  Future<void> _recenterOnMe() async {
    final pos = await getCurrentPositionOrNull();
    if (pos == null || !mounted) return;
    setState(() => _myPosition = pos);
    _animatedMapMove(LatLng(pos.latitude, pos.longitude), 14);
  }

  /// Smoothly glides the camera to [dest]/[destZoom] (flutter_map's `move`
  /// is instant; this is the standard tween recipe).
  void _animatedMapMove(LatLng dest, double destZoom) {
    _cameraAnim?.dispose();
    final camera = _mapController.camera;
    final latTween =
        Tween(begin: camera.center.latitude, end: dest.latitude);
    final lngTween =
        Tween(begin: camera.center.longitude, end: dest.longitude);
    final zoomTween = Tween(begin: camera.zoom, end: destZoom);

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _cameraAnim = controller;
    final anim = CurvedAnimation(parent: controller, curve: Curves.easeInOut);
    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(anim), lngTween.evaluate(anim)),
        zoomTween.evaluate(anim),
      );
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        if (identical(_cameraAnim, controller)) _cameraAnim = null;
        controller.dispose();
      }
    });
    controller.forward();
  }

  /// Google-Maps-style pin tap: open the half-screen panel and zoom in with
  /// the pin resting in the upper half (the panel covers the lower half).
  void _selectPlace(MapPlaceCluster cluster) {
    setState(() => _selectedCluster = cluster);
    const zoom = 16.5;
    final camera = _mapController.camera;
    final pin = LatLng(cluster.lat, cluster.lng);
    // Center the camera a quarter viewport south of the pin so the pin sits
    // ~25% from the top once the panel is up.
    final shifted = camera.unprojectAtZoom(
      camera.projectAtZoom(pin, zoom) +
          Offset(0, camera.nonRotatedSize.height * 0.25),
      zoom,
    );
    _animatedMapMove(shifted, zoom);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.single, 13);
      } else {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: points,
            padding: const EdgeInsets.all(64),
            maxZoom: 15,
          ),
        );
      }
    });
  }

  List<Marker> _placeMarkers(List<MapPlaceCluster> clusters) {
    return clusters.map((c) {
      return Marker(
        point: LatLng(c.lat, c.lng),
        width: 96,
        height: 56,
        // Bubble sits above the point; the tail tip is the anchor.
        alignment: Alignment.topCenter,
        child: SpendPlaceMarker(
          cluster: c,
          onTap: () => _selectPlace(c),
        ),
      );
    }).toList();
  }

  List<Marker> _friendMarkers() {
    return _friendPins.map((pin) {
      return Marker(
        point: LatLng(pin.lat, pin.lng),
        width: 72,
        height: 72,
        alignment: Alignment.topCenter,
        child: FriendMapMarker(
          pin: pin,
          onTap: () => FriendPinSheet.show(context, pin),
        ),
      );
    }).toList();
  }

  Marker? _myLocationMarker(List<TransactionView> allRows) {
    final pos = _myPosition;
    final config = _myAvatarConfig;
    if (pos == null || config == null) return null;
    final mood =
        deriveAvatarMood(todaysTransactions(allRows, DateTime.now()));
    return Marker(
      point: LatLng(pos.latitude, pos.longitude),
      width: 56,
      height: 56,
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

  List<CircleMarker> _heatCircles(List<TransactionView> rows) {
    final circles = <CircleMarker>[];
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
        CircleMarker(
          point: center,
          radius: 3200,
          useRadiusInMeter: true,
          color: color.withValues(alpha: 0.15),
        ),
      );
      circles.add(
        CircleMarker(
          point: center,
          radius: 1600,
          useRadiusInMeter: true,
          color: color.withValues(alpha: 0.35),
        ),
      );
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

          if (filtered.isEmpty && _friendPins.isEmpty) {
            return const EmptyState(
              title: 'No map data yet',
              subtitle:
                  'Share receipts with location or enable location when sharing to see spend bubbles.',
              mascotAsset: 'assets/branding/pug-empty-state.png',
            );
          }

          _autoFitOnce(clusters);
          final myMarker = _myLocationMarker(all);

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
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _malaysiaCenter,
                  initialZoom: 11,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  // Tapping bare map dismisses the place panel, like
                  // Google Maps.
                  onTap: (_, _) => _closePanel(),
                ),
                children: [
                  TileLayer(
                    urlTemplate: _tileUrl,
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.receiptdrop.receipt_drop',
                    retinaMode: RetinaMode.isHighDensity(context),
                    tileProvider: CancellableNetworkTileProvider(),
                    // Tile fetch failures are otherwise swallowed silently,
                    // which makes a dead basemap look like "still loading".
                    errorTileCallback: (tile, error, stackTrace) =>
                        debugPrint('Map tile failed: ${tile.coordinates} $error'),
                  ),
                  if (_heatmapMode)
                    CircleLayer(circles: _heatCircles(filtered)),
                  if (!_heatmapMode)
                    MarkerLayer(markers: _placeMarkers(clusters)),
                  MarkerLayer(
                    markers: [
                      ..._friendMarkers(),
                      ?myMarker,
                    ],
                  ),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution('© OpenStreetMap contributors'),
                      TextSourceAttribution('© CARTO'),
                    ],
                  ),
                ],
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
