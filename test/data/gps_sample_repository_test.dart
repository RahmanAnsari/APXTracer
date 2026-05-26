import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:apx_tracer/data/database_helper.dart';
import 'package:apx_tracer/data/gps_sample_repository.dart';
import 'package:apx_tracer/models/gps_sample.dart';

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
  late GpsSampleRepository repository;

  setUp(() {
    mockDbHelper = MockDatabaseHelper();
    mockDb = MockDatabase();
    repository = GpsSampleRepository(mockDbHelper);

    when(() => mockDbHelper.database).thenAnswer((_) async => mockDb);
  });

  group('GpsSampleRepository', () {
    group('batchInsert', () {
      test('inserts all samples in a transaction with correct session_id',
          () async {
        final mockTxn = MockTransaction();
        final mockBatch = MockBatch();
        mockDb.mockTxn = mockTxn;

        final samples = [
          const GpsSample(
            timestamp: 1700000000000,
            latitude: 51.5074,
            longitude: -0.1278,
            speed: 20.0,
          ),
          const GpsSample(
            timestamp: 1700000000100,
            latitude: 51.5075,
            longitude: -0.1279,
            speed: 21.0,
          ),
          const GpsSample(
            timestamp: 1700000000200,
            latitude: 51.5076,
            longitude: -0.1280,
            speed: 22.0,
          ),
        ];

        when(() => mockTxn.batch()).thenReturn(mockBatch);
        when(() => mockBatch.insert('gps_samples', any()))
            .thenReturn(null);
        when(() => mockBatch.commit(noResult: true))
            .thenAnswer((_) async => []);

        await repository.batchInsert('session-1', samples);

        verify(() => mockBatch.insert('gps_samples', any())).called(3);
        verify(() => mockBatch.commit(noResult: true)).called(1);
      });

      test('batch insert preserves order and count', () async {
        final mockTxn = MockTransaction();
        final mockBatch = MockBatch();
        mockDb.mockTxn = mockTxn;

        final samples = List.generate(
          10,
          (i) => GpsSample(
            timestamp: 1700000000000 + (i * 100),
            latitude: 51.5074 + (i * 0.0001),
            longitude: -0.1278 + (i * 0.0001),
          ),
        );

        final insertedMaps = <Map<String, dynamic>>[];

        when(() => mockTxn.batch()).thenReturn(mockBatch);
        when(() => mockBatch.insert('gps_samples', any()))
            .thenAnswer((invocation) {
          insertedMaps
              .add(Map<String, dynamic>.from(
                  invocation.positionalArguments[1] as Map<String, dynamic>));
        });
        when(() => mockBatch.commit(noResult: true))
            .thenAnswer((_) async => []);

        await repository.batchInsert('session-1', samples);

        // Verify count
        expect(insertedMaps.length, 10);

        // Verify order is preserved (timestamps should be ascending)
        for (int i = 0; i < insertedMaps.length - 1; i++) {
          expect(
            insertedMaps[i]['timestamp'] as int,
            lessThan(insertedMaps[i + 1]['timestamp'] as int),
          );
        }

        // Verify session_id is added to each map
        for (final map in insertedMaps) {
          expect(map['session_id'], 'session-1');
        }
      });

      test('does nothing when samples list is empty', () async {
        await repository.batchInsert('session-1', []);

        // Should not even access the database
        verifyNever(() => mockDbHelper.database);
      });

      test('transaction rollback on failure propagates error', () async {
        mockDb.transactionError = Exception('Transaction failed');

        final samples = [
          const GpsSample(
            timestamp: 1700000000000,
            latitude: 51.5074,
            longitude: -0.1278,
          ),
        ];

        expect(
          () => repository.batchInsert('session-1', samples),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('getBySessionId', () {
      test('returns samples ordered by timestamp ascending', () async {
        final sampleMaps = [
          <String, dynamic>{
            'id': 1,
            'session_id': 'session-1',
            'timestamp': 1700000000000,
            'latitude': 51.5074,
            'longitude': -0.1278,
            'altitude': null,
            'speed': 20.0,
            'heading': null,
            'accuracy': 5.0,
            'is_low_accuracy': 0,
          },
          <String, dynamic>{
            'id': 2,
            'session_id': 'session-1',
            'timestamp': 1700000000100,
            'latitude': 51.5075,
            'longitude': -0.1279,
            'altitude': null,
            'speed': 21.0,
            'heading': null,
            'accuracy': 5.0,
            'is_low_accuracy': 0,
          },
          <String, dynamic>{
            'id': 3,
            'session_id': 'session-1',
            'timestamp': 1700000000200,
            'latitude': 51.5076,
            'longitude': -0.1280,
            'altitude': null,
            'speed': 22.0,
            'heading': null,
            'accuracy': 5.0,
            'is_low_accuracy': 0,
          },
        ];

        when(() => mockDb.query(
              'gps_samples',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
              orderBy: 'timestamp ASC',
            )).thenAnswer((_) async => sampleMaps);

        final results = await repository.getBySessionId('session-1');

        expect(results.length, 3);
        expect(results[0].timestamp, 1700000000000);
        expect(results[1].timestamp, 1700000000100);
        expect(results[2].timestamp, 1700000000200);
        // Verify ascending order
        expect(results[0].timestamp, lessThan(results[1].timestamp));
        expect(results[1].timestamp, lessThan(results[2].timestamp));
      });

      test('returns empty list when no samples exist', () async {
        when(() => mockDb.query(
              'gps_samples',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
              orderBy: 'timestamp ASC',
            )).thenAnswer((_) async => []);

        final results = await repository.getBySessionId('session-1');

        expect(results, isEmpty);
      });
    });

    group('countBySessionId', () {
      test('returns correct count', () async {
        when(() => mockDb.rawQuery(
              'SELECT COUNT(*) as count FROM gps_samples WHERE session_id = ?',
              ['session-1'],
            )).thenAnswer((_) async => [
              {'COUNT(*)': 150}
            ]);

        final count = await repository.countBySessionId('session-1');

        expect(count, 150);
      });

      test('returns 0 when no samples exist', () async {
        when(() => mockDb.rawQuery(
              'SELECT COUNT(*) as count FROM gps_samples WHERE session_id = ?',
              ['session-1'],
            )).thenAnswer((_) async => [
              {'COUNT(*)': 0}
            ]);

        final count = await repository.countBySessionId('session-1');

        expect(count, 0);
      });
    });

    group('deleteBySessionId', () {
      test('deletes all samples for session', () async {
        when(() => mockDb.delete(
              'gps_samples',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
            )).thenAnswer((_) async => 100);

        await repository.deleteBySessionId('session-1');

        verify(() => mockDb.delete(
              'gps_samples',
              where: 'session_id = ?',
              whereArgs: ['session-1'],
            )).called(1);
      });
    });
  });
}
