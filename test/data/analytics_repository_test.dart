import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:apx_tracer/data/database_helper.dart';
import 'package:apx_tracer/data/analytics_repository.dart';
import 'package:apx_tracer/models/session_analytics.dart';

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

class MockDatabase extends Mock implements Database {}

void main() {
  late MockDatabaseHelper mockDbHelper;
  late MockDatabase mockDb;
  late AnalyticsRepository repository;

  setUp(() {
    mockDbHelper = MockDatabaseHelper();
    mockDb = MockDatabase();
    repository = AnalyticsRepository(mockDbHelper);

    when(() => mockDbHelper.database).thenAnswer((_) async => mockDb);
  });

  group('AnalyticsRepository', () {
    group('insert', () {
      test('inserts analytics into database', () async {
        const analytics = SessionAnalytics(
          sessionId: 'session-1',
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

        when(() => mockDb.insert(
              'session_analytics',
              any(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            )).thenAnswer((_) async => 1);

        await repository.insert(analytics);

        verify(() => mockDb.insert(
              'session_analytics',
              analytics.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            )).called(1);
      });

      test('replaces existing analytics on conflict', () async {
        const analytics = SessionAnalytics(
          sessionId: 'session-1',
          durationSeconds: 1800.0,
          distanceKm: 6.0,
          totalLaps: 5,
          averageSpeedKmh: 72.0,
          maxSpeedKmh: 100.0,
          speedTraceKmh: [70.0, 80.0, 100.0],
        );

        when(() => mockDb.insert(
              'session_analytics',
              any(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            )).thenAnswer((_) async => 1);

        await repository.insert(analytics);

        verify(() => mockDb.insert(
              'session_analytics',
              any(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            )).called(1);
      });
    });

    group('getBySessionId', () {
      test('returns analytics when found', () async {
        final analyticsMap = <String, dynamic>{
          'session_id': 'session-1',
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

        when(() => mockDb.query(
              'session_analytics',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
              limit: 1,
            )).thenAnswer((_) async => [analyticsMap]);

        final result = await repository.getBySessionId('session-1');

        expect(result, isNotNull);
        expect(result!.sessionId, 'session-1');
        expect(result.durationSeconds, 3600.0);
        expect(result.distanceKm, 12.45);
        expect(result.totalLaps, 10);
        expect(result.bestLapTimeMs, 45000);
        expect(result.averageLapTimeMs, 48000);
        expect(result.averageSpeedKmh, 85.3);
        expect(result.maxSpeedKmh, 120.5);
        expect(result.speedTraceKmh, [80.0, 85.0, 90.0, 120.5, 100.0]);
        expect(result.bestSector1Ms, 15000);
        expect(result.bestSector2Ms, 14500);
        expect(result.bestSector3Ms, 15500);
      });

      test('returns null when not found', () async {
        when(() => mockDb.query(
              'session_analytics',
              where: 'session_id = ?',
              whereArgs: ['nonexistent'],
              limit: 1,
            )).thenAnswer((_) async => []);

        final result = await repository.getBySessionId('nonexistent');

        expect(result, isNull);
      });

      test('handles analytics with null optional fields', () async {
        final analyticsMap = <String, dynamic>{
          'session_id': 'session-1',
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

        when(() => mockDb.query(
              'session_analytics',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
              limit: 1,
            )).thenAnswer((_) async => [analyticsMap]);

        final result = await repository.getBySessionId('session-1');

        expect(result, isNotNull);
        expect(result!.totalLaps, 0);
        expect(result.bestLapTimeMs, isNull);
        expect(result.averageLapTimeMs, isNull);
        expect(result.bestSector1Ms, isNull);
        expect(result.bestSector2Ms, isNull);
        expect(result.bestSector3Ms, isNull);
      });
    });

    group('deleteBySessionId', () {
      test('deletes analytics for session', () async {
        when(() => mockDb.delete(
              'session_analytics',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
            )).thenAnswer((_) async => 1);

        await repository.deleteBySessionId('session-1');

        verify(() => mockDb.delete(
              'session_analytics',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
            )).called(1);
      });
    });
  });
}
