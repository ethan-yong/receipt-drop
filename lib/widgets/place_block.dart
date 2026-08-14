import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/theme/app_theme.dart';

class PlaceBlock extends StatelessWidget {
  const PlaceBlock({
    super.key,
    required this.placeName,
    this.onChangePlace,
    this.lat,
    this.lng,
  });

  final String placeName;
  final double? lat;
  final double? lng;

  /// When null, the map and Change place control are display-only.
  final VoidCallback? onChangePlace;

  @override
  Widget build(BuildContext context) {
    final canChange = onChangePlace != null;
    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Place', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            GestureDetector(
              onTap: onChangePlace,
              behavior: HitTestBehavior.opaque,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                child: SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: _buildPreview(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    placeName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (canChange)
                  TextButton(
                    onPressed: onChangePlace,
                    child: const Text('Change place'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final lat = this.lat;
    final lng = this.lng;
    if (lat == null || lng == null) {
      return Container(
        color: AppColors.divider,
        child: const Icon(
          Icons.map_outlined,
          size: 40,
          color: AppColors.textMuted,
        ),
      );
    }
    // GoogleMap ignores post-creation changes to initialCameraPosition, so
    // key it by coordinates to force a rebuild when the place changes.
    return IgnorePointer(
      child: GoogleMap(
        key: ValueKey('place-block-map-$lat-$lng'),
        initialCameraPosition: CameraPosition(target: LatLng(lat, lng), zoom: 15),
        markers: {
          Marker(markerId: const MarkerId('place'), position: LatLng(lat, lng)),
        },
        zoomControlsEnabled: false,
        zoomGesturesEnabled: false,
        scrollGesturesEnabled: false,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        myLocationButtonEnabled: false,
        mapToolbarEnabled: false,
        compassEnabled: false,
      ),
    );
  }
}
