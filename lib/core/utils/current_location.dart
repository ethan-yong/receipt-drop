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

/// Same as [getCurrentPositionOrNull], except it never calls
/// `Geolocator.requestPermission()` — it only proceeds if permission was
/// already granted. Used by flows that fire silently in the background
/// (e.g. right after an OS share intent, before the user has necessarily
/// even switched back to Receipt Drop), where popping a first-time OS
/// permission dialog would be a surprising, intrusive interruption rather
/// than the "helpful reminder" the location is meant to be. First-time
/// permission priming stays with the app's existing deliberate moments for
/// it (e.g. the spend map) — see
/// `docs/plans/2026-07-30-pending-receipt-location-context.md`.
Future<Position?> getCurrentPositionPassiveOrNull() async {
  if (kIsWeb) return null;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
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
