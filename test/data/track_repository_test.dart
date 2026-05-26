import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:apx_tracer/data/database_helper.dart';
import 'package:apx_tracer/data/track_repository.dart';
import 'package:apx_tracer/models/track.dart';
import 'package:latlong2/latlong.dart';

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

class MockDatabase extends Mock implements Database {}

void main() {
  late MockDatabaseHelper mockDbHelper;
  late MockDatabase mockDb;
  late TrackRepository repository;

  setUp(() {
    mockDbHelper = MockDatabaseHelper();
    mockDb = MockDatabase();
    repository = TrackRepository(mockDbHelper);

    when(() => mockDbHelper.database).thenAnswer((_) async => mockDb);
  });

  group('TrackRepository', () {
    group('insert', () {
      test('inserts track into database', () async {
        final track = Track(
          id: 'track-1',
          name: 'Silverstone',
          polyline: [
            LatLng(52.0786, -1.0169),
            LatLng(52.0790, -1.0165),
          ],
          startFinish: LatLng(52.0786, -1.0169),
          sector1Fraction: 0.333,
          sector2Fraction: 0.666,
          sessionCount: 1,
          lastDriven: 1700000000000,
        );

        when(() => mockDb.insert(
              'tracks',
              any(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            )).thenAnswer((_) async => 1);

        await repository.insert(track);

        verify(() => mockDb.insert(
              'tracks',
              track.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            )).called(1);
      });
    });

    group('getById', () {
      test('returns track when found', () async {
        final trackMap = <String, dynamic>{
          'id': 'track-1',
          'name': 'Silverstone',
          'polyline': '[[52.0786,-1.0169],[52.079,-1.0165]]',
          'start_lat': 52.0786,
          'start_lng': -1.0169,
          'sector1_fraction': 0.333,
          'sector2_fraction': 0.666,
          'session_count': 5,
          'last_driven': 1700000000000,
          'created_at': 1700000000000,
        };

        when(() => mockDb.query(
              'tracks',
              where: 'id = ?',
              whereArgs: ['track-1'],
              limit: 1,
            )).thenAnswer((_) async => [trackMap]);

        final result = await repository.getById('track-1');

        expect(result, isNotNull);
        expect(result!.id, 'track-1');
        expect(result.name, 'Silverstone');
        expect(result.sessionCount, 5);
      });

      test('returns null when not found', () async {
        when(() => mockDb.query(
              'tracks',
              where: 'id = ?',
              whereArgs: ['nonexistent'],
              limit: 1,
            )).thenAnswer((_) async => []);

        final result = await repository.getById('nonexistent');

        expect(result, isNull);
      });
    });

    group('getAll', () {
      test('returns tracks ordered by last_driven descending', () async {
        final trackMaps = [
          <String, dynamic>{
            'id': 'track-3',
            'name': 'Brands Hatch',
            'polyline': '[[51.3569,0.2631]]',
            'start_lat': 51.3569,
            'start_lng': 0.2631,
            'sector1_fraction': 0.333,
            'sector2_fraction': 0.666,
            'session_count': 2,
            'last_driven': 1700010000000,
            'created_at': 1700000000000,
          },
          <String, dynamic>{
            'id': 'track-2',
            'name': 'Donington',
            'polyline': '[[52.8306,-1.3747]]',
            'start_lat': 52.8306,
            'start_lng': -1.3747,
            'sector1_fraction': 0.333,
            'sector2_fraction': 0.666,
            'session_count': 3,
            'last_driven': 1700005000000,
            'created_at': 1700000000000,
          },
          <String, dynamic>{
            'id': 'track-1',
            'name': 'Silverstone',
            'polyline': '[[52.0786,-1.0169]]',
            'start_lat': 52.0786,
            'start_lng': -1.0169,
            'sector1_fraction': 0.333,
            'sector2_fraction': 0.666,
            'session_count': 5,
            'last_driven': 1700000000000,
            'created_at': 1700000000000,
          },
        ];

        when(() => mockDb.query(
              'tracks',
              orderBy: 'last_driven DESC',
            )).thenAnswer((_) async => trackMaps);

        final results = await repository.getAll();

        expect(results.length, 3);
        expect(results[0].id, 'track-3');
        expect(results[1].id, 'track-2');
        expect(results[2].id, 'track-1');
        // Verify ordering: most recently driven first
        expect(results[0].lastDriven, greaterThan(results[1].lastDriven));
        expect(results[1].lastDriven, greaterThan(results[2].lastDriven));
      });

      test('returns empty list when no tracks exist', () async {
        when(() => mockDb.query(
              'tracks',
              orderBy: 'last_driven DESC',
            )).thenAnswer((_) async => []);

        final results = await repository.getAll();

        expect(results, isEmpty);
      });

      test('queries with correct orderBy parameter', () async {
        when(() => mockDb.query(
              'tracks',
              orderBy: 'last_driven DESC',
            )).thenAnswer((_) async => []);

        await repository.getAll();

        verify(() => mockDb.query(
              'tracks',
              orderBy: 'last_driven DESC',
            )).called(1);
      });
    });

    group('findNearby', () {
      test('returns tracks within 50m of given coordinates', () async {
        // Silverstone start/finish: 52.0786, -1.0169
        // A point very close (within 50m): 52.0786, -1.0169 (same point)
        final trackMaps = [
          <String, dynamic>{
            'id': 'track-1',
            'name': 'Silverstone',
            'polyline': '[[52.0786,-1.0169]]',
            'start_lat': 52.0786,
            'start_lng': -1.0169,
            'sector1_fraction': 0.333,
            'sector2_fraction': 0.666,
            'session_count': 5,
            'last_driven': 1700000000000,
            'created_at': 1700000000000,
          },
        ];

        when(() => mockDb.query(
              'tracks',
              orderBy: 'last_driven DESC',
            )).thenAnswer((_) async => trackMaps);

        final results = await repository.findNearby(52.0786, -1.0169);

        expect(results.length, 1);
        expect(results[0].id, 'track-1');
      });

      test('excludes tracks beyond 50m', () async {
        // Silverstone: 52.0786, -1.0169
        // A point far away: 51.5074, -0.1278 (London - ~100km away)
        final trackMaps = [
          <String, dynamic>{
            'id': 'track-1',
            'name': 'Silverstone',
            'polyline': '[[52.0786,-1.0169]]',
            'start_lat': 52.0786,
            'start_lng': -1.0169,
            'sector1_fraction': 0.333,
            'sector2_fraction': 0.666,
            'session_count': 5,
            'last_driven': 1700000000000,
            'created_at': 1700000000000,
          },
        ];

        when(() => mockDb.query(
              'tracks',
              orderBy: 'last_driven DESC',
            )).thenAnswer((_) async => trackMaps);

        final results = await repository.findNearby(51.5074, -0.1278);

        expect(results, isEmpty);
      });

      test('returns empty list when no tracks exist', () async {
        when(() => mockDb.query(
              'tracks',
              orderBy: 'last_driven DESC',
            )).thenAnswer((_) async => []);

        final results = await repository.findNearby(52.0786, -1.0169);

        expect(results, isEmpty);
      });
    });

    group('update', () {
      test('updates track in database', () async {
        final track = Track(
          id: 'track-1',
          name: 'Updated Name',
          polyline: [LatLng(52.0786, -1.0169)],
          startFinish: LatLng(52.0786, -1.0169),
          sector1Fraction: 0.333,
          sector2Fraction: 0.666,
          sessionCount: 6,
          lastDriven: 1700010000000,
        );

        when(() => mockDb.update(
              'tracks',
              any(),
              where: 'id = ?',
              whereArgs: ['track-1'],
            )).thenAnswer((_) async => 1);

        await repository.update(track);

        verify(() => mockDb.update(
              'tracks',
              track.toMap(),
              where: 'id = ?',
              whereArgs: ['track-1'],
            )).called(1);
      });
    });

    group('delete', () {
      test('deletes track by id', () async {
        when(() => mockDb.delete(
              'tracks',
              where: 'id = ?',
              whereArgs: ['track-1'],
            )).thenAnswer((_) async => 1);

        await repository.delete('track-1');

        verify(() => mockDb.delete(
              'tracks',
              where: 'id = ?',
              whereArgs: ['track-1'],
            )).called(1);
      });
    });
  });
}
