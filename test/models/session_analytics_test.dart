import 'package:flutter_test/flutter_test.dart';
import 'package:apx_tracer/models/session_analytics.dart';

void main() {
  group('SessionAnalytics', () {
    test('toMap() serializes all fields correctly', () {
      const analytics = SessionAnalytics(
        sessionId: 'session-123',
        durationSeconds: 3600.0,
        distanceKm: 12.45,
        totalLaps: 10,
        bestLapTimeMs: 45000,
        averageLapTimeMs: 48000,
        averageSpeedKmh: 85.3,
        maxSpeedKmh: 120.5,
        speedTraceKmh: [80.0, 85.0, 90.0, 120.5, 100.0],
        bestSector1Ms: 15000,
        bestSector2Ms: 14500,
        bestSector3Ms: 15500,
      );

      final map = analytics.toMap();

      expect(map['session_id'], 'session-123');
      expect(map['duration_seconds'], 3600.0);
      expect(map['distance_km'], 12.45);
      expect(map['total_laps'], 10);
      expect(map['best_lap_time_ms'], 45000);
      expect(map['average_lap_time_ms'], 48000);
      expect(map['average_speed_kmh'], 85.3);
      expect(map['max_speed_kmh'], 120.5);
      expect(map['speed_trace'], isA<String>());
      expect(map['speed_trace'], contains('120.5'));
      expect(map['best_sector1_ms'], 15000);
      expect(map['best_sector2_ms'], 14500);
      expect(map['best_sector3_ms'], 15500);
    });

    test('toMap() serializes null fields for no-lap sessions', () {
      const analytics = SessionAnalytics(
        sessionId: 'session-123',
        durationSeconds: 600.0,
        distanceKm: 5.00,
        totalLaps: 0,
        averageSpeedKmh: 30.0,
        maxSpeedKmh: 50.0,
        speedTraceKmh: [30.0, 35.0, 50.0],
      );

      final map = analytics.toMap();

      expect(map['best_lap_time_ms'], isNull);
      expect(map['average_lap_time_ms'], isNull);
      expect(map['best_sector1_ms'], isNull);
      expect(map['best_sector2_ms'], isNull);
      expect(map['best_sector3_ms'], isNull);
    });

    test('fromMap() deserializes all fields correctly', () {
      final map = <String, dynamic>{
        'session_id': 'session-123',
        'duration_seconds': 3600.0,
        'distance_km': 12.45,
        'total_laps': 10,
        'best_lap_time_ms': 45000,
        'average_lap_time_ms': 48000,
        'average_speed_kmh': 85.3,
        'max_speed_kmh': 120.5,
        'speed_trace': '[80.0,85.0,90.0,120.5,100.0]',
        'best_sector1_ms': 15000,
        'best_sector2_ms': 14500,
        'best_sector3_ms': 15500,
      };

      final analytics = SessionAnalytics.fromMap(map);

      expect(analytics.sessionId, 'session-123');
      expect(analytics.durationSeconds, 3600.0);
      expect(analytics.distanceKm, 12.45);
      expect(analytics.totalLaps, 10);
      expect(analytics.bestLapTimeMs, 45000);
      expect(analytics.averageLapTimeMs, 48000);
      expect(analytics.averageSpeedKmh, 85.3);
      expect(analytics.maxSpeedKmh, 120.5);
      expect(analytics.speedTraceKmh, [80.0, 85.0, 90.0, 120.5, 100.0]);
      expect(analytics.bestSector1Ms, 15000);
      expect(analytics.bestSector2Ms, 14500);
      expect(analytics.bestSector3Ms, 15500);
    });

    test('fromMap() handles null optional fields', () {
      final map = <String, dynamic>{
        'session_id': 'session-123',
        'duration_seconds': 600.0,
        'distance_km': 5.0,
        'total_laps': 0,
        'best_lap_time_ms': null,
        'average_lap_time_ms': null,
        'average_speed_kmh': 30.0,
        'max_speed_kmh': 50.0,
        'speed_trace': '[30.0,35.0,50.0]',
        'best_sector1_ms': null,
        'best_sector2_ms': null,
        'best_sector3_ms': null,
      };

      final analytics = SessionAnalytics.fromMap(map);

      expect(analytics.bestLapTimeMs, isNull);
      expect(analytics.averageLapTimeMs, isNull);
      expect(analytics.bestSector1Ms, isNull);
      expect(analytics.bestSector2Ms, isNull);
      expect(analytics.bestSector3Ms, isNull);
    });

    test('round-trip toMap/fromMap preserves all data', () {
      const original = SessionAnalytics(
        sessionId: 'session-abc',
        durationSeconds: 1800.5,
        distanceKm: 8.75,
        totalLaps: 5,
        bestLapTimeMs: 42000,
        averageLapTimeMs: 44000,
        averageSpeedKmh: 72.5,
        maxSpeedKmh: 110.2,
        speedTraceKmh: [60.0, 72.5, 110.2, 95.0, 80.0],
        bestSector1Ms: 14000,
        bestSector2Ms: 13500,
        bestSector3Ms: 14500,
      );

      final restored = SessionAnalytics.fromMap(original.toMap());

      expect(restored.sessionId, original.sessionId);
      expect(restored.durationSeconds, original.durationSeconds);
      expect(restored.distanceKm, original.distanceKm);
      expect(restored.totalLaps, original.totalLaps);
      expect(restored.bestLapTimeMs, original.bestLapTimeMs);
      expect(restored.averageLapTimeMs, original.averageLapTimeMs);
      expect(restored.averageSpeedKmh, original.averageSpeedKmh);
      expect(restored.maxSpeedKmh, original.maxSpeedKmh);
      expect(restored.speedTraceKmh, original.speedTraceKmh);
      expect(restored.bestSector1Ms, original.bestSector1Ms);
      expect(restored.bestSector2Ms, original.bestSector2Ms);
      expect(restored.bestSector3Ms, original.bestSector3Ms);
    });
  });
}
