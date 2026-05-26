import 'package:flutter_test/flutter_test.dart';
import 'package:apx_tracer/utils/haversine.dart';

void main() {
  group('haversineDistance', () {
    test('returns 0 for identical points', () {
      final distance = haversineDistance(51.5074, -0.1278, 51.5074, -0.1278);
      expect(distance, equals(0.0));
    });

    test('calculates known distance between London and Paris', () {
      // London: 51.5074° N, 0.1278° W
      // Paris: 48.8566° N, 2.3522° E
      // Known distance: ~341 km
      final distance = haversineDistance(51.5074, -0.1278, 48.8566, 2.3522);
      expect(distance, closeTo(343500, 2000)); // within 2km tolerance
    });

    test('calculates short distance accurately (within 50m range)', () {
      // Two points approximately 30 meters apart
      // Starting at 0,0 and moving ~30m north
      // 1 degree latitude ≈ 111,320 meters
      // 30m ≈ 0.000269 degrees latitude
      final distance = haversineDistance(0.0, 0.0, 0.000269, 0.0);
      expect(distance, closeTo(30, 1)); // within 1m tolerance
    });

    test('returns distance in meters for nearby points used in track matching', () {
      // Two points ~50m apart (the threshold for track matching)
      // 50m ≈ 0.000449 degrees latitude at equator
      final distance = haversineDistance(0.0, 0.0, 0.000449, 0.0);
      expect(distance, closeTo(50, 1)); // within 1m tolerance
    });

    test('is symmetric (distance A to B equals B to A)', () {
      final distAB = haversineDistance(40.7128, -74.0060, 34.0522, -118.2437);
      final distBA = haversineDistance(34.0522, -118.2437, 40.7128, -74.0060);
      expect(distAB, closeTo(distBA, 0.001));
    });

    test('handles negative latitudes (southern hemisphere)', () {
      // Sydney: -33.8688° S, 151.2093° E
      // Melbourne: -37.8136° S, 144.9631° E
      // Known distance: ~714 km
      final distance = haversineDistance(-33.8688, 151.2093, -37.8136, 144.9631);
      expect(distance, closeTo(714000, 5000)); // within 5km tolerance
    });

    test('handles crossing the prime meridian', () {
      // Point just west of prime meridian to point just east
      final distance = haversineDistance(51.5, -0.01, 51.5, 0.01);
      expect(distance, greaterThan(0));
      expect(distance, closeTo(1390, 50)); // ~1.39km at this latitude
    });
  });
}
