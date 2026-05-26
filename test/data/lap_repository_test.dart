import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:apx_tracer/data/database_helper.dart';
import 'package:apx_tracer/data/lap_repository.dart';
import 'package:apx_tracer/models/lap.dart';

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

class MockBatch extends Mock implements Batch {}

void main() {
  late MockDatabaseHelper mockDbHelper;
  late MockDatabase mockDb;
  late LapRepository repository;

  setUp(() {
    mockDbHelper = MockDatabaseHelper();
    mockDb = MockDatabase();
    repository = LapRepository(mockDbHelper);

    when(() => mockDbHelper.database).thenAnswer((_) async => mockDb);
  });

  group('LapRepository', () {
    group('insert', () {
      test('inserts a single lap into database', () async {
        const lap = Lap(
          id: 'lap-1',
          sessionId: 'session-1',
          trackId: 'track-1',
          lapNumber: 1,
          startTimestamp: 1700000000000,
          endTimestamp: 1700000060000,
          lapTimeMs: 60000,
          sector1Ms: 20000,
          sector2Ms: 20000,
          sector3Ms: 20000,
          isBestLap: true,
        );

        when(() => mockDb.insert(
              'laps',
              any(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            )).thenAnswer((_) async => 1);

        await repository.insert(lap);

        verify(() => mockDb.insert(
              'laps',
              lap.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            )).called(1);
      });
    });

    group('insertBatch', () {
      test('inserts all laps in a transaction', () async {
        final mockTxn = MockTransaction();
        final mockBatch = MockBatch();
        mockDb.mockTxn = mockTxn;

        final laps = [
          const Lap(
            id: 'lap-1',
            sessionId: 'session-1',
            trackId: 'track-1',
            lapNumber: 1,
            startTimestamp: 1700000000000,
            endTimestamp: 1700000060000,
            lapTimeMs: 60000,
          ),
          const Lap(
            id: 'lap-2',
            sessionId: 'session-1',
            trackId: 'track-1',
            lapNumber: 2,
            startTimestamp: 1700000060000,
            endTimestamp: 1700000120000,
            lapTimeMs: 60000,
          ),
          const Lap(
            id: 'lap-3',
            sessionId: 'session-1',
            trackId: 'track-1',
            lapNumber: 3,
            startTimestamp: 1700000120000,
            endTimestamp: 1700000175000,
            lapTimeMs: 55000,
            isBestLap: true,
          ),
        ];

        when(() => mockTxn.batch()).thenReturn(mockBatch);
        when(() => mockBatch.insert(
              'laps',
              any(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            )).thenReturn(null);
        when(() => mockBatch.commit(noResult: true))
            .thenAnswer((_) async => []);

        await repository.insertBatch(laps);

        verify(() => mockBatch.insert(
              'laps',
              any(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            )).called(3);
        verify(() => mockBatch.commit(noResult: true)).called(1);
      });

      test('batch insert preserves order and count', () async {
        final mockTxn = MockTransaction();
        final mockBatch = MockBatch();
        mockDb.mockTxn = mockTxn;

        final laps = List.generate(
          5,
          (i) => Lap(
            id: 'lap-$i',
            sessionId: 'session-1',
            trackId: 'track-1',
            lapNumber: i + 1,
            startTimestamp: 1700000000000 + (i * 60000),
            endTimestamp: 1700000060000 + (i * 60000),
            lapTimeMs: 60000,
          ),
        );

        final insertedMaps = <Map<String, dynamic>>[];

        when(() => mockTxn.batch()).thenReturn(mockBatch);
        when(() => mockBatch.insert(
              'laps',
              any(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            )).thenAnswer((invocation) {
          insertedMaps.add(Map<String, dynamic>.from(
              invocation.positionalArguments[1] as Map<String, dynamic>));
        });
        when(() => mockBatch.commit(noResult: true))
            .thenAnswer((_) async => []);

        await repository.insertBatch(laps);

        // Verify count
        expect(insertedMaps.length, 5);

        // Verify order is preserved (lap numbers should be sequential)
        for (int i = 0; i < insertedMaps.length; i++) {
          expect(insertedMaps[i]['lap_number'], i + 1);
        }
      });

      test('does nothing when laps list is empty', () async {
        await repository.insertBatch([]);

        // Should not even access the database
        verifyNever(() => mockDbHelper.database);
      });

      test('transaction rollback on failure propagates error', () async {
        mockDb.transactionError = Exception('Transaction failed');

        final laps = [
          const Lap(
            id: 'lap-1',
            sessionId: 'session-1',
            trackId: 'track-1',
            lapNumber: 1,
            startTimestamp: 1700000000000,
            endTimestamp: 1700000060000,
            lapTimeMs: 60000,
          ),
        ];

        expect(
          () => repository.insertBatch(laps),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('getBySessionId', () {
      test('returns laps ordered by lap_number ascending', () async {
        final lapMaps = [
          <String, dynamic>{
            'id': 'lap-1',
            'session_id': 'session-1',
            'track_id': 'track-1',
            'lap_number': 1,
            'start_timestamp': 1700000000000,
            'end_timestamp': 1700000060000,
            'lap_time_ms': 60000,
            'sector1_ms': 20000,
            'sector2_ms': 20000,
            'sector3_ms': 20000,
            'is_best_lap': 0,
          },
          <String, dynamic>{
            'id': 'lap-2',
            'session_id': 'session-1',
            'track_id': 'track-1',
            'lap_number': 2,
            'start_timestamp': 1700000060000,
            'end_timestamp': 1700000115000,
            'lap_time_ms': 55000,
            'sector1_ms': 18000,
            'sector2_ms': 18000,
            'sector3_ms': 19000,
            'is_best_lap': 1,
          },
          <String, dynamic>{
            'id': 'lap-3',
            'session_id': 'session-1',
            'track_id': 'track-1',
            'lap_number': 3,
            'start_timestamp': 1700000115000,
            'end_timestamp': 1700000175000,
            'lap_time_ms': 60000,
            'sector1_ms': 20000,
            'sector2_ms': 20000,
            'sector3_ms': 20000,
            'is_best_lap': 0,
          },
        ];

        when(() => mockDb.query(
              'laps',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
              orderBy: 'lap_number ASC',
            )).thenAnswer((_) async => lapMaps);

        final results = await repository.getBySessionId('session-1');

        expect(results.length, 3);
        expect(results[0].lapNumber, 1);
        expect(results[1].lapNumber, 2);
        expect(results[2].lapNumber, 3);
        // Verify best lap is correctly deserialized
        expect(results[1].isBestLap, true);
      });

      test('returns empty list when no laps exist', () async {
        when(() => mockDb.query(
              'laps',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
              orderBy: 'lap_number ASC',
            )).thenAnswer((_) async => []);

        final results = await repository.getBySessionId('session-1');

        expect(results, isEmpty);
      });
    });

    group('deleteBySessionId', () {
      test('deletes all laps for session', () async {
        when(() => mockDb.delete(
              'laps',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
            )).thenAnswer((_) async => 3);

        await repository.deleteBySessionId('session-1');

        verify(() => mockDb.delete(
              'laps',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
            )).called(1);
      });
    });
  });
}
