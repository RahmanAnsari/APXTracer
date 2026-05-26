import 'dart:math';

/// Calculates the Haversine distance between two geographic coordinates.
///
/// Returns the distance in meters between the two points.
double haversineDistance(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  const double earthRadius = 6371000.0; // Earth's radius in meters

  final double dLat = _toRadians(lat2 - lat1);
  final double dLng = _toRadians(lng2 - lng1);

  final double a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(lat1)) *
          cos(_toRadians(lat2)) *
          sin(dLng / 2) *
          sin(dLng / 2);

  final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return earthRadius * c;
}

double _toRadians(double degrees) => degrees * pi / 180.0;
