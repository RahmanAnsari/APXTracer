import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'haversine.dart';
import 'polyline_utils.dart';

/// Builds a clean reference polyline from raw GPS samples.
///
/// Pipeline:
///   raw GPS points (best lap, ~600 pts at 10 Hz)
///     → Chaikin closed-loop smoothing  — removes GPS jitter, preserves corners
///     → Douglas-Peucker simplification — reduces to ~200–400 pts for rendering
///     → result: professional circuit centerline, ready for storage and display
class CircuitBuilder {
  CircuitBuilder._();

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Full pipeline: smooth then simplify a closed-loop GPS polyline.
  static List<LatLng> buildReferencePolyline(
    List<LatLng> rawPoints, {
    int smoothIterations = 3,
    double simplifyEpsilonMeters = 2.0,
  }) {
    if (rawPoints.length < 3) return List.from(rawPoints);
    final smoothed = chaikinSmooth(rawPoints, iterations: smoothIterations);
    return douglasPeckerClosed(smoothed, simplifyEpsilonMeters);
  }

  /// Total arc length of a polyline in metres. Delegates to [polylineLength].
  static double computeArcLengthMeters(List<LatLng> points) =>
      polylineLength(points);

  // ─── Chaikin smoothing ─────────────────────────────────────────────────────

  /// Chaikin corner-cutting subdivision for a closed-loop polyline.
  ///
  /// Each iteration inserts two new points at the 1/4 and 3/4 positions of
  /// every edge, converging to a smooth B-spline after a few rounds.
  /// Wraps around the end→start edge so the S/F area is smoothed equally.
  static List<LatLng> chaikinSmooth(
    List<LatLng> points, {
    int iterations = 3,
  }) {
    var result = points;
    for (int i = 0; i < iterations; i++) {
      result = _chaikinIteration(result);
    }
    return result;
  }

  static List<LatLng> _chaikinIteration(List<LatLng> points) {
    final n = points.length;
    final result = <LatLng>[];
    for (int i = 0; i < n; i++) {
      final p0 = points[i];
      final p1 = points[(i + 1) % n]; // wrap-around for closed loop
      // Q = 3/4 * p0 + 1/4 * p1
      result.add(LatLng(
        0.75 * p0.latitude + 0.25 * p1.latitude,
        0.75 * p0.longitude + 0.25 * p1.longitude,
      ));
      // R = 1/4 * p0 + 3/4 * p1
      result.add(LatLng(
        0.25 * p0.latitude + 0.75 * p1.latitude,
        0.25 * p0.longitude + 0.75 * p1.longitude,
      ));
    }
    return result;
  }

  // ─── Douglas-Peucker simplification ────────────────────────────────────────

  /// Ramer-Douglas-Peucker simplification adapted for a closed-loop polyline.
  ///
  /// Finds the point farthest from the start (the circuit's "opposite" end),
  /// splits there, then runs standard DP on each half independently.
  /// This avoids the degenerate case where DP on a nearly-closed polyline
  /// collapses everything to two points.
  static List<LatLng> douglasPeckerClosed(
    List<LatLng> points,
    double epsilonMeters,
  ) {
    if (points.length <= 3) return List.from(points);

    // Find the point farthest from the first point — the natural split.
    int splitIndex = 1;
    double maxDist = 0;
    for (int i = 1; i < points.length - 1; i++) {
      final d = haversineDistance(
        points.first.latitude, points.first.longitude,
        points[i].latitude, points[i].longitude,
      );
      if (d > maxDist) {
        maxDist = d;
        splitIndex = i;
      }
    }

    final firstHalf =
        _douglasPeuckerOpen(points.sublist(0, splitIndex + 1), epsilonMeters);
    final secondHalf =
        _douglasPeuckerOpen(points.sublist(splitIndex), epsilonMeters);

    // Merge: drop the duplicate split point at the junction.
    return [...firstHalf.sublist(0, firstHalf.length - 1), ...secondHalf];
  }

  /// Standard Ramer-Douglas-Peucker for an open polyline segment.
  static List<LatLng> _douglasPeuckerOpen(
    List<LatLng> points,
    double epsilonMeters,
  ) {
    if (points.length <= 2) return List.from(points);

    double maxDist = 0;
    int maxIndex = 0;

    for (int i = 1; i < points.length - 1; i++) {
      final dist = _crossTrackDistanceMeters(
        points[i],
        points.first,
        points.last,
      );
      if (dist > maxDist) {
        maxDist = dist;
        maxIndex = i;
      }
    }

    if (maxDist > epsilonMeters) {
      final left =
          _douglasPeuckerOpen(points.sublist(0, maxIndex + 1), epsilonMeters);
      final right =
          _douglasPeuckerOpen(points.sublist(maxIndex), epsilonMeters);
      return [...left.sublist(0, left.length - 1), ...right];
    }

    return [points.first, points.last];
  }

  // ─── Geometry helpers ──────────────────────────────────────────────────────

  /// Perpendicular (cross-track) distance from [point] to the segment
  /// [lineStart] → [lineEnd] using an equirectangular projection.
  ///
  /// Accurate to < 0.1 % for distances up to 50 km — sufficient for any
  /// racing circuit.
  static double _crossTrackDistanceMeters(
    LatLng point,
    LatLng lineStart,
    LatLng lineEnd,
  ) {
    const degToRad = math.pi / 180.0;
    const earthRadius = 6371000.0;

    final refLat =
        (lineStart.latitude + lineEnd.latitude) / 2.0 * degToRad;
    final cosLat = math.cos(refLat);

    final x0 = point.longitude * cosLat * earthRadius * degToRad;
    final y0 = point.latitude * earthRadius * degToRad;
    final x1 = lineStart.longitude * cosLat * earthRadius * degToRad;
    final y1 = lineStart.latitude * earthRadius * degToRad;
    final x2 = lineEnd.longitude * cosLat * earthRadius * degToRad;
    final y2 = lineEnd.latitude * earthRadius * degToRad;

    final dx = x2 - x1;
    final dy = y2 - y1;
    final len = math.sqrt(dx * dx + dy * dy);

    if (len < 1e-10) {
      return haversineDistance(
        point.latitude, point.longitude,
        lineStart.latitude, lineStart.longitude,
      );
    }

    return ((x0 - x1) * dy - (y0 - y1) * dx).abs() / len;
  }
}
