import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/logic/dashboard_aggregates.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/map_filter_chips.dart';
import '../../widgets/spend_map_bottom_sheet.dart';

/// Malaysia-default spend map with place bubbles.
class SpendMapScreen extends StatefulWidget {
  const SpendMapScreen({super.key});

  @override
  State<SpendMapScreen> createState() => _SpendMapScreenState();
}

class _SpendMapScreenState extends State<SpendMapScreen> {
  static const _malaysiaCenter = LatLng(3.1390, 101.6869);

  String _timeFilter = 'This month';
  String _categoryFilter = 'All categories';

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

          if (clusters.isEmpty) {
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
                markers: _buildMarkers(clusters),
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                onMapCreated: (_) {},
              ),
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: TextField(
                        readOnly: true,
                        decoration: InputDecoration(
                          hintText: 'Search places',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: AppColors.cardSurface,
                        ),
                        onTap: () {},
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
