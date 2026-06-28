/// Geohash at the given precision for heatmap aggregation.
String geohashAt(double latitude, double longitude, int precision) =>
    _geohashEncode(latitude, longitude, precision);

/// Approximate center of a geohash cell.
({double lat, double lng}) geohashCentroid(String geohash) {
  const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  var latMin = -90.0;
  var latMax = 90.0;
  var lonMin = -180.0;
  var lonMax = 180.0;
  var even = true;

  for (final c in geohash.split('')) {
    final cd = base32.indexOf(c);
    if (cd < 0) continue;
    for (var mask = 16; mask != 0; mask >>= 1) {
      if (even) {
        final mid = (lonMin + lonMax) / 2;
        if ((cd & mask) != 0) {
          lonMin = mid;
        } else {
          lonMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if ((cd & mask) != 0) {
          latMin = mid;
        } else {
          latMax = mid;
        }
      }
      even = !even;
    }
  }

  return (lat: (latMin + latMax) / 2, lng: (lonMin + lonMax) / 2);
}

/// Stable key for aggregating spend on the map (design spec §9).
///
/// Prefer Google `place_id` when known; otherwise geohash precision 8 (~38m × 19m).
String effectivePlaceKey(String? placeGooglePlaceId, double lat, double lng) {
  final id = placeGooglePlaceId?.trim();
  if (id != null && id.isNotEmpty) {
    return 'pid:$id';
  }
  return 'gh8:${_geohashEncode(lat, lng, 8)}';
}

/// Standard geohash base-32 encoding ([Wikipedia: Geohash](https://en.wikipedia.org/wiki/Geohash)).
String _geohashEncode(double latitude, double longitude, int precision) {
  const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  var latMin = -90.0;
  var latMax = 90.0;
  var lonMin = -180.0;
  var lonMax = 180.0;
  final bits = <int>[16, 8, 4, 2, 1];
  final out = StringBuffer();
  var bit = 0;
  var ch = 0;
  var even = true;

  while (out.length < precision) {
    if (even) {
      final mid = (lonMin + lonMax) / 2;
      if (longitude > mid) {
        ch |= bits[bit];
        lonMin = mid;
      } else {
        lonMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (latitude > mid) {
        ch |= bits[bit];
        latMin = mid;
      } else {
        latMax = mid;
      }
    }
    even = !even;
    if (bit < 4) {
      bit++;
    } else {
      out.write(base32[ch]);
      bit = 0;
      ch = 0;
    }
  }
  return out.toString();
}
