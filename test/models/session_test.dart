import 'package:flutter_test/flutter_test.dart';
import 'package:apx_tracer/models/session.dart';

void main() {
  group('Session', () {
    test('toMap() serializes all fields correctly', () {
      const session = Session(
        id: 'session-123',
        startTime: 1700000000000,
        endTime: 1700003600000,
        durationMs: 3600000,
        trackId: 'track-456',
      );

      final map = session.toMap();

      expect(map['id'], 'session-123');
      expect(map['start_time'], 1700000000000);
      expect(map['end_time'], 1700003600000);
      expect(map['duration_ms'], 3600000);
      expect(map['track_id'], 'track-456');
      expect(map['created_at'], 1700000000000);
    });

    test('toMap() serializes null optional fields', () {
      const session = Session(
        id: 'session-123',
        startTime: 1700000000000,
      );

      final map = session.toMap();

      expect(map['end_time'], isNull);
      expect(map['duration_ms'], isNull);
      expect(map['track_id'], isNull);
    });

    test('fromMap() deserializes all fields correctly', () {
      final map = <String, dynamic>{
        'id': 'session-123',
        'start_time': 1700000000000,
        'end_time': 1700003600000,
        'duration_ms': 3600000,
        'track_id': 'track-456',
        'created_at': 1700000000000,
      };

      final session = Session.fromMap(map);

      expect(session.id, 'session-123');
      expect(session.startTime, 1700000000000);
      expect(session.endTime, 1700003600000);
      expect(session.durationMs, 3600000);
      expect(session.trackId, 'track-456');
    });

    test('fromMap() handles null optional fields', () {
      final map = <String, dynamic>{
        'id': 'session-123',
        'start_time': 1700000000000,
        'end_time': null,
        'duration_ms': null,
        'track_id': null,
        'created_at': 1700000000000,
      };

      final session = Session.fromMap(map);

      expect(session.endTime, isNull);
      expect(session.durationMs, isNull);
      expect(session.trackId, isNull);
    });

    test('round-trip toMap/fromMap preserves all data', () {
      const original = Session(
        id: 'session-abc',
        startTime: 1700000000000,
        endTime: 1700003600000,
        durationMs: 3600000,
        trackId: 'track-xyz',
      );

      final restored = Session.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.startTime, original.startTime);
      expect(restored.endTime, original.endTime);
      expect(restored.durationMs, original.durationMs);
      expect(restored.trackId, original.trackId);
    });
  });
}
