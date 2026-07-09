import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Best-effort device position: null on web, when location services are off,
/// when permission is denied, or when the fix takes longer than 8 seconds.
/// Shared by receipt ingest (tagging a share with its location) and the
/// spend map ("recenter on me" / own-avatar marker).
Future<Position?> getCurrentPositionOrNull() async {
  if (kIsWeb) return null;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 8),
      ),
    );
  } catch (_) {
    return null;
  }
}
