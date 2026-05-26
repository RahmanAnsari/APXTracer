import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:apx_tracer/data/database_helper.dart';
import 'package:apx_tracer/data/session_repository.dart';
import 'package:apx_tracer/models/session.dart';

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

class MockDatabase extends Mock implements Database {
  MockTransaction? mockTxn;
  Exception? transactionError;

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
      {bool? exclusive}) async {
    if (transactionError != null) {
      throw transactionError!;
    }
    return action(mockTxn ?? MockTransaction());
  }
}

class MockTransaction extends Mock implements Transaction {}

void main() {
  late MockDatabaseHelper mockDbHelper;
  late MockDatabase mockDb;
  late SessionRepository repository;

  setUp(() {
    mockDbHelper = MockDatabaseHelper();
    mockDb = MockDatabase();
    repository = SessionRepository(mockDbHelper);

    when(() => mockDbHelper.database).thenAnswer((_) async => mockDb);
  });

  group('SessionRepository', () {
    group('insert', () {
      test('inserts session into database', () async {
        const session = Session(
          id: 'session-1',
          startTime: 1700000000000,
          endTime: 1700003600000,
          durationMs: 3600000,
          trackId: 'track-1',
        );

        when(() => mockDb.insert(
              'sessions',
              any(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            )).thenAnswer((_) async => 1);

        await repository.insert(session);

        verify(() => mockDb.insert(
              'sessions',
              session.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            )).called(1);
      });
    });

    group('getById', () {
      test('returns session when found', () async {
        final sessionMap = <String, dynamic>{
          'id': 'session-1',
          'start_time': 1700000000000,
          'end_time': 1700003600000,
          'duration_ms': 3600000,
          'track_id': 'track-1',
          'created_at': 1700000000000,
        };

        when(() => mockDb.query(
              'sessions',
              where: 'id = ?',
              whereArgs: ['session-1'],
              limit: 1,
            )).thenAnswer((_) async => [sessionMap]);

        final result = await repository.getById('session-1');

        expect(result, isNotNull);
        expect(result!.id, 'session-1');
        expect(result.startTime, 1700000000000);
        expect(result.endTime, 1700003600000);
        expect(result.durationMs, 3600000);
        expect(result.trackId, 'track-1');
      });

      test('returns null when not found', () async {
        when(() => mockDb.query(
              'sessions',
              where: 'id = ?',
              whereArgs: ['nonexistent'],
              limit: 1,
            )).thenAnswer((_) async => []);

        final result = await repository.getById('nonexistent');

        expect(result, isNull);
      });
    });

    group('getAll', () {
      test('returns sessions ordered by start_time descending', () async {
        final sessionMaps = [
          <String, dynamic>{
            'id': 'session-3',
            'start_time': 1700010000000,
            'end_time': 1700013600000,
            'duration_ms': 3600000,
            'track_id': null,
            'created_at': 1700010000000,
          },
          <String, dynamic>{
            'id': 'session-2',
            'start_time': 1700005000000,
            'end_time': 1700008600000,
            'duration_ms': 3600000,
            'track_id': null,
            'created_at': 1700005000000,
          },
          <String, dynamic>{
            'id': 'session-1',
            'start_time': 1700000000000,
            'end_time': 1700003600000,
            'duration_ms': 3600000,
            'track_id': null,
            'created_at': 1700000000000,
          },
        ];

        when(() => mockDb.query(
              'sessions',
              orderBy: 'start_time DESC',
            )).thenAnswer((_) async => sessionMaps);

        final results = await repository.getAll();

        expect(results.length, 3);
        expect(results[0].id, 'session-3');
        expect(results[1].id, 'session-2');
        expect(results[2].id, 'session-1');
        // Verify ordering: most recent first
        expect(results[0].startTime, greaterThan(results[1].startTime));
        expect(results[1].startTime, greaterThan(results[2].startTime));
      });

      test('returns empty list when no sessions exist', () async {
        when(() => mockDb.query(
              'sessions',
              orderBy: 'start_time DESC',
            )).thenAnswer((_) async => []);

        final results = await repository.getAll();

        expect(results, isEmpty);
      });

      test('queries with correct orderBy parameter', () async {
        when(() => mockDb.query(
              'sessions',
              orderBy: 'start_time DESC',
            )).thenAnswer((_) async => []);

        await repository.getAll();

        verify(() => mockDb.query(
              'sessions',
              orderBy: 'start_time DESC',
            )).called(1);
      });
    });

    group('update', () {
      test('updates session in database', () async {
        const session = Session(
          id: 'session-1',
          startTime: 1700000000000,
          endTime: 1700003600000,
          durationMs: 3600000,
          trackId: 'track-1',
        );

        when(() => mockDb.update(
              'sessions',
              any(),
              where: 'id = ?',
              whereArgs: ['session-1'],
            )).thenAnswer((_) async => 1);

        await repository.update(session);

        verify(() => mockDb.update(
              'sessions',
              session.toMap(),
              where: 'id = ?',
              whereArgs: ['session-1'],
            )).called(1);
      });
    });

    group('delete', () {
      test('deletes session and associated data in transaction', () async {
        final mockTxn = MockTransaction();
        mockDb.mockTxn = mockTxn;

        when(() => mockTxn.delete(
              'session_analytics',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
            )).thenAnswer((_) async => 1);

        when(() => mockTxn.delete(
              'laps',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
            )).thenAnswer((_) async => 1);

        when(() => mockTxn.delete(
              'gps_samples',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
            )).thenAnswer((_) async => 1);

        when(() => mockTxn.delete(
              'sessions',
              where: 'id = ?',
              whereArgs: ['session-1'],
            )).thenAnswer((_) async => 1);

        await repository.delete('session-1');

        verify(() => mockTxn.delete(
              'session_analytics',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
            )).called(1);
        verify(() => mockTxn.delete(
              'laps',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
            )).called(1);
        verify(() => mockTxn.delete(
              'gps_samples',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
            )).called(1);
        verify(() => mockTxn.delete(
              'sessions',
              where: 'id = ?',
              whereArgs: ['session-1'],
            )).called(1);
      });

      test('transaction rollback on failure propagates error', () async {
        mockDb.transactionError = Exception('Transaction failed');

        expect(
          () => repository.delete('session-1'),
          throwsA(isA<Exception>()),
        );
      });
    });
  });
}
