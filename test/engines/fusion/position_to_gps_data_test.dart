import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:apx_tracer/engines/fusion/nav_state_converter.dart';

void main() {
  group('positionToGpsData', () {
    /// Helper to create a Position with sensible defaults.
    Position createPosition({
      double latitude = 51.5074,
      double longitude = -0.1278,
      double altitude = 100.0,
      double speed = 25.0,
      double heading = 180.0,
      double accuracy = 5.0,
      DateTime? timestamp,
    }) {
      return Position(
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        speed: speed,
        heading: heading,
        accuracy: accuracy,
        timestamp: timestamp ?? DateTime(2024, 6, 15, 12, 0, 0),
        altitudeAccuracy: 1.0,
        headingAccuracy: 1.0,
        speedAccuracy: 1.0,
      );
    }

    test('maps all fields correctly for a valid Position', () {
      final timestamp = DateTime(2024, 6, 15, 12, 30, 45);
      final position = createPosition(
        latitude: 48.8566,
        longitude: 2.3522,
        altitude: 35.0,
        speed: 30.5,
        heading: 270.0,
        accuracy: 3.5,
        timestamp: timestamp,
      );

      final gpsData = positionToGpsData(position);

      expect(gpsData.latitude, 48.8566);
      expect(gpsData.longitude, 2.3522);
      expect(gpsData.altitude, 35.0);
      expect(gpsData.speed, 30.5);
      expect(gpsData.heading, 270.0);
      expect(gpsData.accuracy, 3.5);
      expect(gpsData.timestamp, timestamp);
    });

    test('speed is null when Position.speed < 0', () {
      final position = createPosition(speed: -1.0);

      final gpsData = positionToGpsData(position);

      expect(gpsData.speed, isNull);
    });

    test('speed is preserved when Position.speed == 0', () {
      final position = createPosition(speed: 0.0);

      final gpsData = positionToGpsData(position);

      expect(gpsData.speed, 0.0);
    });

    test('heading is null when Position.heading < 0', () {
      final position = createPosition(heading: -1.0);

      final gpsData = positionToGpsData(position);

      expect(gpsData.heading, isNull);
    });

    test('heading is preserved when Position.heading == 0', () {
      final position = createPosition(heading: 0.0);

      final gpsData = positionToGpsData(position);

      expect(gpsData.heading, 0.0);
    });

    test('accuracy defaults to 100.0 when Position.accuracy <= 0', () {
      final positionZero = createPosition(accuracy: 0.0);
      final positionNegative = createPosition(accuracy: -5.0);

      final gpsDataZero = positionToGpsData(positionZero);
      final gpsDataNegative = positionToGpsData(positionNegative);

      expect(gpsDataZero.accuracy, 100.0);
      expect(gpsDataNegative.accuracy, 100.0);
    });

    test('accuracy is preserved when Position.accuracy > 0', () {
      final position = createPosition(accuracy: 8.5);

      final gpsData = positionToGpsData(position);

      expect(gpsData.accuracy, 8.5);
    });

    test('latitude is preserved exactly', () {
      final position = createPosition(latitude: -33.8688);

      final gpsData = positionToGpsData(position);

      expect(gpsData.latitude, -33.8688);
    });

    test('longitude is preserved exactly', () {
      final position = createPosition(longitude: 151.2093);

      final gpsData = positionToGpsData(position);

      expect(gpsData.longitude, 151.2093);
    });

    test('altitude is preserved exactly', () {
      final position = createPosition(altitude: 2450.75);

      final gpsData = positionToGpsData(position);

      expect(gpsData.altitude, 2450.75);
    });

    test('timestamp is preserved', () {
      final timestamp = DateTime(2024, 1, 1, 0, 0, 0, 123);
      final position = createPosition(timestamp: timestamp);

      final gpsData = positionToGpsData(position);

      expect(gpsData.timestamp, timestamp);
    });
  });
}
