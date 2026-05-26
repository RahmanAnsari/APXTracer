import 'package:flutter_test/flutter_test.dart';
import 'package:apx_tracer/models/gps_sample.dart';

void main() {
  group('GpsSample', () {
    test('toMap() serializes all fields correctly', () {
      const sample = GpsSample(
        timestamp: 1700000000000,
        latitude: 51.5074,
        longitude: -0.1278,
        altitude: 15.5,
        speed: 22.3,
        heading: 180.0,
        accuracy: 5.0,
        isLowAccuracy: false,
      );

      final map = sample.toMap();

      expect(map['timestamp'], 1700000000000);
      expect(map['latitude'], 51.5074);
      expect(map['longitude'], -0.1278);
      expect(map['altitude'], 15.5);
      expect(map['speed'], 22.3);
      expect(map['heading'], 180.0);
      expect(map['accuracy'], 5.0);
      expect(map['is_low_accuracy'], 0);
    });

    test('toMap() serializes null optional fields', () {
      const sample = GpsSample(
        timestamp: 1700000000000,
        latitude: 51.5074,
        longitude: -0.1278,
      );

      final map = sample.toMap();

      expect(map['altitude'], isNull);
      expect(map['speed'], isNull);
      expect(map['heading'], isNull);
      expect(map['accuracy'], isNull);
      expect(map['is_low_accuracy'], 0);
    });

    test('toMap() serializes isLowAccuracy as 1 when true', () {
      const sample = GpsSample(
        timestamp: 1700000000000,
        latitude: 51.5074,
        longitude: -0.1278,
        accuracy: 60.0,
        isLowAccuracy: true,
      );

      final map = sample.toMap();

      expect(map['is_low_accuracy'], 1);
    });

    test('fromMap() deserializes all fields correctly', () {
      final map = <String, dynamic>{
        'timestamp': 1700000000000,
        'latitude': 51.5074,
        'longitude': -0.1278,
        'altitude': 15.5,
        'speed': 22.3,
        'heading': 180.0,
        'accuracy': 5.0,
        'is_low_accuracy': 0,
      };

      final sample = GpsSample.fromMap(map);

      expect(sample.timestamp, 1700000000000);
      expect(sample.latitude, 51.5074);
      expect(sample.longitude, -0.1278);
      expect(sample.altitude, 15.5);
      expect(sample.speed, 22.3);
      expect(sample.heading, 180.0);
      expect(sample.accuracy, 5.0);
      expect(sample.isLowAccuracy, false);
    });

    test('fromMap() handles null optional fields', () {
      final map = <String, dynamic>{
        'timestamp': 1700000000000,
        'latitude': 51.5074,
        'longitude': -0.1278,
        'altitude': null,
        'speed': null,
        'heading': null,
        'accuracy': null,
        'is_low_accuracy': 0,
      };

      final sample = GpsSample.fromMap(map);

      expect(sample.altitude, isNull);
      expect(sample.speed, isNull);
      expect(sample.heading, isNull);
      expect(sample.accuracy, isNull);
      expect(sample.isLowAccuracy, false);
    });

    test('fromMap() deserializes isLowAccuracy correctly', () {
      final map = <String, dynamic>{
        'timestamp': 1700000000000,
        'latitude': 51.5074,
        'longitude': -0.1278,
        'altitude': null,
        'speed': null,
        'heading': null,
        'accuracy': 60.0,
        'is_low_accuracy': 1,
      };

      final sample = GpsSample.fromMap(map);

      expect(sample.isLowAccuracy, true);
    });

    test('round-trip toMap/fromMap preserves all data', () {
      const original = GpsSample(
        timestamp: 1700000000000,
        latitude: 51.5074,
        longitude: -0.1278,
        altitude: 15.5,
        speed: 22.3,
        heading: 180.0,
        accuracy: 5.0,
        isLowAccuracy: false,
      );

      final restored = GpsSample.fromMap(original.toMap());

      expect(restored.timestamp, original.timestamp);
      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
      expect(restored.altitude, original.altitude);
      expect(restored.speed, original.speed);
      expect(restored.heading, original.heading);
      expect(restored.accuracy, original.accuracy);
      expect(restored.isLowAccuracy, original.isLowAccuracy);
    });
  });
}
