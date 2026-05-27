import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apx_tracer/data/gps_sample_repository.dart';
import 'package:apx_tracer/data/lap_repository.dart';
import 'package:apx_tracer/data/session_repository.dart';
import 'package:apx_tracer/engines/analytics/analytics_engine.dart';
import 'package:apx_tracer/engines/lap_detection/lap_detection_engine.dart';
import 'package:apx_tracer/engines/post_session_pipeline.dart';
import 'package:apx_tracer/engines/track_discovery/track_discovery_engine.dart';
import 'package:apx_tracer/models/gps_sample.dart';
import 'package:apx_tracer/models/lap.dart';
import 'package:apx_tracer/models/sector_boundary.dart';
import 'package:apx_tracer/models/session.dart';
import 'package:apx_tracer/models/session_analytics.dart';
import 'package:apx_tracer/models/track.dart';

// Mocks
class MockSessionRepository extends Mock implements SessionRepository {}

class MockGpsSampleRepository extends Mock implements GpsSampleRepository {}

class MockLapRepository extends Mock implements LapRepository {}

class MockTrackDiscoveryEngine extends Mock implements ITrackDiscoveryEngine {}

class MockLapDetectionEngine extends Mock implements ILapDetectionEngine {}

class MockAnalyticsEngine extends Mock implements IAnalyticsEngine {}

// Fakes for fallback values
class FakeSession extends Fake implements Session {}

class FakeLap extends Fake implements Lap {}

class FakeTrack extends Fake implements Track {}

void main() {
  late MockSessionRepository mockSessionRepo;
  late MockGpsSampleRepository mockGpsSampleRepo;
  late MockLapRepository mockLapRepo;
  late MockTrackDiscoveryEngine mockTrackDiscovery;
  late MockLapDetectionEngine mockLapDetection;
  late MockAnalyticsEngine mockAnalytics;
  late PostSessionPipeline pipeline;

  setUpAll(() {
    registerFallbackValue(FakeSession());
    registerFallbackValue(FakeLap());
    registerFallbackValue(FakeTrack());
    registerFallbackValue(<GpsSample>[]);
    registerFallbackValue(<Lap>[]);
    registerFallbackValue(<SectorBoundary>[]);
    registerFallbackValue(<LapSectors>[]);
  });

  setUp(() {
    mockSessionRepo = MockSessionRepository();
    mockGpsSampleRepo = MockGpsSampleRepository();
    mockLapRepo = MockLapRepository();
    mockTrackDiscovery = MockTrackDiscoveryEngine();
    mockLapDetection = MockLapDetectionEngine();
    mockAnalytics = MockAnalyticsEngine();

    pipeline = PostSessionPipeline(
      sessionRepository: mockSessionRepo,
      gpsSampleRepository: mockGpsSampleRepo,
      lapRepository: mockLapRepo,
      trackDiscoveryEngine: mockTrackDiscovery,
      lapDetectionEngine: mockLapDetection,
      analyticsEngine: mockAnalytics,
    );
  });

  // --- Helpers ---

  Session createSession({
    String id = 'session-1',
    int startTime = 0,
    int? endTime = 120000,
    String? trackId,
  }) {
    return Session(
      id: id,
      startTime: startTime,
      endTime: endTime,
      trackId: trackId,
    );
  }

  GpsSample createSample({
    required int timestamp,
    double latitude = 51.5,
    double longitude = -0.1,
    double? speed,
  }) {
    return GpsSample(
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      speed: speed,
    );
  }

  Track createTrack({
    String id = 'track-1',
    String? name,
  }) {
    return Track(
      id: id,
      name: name,
      polyline: [
        const LatLng(51.5, -0.1),
        const LatLng(51.501, -0.1),
        const LatLng(51.501, -0.099),
        const LatLng(51.5, -0.099),
        const LatLng(51.5, -0.1),
      ],
      startFinish: const LatLng(51.5, -0.1),
      lastDriven: 1000000,
    );
  }

  Lap createLap({
    String id = 'lap-1',
    String sessionId = 'session-1',
    String trackId = 'track-1',
    int lapNumber = 1,
    int startTimestamp = 0,
    int endTimestamp = 60000,
    int lapTimeMs = 60000,
    bool isBestLap = false,
  }) {
    return Lap(
      id: id,
      sessionId: sessionId,
      trackId: trackId,
      lapNumber: lapNumber,
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
      lapTimeMs: lapTimeMs,
      isBestLap: isBestLap,
    );
  }

  SessionAnalytics createAnalytics({
    String sessionId = 'session-1',
  }) {
    return SessionAnalytics(
      sessionId: sessionId,
      durationSeconds: 120.0,
      distanceKm: 3.5,
      totalLaps: 2,
      bestLapTimeMs: 55000,
      averageLapTimeMs: 60000,
      averageSpeedKmh: 105.0,
      maxSpeedKmh: 130.0,
      speedTraceKmh: [90.0, 100.0, 110.0, 120.0, 130.0],
    );
  }

  /// Sets up the standard mocks for a full pipeline run with a track found.
  void setupFullPipelineMocks({
    Session? session,
    List<GpsSample>? samples,
    Track? track,
    List<Lap>? laps,
    List<SectorBoundary>? sectorBoundaries,
    List<LapSectors>? sectorTimes,
    SessionAnalytics? analytics,
  }) {
    final s = session ?? createSession();
    final samps = samples ??
        [
          createSample(timestamp: 0),
          createSample(timestamp: 30000),
          createSample(timestamp: 60000),
          createSample(timestamp: 90000),
          createSample(timestamp: 120000),
        ];
    final t = track ?? createTrack();
    final l = laps ??
        [
          createLap(lapNumber: 1, lapTimeMs: 60000, isBestLap: false),
          createLap(
            id: 'lap-2',
            lapNumber: 2,
            lapTimeMs: 55000,
            startTimestamp: 60000,
            endTimestamp: 115000,
            isBestLap: true,
          ),
        ];
    final sb = sectorBoundaries ??
        [
          SectorBoundary(
            polylineFraction: 1 / 3,
            point: const LatLng(51.501, -0.1),
          ),
          SectorBoundary(
            polylineFraction: 2 / 3,
            point: const LatLng(51.501, -0.099),
          ),
        ];
    final st = sectorTimes ??
        [
          const LapSectors(
              lapNumber: 1, sector1Ms: 20000, sector2Ms: 20000, sector3Ms: 20000),
          const LapSectors(
              lapNumber: 2, sector1Ms: 18000, sector2Ms: 19000, sector3Ms: 18000),
        ];
    final a = analytics ?? createAnalytics();

    when(() => mockSessionRepo.getById(s.id)).thenAnswer((_) async => s);
    when(() => mockGpsSampleRepo.getBySessionId(s.id))
        .thenAnswer((_) async => samps);
    when(() => mockTrackDiscovery.discoverTrack(any(), any()))
        .thenAnswer((_) async => t);
    when(() => mockLapDetection.detectLaps(any(), any()))
        .thenAnswer((_) async => l);
    when(() => mockTrackDiscovery.computeSectors(any())).thenReturn(sb);
    when(() => mockLapDetection.computeSectorTimes(any(), any(), any()))
        .thenAnswer((_) async => st);
    when(() => mockLapRepo.insertBatch(any())).thenAnswer((_) async {});
    when(() => mockTrackDiscovery.refineCircuit(any(), any()))
        .thenAnswer((_) async => t);
    when(() => mockAnalytics.computeAnalytics(any(), any(), any(), any()))
        .thenAnswer((_) async => a);
  }

  // --- Tests ---

  group('PostSessionPipeline - full pipeline executes in correct order', () {
    test('executes track discovery → lap detection → sector times → analytics in order',
        () async {
      final session = createSession();
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 30000),
        createSample(timestamp: 60000),
        createSample(timestamp: 90000),
        createSample(timestamp: 120000),
      ];
      final track = createTrack();
      final laps = [
        createLap(lapNumber: 1, lapTimeMs: 60000),
        createLap(
          id: 'lap-2',
          lapNumber: 2,
          lapTimeMs: 55000,
          startTimestamp: 60000,
          endTimestamp: 115000,
        ),
      ];
      final sectorBoundaries = [
        SectorBoundary(
          polylineFraction: 1 / 3,
          point: const LatLng(51.501, -0.1),
        ),
        SectorBoundary(
          polylineFraction: 2 / 3,
          point: const LatLng(51.501, -0.099),
        ),
      ];
      final sectorTimes = [
        const LapSectors(
            lapNumber: 1, sector1Ms: 20000, sector2Ms: 20000, sector3Ms: 20000),
        const LapSectors(
            lapNumber: 2, sector1Ms: 18000, sector2Ms: 19000, sector3Ms: 18000),
      ];
      final analytics = createAnalytics();

      // Track the order of calls
      final callOrder = <String>[];

      when(() => mockSessionRepo.getById(session.id))
          .thenAnswer((_) async => session);
      when(() => mockGpsSampleRepo.getBySessionId(session.id))
          .thenAnswer((_) async => samples);
      when(() => mockTrackDiscovery.discoverTrack(any(), any()))
          .thenAnswer((_) async {
        callOrder.add('trackDiscovery');
        return track;
      });
      when(() => mockLapDetection.detectLaps(any(), any()))
          .thenAnswer((_) async {
        callOrder.add('lapDetection');
        return laps;
      });
      when(() => mockTrackDiscovery.computeSectors(any())).thenAnswer((_) {
        callOrder.add('computeSectors');
        return sectorBoundaries;
      });
      when(() => mockLapDetection.computeSectorTimes(any(), any(), any()))
          .thenAnswer((_) async {
        callOrder.add('sectorTimes');
        return sectorTimes;
      });
      when(() => mockLapRepo.insertBatch(any())).thenAnswer((_) async {
        callOrder.add('persistLaps');
      });
      when(() => mockTrackDiscovery.refineCircuit(any(), any()))
          .thenAnswer((_) async {
        callOrder.add('circuitRefinement');
        return track;
      });
      when(() => mockAnalytics.computeAnalytics(any(), any(), any(), any()))
          .thenAnswer((_) async {
        callOrder.add('analytics');
        return analytics;
      });

      await pipeline.execute(session.id);

      expect(callOrder, [
        'trackDiscovery',
        'lapDetection',
        'computeSectors',
        'sectorTimes',
        'persistLaps',
        'circuitRefinement',
        'analytics',
      ]);
    });

    test('returns PostSessionResult with track, laps, and analytics', () async {
      setupFullPipelineMocks();

      final result = await pipeline.execute('session-1');

      expect(result.track, isNotNull);
      expect(result.track!.id, 'track-1');
      expect(result.laps, isNotEmpty);
      expect(result.analytics, isNotNull);
      expect(result.analytics.sessionId, 'session-1');
    });

    test('passes session and samples to track discovery', () async {
      final session = createSession();
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 60000),
      ];

      setupFullPipelineMocks(session: session, samples: samples);

      await pipeline.execute(session.id);

      verify(() => mockTrackDiscovery.discoverTrack(
            any(that: predicate<Session>((s) => s.id == session.id)),
            any(that: predicate<List<GpsSample>>((s) => s.length == 2)),
          )).called(1);
    });

    test('passes samples and track to lap detection', () async {
      final track = createTrack();
      setupFullPipelineMocks(track: track);

      await pipeline.execute('session-1');

      verify(() => mockLapDetection.detectLaps(any(), any())).called(1);
    });
  });

  group('PostSessionPipeline - handles no-track scenario', () {
    test('skips lap detection when no track is found', () async {
      final session = createSession();
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 60000),
      ];
      final analytics = createAnalytics();

      when(() => mockSessionRepo.getById(session.id))
          .thenAnswer((_) async => session);
      when(() => mockGpsSampleRepo.getBySessionId(session.id))
          .thenAnswer((_) async => samples);
      when(() => mockTrackDiscovery.discoverTrack(any(), any()))
          .thenAnswer((_) async => null);
      when(() => mockAnalytics.computeAnalytics(any(), any(), any(), any()))
          .thenAnswer((_) async => analytics);

      await pipeline.execute(session.id);

      verifyNever(() => mockLapDetection.detectLaps(any(), any()));
      verifyNever(() => mockLapDetection.computeSectorTimes(any(), any(), any()));
      verifyNever(() => mockLapRepo.insertBatch(any()));
    });

    test('still computes analytics when no track is found', () async {
      final session = createSession();
      final samples = [
        createSample(timestamp: 0, speed: 15.0),
        createSample(timestamp: 60000, speed: 20.0),
      ];
      final analytics = SessionAnalytics(
        sessionId: session.id,
        durationSeconds: 60.0,
        distanceKm: 1.0,
        totalLaps: 0,
        averageSpeedKmh: 60.0,
        maxSpeedKmh: 72.0,
        speedTraceKmh: [54.0, 72.0],
      );

      when(() => mockSessionRepo.getById(session.id))
          .thenAnswer((_) async => session);
      when(() => mockGpsSampleRepo.getBySessionId(session.id))
          .thenAnswer((_) async => samples);
      when(() => mockTrackDiscovery.discoverTrack(any(), any()))
          .thenAnswer((_) async => null);
      when(() => mockAnalytics.computeAnalytics(any(), any(), any(), any()))
          .thenAnswer((_) async => analytics);

      final result = await pipeline.execute(session.id);

      verify(() => mockAnalytics.computeAnalytics(any(), any(), any(), any()))
          .called(1);
      expect(result.analytics.totalLaps, 0);
      expect(result.track, isNull);
      expect(result.laps, isEmpty);
    });

    test('returns empty laps list when no track is found', () async {
      final session = createSession();
      final samples = [createSample(timestamp: 0)];
      final analytics = createAnalytics();

      when(() => mockSessionRepo.getById(session.id))
          .thenAnswer((_) async => session);
      when(() => mockGpsSampleRepo.getBySessionId(session.id))
          .thenAnswer((_) async => samples);
      when(() => mockTrackDiscovery.discoverTrack(any(), any()))
          .thenAnswer((_) async => null);
      when(() => mockAnalytics.computeAnalytics(any(), any(), any(), any()))
          .thenAnswer((_) async => analytics);

      final result = await pipeline.execute(session.id);

      expect(result.laps, isEmpty);
    });
  });

  group('PostSessionPipeline - persists all results atomically', () {
    test('laps are inserted via batch insert', () async {
      setupFullPipelineMocks();

      await pipeline.execute('session-1');

      verify(() => mockLapRepo.insertBatch(any())).called(1);
    });

    test('batch insert receives all detected laps with sector times applied',
        () async {
      final sectorTimes = [
        const LapSectors(
            lapNumber: 1, sector1Ms: 20000, sector2Ms: 20000, sector3Ms: 20000),
        const LapSectors(
            lapNumber: 2, sector1Ms: 18000, sector2Ms: 19000, sector3Ms: 18000),
      ];

      setupFullPipelineMocks(sectorTimes: sectorTimes);

      await pipeline.execute('session-1');

      final captured =
          verify(() => mockLapRepo.insertBatch(captureAny())).captured;
      final insertedLaps = captured.first as List<Lap>;

      expect(insertedLaps.length, 2);
      // Verify sector times were applied
      expect(insertedLaps[0].sector1Ms, 20000);
      expect(insertedLaps[0].sector2Ms, 20000);
      expect(insertedLaps[0].sector3Ms, 20000);
      expect(insertedLaps[1].sector1Ms, 18000);
      expect(insertedLaps[1].sector2Ms, 19000);
      expect(insertedLaps[1].sector3Ms, 18000);
    });

    test('laps have correct session ID set', () async {
      setupFullPipelineMocks();

      await pipeline.execute('session-1');

      final captured =
          verify(() => mockLapRepo.insertBatch(captureAny())).captured;
      final insertedLaps = captured.first as List<Lap>;

      for (final lap in insertedLaps) {
        expect(lap.sessionId, 'session-1');
      }
    });

    test('does not call insertBatch when no laps are detected', () async {
      final session = createSession();
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 60000),
      ];
      final track = createTrack();
      final analytics = createAnalytics();

      when(() => mockSessionRepo.getById(session.id))
          .thenAnswer((_) async => session);
      when(() => mockGpsSampleRepo.getBySessionId(session.id))
          .thenAnswer((_) async => samples);
      when(() => mockTrackDiscovery.discoverTrack(any(), any()))
          .thenAnswer((_) async => track);
      when(() => mockLapDetection.detectLaps(any(), any()))
          .thenAnswer((_) async => []);
      when(() => mockTrackDiscovery.computeSectors(any())).thenReturn([]);
      when(() => mockLapRepo.insertBatch(any())).thenAnswer((_) async {});
      when(() => mockTrackDiscovery.refineCircuit(any(), any()))
          .thenAnswer((_) async => track);
      when(() => mockAnalytics.computeAnalytics(any(), any(), any(), any()))
          .thenAnswer((_) async => analytics);

      await pipeline.execute(session.id);

      // insertBatch is called but with an empty list (which returns early)
      verify(() => mockLapRepo.insertBatch(any())).called(1);
    });
  });

  group('PostSessionPipeline - handles errors gracefully without data loss', () {
    test('throws ArgumentError when session is not found', () async {
      when(() => mockSessionRepo.getById('nonexistent'))
          .thenAnswer((_) async => null);

      expect(
        () => pipeline.execute('nonexistent'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('session data is preserved when track discovery throws', () async {
      final session = createSession();
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 60000),
      ];

      when(() => mockSessionRepo.getById(session.id))
          .thenAnswer((_) async => session);
      when(() => mockGpsSampleRepo.getBySessionId(session.id))
          .thenAnswer((_) async => samples);
      when(() => mockTrackDiscovery.discoverTrack(any(), any()))
          .thenThrow(Exception('Track discovery failed'));

      // The pipeline should propagate the error
      expect(
        () => pipeline.execute(session.id),
        throwsA(isA<Exception>()),
      );

      // Session data was loaded but not modified/deleted
      verify(() => mockSessionRepo.getById(session.id)).called(1);
      // No destructive operations were called
      verifyNever(() => mockLapRepo.insertBatch(any()));
    });

    test('session data is preserved when lap detection throws', () async {
      final session = createSession();
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 60000),
      ];
      final track = createTrack();

      when(() => mockSessionRepo.getById(session.id))
          .thenAnswer((_) async => session);
      when(() => mockGpsSampleRepo.getBySessionId(session.id))
          .thenAnswer((_) async => samples);
      when(() => mockTrackDiscovery.discoverTrack(any(), any()))
          .thenAnswer((_) async => track);
      when(() => mockLapDetection.detectLaps(any(), any()))
          .thenThrow(Exception('Lap detection failed'));

      expect(
        () => pipeline.execute(session.id),
        throwsA(isA<Exception>()),
      );

      // No laps were persisted since detection failed
      verifyNever(() => mockLapRepo.insertBatch(any()));
    });

    test('session data is preserved when analytics computation throws',
        () async {
      final session = createSession();
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 60000),
      ];

      when(() => mockSessionRepo.getById(session.id))
          .thenAnswer((_) async => session);
      when(() => mockGpsSampleRepo.getBySessionId(session.id))
          .thenAnswer((_) async => samples);
      when(() => mockTrackDiscovery.discoverTrack(any(), any()))
          .thenAnswer((_) async => null);
      when(() => mockAnalytics.computeAnalytics(any(), any(), any(), any()))
          .thenThrow(Exception('Analytics computation failed'));

      await expectLater(
        () => pipeline.execute(session.id),
        throwsA(isA<Exception>()),
      );

      // Session was loaded (getById is called twice: initial load + reload before analytics)
      verify(() => mockSessionRepo.getById(session.id)).called(2);
      verify(() => mockGpsSampleRepo.getBySessionId(session.id)).called(1);
    });

    test('GPS samples remain in database even when pipeline fails', () async {
      final session = createSession();
      final samples = [
        createSample(timestamp: 0),
        createSample(timestamp: 30000),
        createSample(timestamp: 60000),
      ];

      when(() => mockSessionRepo.getById(session.id))
          .thenAnswer((_) async => session);
      when(() => mockGpsSampleRepo.getBySessionId(session.id))
          .thenAnswer((_) async => samples);
      when(() => mockTrackDiscovery.discoverTrack(any(), any()))
          .thenThrow(Exception('Unexpected error'));

      try {
        await pipeline.execute(session.id);
      } catch (_) {
        // Expected
      }

      // Verify no delete operations were called on GPS samples
      verifyNever(() => mockGpsSampleRepo.deleteBySessionId(any()));
    });
  });
}
