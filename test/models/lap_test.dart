import 'package:flutter_test/flutter_test.dart';
import 'package:apx_tracer/models/lap.dart';

void main() {
  group('Lap', () {
    test('toMap() serializes all fields correctly', () {
      const lap = Lap(
        id: 'lap-123',
        sessionId: 'session-456',
        trackId: 'track-789',
        lapNumber: 3,
        startTimestamp: 1700000000000,
        endTimestamp: 1700000060000,
        lapTimeMs: 60000,
        sector1Ms: 20000,
        sector2Ms: 20000,
        sector3Ms: 20000,
        isBestLap: true,
      );

      final map = lap.toMap();

      expect(map['id'], 'lap-123');
      expect(map['session_id'], 'session-456');
      expect(map['track_id'], 'track-789');
      expect(map['lap_number'], 3);
      expect(map['start_timestamp'], 1700000000000);
      expect(map['end_timestamp'], 1700000060000);
      expect(map['lap_time_ms'], 60000);
      expect(map['sector1_ms'], 20000);
      expect(map['sector2_ms'], 20000);
      expect(map['sector3_ms'], 20000);
      expect(map['is_best_lap'], 1);
    });

    test('toMap() serializes null sector times and isBestLap=false', () {
      const lap = Lap(
        id: 'lap-123',
        sessionId: 'session-456',
        trackId: 'track-789',
        lapNumber: 1,
        startTimestamp: 1700000000000,
        endTimestamp: 1700000060000,
        lapTimeMs: 60000,
      );

      final map = lap.toMap();

      expect(map['sector1_ms'], isNull);
      expect(map['sector2_ms'], isNull);
      expect(map['sector3_ms'], isNull);
      expect(map['is_best_lap'], 0);
    });

    test('fromMap() deserializes all fields correctly', () {
      final map = <String, dynamic>{
        'id': 'lap-123',
        'session_id': 'session-456',
        'track_id': 'track-789',
        'lap_number': 3,
        'start_timestamp': 1700000000000,
        'end_timestamp': 1700000060000,
        'lap_time_ms': 60000,
        'sector1_ms': 20000,
        'sector2_ms': 20000,
        'sector3_ms': 20000,
        'is_best_lap': 1,
      };

      final lap = Lap.fromMap(map);

      expect(lap.id, 'lap-123');
      expect(lap.sessionId, 'session-456');
      expect(lap.trackId, 'track-789');
      expect(lap.lapNumber, 3);
      expect(lap.startTimestamp, 1700000000000);
      expect(lap.endTimestamp, 1700000060000);
      expect(lap.lapTimeMs, 60000);
      expect(lap.sector1Ms, 20000);
      expect(lap.sector2Ms, 20000);
      expect(lap.sector3Ms, 20000);
      expect(lap.isBestLap, true);
    });

    test('fromMap() handles null sector times', () {
      final map = <String, dynamic>{
        'id': 'lap-123',
        'session_id': 'session-456',
        'track_id': 'track-789',
        'lap_number': 1,
        'start_timestamp': 1700000000000,
        'end_timestamp': 1700000060000,
        'lap_time_ms': 60000,
        'sector1_ms': null,
        'sector2_ms': null,
        'sector3_ms': null,
        'is_best_lap': 0,
      };

      final lap = Lap.fromMap(map);

      expect(lap.sector1Ms, isNull);
      expect(lap.sector2Ms, isNull);
      expect(lap.sector3Ms, isNull);
      expect(lap.isBestLap, false);
    });

    test('round-trip toMap/fromMap preserves all data', () {
      const original = Lap(
        id: 'lap-abc',
        sessionId: 'session-def',
        trackId: 'track-ghi',
        lapNumber: 5,
        startTimestamp: 1700000000000,
        endTimestamp: 1700000045000,
        lapTimeMs: 45000,
        sector1Ms: 15000,
        sector2Ms: 14500,
        sector3Ms: 15500,
        isBestLap: true,
      );

      final restored = Lap.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.sessionId, original.sessionId);
      expect(restored.trackId, original.trackId);
      expect(restored.lapNumber, original.lapNumber);
      expect(restored.startTimestamp, original.startTimestamp);
      expect(restored.endTimestamp, original.endTimestamp);
      expect(restored.lapTimeMs, original.lapTimeMs);
      expect(restored.sector1Ms, original.sector1Ms);
      expect(restored.sector2Ms, original.sector2Ms);
      expect(restored.sector3Ms, original.sector3Ms);
      expect(restored.isBestLap, original.isBestLap);
    });
  });
}
