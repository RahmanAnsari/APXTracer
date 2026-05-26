import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

import 'package:apx_tracer/data/gps_sample_repository.dart';
import 'package:apx_tracer/data/session_repository.dart';
import 'package:apx_tracer/engines/recording/gps_service.dart';
import 'package:apx_tracer/engines/recording/recording_engine.dart';
import 'package:apx_tracer/engines/recording/recording_messages.dart';
import 'package:apx_tracer/models/gps_sample.dart';
import 'package:apx_tracer/models/session.dart';

// --- Mocks ---

class MockSessionRepository extends Mock implements SessionRepository {}

class MockGpsSampleRepository extends Mock implements GpsSampleRepository {}

class MockGpsService extends Mock implements GpsService {}

class MockUuid extends Mock implements Uuid {}

// --- Fake classes for mocktail ---

class FakeSession extends Fake implements Session {}

class FakeGpsSample extends Fake implements GpsSample {}

void main() {
  late MockSessionRepository mockSessionRepo;
  late MockGpsSampleRepository mockGpsSampleRepo;
  late MockGpsService mockGpsService;
  late MockUuid mockUuid;
  late RecordingEngine engine;

  // StreamController to simulate GPS position stream
  late StreamController<Position> positionStreamController;

  setUpAll(() {
    registerFallbackValue(FakeSession());
    registerFallbackValue(<GpsSample>[]);
    registerFallbackValue(const Duration(seconds: 10));
    registerFallbackValue('');
  });

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

  Position createFakePosition({
    double latitude = 51.5074,
    double longitude = -0.1278,
    double accuracy = 5.0,
    double speed = 10.0,
    double heading = 90.0,
    double altitude = 100.0,
    DateTime? timestamp,
  }) {
    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp ?? DateTime.now(),
      accuracy: accuracy,
      altitude: altitude,
      altitudeAccuracy: 1.0,
      heading: heading,
      headingAccuracy: 1.0,
      speed: speed,
      speedAccuracy: 1.0,
    );
  }

  /// Sets up mocks for a successful startSession flow.
  void setupSuccessfulStart({String sessionId = 'test-session-id'}) {
    when(() => mockUuid.v4()).thenReturn(sessionId);
    when(() => mockGpsService.checkPermissionsAndAcquireFix(
          timeout: any(named: 'timeout'),
        )).thenAnswer((_) async => createFakePosition());
    when(() => mockGpsService.getPositionStream())
        .thenAnswer((_) => positionStreamController.stream);
    when(() => mockSessionRepo.insert(any())).thenAnswer((_) async {});
    when(() => mockSessionRepo.update(any())).thenAnswer((_) async {});
    when(() => mockSessionRepo.getById(any())).thenAnswer((_) async => Session(
          id: sessionId,
          startTime: DateTime.now().millisecondsSinceEpoch,
          endTime: DateTime.now().millisecondsSinceEpoch + 60000,
          durationMs: 60000,
        ));
    when(() => mockGpsSampleRepo.batchInsert(any(), any()))
        .thenAnswer((_) async {});
  }

  group('RecordingEngine', () {
    group('startSession', () {
      test('returns session ID within expected time', () async {
        setupSuccessfulStart(sessionId: 'abc-123');

        final stopwatch = Stopwatch()..start();
        final sessionId = await engine.startSession();
        stopwatch.stop();

        expect(sessionId, equals('abc-123'));
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));

        // Verify session was inserted into DB
        verify(() => mockSessionRepo.insert(any())).called(1);
      });

      test('throws GpsPermissionDeniedException when permission denied',
          () async {
        when(() => mockGpsService.checkPermissionsAndAcquireFix(
              timeout: any(named: 'timeout'),
            )).thenAnswer((_) async => throw const GpsPermissionDeniedException(
              'Location permission was denied',
            ));

        await expectLater(
          engine.startSession(),
          throwsA(isA<GpsPermissionDeniedException>()),
        );

        // Verify engine is NOT in recording state
        expect(engine.isRecording, isFalse);
      });

      test('throws GpsFixTimeoutException after 10s timeout', () async {
        when(() => mockGpsService.checkPermissionsAndAcquireFix(
              timeout: any(named: 'timeout'),
            )).thenAnswer((_) async => throw const GpsFixTimeoutException(
              timeout: Duration(seconds: 10),
              message: 'Could not acquire GPS fix within 10 seconds',
            ));

        await expectLater(
          engine.startSession(),
          throwsA(isA<GpsFixTimeoutException>()),
        );

        expect(engine.isRecording, isFalse);
      });

      test('prevents duplicate concurrent sessions', () async {
        setupSuccessfulStart();

        await engine.startSession();

        await expectLater(
          engine.startSession(),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('GPS sample handling', () {
      test('GPS samples stored sequentially with zero loss', () async {
        setupSuccessfulStart();

        await engine.startSession();

        // Simulate GPS positions arriving
        for (int i = 0; i < 10; i++) {
          positionStreamController.add(createFakePosition(
            latitude: 51.5074 + (i * 0.0001),
            longitude: -0.1278 + (i * 0.0001),
            speed: 10.0 + i,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
                1700000000000 + (i * 100)),
          ));
        }

        // Wait for the batch persist timer to fire
        await Future.delayed(const Duration(milliseconds: 1500));

        // Verify samples were persisted
        final captured = verify(
          () => mockGpsSampleRepo.batchInsert('test-session-id', captureAny()),
        ).captured;

        // All 10 samples should be persisted
        final totalSamples = captured.fold<int>(
          0,
          (sum, batch) => sum + (batch as List<GpsSample>).length,
        );
        expect(totalSamples, equals(10));

        // Verify sequential order
        final allSamples =
            captured.expand((batch) => batch as List<GpsSample>).toList();
        for (int i = 1; i < allSamples.length; i++) {
          expect(allSamples[i].timestamp,
              greaterThan(allSamples[i - 1].timestamp));
        }
      });

      test('captures at 10 Hz rate - processes positions from stream',
          () async {
        setupSuccessfulStart();

        await engine.startSession();

        // Simulate 10 positions arriving in 1 second (10 Hz)
        for (int i = 0; i < 10; i++) {
          positionStreamController.add(createFakePosition(
            timestamp: DateTime.fromMillisecondsSinceEpoch(
                1700000000000 + (i * 100)),
            speed: 15.0,
          ));
        }

        // Wait for batch persist
        await Future.delayed(const Duration(milliseconds: 1500));

        // Verify all 10 samples were persisted
        final captured = verify(
          () => mockGpsSampleRepo.batchInsert('test-session-id', captureAny()),
        ).captured;

        final totalSamples = captured.fold<int>(
          0,
          (sum, batch) => sum + (batch as List<GpsSample>).length,
        );
        expect(totalSamples, equals(10));
      });

      test('low-accuracy flagged when accuracy > 50m', () async {
        setupSuccessfulStart();

        await engine.startSession();

        // Send a position with accuracy > 50m
        positionStreamController.add(createFakePosition(
          accuracy: 60.0,
          speed: 10.0,
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ));

        // Wait for batch persist
        await Future.delayed(const Duration(milliseconds: 1500));

        // Verify the sample was persisted with isLowAccuracy = true
        final captured = verify(
          () => mockGpsSampleRepo.batchInsert('test-session-id', captureAny()),
        ).captured;

        final persistedSamples = captured.first as List<GpsSample>;
        expect(persistedSamples.first.isLowAccuracy, isTrue);
        expect(persistedSamples.first.accuracy, equals(60.0));
      });

      test('low-accuracy sample still persisted', () async {
        setupSuccessfulStart();

        await engine.startSession();

        // Send a low-accuracy position
        positionStreamController.add(createFakePosition(
          accuracy: 75.0,
          speed: 5.0,
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ));

        // Wait for batch persist
        await Future.delayed(const Duration(milliseconds: 1500));

        // Verify batchInsert was called (sample was NOT discarded)
        verify(() => mockGpsSampleRepo.batchInsert('test-session-id', any()))
            .called(greaterThanOrEqualTo(1));
      });
    });

    group('recording continues without internet', () {
      test('recording operates without network dependency', () async {
        setupSuccessfulStart();

        final sessionId = await engine.startSession();
        expect(sessionId, isNotEmpty);

        // Send positions (simulating GPS working without internet)
        positionStreamController.add(createFakePosition(
          speed: 20.0,
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ));

        await Future.delayed(const Duration(milliseconds: 1500));

        // Verify samples persisted to local DB (no network calls involved)
        verify(() => mockGpsSampleRepo.batchInsert(any(), any()))
            .called(greaterThanOrEqualTo(1));
      });
    });

    group('stopSession', () {
      test('persists all data', () async {
        setupSuccessfulStart();

        await engine.startSession();

        // Send some positions
        for (int i = 0; i < 5; i++) {
          positionStreamController.add(createFakePosition(
            timestamp: DateTime.fromMillisecondsSinceEpoch(
                1700000000000 + (i * 100)),
            speed: 10.0,
          ));
        }

        // Wait for positions to be received
        await Future.delayed(const Duration(milliseconds: 300));

        // Stop session
        final session = await engine.stopSession();

        expect(session, isNotNull);
        expect(session.id, equals('test-session-id'));
        expect(session.endTime, isNotNull);
        expect(session.durationMs, isNotNull);

        // Verify session was updated with end time and duration
        verify(() => mockSessionRepo.update(any())).called(1);

        // Verify remaining samples were flushed to DB
        verify(() => mockGpsSampleRepo.batchInsert('test-session-id', any()))
            .called(greaterThanOrEqualTo(1));
      });
    });

    group('signal loss and resume', () {
      test('resumes without data loss after signal gap', () async {
        setupSuccessfulStart();

        await engine.startSession();

        // Send first batch of positions
        for (int i = 0; i < 5; i++) {
          positionStreamController.add(createFakePosition(
            latitude: 51.5074 + (i * 0.0001),
            timestamp: DateTime.fromMillisecondsSinceEpoch(
                1700000000000 + (i * 100)),
            speed: 10.0,
          ));
        }

        // Wait for batch to be processed and persisted
        await Future.delayed(const Duration(milliseconds: 1500));

        // Simulate signal loss (no positions for > 3 seconds)
        await Future.delayed(const Duration(milliseconds: 3500));

        // Send second batch after signal restored
        for (int i = 0; i < 5; i++) {
          positionStreamController.add(createFakePosition(
            latitude: 51.5080 + (i * 0.0001),
            timestamp: DateTime.fromMillisecondsSinceEpoch(
                1700000005000 + (i * 100)),
            speed: 12.0,
          ));
        }

        // Wait for second batch to be processed
        await Future.delayed(const Duration(milliseconds: 1500));

        // Verify both batches were persisted (no data loss)
        final verificationResult = verify(
          () => mockGpsSampleRepo.batchInsert('test-session-id', captureAny()),
        );
        verificationResult.called(greaterThanOrEqualTo(2));

        final allPersistedSamples = verificationResult.captured
            .expand((batch) => batch as List<GpsSample>)
            .toList();
        expect(allPersistedSamples.length, equals(10));
      });
    });

    group('UI updates stream', () {
      test('emits updates at 1 Hz minimum', () async {
        setupSuccessfulStart();

        await engine.startSession();

        // Collect updates for ~2.5 seconds
        final updates = <RecordingUpdate>[];
        final subscription = engine.updates.listen(updates.add);

        await Future.delayed(const Duration(milliseconds: 2500));

        await subscription.cancel();

        // Should have at least 2 updates in 2.5 seconds (1 Hz)
        expect(updates.length, greaterThanOrEqualTo(2));

        // Each update should have valid fields
        for (final update in updates) {
          expect(update.elapsed.inMilliseconds, greaterThan(0));
          expect(update.gpsStatus, isNotNull);
          expect(update.sampleCount, greaterThanOrEqualTo(0));
        }
      });
    });
  });
}
