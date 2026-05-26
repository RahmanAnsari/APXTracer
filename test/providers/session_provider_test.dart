import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apx_tracer/data/analytics_repository.dart';
import 'package:apx_tracer/data/lap_repository.dart';
import 'package:apx_tracer/data/session_repository.dart';
import 'package:apx_tracer/models/lap.dart';
import 'package:apx_tracer/models/session.dart';
import 'package:apx_tracer/models/session_analytics.dart';
import 'package:apx_tracer/providers/session_provider.dart';

// --- Mocks ---

class MockSessionRepository extends Mock implements SessionRepository {}

class MockAnalyticsRepository extends Mock implements AnalyticsRepository {}

class MockLapRepository extends Mock implements LapRepository {}

void main() {
  late MockSessionRepository mockSessionRepo;
  late MockAnalyticsRepository mockAnalyticsRepo;
  late MockLapRepository mockLapRepo;

  setUp(() {
    mockSessionRepo = MockSessionRepository();
    mockAnalyticsRepo = MockAnalyticsRepository();
    mockLapRepo = MockLapRepository();
  });

  group('sessionsProvider', () {
    test('returns sessions in reverse chronological order', () async {
      // Sessions already ordered by start_time DESC from repository
      final sessions = [
        const Session(id: 's3', startTime: 1700003000000), // most recent
        const Session(id: 's2', startTime: 1700002000000),
        const Session(id: 's1', startTime: 1700001000000), // oldest
      ];

      when(() => mockSessionRepo.getAll()).thenAnswer((_) async => sessions);

      final container = ProviderContainer(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(mockSessionRepo),
        ],
      );
      addTearDown(container.dispose);

      // Read the provider and wait for it to resolve
      final result = await container.read(sessionsProvider.future);

      expect(result, hasLength(3));
      expect(result[0].id, equals('s3'));
      expect(result[1].id, equals('s2'));
      expect(result[2].id, equals('s1'));

      // Verify ordering: first element has the latest start time
      expect(result[0].startTime, greaterThan(result[1].startTime));
      expect(result[1].startTime, greaterThan(result[2].startTime));
    });

    test('returns empty list when no sessions exist', () async {
      when(() => mockSessionRepo.getAll()).thenAnswer((_) async => []);

      final container = ProviderContainer(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(mockSessionRepo),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(sessionsProvider.future);

      expect(result, isEmpty);
    });
  });

  group('sessionDetailProvider', () {
    test('loads session with analytics and laps', () async {
      const session = Session(
        id: 'session-1',
        startTime: 1700000000000,
        endTime: 1700000060000,
        durationMs: 60000,
        trackId: 'track-1',
      );

      const analytics = SessionAnalytics(
        sessionId: 'session-1',
        durationSeconds: 60.0,
        distanceKm: 2.5,
        totalLaps: 3,
        bestLapTimeMs: 18000,
        averageLapTimeMs: 20000,
        averageSpeedKmh: 150.0,
        maxSpeedKmh: 180.0,
        speedTraceKmh: [140.0, 150.0, 160.0],
      );

      final laps = [
        const Lap(
          id: 'lap-1',
          sessionId: 'session-1',
          trackId: 'track-1',
          lapNumber: 1,
          startTimestamp: 1700000000000,
          endTimestamp: 1700000020000,
          lapTimeMs: 20000,
        ),
        const Lap(
          id: 'lap-2',
          sessionId: 'session-1',
          trackId: 'track-1',
          lapNumber: 2,
          startTimestamp: 1700000020000,
          endTimestamp: 1700000038000,
          lapTimeMs: 18000,
          isBestLap: true,
        ),
      ];

      when(() => mockSessionRepo.getById('session-1'))
          .thenAnswer((_) async => session);
      when(() => mockAnalyticsRepo.getBySessionId('session-1'))
          .thenAnswer((_) async => analytics);
      when(() => mockLapRepo.getBySessionId('session-1'))
          .thenAnswer((_) async => laps);

      final container = ProviderContainer(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(mockSessionRepo),
          analyticsRepositoryProvider.overrideWithValue(mockAnalyticsRepo),
          lapRepositoryProvider.overrideWithValue(mockLapRepo),
        ],
      );
      addTearDown(container.dispose);

      final result =
          await container.read(sessionDetailProvider('session-1').future);

      expect(result, isNotNull);
      expect(result!.session.id, equals('session-1'));
      expect(result.analytics, isNotNull);
      expect(result.analytics!.totalLaps, equals(3));
      expect(result.analytics!.bestLapTimeMs, equals(18000));
      expect(result.laps, hasLength(2));
      expect(result.laps[0].lapNumber, equals(1));
      expect(result.laps[1].lapNumber, equals(2));
    });

    test('returns null for non-existent session', () async {
      when(() => mockSessionRepo.getById('non-existent'))
          .thenAnswer((_) async => null);

      final container = ProviderContainer(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(mockSessionRepo),
          analyticsRepositoryProvider.overrideWithValue(mockAnalyticsRepo),
          lapRepositoryProvider.overrideWithValue(mockLapRepo),
        ],
      );
      addTearDown(container.dispose);

      final result =
          await container.read(sessionDetailProvider('non-existent').future);

      expect(result, isNull);
    });
  });
}
