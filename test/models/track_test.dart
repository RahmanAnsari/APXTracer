import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:apx_tracer/models/track.dart';

void main() {
  group('Track', () {
    test('toMap() serializes all fields correctly', () {
      final track = Track(
        id: 'track-123',
        name: 'Silverstone',
        polyline: [
          LatLng(52.0786, -1.0169),
          LatLng(52.0790, -1.0165),
          LatLng(52.0795, -1.0160),
        ],
        startFinish: LatLng(52.0786, -1.0169),
        sector1Fraction: 0.333,
        sector2Fraction: 0.666,
        sessionCount: 5,
        lastDriven: 1700000000000,
      );

      final map = track.toMap();

      expect(map['id'], 'track-123');
      expect(map['name'], 'Silverstone');
      expect(map['start_lat'], 52.0786);
      expect(map['start_lng'], -1.0169);
      expect(map['sector1_fraction'], 0.333);
      expect(map['sector2_fraction'], 0.666);
      expect(map['session_count'], 5);
      expect(map['last_driven'], 1700000000000);
      expect(map['created_at'], 1700000000000);
      // Polyline should be a JSON string
      expect(map['polyline'], isA<String>());
      expect(map['polyline'], contains('52.0786'));
    });

    test('toMap() serializes null name', () {
      final track = Track(
        id: 'track-123',
        polyline: [LatLng(52.0786, -1.0169)],
        startFinish: LatLng(52.0786, -1.0169),
        lastDriven: 1700000000000,
      );

      final map = track.toMap();

      expect(map['name'], isNull);
    });

    test('fromMap() deserializes all fields correctly', () {
      final map = <String, dynamic>{
        'id': 'track-123',
        'name': 'Silverstone',
        'polyline': '[[52.0786,-1.0169],[52.079,-1.0165],[52.0795,-1.016]]',
        'start_lat': 52.0786,
        'start_lng': -1.0169,
        'sector1_fraction': 0.333,
        'sector2_fraction': 0.666,
        'session_count': 5,
        'last_driven': 1700000000000,
        'created_at': 1700000000000,
      };

      final track = Track.fromMap(map);

      expect(track.id, 'track-123');
      expect(track.name, 'Silverstone');
      expect(track.polyline.length, 3);
      expect(track.polyline[0].latitude, 52.0786);
      expect(track.polyline[0].longitude, -1.0169);
      expect(track.startFinish.latitude, 52.0786);
      expect(track.startFinish.longitude, -1.0169);
      expect(track.sector1Fraction, 0.333);
      expect(track.sector2Fraction, 0.666);
      expect(track.sessionCount, 5);
      expect(track.lastDriven, 1700000000000);
    });

    test('fromMap() handles null name', () {
      final map = <String, dynamic>{
        'id': 'track-123',
        'name': null,
        'polyline': '[[52.0786,-1.0169]]',
        'start_lat': 52.0786,
        'start_lng': -1.0169,
        'sector1_fraction': 0.333,
        'sector2_fraction': 0.666,
        'session_count': 1,
        'last_driven': 1700000000000,
        'created_at': 1700000000000,
      };

      final track = Track.fromMap(map);

      expect(track.name, isNull);
    });

    test('round-trip toMap/fromMap preserves all data', () {
      final original = Track(
        id: 'track-abc',
        name: 'Brands Hatch',
        polyline: [
          LatLng(51.3569, 0.2631),
          LatLng(51.3575, 0.2640),
          LatLng(51.3580, 0.2650),
        ],
        startFinish: LatLng(51.3569, 0.2631),
        sector1Fraction: 0.333,
        sector2Fraction: 0.666,
        sessionCount: 3,
        lastDriven: 1700000000000,
      );

      final restored = Track.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.polyline.length, original.polyline.length);
      expect(restored.polyline[0].latitude, original.polyline[0].latitude);
      expect(restored.polyline[0].longitude, original.polyline[0].longitude);
      expect(restored.startFinish.latitude, original.startFinish.latitude);
      expect(restored.startFinish.longitude, original.startFinish.longitude);
      expect(restored.sector1Fraction, original.sector1Fraction);
      expect(restored.sector2Fraction, original.sector2Fraction);
      expect(restored.sessionCount, original.sessionCount);
      expect(restored.lastDriven, original.lastDriven);
    });

    test('default sector fractions are 1/3 and 2/3', () {
      final track = Track(
        id: 'track-123',
        polyline: [LatLng(52.0786, -1.0169)],
        startFinish: LatLng(52.0786, -1.0169),
        lastDriven: 1700000000000,
      );

      expect(track.sector1Fraction, closeTo(0.333, 0.001));
      expect(track.sector2Fraction, closeTo(0.666, 0.001));
    });
  });
}
