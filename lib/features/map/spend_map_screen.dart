import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/place_key.dart';
import '../../data/repositories/places_repository.dart';
import '../../domain/logic/dashboard_aggregates.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/map_filter_chips.dart';
import '../../widgets/spend_map_bottom_sheet.dart';

/// Malaysia-default spend map with personal markers or spend heatmap.
class SpendMapScreen extends StatefulWidget {
  const SpendMapScreen({super.key});

  @override
  State<SpendMapScreen> createState() => _SpendMapScreenState();
}

class _SpendMapScreenState extends State<SpendMapScreen> {
  static const _malaysiaCenter = LatLng(3.1390, 101.6869);

  GoogleMapController? _mapController;
  String _timeFilter = 'This month';
  String _categoryFilter = 'All categories';
  var _heatmapMode = false;

  Set<Marker> _buildMarkers(List<MapPlaceCluster> clusters) {
    return clusters.map((c) {
      return Marker(
        markerId: MarkerId(c.placeKey),
        position: LatLng(c.lat, c.lng),
        onTap: () => SpendMapBottomSheet.show(context, c),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueYellow,
        ),
        infoWindow: InfoWindow(
          title: c.displayName,
          snippet: 'RM ${c.totalSpend.toStringAsFixed(0)}',
        ),
      );
    }).toSet();
  }

  Set<Circle> _buildHeatmapCircles(List<TransactionView> rows) {
    final totals = <String, double>{};
    for (final t in rows) {
      final lat = t.placeLat;
      final lng = t.placeLng;
      if (lat == null || lng == null || t.amountMyr == null) continue;
      final cell = geohashAt(lat, lng, 5);
      totals[cell] = (totals[cell] ?? 0) + t.amountMyr!;
    }
    if (totals.isEmpty) return const {};

    final maxTotal = totals.values.reduce((a, b) => a > b ? a : b);
    return totals.entries.map((e) {
      final center = geohashCentroid(e.key);
      final ratio = maxTotal == 0 ? 0.0 : e.value / maxTotal;
      final color = Color.lerp(AppColors.impactLow, AppColors.impactHigh, ratio)!;
      return Circle(
        circleId: CircleId(e.key),
        center: LatLng(center.lat, center.lng),
        radius: 2500,
        fillColor: color.withValues(alpha: 0.35),
        strokeWidth: 0,
      );
    }).toSet();
  }

  List<TransactionView> _filterRows(List<TransactionView> rows) {
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
      if (_categoryFilter != 'All categories' &&
          t.effectiveCategory != _categoryFilter) {
        return false;
      }
      return t.placeLat != null && t.placeLng != null;
    }).toList();
  }

  Future<void> _openPlaceSearch() async {
    final result = await context.pushNamed<PlaceResult>('places-search');
    if (result == null || _mapController == null) return;
    await _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(result.lat, result.lng), 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: StreamBuilder<List<TransactionView>>(
        stream: AppServices.transactions.watchAll(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? [];
          final filtered = _filterRows(all);
          final clusters = mapClusters(filtered);
          final hasGeo = filtered.isNotEmpty;

          if (!hasGeo) {
            return const EmptyState(
              title: 'No map data yet',
              subtitle:
                  'Share receipts with location or enable location when sharing to see spend bubbles.',
              mascotAsset: 'assets/branding/pug-empty-state.png',
            );
          }

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: _malaysiaCenter,
                  zoom: 11,
                ),
                markers: _heatmapMode ? const {} : _buildMarkers(clusters),
                circles: _heatmapMode ? _buildHeatmapCircles(filtered) : const {},
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                onMapCreated: (c) => _mapController = c,
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
                      categories: const [
                        'All categories',
                        'Food & Drink',
                        'Groceries',
                        'Transport',
                      ],
                      selectedCategory: _categoryFilter,
                      onCategoryChanged: (v) =>
                          setState(() => _categoryFilter = v),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
