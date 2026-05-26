import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:apx_tracer/utils/polyline_utils.dart';

void main() {
  group('polylineLength', () {
    test('returns 0 for empty list', () {
      expect(polylineLength([]), equals(0.0));
    });

    test('returns 0 for single point', () {
      expect(polylineLength([const LatLng(0, 0)]), equals(0.0));
    });

    test('calculates distance for two points', () {
      // Two points ~111km apart (1 degree latitude at equator)
      final points = [const LatLng(0, 0), const LatLng(1, 0)];
      final length = polylineLength(points);
      expect(length, closeTo(111195, 200)); // ~111.2 km
    });

    test('sums distances along multi-segment polyline', () {
      // Three points forming an L-shape
      final points = [
        const LatLng(0, 0),
        const LatLng(0, 1), // ~111km east at equator
        const LatLng(1, 1), // ~111km north
      ];
      final length = polylineLength(points);
      // Total should be approximately 222 km
      expect(length, closeTo(222390, 500));
    });

    test('returns 0 for identical consecutive points', () {
      final points = [
        const LatLng(51.5, -0.1),
        const LatLng(51.5, -0.1),
        const LatLng(51.5, -0.1),
      ];
      expect(polylineLength(points), equals(0.0));
    });
  });

  group('pointAtFraction', () {
    test('throws ArgumentError for empty list', () {
      expect(
        () => pointAtFraction([], 0.5),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for fraction < 0', () {
      expect(
        () => pointAtFraction([const LatLng(0, 0)], -0.1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for fraction > 1', () {
      expect(
        () => pointAtFraction([const LatLng(0, 0)], 1.1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('returns first point at fraction 0', () {
      final points = [const LatLng(0, 0), const LatLng(1, 0)];
      final result = pointAtFraction(points, 0.0);
      expect(result.latitude, equals(0.0));
      expect(result.longitude, equals(0.0));
    });

    test('returns last point at fraction 1', () {
      final points = [const LatLng(0, 0), const LatLng(1, 0)];
      final result = pointAtFraction(points, 1.0);
      expect(result.latitude, equals(1.0));
      expect(result.longitude, equals(0.0));
    });

    test('returns midpoint at fraction 0.5 for two-point polyline', () {
      final points = [const LatLng(0, 0), const LatLng(2, 0)];
      final result = pointAtFraction(points, 0.5);
      expect(result.latitude, closeTo(1.0, 0.001));
      expect(result.longitude, closeTo(0.0, 0.001));
    });

    test('returns point at 1/3 fraction for sector boundary', () {
      // Straight line from (0,0) to (3,0)
      final points = [const LatLng(0, 0), const LatLng(3, 0)];
      final result = pointAtFraction(points, 1.0 / 3.0);
      expect(result.latitude, closeTo(1.0, 0.001));
      expect(result.longitude, closeTo(0.0, 0.001));
    });

    test('returns point at 2/3 fraction for sector boundary', () {
      // Straight line from (0,0) to (3,0)
      final points = [const LatLng(0, 0), const LatLng(3, 0)];
      final result = pointAtFraction(points, 2.0 / 3.0);
      expect(result.latitude, closeTo(2.0, 0.001));
      expect(result.longitude, closeTo(0.0, 0.001));
    });

    test('interpolates correctly across multiple segments', () {
      // Three equal-length segments along latitude
      final points = [
        const LatLng(0, 0),
        const LatLng(1, 0),
        const LatLng(2, 0),
        const LatLng(3, 0),
      ];
      // At fraction 0.5, should be at latitude ~1.5
      final result = pointAtFraction(points, 0.5);
      expect(result.latitude, closeTo(1.5, 0.01));
      expect(result.longitude, closeTo(0.0, 0.001));
    });

    test('returns the single point for single-element list', () {
      final result = pointAtFraction([const LatLng(42.0, 13.0)], 0.5);
      expect(result.latitude, equals(42.0));
      expect(result.longitude, equals(13.0));
    });
  });

  group('fractionAtPoint', () {
    test('throws ArgumentError for empty list', () {
      expect(
        () => fractionAtPoint([], const LatLng(0, 0)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('returns 0 for single-point polyline', () {
      expect(
        fractionAtPoint([const LatLng(0, 0)], const LatLng(1, 1)),
        equals(0.0),
      );
    });

    test('returns 0 for point at start of polyline', () {
      final points = [const LatLng(0, 0), const LatLng(2, 0)];
      final fraction = fractionAtPoint(points, const LatLng(0, 0));
      expect(fraction, closeTo(0.0, 0.01));
    });

    test('returns 1 for point at end of polyline', () {
      final points = [const LatLng(0, 0), const LatLng(2, 0)];
      final fraction = fractionAtPoint(points, const LatLng(2, 0));
      expect(fraction, closeTo(1.0, 0.01));
    });

    test('returns ~0.5 for point at midpoint of straight polyline', () {
      final points = [const LatLng(0, 0), const LatLng(2, 0)];
      final fraction = fractionAtPoint(points, const LatLng(1, 0));
      expect(fraction, closeTo(0.5, 0.01));
    });

    test('returns ~0.333 for point at 1/3 of polyline', () {
      final points = [const LatLng(0, 0), const LatLng(3, 0)];
      final fraction = fractionAtPoint(points, const LatLng(1, 0));
      expect(fraction, closeTo(1.0 / 3.0, 0.01));
    });

    test('returns ~0.666 for point at 2/3 of polyline', () {
      final points = [const LatLng(0, 0), const LatLng(3, 0)];
      final fraction = fractionAtPoint(points, const LatLng(2, 0));
      expect(fraction, closeTo(2.0 / 3.0, 0.01));
    });

    test('projects nearby off-polyline point correctly', () {
      // Polyline goes along latitude, point is slightly off to the side
      final points = [const LatLng(0, 0), const LatLng(2, 0)];
      // Point at (1, 0.001) — slightly east of midpoint
      final fraction = fractionAtPoint(points, const LatLng(1, 0.001));
      expect(fraction, closeTo(0.5, 0.02));
    });

    test('handles multi-segment polyline', () {
      final points = [
        const LatLng(0, 0),
        const LatLng(1, 0),
        const LatLng(2, 0),
      ];
      // Point at the second vertex (midpoint of total length)
      final fraction = fractionAtPoint(points, const LatLng(1, 0));
      expect(fraction, closeTo(0.5, 0.01));
    });
  });
}
