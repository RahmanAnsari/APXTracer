import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

import 'package:apx_tracer/data/gps_sample_repository.dart';
import 'package:apx_tracer/data/session_repository.dart';
import 'package:apx_tracer/engines/fusion/fusion_engine.dart';
import 'package:apx_tracer/engines/fusion/imu_service.dart';
import 'package:apx_tracer/engines/recording/gps_service.dart';
import 'package:apx_tracer/engines/recording/recording_engine.dart';
import 'package:apx_tracer/engines/recording/recording_messages.dart';
import 'package:apx_tracer/models/gps_sample.dart';
import 'package:apx_tracer/models/session.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockFusionEngine extends Mock implements FusionEngine {}

class MockImuService extends Mock implements ImuService {}

class MockGpsService extends Mock implements GpsService {}

class MockSessionRepository extends Mock implements SessionRepository {}

class MockGpsSampleRepository extends Mock implements GpsSampleRepository {}

class MockUuid extends Mock implements Uuid {}

// ─── Fakes ───────────────────────────────────────────────────────────────────

class FakeSession extends Fake implements Session {}

class FakeGpsSample extends Fake implements GpsSample {}

class FakePosition extends Fake implements Position {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

Position createFakePosition({
  double latitude = 51.5074,
  double longitude = -0.1278,
  double altitude = 100.0,
  double speed = 25.0,
  double heading = 180.0,
  double accuracy = 5.0,
  DateTime? timestamp,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    altitude: altitude,
    speed: speed,
    heading: heading,
    accuracy: accuracy,
    timestamp: timestamp ?? DateTime(2024, 6, 15, 12, 0, 0),
    altitudeAccuracy: 1.0,
    headingAccuracy: 1.0,
    speedAccuracy: 1.0,
  );
}

GpsSample createFusedSample({
  int timestamp = 1700000000000,
  double latitude = 51.5074,
  double longitude = -0.1278,
  double speed = 25.0,
  double heading = 180.0,
  double accuracy = 5.0,
}) {
  return GpsSample(
    timestamp: timestamp,
    latitude: latitude,
    longitude: longitude,
    altitude: 100.0,
    speed: speed,
    heading: heading,
    accuracy: accuracy,
    isLowAccuracy: accuracy > 50.0,
  );
}

void main() {
  late MockFusionEngine mockFusionEngine;
  late MockGpsService mockGpsService;
  late MockSessionRepository mockSessionRepo;
  late MockGpsSampleRepository mockGpsSampleRepo;
  late MockUuid mockUuid;

  late StreamController<Position> positionStreamController;
  late StreamController<GpsSample> fusedSampleController;
  late StreamController<FusionStatusUpdate> fusionStatusController;

  setUpAll(() {
    registerFallbackValue(FakeSession());
    registerFallbackValue(<GpsSample>[]);
    registerFallbackValue(FakePosition());
    registerFallbackValue(const Duration(seconds: 10));
    registerFallbackValue('');
  });

  setUp(() {
    mockFusionEngine = MockFusionEngine();
    mockGpsService = MockGpsService();
    mockSessionRepo = MockSessionRepository();
    mockGpsSampleRepo = MockGpsSampleRepository();
    mockUuid = MockUuid();

    positionStreamController = StreamController<Position>.broadcast();
    fusedSampleController = StreamController<GpsSample>.broadcast();
    fusionStatusController = StreamController<FusionStatusUpdate>.broadcast();

    // Default mock setups
    when(() => mockUuid.v4()).thenReturn('test-session-id');
    when(() => mockGpsService.checkPermissionsAndAcquireFix(
          timeout: any(named: 'timeout'),
        )).thenAnswer((_) async => createFakePosition());
    when(() => mockGpsService.getPositionStream())
        .thenAnswer((_) => positionStreamController.stream);
    when(() => mockSessionRepo.insert(any())).thenAnswer((_) async {});
    when(() => mockSessionRepo.update(any())).thenAnswer((_) async {});
    when(() => mockSessionRepo.getById(any())).thenAnswer((_) async => Session(
          id: 'test-session-id',
          startTime: DateTime.now().millisecondsSinceEpoch,
          endTime: DateTime.now().millisecondsSinceEpoch + 60000,
          durationMs: 60000,
        ));
    when(() => mockGpsSampleRepo.batchInsert(any(), any()))
        .thenAnswer((_) async {});

    // FusionEngine mock setups
    when(() => mockFusionEngine.start()).thenAnswer((_) async {});
    when(() => mockFusionEngine.stop()).thenAnswer((_) async {});
    when(() => mockFusionEngine.onGpsFix(any())).thenReturn(null);
    when(() => mockFusionEngine.fusedSamples)
        .thenAnswer((_) => fusedSampleController.stream);
    when(() => mockFusionEngine.statusUpdates)
        .thenAnswer((_) => fusionStatusController.stream);
    when(() => mockFusionEngine.status).thenReturn(FusionStatus.uninitialized);
  });

  tearDown(() {
    positionStreamController.close();
    fusedSampleController.close();
    fusionStatusController.close();
  });

  RecordingEngine createEngineWithFusion() {
    return RecordingEngine(
      sessionRepository: mockSessionRepo,
      gpsSampleRepository: mockGpsSampleRepo,
      gpsService: mockGpsService,
      uuid: mockUuid,
      fusionEngine: mockFusionEngine,
    );
  }

  RecordingEngine createEngineWithoutFusion() {
    return RecordingEngine(
      sessionRepository: mockSessionRepo,
      gpsSampleRepository: mockGpsSampleRepo,
      gpsService: mockGpsService,
      uuid: mockUuid,
    );
  }

  group('RecordingEngine fusion delegation', () {
    group('startSession delegation', () {
      test(
          'startSession() delegates to FusionEngine when IMU is available',
          () async {
        final engine = createEngineWithFusion();

        await engine.startSession();

        verify(() => mockFusionEngine.start()).called(1);
        verify(() => mockFusionEngine.fusedSamples).called(1);
        verify(() => mockFusionEngine.statusUpdates).called(1);

        engine.dispose();
      });

      test(
          'startSession() uses GPS-only path when FusionEngine is null',
          () async {
        final engine = createEngineWithoutFusion();

        await engine.startSession();

        // FusionEngine should never be called
        verifyNever(() => mockFusionEngine.start());
        verifyNever(() => mockFusionEngine.fusedSamples);
        verifyNever(() => mockFusionEngine.statusUpdates);

        // GPS stream should still be subscribed
        expect(engine.isRecording, isTrue);

        engine.dispose();
      });
    });

    group('GPS position routing', () {
      test(
          'GPS positions are routed through FusionEngine.onGpsFix() when fusion is active',
          () async {
        final engine = createEngineWithFusion();
        await engine.startSession();

        // Transition fusion to active
        fusionStatusController.add(FusionStatusUpdate(
          status: FusionStatus.active,
          timestamp: DateTime.now(),
        ));
        await Future.delayed(Duration.zero);

        // Send GPS positions
        final position = createFakePosition(
          latitude: 51.5080,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        );
        positionStreamController.add(position);
        await Future.delayed(Duration.zero);

        verify(() => mockFusionEngine.onGpsFix(any())).called(1);

        engine.dispose();
      });

      test(
          'GPS positions are persisted directly when fusion is in fallback mode',
          () async {
        final engine = createEngineWithFusion();
        await engine.startSession();

        // Transition fusion to fallback
        fusionStatusController.add(FusionStatusUpdate(
          status: FusionStatus.fallback,
          timestamp: DateTime.now(),
        ));
        await Future.delayed(Duration.zero);

        // Send GPS position
        final position = createFakePosition(
          latitude: 51.5080,
          speed: 15.0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        );
        positionStreamController.add(position);
        await Future.delayed(Duration.zero);

        // Should NOT route through FusionEngine
        verifyNever(() => mockFusionEngine.onGpsFix(any()));

        // Wait for batch persist timer to fire
        await Future.delayed(const Duration(milliseconds: 1500));

        // Verify sample was persisted directly
        verify(() => mockGpsSampleRepo.batchInsert('test-session-id', any()))
            .called(greaterThanOrEqualTo(1));

        engine.dispose();
      });

      test(
          'GPS positions are persisted directly when FusionEngine is null (GPS-only mode)',
          () async {
        final engine = createEngineWithoutFusion();
        await engine.startSession();

        // Send GPS position
        final position = createFakePosition(
          latitude: 51.5080,
          speed: 20.0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        );
        positionStreamController.add(position);
        await Future.delayed(Duration.zero);

        // Wait for batch persist timer
        await Future.delayed(const Duration(milliseconds: 1500));

        // Verify sample was persisted directly
        verify(() => mockGpsSampleRepo.batchInsert('test-session-id', any()))
            .called(greaterThanOrEqualTo(1));

        engine.dispose();
      });
    });

    group('active → fallback transition', () {
      test(
          'transition from active to fallback: next GPS fix persisted directly, no duplicates',
          () async {
        final engine = createEngineWithFusion();
        await engine.startSession();

        // Start in active mode
        fusionStatusController.add(FusionStatusUpdate(
          status: FusionStatus.active,
          timestamp: DateTime.now(),
        ));
        await Future.delayed(Duration.zero);

        // Send a GPS fix while active — routed through FusionEngine
        positionStreamController.add(createFakePosition(
          latitude: 51.5080,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000001000),
        ));
        await Future.delayed(Duration.zero);

        // Emit a fused sample from FusionEngine (simulating fusion output)
        fusedSampleController.add(createFusedSample(
          timestamp: 1700000001000,
          latitude: 51.5080,
        ));
        await Future.delayed(Duration.zero);

        // Transition to fallback
        fusionStatusController.add(FusionStatusUpdate(
          status: FusionStatus.fallback,
          timestamp: DateTime.now(),
        ));
        await Future.delayed(Duration.zero);

        // Send next GPS fix — should be persisted directly (not through FusionEngine)
        positionStreamController.add(createFakePosition(
          latitude: 51.5081,
          speed: 12.0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000002000),
        ));
        await Future.delayed(Duration.zero);

        // Total onGpsFix calls should be exactly 1 (only the active-mode fix)
        verify(() => mockFusionEngine.onGpsFix(any())).called(1);

        // Wait for batch persist
        await Future.delayed(const Duration(milliseconds: 1500));

        // Verify samples were persisted (1 fused + 1 direct = 2 total)
        final captured = verify(
          () => mockGpsSampleRepo.batchInsert('test-session-id', captureAny()),
        ).captured;

        final totalSamples = captured.fold<int>(
          0,
          (sum, batch) => sum + (batch as List<GpsSample>).length,
        );
        expect(totalSamples, equals(2));

        engine.dispose();
      });
    });

    group('fallback → active transition', () {
      test(
          'transition from fallback to active: next fused sample persisted, no duplicates',
          () async {
        final engine = createEngineWithFusion();
        await engine.startSession();

        // Start in fallback mode
        fusionStatusController.add(FusionStatusUpdate(
          status: FusionStatus.fallback,
          timestamp: DateTime.now(),
        ));
        await Future.delayed(Duration.zero);

        // Send GPS fix while in fallback — persisted directly
        positionStreamController.add(createFakePosition(
          latitude: 51.5080,
          speed: 10.0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000001000),
        ));
        await Future.delayed(Duration.zero);

        // Transition to active
        fusionStatusController.add(FusionStatusUpdate(
          status: FusionStatus.active,
          timestamp: DateTime.now(),
        ));
        await Future.delayed(Duration.zero);

        // Send GPS fix while active — routed through FusionEngine
        positionStreamController.add(createFakePosition(
          latitude: 51.5081,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000002000),
        ));
        await Future.delayed(Duration.zero);

        verify(() => mockFusionEngine.onGpsFix(any())).called(1);

        // FusionEngine emits fused sample
        fusedSampleController.add(createFusedSample(
          timestamp: 1700000002000,
          latitude: 51.5081,
        ));
        await Future.delayed(Duration.zero);

        // Wait for batch persist
        await Future.delayed(const Duration(milliseconds: 1500));

        // Verify: 1 direct sample (fallback) + 1 fused sample (active) = 2 total
        final captured = verify(
          () => mockGpsSampleRepo.batchInsert('test-session-id', captureAny()),
        ).captured;

        final totalSamples = captured.fold<int>(
          0,
          (sum, batch) => sum + (batch as List<GpsSample>).length,
        );
        expect(totalSamples, equals(2));

        // Verify no duplicates — each sample has a unique timestamp
        final allSamples =
            captured.expand((batch) => batch as List<GpsSample>).toList();
        final timestamps = allSamples.map((s) => s.timestamp).toSet();
        expect(timestamps.length, equals(allSamples.length));

        engine.dispose();
      });
    });

    group('RecordingUpdate emission', () {
      test(
          'RecordingUpdate is emitted at 1 Hz regardless of fusion mode',
          () async {
        final engine = createEngineWithFusion();
        await engine.startSession();

        // Collect updates
        final updates = <RecordingUpdate>[];
        final subscription = engine.updates.listen(updates.add);

        // Transition to active
        fusionStatusController.add(FusionStatusUpdate(
          status: FusionStatus.active,
          timestamp: DateTime.now(),
        ));
        await Future.delayed(Duration.zero);

        // Wait for ~2.5 seconds to collect updates
        await Future.delayed(const Duration(milliseconds: 2500));

        await subscription.cancel();

        // Should have at least 2 updates in 2.5 seconds (1 Hz)
        expect(updates.length, greaterThanOrEqualTo(2));

        for (final update in updates) {
          expect(update.elapsed.inMilliseconds, greaterThan(0));
          expect(update.gpsStatus, isNotNull);
          expect(update.sampleCount, greaterThanOrEqualTo(0));
        }

        engine.dispose();
      });

      test(
          'RecordingUpdate is emitted at 1 Hz in GPS-only mode',
          () async {
        final engine = createEngineWithoutFusion();
        await engine.startSession();

        // Collect updates
        final updates = <RecordingUpdate>[];
        final subscription = engine.updates.listen(updates.add);

        // Wait for ~2.5 seconds
        await Future.delayed(const Duration(milliseconds: 2500));

        await subscription.cancel();

        // Should have at least 2 updates in 2.5 seconds (1 Hz)
        expect(updates.length, greaterThanOrEqualTo(2));

        for (final update in updates) {
          expect(update.elapsed.inMilliseconds, greaterThan(0));
          expect(update.gpsStatus, isNotNull);
        }

        engine.dispose();
      });
    });

    group('stopSession', () {
      test(
          'stopSession() calls FusionEngine.stop() and persists all buffered samples',
          () async {
        final engine = createEngineWithFusion();
        await engine.startSession();

        // Transition to active
        fusionStatusController.add(FusionStatusUpdate(
          status: FusionStatus.active,
          timestamp: DateTime.now(),
        ));
        await Future.delayed(Duration.zero);

        // Send some GPS fixes and fused samples
        for (int i = 0; i < 3; i++) {
          positionStreamController.add(createFakePosition(
            latitude: 51.5074 + (i * 0.0001),
            timestamp: DateTime.fromMillisecondsSinceEpoch(
                1700000000000 + (i * 1000)),
          ));
          fusedSampleController.add(createFusedSample(
            timestamp: 1700000000000 + (i * 1000),
            latitude: 51.5074 + (i * 0.0001),
          ));
        }
        await Future.delayed(const Duration(milliseconds: 100));

        // Stop session
        await engine.stopSession();

        // Verify FusionEngine.stop() was called
        verify(() => mockFusionEngine.stop()).called(1);

        // Verify all buffered samples were persisted
        verify(() => mockGpsSampleRepo.batchInsert('test-session-id', any()))
            .called(greaterThanOrEqualTo(1));

        engine.dispose();
      });

      test(
          'all buffered fused samples are persisted within 500 ms on stop',
          () async {
        final engine = createEngineWithFusion();
        await engine.startSession();

        // Transition to active
        fusionStatusController.add(FusionStatusUpdate(
          status: FusionStatus.active,
          timestamp: DateTime.now(),
        ));
        await Future.delayed(Duration.zero);

        // Buffer several fused samples
        for (int i = 0; i < 5; i++) {
          fusedSampleController.add(createFusedSample(
            timestamp: 1700000000000 + (i * 100),
            latitude: 51.5074 + (i * 0.0001),
          ));
        }
        await Future.delayed(const Duration(milliseconds: 100));

        // Measure stop time
        final stopwatch = Stopwatch()..start();
        await engine.stopSession();
        stopwatch.stop();

        // Stop should complete within 500 ms
        expect(stopwatch.elapsedMilliseconds, lessThan(500));

        // Verify all 5 samples were persisted
        final captured = verify(
          () => mockGpsSampleRepo.batchInsert('test-session-id', captureAny()),
        ).captured;

        final totalSamples = captured.fold<int>(
          0,
          (sum, batch) => sum + (batch as List<GpsSample>).length,
        );
        expect(totalSamples, equals(5));

        engine.dispose();
      });

      test(
          'stopSession() without FusionEngine does not call FusionEngine.stop()',
          () async {
        final engine = createEngineWithoutFusion();
        await engine.startSession();

        // Send some GPS positions
        positionStreamController.add(createFakePosition(
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ));
        await Future.delayed(const Duration(milliseconds: 100));

        await engine.stopSession();

        // FusionEngine should never be called
        verifyNever(() => mockFusionEngine.stop());

        engine.dispose();
      });
    });

    group('fused sample handling', () {
      test(
          'fused samples from FusionEngine are buffered and persisted',
          () async {
        final engine = createEngineWithFusion();
        await engine.startSession();

        // Transition to active
        fusionStatusController.add(FusionStatusUpdate(
          status: FusionStatus.active,
          timestamp: DateTime.now(),
        ));
        await Future.delayed(Duration.zero);

        // Emit fused samples
        for (int i = 0; i < 4; i++) {
          fusedSampleController.add(createFusedSample(
            timestamp: 1700000000000 + (i * 1000),
            latitude: 51.5074 + (i * 0.0001),
            speed: 20.0 + i,
          ));
        }
        await Future.delayed(Duration.zero);

        // Wait for batch persist timer
        await Future.delayed(const Duration(milliseconds: 1500));

        // Verify all fused samples were persisted
        final captured = verify(
          () => mockGpsSampleRepo.batchInsert('test-session-id', captureAny()),
        ).captured;

        final totalSamples = captured.fold<int>(
          0,
          (sum, batch) => sum + (batch as List<GpsSample>).length,
        );
        expect(totalSamples, equals(4));

        engine.dispose();
      });

      test(
          'fused samples update current speed for RecordingUpdate',
          () async {
        final engine = createEngineWithFusion();
        await engine.startSession();

        // Transition to active
        fusionStatusController.add(FusionStatusUpdate(
          status: FusionStatus.active,
          timestamp: DateTime.now(),
        ));
        await Future.delayed(Duration.zero);

        // Emit a fused sample with known speed (m/s)
        fusedSampleController.add(createFusedSample(
          timestamp: 1700000000000,
          speed: 10.0, // 10 m/s = 36 km/h
        ));
        await Future.delayed(Duration.zero);

        // Collect the next RecordingUpdate
        final updates = <RecordingUpdate>[];
        final subscription = engine.updates.listen(updates.add);

        await Future.delayed(const Duration(milliseconds: 1500));
        await subscription.cancel();

        // Speed should be converted to km/h
        expect(updates.isNotEmpty, isTrue);
        expect(updates.last.currentSpeedKmh, closeTo(36.0, 0.1));

        engine.dispose();
      });
    });
  });
}
