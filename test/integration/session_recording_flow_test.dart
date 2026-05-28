import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apx_tracer/data/analytics_repository.dart';
import 'package:apx_tracer/data/gps_sample_repository.dart';
import 'package:apx_tracer/data/lap_repository.dart';
import 'package:apx_tracer/data/session_repository.dart';
import 'package:apx_tracer/data/track_repository.dart';
import 'package:apx_tracer/engines/analytics/analytics_engine.dart';
import 'package:apx_tracer/engines/lap_detection/lap_detection_engine.dart';
import 'package:apx_tracer/engines/post_session_pipeline.dart';
import 'package:apx_tracer/engines/recording/gps_service.dart';
import 'package:apx_tracer/engines/recording/recording_engine.dart';
import 'package:apx_tracer/engines/track_discovery/track_discovery_engine.dart';
import 'package:apx_tracer/models/gps_sample.dart';
import 'package:apx_tracer/models/lap.dart';
import 'package:apx_tracer/models/sector_boundary.dart';
import 'package:apx_tracer/models/session.dart';
import 'package:apx_tracer/models/session_analytics.dart';
import 'package:apx_tracer/models/track.dart';
import 'package:apx_tracer/providers/recording_provider.dart';
import 'package:apx_tracer/providers/analytics_provider.dart';
import 'package:apx_tracer/providers/session_provider.dart';
import 'package:apx_tracer/screens/home_screen.dart';
import 'package:apx_tracer/screens/recording_screen.dart';
import 'package:apx_tracer/screens/session_summary_screen.dart';

import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

// --- Mocks ---

class MockSessionRepository extends Mock implements SessionRepository {}

class MockGpsSampleRepository extends Mock implements GpsSampleRepository {}

class MockLapRepository extends Mock implements LapRepository {}

class MockTrackDiscoveryEngine extends Mock implements ITrackDiscoveryEngine {}

class MockLapDetectionEngine extends Mock implements ILapDetectionEngine {}

class MockAnalyticsEngine extends Mock implements IAnalyticsEngine {}

class MockGpsService extends Mock implements GpsService {}

class MockUuid extends Mock implements Uuid {}

class MockRecordingEngine extends Mock implements IRecordingEngine {}

class MockPostSessionPipeline extends Mock implements PostSessionPipeline {}

class MockAnalyticsRepository extends Mock implements AnalyticsRepository {}

class MockTrackRepository extends Mock implements TrackRepository {}

// --- Fakes ---

class FakeSession extends Fake implements Session {}

class FakeGpsSample extends Fake implements GpsSample {}

class FakeLap extends Fake implements Lap {}

class FakeTrack extends Fake implements Track {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeSession());
    registerFallbackValue(FakeGpsSample());
    registerFallbackValue(FakeLap());
    registerFallbackValue(FakeTrack());
    registerFallbackValue(<GpsSample>[]);
    registerFallbackValue(<Lap>[]);
    registerFallbackValue(<SectorBoundary>[]);
    registerFallbackValue(<LapSectors>[]);
    registerFallbackValue(const Duration(seconds: 10));
    registerFallbackValue('');
  });

  // =========================================================================
  // Test 1: Full session recording flow with mocked GPS
  // Validates: Requirements 1.1, 1.5
  // =========================================================================
  group('Full session recording flow with mocked GPS', () {
    late MockSessionRepository mockSessionRepo;
    late MockGpsSampleRepository mockGpsSampleRepo;
    late MockGpsService mockGpsService;
    late MockUuid mockUuid;
    late RecordingEngine engine;
    late StreamController<Position> positionStreamController;

    setUp(() {
      mockSessionRepo = MockSessionRepository();
      mockGpsSampleRepo = MockGpsSampleRepository();
      mockGpsService = MockGpsService();
      mockUuid = MockUuid();
      positionStreamController = StreamController<Position>.broadcast();

      engine = RecordingEngine(
        sessionRepository: mockSessionRepo,
        gpsSampleRepository: mockGpsSampleRepo,
        gpsService: mockGpsService,
        uuid: mockUuid,
      );
    });

    tearDown(() {
      engine.dispose();
      positionStreamController.close();
    });

    /// Sets up mocks for a successful start.
    void setupSuccessfulStart({String sessionId = 'integration-session'}) {
      when(() => mockUuid.v4()).thenReturn(sessionId);
      when(() => mockGpsService.checkPermissionsAndAcquireFix(
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => Position(
            latitude: 51.5074,
            longitude: -0.1278,
            timestamp: DateTime.now(),
            accuracy: 5.0,
            altitude: 100.0,
            altitudeAccuracy: 1.0,
            heading: 90.0,
            headingAccuracy: 1.0,
            speed: 0.0,
            speedAccuracy: 1.0,
          ));
      when(() => mockGpsService.getPositionStream())
          .thenAnswer((_) => positionStreamController.stream);
      when(() => mockSessionRepo.insert(any())).thenAnswer((_) async {});
      when(() => mockSessionRepo.update(any())).thenAnswer((_) async {});
      when(() => mockSessionRepo.getById(any())).thenAnswer((_) async =>
          Session(
            id: sessionId,
            startTime: DateTime.now().millisecondsSinceEpoch,
            endTime: DateTime.now().millisecondsSinceEpoch + 60000,
            durationMs: 60000,
          ));
      when(() => mockGpsSampleRepo.batchInsert(any(), any()))
          .thenAnswer((_) async {});
    }

    test('recording starts, captures GPS samples, and persists to DB',
        () async {
      setupSuccessfulStart();

      // Start session
      final sessionId = await engine.startSession();
      expect(sessionId, equals('integration-session'));
      expect(engine.isRecording, isTrue);

      // Simulate GPS positions arriving (circuit with 30 samples at 10 Hz)
      for (int i = 0; i < 30; i++) {
        positionStreamController.add(Position(
          latitude: 51.5074 + (i * 0.0001),
          longitude: -0.1278 + (i * 0.00005),
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              1700000000000 + (i * 100)),
          accuracy: 5.0,
          altitude: 100.0,
          altitudeAccuracy: 1.0,
          heading: (i * 12.0) % 360,
          headingAccuracy: 1.0,
          speed: 15.0 + (i % 5).toDouble(),
          speedAccuracy: 1.0,
        ));
      }

      // Wait for batch persist timer to fire
      await Future.delayed(const Duration(milliseconds: 1500));

      // Verify samples were persisted to the database
      final captured = verify(
        () => mockGpsSampleRepo.batchInsert('integration-session', captureAny()),
      ).captured;

      final totalSamples = captured.fold<int>(
        0,
        (sum, batch) => sum + (batch as List<GpsSample>).length,
      );
      expect(totalSamples, equals(30));

      // Verify chronological order is preserved
      final allSamples =
          captured.expand((batch) => batch as List<GpsSample>).toList();
      for (int i = 1; i < allSamples.length; i++) {
        expect(
          allSamples[i].timestamp,
          greaterThan(allSamples[i - 1].timestamp),
        );
      }

      // Stop session and verify finalization
      final session = await engine.stopSession();
      expect(session, isNotNull);
      expect(session.endTime, isNotNull);
      expect(session.durationMs, isNotNull);
      expect(engine.isRecording, isFalse);

      // Verify session was updated with end time
      verify(() => mockSessionRepo.update(any())).called(1);
    });

    test('stop session flushes remaining buffered samples', () async {
      setupSuccessfulStart();

      await engine.startSession();

      // Send positions just before stopping (won't have time for timer)
      for (int i = 0; i < 5; i++) {
        positionStreamController.add(Position(
          latitude: 51.5074,
          longitude: -0.1278,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              1700000000000 + (i * 100)),
          accuracy: 5.0,
          altitude: 100.0,
          altitudeAccuracy: 1.0,
          heading: 90.0,
          headingAccuracy: 1.0,
          speed: 10.0,
          speedAccuracy: 1.0,
        ));
      }

      // Small delay for message processing but not enough for timer
      await Future.delayed(const Duration(milliseconds: 200));

      // Stop session - should flush remaining samples
      await engine.stopSession();

      // Verify all samples were persisted (flushed on stop)
      verify(() => mockGpsSampleRepo.batchInsert('integration-session', any()))
          .called(greaterThanOrEqualTo(1));
    });
  });

  // =========================================================================
  // Test 2: Post-session pipeline produces correct track, laps, analytics
  // Validates: Requirements 3.1, 4.1, 6.1
  // =========================================================================
  group('Post-session pipeline produces correct track, laps, and analytics',
      () {
    late MockSessionRepository mockSessionRepo;
    late MockGpsSampleRepository mockGpsSampleRepo;
    late MockLapRepository mockLapRepo;
    late MockTrackRepository mockTrackRepo;
    late MockTrackDiscoveryEngine mockTrackDiscovery;
    late MockLapDetectionEngine mockLapDetection;
    late MockAnalyticsEngine mockAnalytics;
    late PostSessionPipeline pipeline;

    setUp(() {
      mockSessionRepo = MockSessionRepository();
      mockGpsSampleRepo = MockGpsSampleRepository();
      mockLapRepo = MockLapRepository();
      mockTrackRepo = MockTrackRepository();
      mockTrackDiscovery = MockTrackDiscoveryEngine();
      mockLapDetection = MockLapDetectionEngine();
      mockAnalytics = MockAnalyticsEngine();

      pipeline = PostSessionPipeline(
        sessionRepository: mockSessionRepo,
        gpsSampleRepository: mockGpsSampleRepo,
        lapRepository: mockLapRepo,
        trackRepository: mockTrackRepo,
        trackDiscoveryEngine: mockTrackDiscovery,
        lapDetectionEngine: mockLapDetection,
        analyticsEngine: mockAnalytics,
      );
    });

    test(
        'closed-loop GPS path triggers track discovery, lap detection, and analytics',
        () async {
      // Setup: a session with a closed-loop GPS path (first ≈ last within 50m)
      const sessionId = 'pipeline-session-1';
      final session = Session(
        id: sessionId,
        startTime: 1700000000000,
        endTime: 1700000120000,
        durationMs: 120000,
      );

      // Generate a closed-loop GPS path (circular track)
      // 40 samples forming a rough circle, ending near the start
      final samples = _generateClosedLoopSamples(
        sampleCount: 40,
        startTimestamp: 1700000000000,
        intervalMs: 3000, // 3s between samples for 2 min session
      );

      final track = Track(
        id: 'track-1',
        polyline: samples.map((s) => LatLng(s.latitude, s.longitude)).toList(),
        startFinish: LatLng(samples.first.latitude, samples.first.longitude),
        lastDriven: session.startTime,
      );

      final laps = [
        Lap(
          id: 'lap-1',
          sessionId: sessionId,
          trackId: 'track-1',
          lapNumber: 1,
          startTimestamp: 1700000000000,
          endTimestamp: 1700000060000,
          lapTimeMs: 60000,
          isBestLap: false,
        ),
        Lap(
          id: 'lap-2',
          sessionId: sessionId,
          trackId: 'track-1',
          lapNumber: 2,
          startTimestamp: 1700000060000,
          endTimestamp: 1700000115000,
          lapTimeMs: 55000,
          isBestLap: true,
        ),
      ];

      final sectorBoundaries = [
        SectorBoundary(
          polylineFraction: 1 / 3,
          point: const LatLng(51.508, -0.126),
        ),
        SectorBoundary(
          polylineFraction: 2 / 3,
          point: const LatLng(51.509, -0.129),
        ),
      ];

      final sectorTimes = [
        const LapSectors(
          lapNumber: 1,
          sector1Ms: 20000,
          sector2Ms: 20000,
          sector3Ms: 20000,
        ),
        const LapSectors(
          lapNumber: 2,
          sector1Ms: 18000,
          sector2Ms: 19000,
          sector3Ms: 18000,
        ),
      ];

      final analytics = SessionAnalytics(
        sessionId: sessionId,
        durationSeconds: 120.0,
        distanceKm: 3.50,
        totalLaps: 2,
        bestLapTimeMs: 55000,
        averageLapTimeMs: 57500,
        averageSpeedKmh: 105.0,
        maxSpeedKmh: 130.0,
        speedTraceKmh: List.generate(40, (i) => 90.0 + (i % 10) * 4.0),
        bestSector1Ms: 18000,
        bestSector2Ms: 19000,
        bestSector3Ms: 18000,
      );

      // Wire up mocks
      when(() => mockSessionRepo.getById(sessionId))
          .thenAnswer((_) async => session);
      when(() => mockGpsSampleRepo.getBySessionId(sessionId))
          .thenAnswer((_) async => samples);
      when(() => mockTrackDiscovery.discoverTrack(any(), any()))
          .thenAnswer((_) async => track);
      when(() => mockLapDetection.detectLaps(any(), any()))
          .thenAnswer((_) async => laps);
      when(() => mockTrackDiscovery.computeSectors(any()))
          .thenReturn(sectorBoundaries);
      when(() => mockLapDetection.computeSectorTimes(any(), any(), any()))
          .thenAnswer((_) async => sectorTimes);
      when(() => mockLapRepo.insertBatch(any())).thenAnswer((_) async {});
      when(() => mockTrackDiscovery.refineCircuit(any(), any()))
          .thenAnswer((_) async => track);
      when(() => mockAnalytics.computeAnalytics(any(), any(), any(), any()))
          .thenAnswer((_) async => analytics);

      // Execute the pipeline
      final result = await pipeline.execute(sessionId);

      // Verify track was discovered
      expect(result.track, isNotNull);
      expect(result.track!.id, equals('track-1'));
      expect(result.track!.startFinish.latitude, closeTo(51.5074, 0.01));

      // Verify laps were detected with correct data
      expect(result.laps, hasLength(2));
      expect(result.laps[0].lapNumber, equals(1));
      expect(result.laps[0].lapTimeMs, equals(60000));
      expect(result.laps[1].lapNumber, equals(2));
      expect(result.laps[1].lapTimeMs, equals(55000));
      expect(result.laps[1].isBestLap, isTrue);

      // Verify sector times were applied to laps
      expect(result.laps[0].sector1Ms, equals(20000));
      expect(result.laps[0].sector2Ms, equals(20000));
      expect(result.laps[0].sector3Ms, equals(20000));
      expect(result.laps[1].sector1Ms, equals(18000));
      expect(result.laps[1].sector2Ms, equals(19000));
      expect(result.laps[1].sector3Ms, equals(18000));

      // Verify analytics were computed correctly
      expect(result.analytics.sessionId, equals(sessionId));
      expect(result.analytics.durationSeconds, equals(120.0));
      expect(result.analytics.distanceKm, equals(3.50));
      expect(result.analytics.totalLaps, equals(2));
      expect(result.analytics.bestLapTimeMs, equals(55000));
      expect(result.analytics.averageLapTimeMs, equals(57500));
      expect(result.analytics.averageSpeedKmh, equals(105.0));
      expect(result.analytics.maxSpeedKmh, equals(130.0));
      expect(result.analytics.speedTraceKmh, hasLength(40));
      expect(result.analytics.bestSector1Ms, equals(18000));
      expect(result.analytics.bestSector2Ms, equals(19000));
      expect(result.analytics.bestSector3Ms, equals(18000));

      // Verify laps were persisted to DB
      verify(() => mockLapRepo.insertBatch(any())).called(1);

      // Verify pipeline called engines in correct order by checking
      // that all expected calls were made
      verify(() => mockTrackDiscovery.discoverTrack(any(), any())).called(1);
      verify(() => mockLapDetection.detectLaps(any(), any())).called(1);
      verify(() => mockTrackDiscovery.computeSectors(any())).called(1);
      verify(() => mockLapDetection.computeSectorTimes(any(), any(), any()))
          .called(1);
      verify(() => mockAnalytics.computeAnalytics(any(), any(), any(), any()))
          .called(1);
    });

    test('non-closed-loop path skips lap detection and returns zero laps',
        () async {
      const sessionId = 'pipeline-session-2';
      final session = Session(
        id: sessionId,
        startTime: 1700000000000,
        endTime: 1700000060000,
        durationMs: 60000,
      );

      // Straight-line path (not a closed loop)
      final samples = List.generate(
        25,
        (i) => GpsSample(
          timestamp: 1700000000000 + (i * 2400),
          latitude: 51.5074 + (i * 0.001), // moving north
          longitude: -0.1278,
          speed: 20.0,
          accuracy: 5.0,
        ),
      );

      final analytics = SessionAnalytics(
        sessionId: sessionId,
        durationSeconds: 60.0,
        distanceKm: 2.78,
        totalLaps: 0,
        averageSpeedKmh: 72.0,
        maxSpeedKmh: 72.0,
        speedTraceKmh: List.generate(25, (_) => 72.0),
      );

      when(() => mockSessionRepo.getById(sessionId))
          .thenAnswer((_) async => session);
      when(() => mockGpsSampleRepo.getBySessionId(sessionId))
          .thenAnswer((_) async => samples);
      when(() => mockTrackDiscovery.discoverTrack(any(), any()))
          .thenAnswer((_) async => null); // No closed loop
      when(() => mockAnalytics.computeAnalytics(any(), any(), any(), any()))
          .thenAnswer((_) async => analytics);

      final result = await pipeline.execute(sessionId);

      // No track discovered
      expect(result.track, isNull);

      // No laps detected
      expect(result.laps, isEmpty);

      // Analytics still computed
      expect(result.analytics.totalLaps, equals(0));
      expect(result.analytics.bestLapTimeMs, isNull);
      expect(result.analytics.averageLapTimeMs, isNull);
      expect(result.analytics.distanceKm, equals(2.78));

      // Lap detection was never called
      verifyNever(() => mockLapDetection.detectLaps(any(), any()));
      verifyNever(() => mockLapRepo.insertBatch(any()));
    });
  });

  // =========================================================================
  // Test 3: Navigation flow from Home → Recording → start → stop → Summary
  // Validates: Requirements 1.1, 1.5, 6.1
  // =========================================================================
  group('Navigation flow from start to summary', () {
    late MockRecordingEngine mockEngine;
    late MockPostSessionPipeline mockPipeline;
    late MockSessionRepository mockSessionRepo;
    late MockGpsSampleRepository mockGpsSampleRepo;

    setUp(() {
      mockEngine = MockRecordingEngine();
      mockPipeline = MockPostSessionPipeline();
      mockSessionRepo = MockSessionRepository();
      mockGpsSampleRepo = MockGpsSampleRepository();
    });

    testWidgets('Home → Recording → start → stop → Session Summary',
        (tester) async {
      // Setup mock engine behavior
      when(() => mockEngine.updates).thenAnswer((_) => const Stream.empty());
      when(() => mockEngine.isRecording).thenReturn(false);
      when(() => mockEngine.startSession())
          .thenAnswer((_) async => 'nav-session-1');

      final stoppedSession = Session(
        id: 'nav-session-1',
        startTime: 1700000000000,
        endTime: 1700000060000,
        durationMs: 60000,
      );
      when(() => mockEngine.stopSession())
          .thenAnswer((_) async => stoppedSession);

      final pipelineResult = PostSessionResult(
        track: Track(
          id: 'track-nav',
          polyline: const [
            LatLng(51.5, -0.1),
            LatLng(51.501, -0.1),
            LatLng(51.501, -0.099),
            LatLng(51.5, -0.1),
          ],
          startFinish: const LatLng(51.5, -0.1),
          lastDriven: 1700000000000,
        ),
        laps: [
          Lap(
            id: 'lap-nav-1',
            sessionId: 'nav-session-1',
            trackId: 'track-nav',
            lapNumber: 1,
            startTimestamp: 1700000000000,
            endTimestamp: 1700000060000,
            lapTimeMs: 60000,
            isBestLap: true,
          ),
        ],
        analytics: const SessionAnalytics(
          sessionId: 'nav-session-1',
          durationSeconds: 60.0,
          distanceKm: 1.50,
          totalLaps: 1,
          bestLapTimeMs: 60000,
          averageLapTimeMs: 60000,
          averageSpeedKmh: 90.0,
          maxSpeedKmh: 120.0,
          speedTraceKmh: [90.0, 100.0, 110.0, 120.0, 100.0],
        ),
      );
      when(() => mockPipeline.execute('nav-session-1'))
          .thenAnswer((_) async => pipelineResult);

      // Mock the repositories that SessionSummaryScreen needs
      when(() => mockSessionRepo.getAll())
          .thenAnswer((_) async => <Session>[]);
      when(() => mockGpsSampleRepo.getBySessionId('nav-session-1'))
          .thenAnswer((_) async => <GpsSample>[]);

      // Build the app with a GoRouter that includes all relevant routes
      final testRouter = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/recording',
            builder: (context, state) => const RecordingScreen(),
          ),
          GoRoute(
            path: '/session/:id/summary',
            builder: (context, state) {
              final sessionId = state.pathParameters['id']!;
              return SessionSummaryScreen(sessionId: sessionId);
            },
          ),
          GoRoute(
            path: '/sessions',
            builder: (context, state) =>
                const Scaffold(body: Text('Sessions')),
          ),
          GoRoute(
            path: '/tracks',
            builder: (context, state) =>
                const Scaffold(body: Text('Tracks')),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) =>
                const Scaffold(body: Text('Settings')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recordingEngineProvider.overrideWithValue(mockEngine),
            postSessionPipelineProvider.overrideWithValue(mockPipeline),
            sessionsProvider.overrideWith((ref) async => <Session>[]),
            sessionRepositoryProvider.overrideWithValue(mockSessionRepo),
            gpsSampleRepositoryProvider.overrideWithValue(mockGpsSampleRepo),
            analyticsRepositoryProvider.overrideWithValue(
              _MockAnalyticsRepoWithData(pipelineResult.analytics),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: testRouter,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify we're on the Home screen
      expect(find.text('Start Recording'), findsOneWidget);

      // Navigate to Recording screen
      await tester.tap(find.text('Start Recording'));
      await tester.pumpAndSettle();

      // Verify we're on the Recording screen
      expect(find.text('Recording'), findsOneWidget);
      expect(find.text('Start Session'), findsOneWidget);

      // Tap Start Session
      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();

      // Verify recording state - Stop button should appear
      expect(find.text('Stop Session'), findsOneWidget);

      // Tap Stop Session
      await tester.tap(find.text('Stop Session'));
      // Allow the async stopSession + pipeline to complete
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      // Verify navigation to Session Summary screen
      // The router should navigate to /session/nav-session-1/summary
      expect(find.byType(SessionSummaryScreen), findsOneWidget);

      // Verify the pipeline was executed
      verify(() => mockPipeline.execute('nav-session-1')).called(1);
    });

    testWidgets('Start Session button is disabled while recording',
        (tester) async {
      when(() => mockEngine.updates).thenAnswer((_) => const Stream.empty());
      when(() => mockEngine.isRecording).thenReturn(false);
      when(() => mockEngine.startSession())
          .thenAnswer((_) async => 'session-disable-test');

      final testRouter = GoRouter(
        initialLocation: '/recording',
        routes: [
          GoRoute(
            path: '/recording',
            builder: (context, state) => const RecordingScreen(),
          ),
          GoRoute(
            path: '/session/:id/summary',
            builder: (context, state) =>
                const Scaffold(body: Text('Summary')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recordingEngineProvider.overrideWithValue(mockEngine),
            postSessionPipelineProvider.overrideWithValue(mockPipeline),
          ],
          child: MaterialApp.router(
            routerConfig: testRouter,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially shows Start Session button
      expect(find.text('Start Session'), findsOneWidget);

      // Tap Start Session
      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();

      // After starting, the Start button should be replaced by Stop button
      // (prevents duplicate concurrent sessions - Req 1.9)
      expect(find.text('Start Session'), findsNothing);
      expect(find.text('Stop Session'), findsOneWidget);
    });
  });
}

/// A mock AnalyticsRepository that returns pre-configured analytics data.
/// Used in widget tests where we need the SessionSummaryScreen to display data.
class _MockAnalyticsRepoWithData extends Mock implements AnalyticsRepository {
  final SessionAnalytics _analytics;

  _MockAnalyticsRepoWithData(this._analytics);

  @override
  Future<SessionAnalytics?> getBySessionId(String sessionId) async {
    return _analytics;
  }
}

/// Generates a closed-loop GPS path (circular track) where the last sample
/// is within 50m of the first sample.
List<GpsSample> _generateClosedLoopSamples({
  required int sampleCount,
  required int startTimestamp,
  required int intervalMs,
  double centerLat = 51.5074,
  double centerLng = -0.1278,
  double radiusDegrees = 0.002,
}) {
  final samples = <GpsSample>[];
  for (int i = 0; i < sampleCount; i++) {
    // Generate points along a circle
    final angle = (i / sampleCount) * 2 * 3.14159265;
    final lat = centerLat + radiusDegrees * _cos(angle);
    final lng = centerLng + radiusDegrees * _sin(angle);

    samples.add(GpsSample(
      timestamp: startTimestamp + (i * intervalMs),
      latitude: lat,
      longitude: lng,
      speed: 25.0 + (i % 5) * 2.0, // varying speed in m/s
      accuracy: 5.0,
      heading: (angle * 180 / 3.14159265) % 360,
      altitude: 100.0,
    ));
  }
  return samples;
}

double _sin(double x) {
  // Simple sin approximation for test data generation
  return x -
      (x * x * x) / 6 +
      (x * x * x * x * x) / 120 -
      (x * x * x * x * x * x * x) / 5040;
}

double _cos(double x) {
  // Simple cos approximation for test data generation
  return 1 -
      (x * x) / 2 +
      (x * x * x * x) / 24 -
      (x * x * x * x * x * x) / 720;
}
