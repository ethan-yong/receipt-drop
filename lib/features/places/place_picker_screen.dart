import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/places_repository.dart';
import '../../domain/logic/merchant_extractor.dart';

/// Signature of the nearby-candidate fetch function. Matches
/// [PlacesRepository.fetchNearbyCandidates] exactly so tests can inject a
/// synchronous stub without modifying production call sites.
typedef NearbyFetcher = Future<List<PlaceCandidate>> Function({
  required double lat,
  required double lng,
  List<MerchantCandidate> candidates,
  String? merchantName,
  String? category,
  int limit,
});

/// Full-screen location picker: shows top nearby place candidates ranked by
/// the same text+distance scoring the enrichment pipeline uses.
///
/// Opened via [push], which bypasses go_router so it works from inside a
/// modal bottom sheet (AdaptiveSheet / showModalBottomSheet).
class PlacePickerScreen extends StatefulWidget {
  const PlacePickerScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.candidates,
    this.merchantName,
    this.category,
    @visibleForTesting this.candidatesFetcher,
    @visibleForTesting this.tileProvider,
  });

  final double lat;
  final double lng;
  final List<MerchantCandidate> candidates;
  final String? merchantName;
  final String? category;

  /// Override the fetch implementation in widget tests to avoid network calls.
  @visibleForTesting
  final NearbyFetcher? candidatesFetcher;

  /// Override the tile provider in widget tests to avoid HTTP requests.
  @visibleForTesting
  final TileProvider? tileProvider;

  static Future<PlaceResult?> push(
    BuildContext context, {
    required double lat,
    required double lng,
    List<MerchantCandidate> candidates = const [],
    String? merchantName,
    String? category,
  }) {
    return Navigator.of(context, rootNavigator: true).push<PlaceResult?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlacePickerScreen(
          lat: lat,
          lng: lng,
          candidates: candidates,
          merchantName: merchantName,
          category: category,
        ),
      ),
    );
  }

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen>
    with TickerProviderStateMixin {
  static const _tileUrl =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

  final _mapController = MapController();
  AnimationController? _cameraAnim;

  List<PlaceCandidate> _results = const [];
  bool _loading = true;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _fetchCandidates();
  }

  @override
  void dispose() {
    _cameraAnim?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _fetchCandidates() async {
    final fetch =
        widget.candidatesFetcher ?? PlacesRepository.fetchNearbyCandidates;
    final results = await fetch(
      lat: widget.lat,
      lng: widget.lng,
      candidates: widget.candidates,
      merchantName: widget.merchantName,
      category: widget.category,
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
      if (results.isNotEmpty) _selectedIndex = 0;
    });
    if (results.isNotEmpty) {
      // Move the camera to the top candidate after the map has been built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(
            LatLng(results[0].lat, results[0].lng),
            17,
          );
        }
      });
    }
  }

  void _selectCandidate(int index) {
    setState(() => _selectedIndex = index);
    final c = _results[index];
    _animatedMapMove(LatLng(c.lat, c.lng), 17);
  }

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

  void _confirm() {
    final i = _selectedIndex;
    if (i == null || i >= _results.length) return;
    Navigator.of(context).pop(_results[i].toPlaceResult());
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Choose location')),
      body: Column(
        children: [
          Expanded(
            flex: 55,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(widget.lat, widget.lng),
                initialZoom: 16,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: _tileUrl,
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.receiptdrop.receipt_drop',
                  retinaMode: RetinaMode.isHighDensity(context),
                  tileProvider: widget.tileProvider ??
                      CancellableNetworkTileProvider(),
                  errorTileCallback: (tile, error, stackTrace) =>
                      debugPrint(
                          'Map tile failed: ${tile.coordinates} $error'),
                ),
                if (selected != null && selected < _results.length)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          _results[selected].lat,
                          _results[selected].lng,
                        ),
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
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
          ),
          Expanded(
            flex: 45,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? _EmptyState(
                        onSearchManually: () =>
                            Navigator.of(context).pop(null),
                      )
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (separatorContext, separatorIndex) =>
                            const Divider(
                          height: 1,
                          indent: AppSpacing.lg,
                          endIndent: AppSpacing.lg,
                        ),
                        itemBuilder: (context, i) {
                          final c = _results[i];
                          final isSelected = i == selected;
                          final distLabel = c.distanceMeters < 1000
                              ? '${c.distanceMeters.round()} m'
                              : '${(c.distanceMeters / 1000).toStringAsFixed(1)} km';
                          return ListTile(
                            tileColor: isSelected
                                ? theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.35)
                                : null,
                            title: Text(
                              c.name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: c.address.isNotEmpty
                                ? Text(
                                    c.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  )
                                : null,
                            trailing: Text(
                              distLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            onTap: () => _selectCandidate(i),
                          );
                        },
                      ),
          ),
          if (!_loading && _results.isNotEmpty)
            Material(
              elevation: 8,
              color: AppColors.cardSurface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selected != null ? _confirm : null,
                      child: const Text('Confirm'),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSearchManually});

  final VoidCallback onSearchManually;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No nearby places found',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: onSearchManually,
              child: const Text('Search by name instead'),
            ),
          ],
        ),
      ),
    );
  }
}
