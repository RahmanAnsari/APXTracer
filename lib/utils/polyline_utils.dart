import 'package:latlong2/latlong.dart';

import 'haversine.dart';

/// Calculates the total distance along a polyline in meters.
///
/// Uses Haversine distance between consecutive points to compute
/// the cumulative path length.
///
/// Returns 0.0 if [points] has fewer than 2 elements.
double polylineLength(List<LatLng> points) {
  if (points.length < 2) return 0.0;

  double total = 0.0;
  for (int i = 0; i < points.length - 1; i++) {
    total += haversineDistance(
      points[i].latitude,
      points[i].longitude,
      points[i + 1].latitude,
      points[i + 1].longitude,
    );
  }
  return total;
}

/// Returns the interpolated geographic point at a given [fraction] of the
/// total polyline length.
///
/// [fraction] should be between 0.0 and 1.0 inclusive.
/// - At 0.0, returns the first point.
/// - At 1.0, returns the last point.
///
/// Throws [ArgumentError] if [points] is empty or [fraction] is outside [0, 1].
LatLng pointAtFraction(List<LatLng> points, double fraction) {
  if (points.isEmpty) {
    throw ArgumentError('points must not be empty');
  }
  if (fraction < 0.0 || fraction > 1.0) {
    throw ArgumentError('fraction must be between 0.0 and 1.0, got $fraction');
  }
  if (points.length == 1) return points.first;
  if (fraction == 0.0) return points.first;
  if (fraction == 1.0) return points.last;

  final double totalLength = polylineLength(points);
  if (totalLength == 0.0) return points.first;

  final double targetDistance = fraction * totalLength;
  double accumulated = 0.0;

  for (int i = 0; i < points.length - 1; i++) {
    final double segmentLength = haversineDistance(
      points[i].latitude,
      points[i].longitude,
      points[i + 1].latitude,
      points[i + 1].longitude,
    );

    if (accumulated + segmentLength >= targetDistance) {
      // The target point lies on this segment
      final double remaining = targetDistance - accumulated;
      final double segmentFraction =
          segmentLength > 0 ? remaining / segmentLength : 0.0;

      // Linear interpolation between the two endpoints
      final double lat = points[i].latitude +
          segmentFraction * (points[i + 1].latitude - points[i].latitude);
      final double lng = points[i].longitude +
          segmentFraction * (points[i + 1].longitude - points[i].longitude);

      return LatLng(lat, lng);
    }

    accumulated += segmentLength;
  }

  // Fallback: return last point (should not normally reach here)
  return points.last;
}

/// Finds the closest position on the polyline to the given [point] and
/// returns its fraction (0.0 to 1.0) along the total polyline length.
///
/// Projects [point] onto each segment of the polyline and returns the
/// fraction corresponding to the closest projection.
///
/// Throws [ArgumentError] if [points] is empty.
double fractionAtPoint(List<LatLng> points, LatLng point) {
  if (points.isEmpty) {
    throw ArgumentError('points must not be empty');
  }
  if (points.length == 1) return 0.0;

  final double totalLength = polylineLength(points);
  if (totalLength == 0.0) return 0.0;

  double bestDistance = double.infinity;
  double bestFraction = 0.0;
  double accumulated = 0.0;

  for (int i = 0; i < points.length - 1; i++) {
    final double segmentLength = haversineDistance(
      points[i].latitude,
      points[i].longitude,
      points[i + 1].latitude,
      points[i + 1].longitude,
    );

    // Project the point onto this segment
    final double t = _projectOntoSegment(points[i], points[i + 1], point);

    // Interpolate to get the projected point on the segment
    final double projLat =
        points[i].latitude + t * (points[i + 1].latitude - points[i].latitude);
    final double projLng = points[i].longitude +
        t * (points[i + 1].longitude - points[i].longitude);

    // Distance from the input point to the projected point
    final double dist = haversineDistance(
      point.latitude,
      point.longitude,
      projLat,
      projLng,
    );

    if (dist < bestDistance) {
      bestDistance = dist;
      bestFraction = (accumulated + t * segmentLength) / totalLength;
    }

    accumulated += segmentLength;
  }

  // Clamp to [0, 1] to handle floating-point edge cases
  return bestFraction.clamp(0.0, 1.0);
}

/// Projects [point] onto the line segment from [a] to [b].
///
/// Returns a value t in [0, 1] representing the position along the segment.
/// t=0 means closest to [a], t=1 means closest to [b].
double _projectOntoSegment(LatLng a, LatLng b, LatLng point) {
  // Use a flat-earth approximation for the projection calculation.
  // This is acceptable for short segments (typical GPS track segments).
  final double dx = b.longitude - a.longitude;
  final double dy = b.latitude - a.latitude;

  if (dx == 0.0 && dy == 0.0) return 0.0;

  final double t =
      ((point.longitude - a.longitude) * dx +
          (point.latitude - a.latitude) * dy) /
      (dx * dx + dy * dy);

  return t.clamp(0.0, 1.0);
}
