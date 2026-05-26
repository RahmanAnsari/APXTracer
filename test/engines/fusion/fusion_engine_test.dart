import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apx_tracer/engines/kalman/dead_reckoning_filter.dart';
import 'package:apx_tracer/engines/kalman/kalman_models.dart';
import 'package:apx_tracer/engines/fusion/fusion_engine.dart';
import 'package:apx_tracer/engines/fusion/imu_service.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockDeadReckoningFilter extends Mock implements DeadReckoningFilter {}

class MockImuService extends Mock implements ImuService {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Creates a stationary IMU sample (low gyro, accel ≈ 9.81 m/s²).
ImuData stationarySample(DateTime timestamp) {
  return ImuData(
    ax: 0.0,
    ay: 0.0,
    az: 9.81, // gravity pointing up
    gx: 0.0,
    gy: 0.0,
    gz: 0.0,
    timestamp: timestamp,
  );
}

/// Creates a non-stationary IMU sample (high gyro rate).
ImuData nonStationarySample(DateTime timestamp) {
  return ImuData(
    ax: 0.0,
    ay: 0.0,
    az: 9.81,
    gx: 0.1, // > 0.05 rad/s threshold
    gy: 0.0,
    gz: 0.0,
    timestamp: timestamp,
  );
}

/// Creates a fake Position with sensible defaults.
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

/// Creates a valid NavState for mocking filter.state.
NavState createValidNavState() {
  return const NavState(
    px: 0.0,
    py: 0.0,
    pz: 0.0,
    vx: 5.0,
    vy: 5.0,
    vz: 0.0,
    roll: 0.0,
    pitch: 0.0,
    yaw: 0.0,
    biasAx: 0.0,
    biasAy: 0.0,
    biasAz: 0.0,
    biasGx: 0.0,
    biasGy: 0.0,
    biasGz: 0.0,
    originLat: 51.5074,
    originLon: -0.1278,
    originAlt: 100.0,
  );
}

/// Sends stationary samples spanning 0.5s to trigger alignment.
void sendStationarySamplesForAlignment(
  StreamController<ImuData> controller,
  DateTime baseTime,
) {
  for (int i = 0; i <= 50; i++) {
    final timestamp = baseTime.add(Duration(milliseconds: i * 10));
    controller.add(stationarySample(timestamp));
  }
}

void main() {
  late MockDeadReckoningFilter mockFilter;
  late MockImuService mockImuService;
  late StreamController<ImuData> imuStreamController;
  late FusionEngine engine;

  setUpAll(() {
    registerFallbackValue(GpsData(
      latitude: 0.0,
      longitude: 0.0,
      altitude: 0.0,
      accuracy: 10.0,
      timestamp: DateTime(2024),
    ));
    registerFallbackValue(<ImuData>[]);
    registerFallbackValue(ImuData(
      ax: 0.0,
      ay: 0.0,
      az: 9.81,
      gx: 0.0,
      gy: 0.0,
      gz: 0.0,
      timestamp: DateTime(2024),
    ));
  });

  setUp(() {
    mockFilter = MockDeadReckoningFilter();
    mockImuService = MockImuService();
    imuStreamController = StreamController<ImuData>.broadcast();

    when(() => mockImuService.startStreaming())
        .thenAnswer((_) => imuStreamController.stream);
    when(() => mockImuService.stopStreaming()).thenAnswer((_) async {});
    when(() => mockFilter.alignWithGravity(any()))
        .thenReturn((roll: 0.0, pitch: 0.0));
    when(() => mockFilter.initWithGps(any(),
        initialRoll: any(named: 'initialRoll'),
        initialPitch: any(named: 'initialPitch'))).thenReturn(null);
    when(() => mockFilter.isInitialized).thenReturn(true);
    when(() => mockFilter.state).thenReturn(createValidNavState());

    engine = FusionEngine(
      filter: mockFilter,
      imuService: mockImuService,
    );
  });

  tearDown(() async {
    await imuStreamController.close();
  });

  group('FusionEngine initialization sequencing', () {
    group('start() behavior', () {
      test('start() transitions status to aligning and begins collecting IMU samples', () async {
        final statusUpdates = <FusionStatusUpdate>[];
        engine.statusUpdates.listen(statusUpdates.add);

        await engine.start();

        expect(engine.status, FusionStatus.aligning);
        expect(statusUpdates.length, 1);
        expect(statusUpdates.first.status, FusionStatus.aligning);
        verify(() => mockImuService.startStreaming()).called(1);
      });

      test('start() does nothing if already started', () async {
        await engine.start();
        await engine.start(); // second call should be ignored

        expect(engine.status, FusionStatus.aligning);
        verify(() => mockImuService.startStreaming()).called(1);
      });
    });

    group('stationarity detection', () {
      test('stationary samples (gyro < 0.05 rad/s, accel within 0.5 m/s² of 9.81) pass alignment', () async {
        await engine.start();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        sendStationarySamplesForAlignment(imuStreamController, baseTime);
        await Future.delayed(Duration.zero);

        expect(engine.status, FusionStatus.initialized);
        verify(() => mockFilter.alignWithGravity(any())).called(1);
      });

      test('non-stationary samples (high gyro) trigger retry', () async {
        await engine.start();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

        // Send some stationary samples first
        for (int i = 0; i < 10; i++) {
          imuStreamController.add(stationarySample(
            baseTime.add(Duration(milliseconds: i * 10)),
          ));
        }
        await Future.delayed(Duration.zero);

        // Send a non-stationary sample — triggers retry
        imuStreamController.add(nonStationarySample(
          baseTime.add(Duration(milliseconds: 100)),
        ));
        await Future.delayed(Duration.zero);

        // Engine should still be aligning (retry in progress)
        expect(engine.status, FusionStatus.aligning);
        verifyNever(() => mockFilter.alignWithGravity(any()));
      });

      test('non-stationary samples (accel deviation > 0.5 from 9.81) trigger retry', () async {
        await engine.start();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

        // Send a sample with accel too far from 9.81
        final badAccelSample = ImuData(
          ax: 0.0,
          ay: 0.0,
          az: 10.5, // |10.5 - 9.81| = 0.69 > 0.5
          gx: 0.0,
          gy: 0.0,
          gz: 0.0,
          timestamp: baseTime,
        );
        imuStreamController.add(badAccelSample);
        await Future.delayed(Duration.zero);

        expect(engine.status, FusionStatus.aligning);
        verifyNever(() => mockFilter.alignWithGravity(any()));
      });

      test('non-stationary samples trigger retry up to 3 attempts', () async {
        await engine.start();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

        // First non-stationary sample — attempt 1
        imuStreamController.add(nonStationarySample(baseTime));
        await Future.delayed(Duration.zero);
        expect(engine.status, FusionStatus.aligning);

        // Second non-stationary sample — attempt 2
        imuStreamController.add(nonStationarySample(
          baseTime.add(const Duration(milliseconds: 100)),
        ));
        await Future.delayed(Duration.zero);
        expect(engine.status, FusionStatus.aligning);

        // Still aligning after 2 attempts
        verifyNever(() => mockFilter.alignWithGravity(any()));
      });
    });

    group('alignment failure', () {
      test('3 failed alignment attempts transitions to error status', () async {
        await engine.start();

        final statusUpdates = <FusionStatusUpdate>[];
        engine.statusUpdates.listen(statusUpdates.add);

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

        // Send 3 non-stationary samples (each triggers a failed attempt)
        for (int i = 0; i < 3; i++) {
          imuStreamController.add(nonStationarySample(
            baseTime.add(Duration(milliseconds: i * 100)),
          ));
        }
        await Future.delayed(Duration.zero);

        expect(engine.status, FusionStatus.error);
        final errorUpdate = statusUpdates.lastWhere(
          (u) => u.status == FusionStatus.error,
        );
        expect(
          errorUpdate.errorMessage,
          'Alignment failed: device not stationary',
        );
        verifyNever(() => mockFilter.alignWithGravity(any()));
      });
    });

    group('alignWithGravity call', () {
      test('alignWithGravity is called with collected samples after successful alignment', () async {
        await engine.start();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        sendStationarySamplesForAlignment(imuStreamController, baseTime);
        await Future.delayed(Duration.zero);

        // Verify alignWithGravity was called with a non-empty list of samples
        final captured = verify(() => mockFilter.alignWithGravity(captureAny()))
            .captured;
        expect(captured.length, 1);
        final samples = captured.first as List<ImuData>;
        expect(samples.isNotEmpty, isTrue);
        // All samples should be stationary
        for (final sample in samples) {
          expect(sample.gx, lessThan(0.05));
        }
      });
    });

    group('GPS initialization', () {
      test('first GPS fix with accuracy ≤ 50 m triggers initWithGps and transitions to active', () async {
        await engine.start();

        // Complete alignment first
        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        sendStationarySamplesForAlignment(imuStreamController, baseTime);
        await Future.delayed(Duration.zero);
        expect(engine.status, FusionStatus.initialized);

        // Send a valid GPS fix (accuracy ≤ 50 m)
        final position = createFakePosition(accuracy: 10.0);
        engine.onGpsFix(position);

        expect(engine.status, FusionStatus.active);
        verify(() => mockFilter.initWithGps(
              any(),
              initialRoll: any(named: 'initialRoll'),
              initialPitch: any(named: 'initialPitch'),
            )).called(1);
      });

      test('GPS fix with accuracy exactly 50 m triggers initWithGps', () async {
        await engine.start();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        sendStationarySamplesForAlignment(imuStreamController, baseTime);
        await Future.delayed(Duration.zero);
        expect(engine.status, FusionStatus.initialized);

        // Send GPS fix with accuracy exactly 50 m
        final position = createFakePosition(accuracy: 50.0);
        engine.onGpsFix(position);

        expect(engine.status, FusionStatus.active);
        verify(() => mockFilter.initWithGps(
              any(),
              initialRoll: any(named: 'initialRoll'),
              initialPitch: any(named: 'initialPitch'),
            )).called(1);
      });

      test('GPS fixes with accuracy > 50 m are discarded during initialization', () async {
        await engine.start();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        sendStationarySamplesForAlignment(imuStreamController, baseTime);
        await Future.delayed(Duration.zero);
        expect(engine.status, FusionStatus.initialized);

        // Send inaccurate GPS fixes
        engine.onGpsFix(createFakePosition(accuracy: 51.0));
        engine.onGpsFix(createFakePosition(accuracy: 100.0));
        engine.onGpsFix(createFakePosition(accuracy: 200.0));

        // Should still be in initialized state
        expect(engine.status, FusionStatus.initialized);
        verifyNever(() => mockFilter.initWithGps(
              any(),
              initialRoll: any(named: 'initialRoll'),
              initialPitch: any(named: 'initialPitch'),
            ));
      });

      test('GPS fix timeout (10s) transitions to error status', () {
        fakeAsync((async) {
          final localFilter = MockDeadReckoningFilter();
          final localImuService = MockImuService();
          final localImuController = StreamController<ImuData>.broadcast();

          when(() => localImuService.startStreaming())
              .thenAnswer((_) => localImuController.stream);
          when(() => localImuService.stopStreaming())
              .thenAnswer((_) async {});
          when(() => localFilter.alignWithGravity(any()))
              .thenReturn((roll: 0.0, pitch: 0.0));

          final localEngine = FusionEngine(
            filter: localFilter,
            imuService: localImuService,
          );

          final statusUpdates = <FusionStatusUpdate>[];
          localEngine.statusUpdates.listen(statusUpdates.add);

          // Start the engine
          localEngine.start();
          async.flushMicrotasks();

          // Complete alignment
          final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
          for (int i = 0; i <= 50; i++) {
            localImuController.add(stationarySample(
              baseTime.add(Duration(milliseconds: i * 10)),
            ));
          }
          async.flushMicrotasks();
          expect(localEngine.status, FusionStatus.initialized);

          // Advance time by 10 seconds without sending a GPS fix
          async.elapse(const Duration(seconds: 10));

          expect(localEngine.status, FusionStatus.error);
          final errorUpdate = statusUpdates.lastWhere(
            (u) => u.status == FusionStatus.error,
          );
          expect(errorUpdate.errorMessage, 'GPS fix timeout');

          localImuController.close();
        });
      });

      test('GPS fix arriving before timeout cancels the timeout', () {
        fakeAsync((async) {
          final localFilter = MockDeadReckoningFilter();
          final localImuService = MockImuService();
          final localImuController = StreamController<ImuData>.broadcast();

          when(() => localImuService.startStreaming())
              .thenAnswer((_) => localImuController.stream);
          when(() => localImuService.stopStreaming())
              .thenAnswer((_) async {});
          when(() => localFilter.alignWithGravity(any()))
              .thenReturn((roll: 0.0, pitch: 0.0));
          when(() => localFilter.initWithGps(any(),
              initialRoll: any(named: 'initialRoll'),
              initialPitch: any(named: 'initialPitch'))).thenReturn(null);
          when(() => localFilter.isInitialized).thenReturn(true);
          when(() => localFilter.state).thenReturn(createValidNavState());
          when(() => localFilter.predictWithImu(any())).thenReturn(null);

          final localEngine = FusionEngine(
            filter: localFilter,
            imuService: localImuService,
          );

          // Start the engine
          localEngine.start();
          async.flushMicrotasks();

          // Complete alignment
          final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
          for (int i = 0; i <= 50; i++) {
            localImuController.add(stationarySample(
              baseTime.add(Duration(milliseconds: i * 10)),
            ));
          }
          async.flushMicrotasks();
          expect(localEngine.status, FusionStatus.initialized);

          // Send valid GPS fix at 5 seconds (before timeout)
          async.elapse(const Duration(seconds: 5));
          localEngine.onGpsFix(createFakePosition(accuracy: 10.0));

          expect(localEngine.status, FusionStatus.active);

          // Keep sending IMU data to prevent watchdog from firing
          for (int i = 0; i < 100; i++) {
            async.elapse(const Duration(milliseconds: 100));
            localImuController.add(stationarySample(
              baseTime.add(Duration(milliseconds: 6000 + i * 100)),
            ));
            async.flushMicrotasks();
          }

          // Should still be active — GPS timeout should NOT have fired
          expect(localEngine.status, FusionStatus.active);

          localImuController.close();
        });
      });
    });

    group('status updates stream', () {
      test('status updates are emitted for each transition in the full flow', () async {
        final statusUpdates = <FusionStatusUpdate>[];
        engine.statusUpdates.listen(statusUpdates.add);

        // Start → aligning
        await engine.start();
        await Future.delayed(Duration.zero);

        // Alignment → initialized
        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        sendStationarySamplesForAlignment(imuStreamController, baseTime);
        await Future.delayed(Duration.zero);

        // GPS fix → active
        engine.onGpsFix(createFakePosition(accuracy: 10.0));
        await Future.delayed(Duration.zero);

        // Verify the full sequence of status transitions
        expect(statusUpdates.length, greaterThanOrEqualTo(3));
        expect(statusUpdates[0].status, FusionStatus.aligning);
        expect(statusUpdates[1].status, FusionStatus.initialized);
        expect(statusUpdates[2].status, FusionStatus.active);
      });

      test('error status update includes error message', () async {
        final statusUpdates = <FusionStatusUpdate>[];
        engine.statusUpdates.listen(statusUpdates.add);

        await engine.start();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        // Trigger 3 failed alignment attempts
        for (int i = 0; i < 3; i++) {
          imuStreamController.add(nonStationarySample(
            baseTime.add(Duration(milliseconds: i * 100)),
          ));
        }
        await Future.delayed(Duration.zero);

        final errorUpdate = statusUpdates.lastWhere(
          (u) => u.status == FusionStatus.error,
        );
        expect(errorUpdate.errorMessage, isNotNull);
        expect(errorUpdate.errorMessage,
            'Alignment failed: device not stationary');
        expect(errorUpdate.timestamp, isNotNull);
      });

      test('each status update has a timestamp', () async {
        final statusUpdates = <FusionStatusUpdate>[];
        engine.statusUpdates.listen(statusUpdates.add);

        await engine.start();
        await Future.delayed(Duration.zero);

        for (final update in statusUpdates) {
          expect(update.timestamp, isA<DateTime>());
        }
      });
    });

    group('full initialization flow', () {
      test('full flow: start → aligning → initialized → active', () async {
        final statusUpdates = <FusionStatusUpdate>[];
        engine.statusUpdates.listen(statusUpdates.add);

        // Step 1: Start
        await engine.start();
        expect(engine.status, FusionStatus.aligning);

        // Step 2: Alignment (stationary samples for 0.5s)
        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        sendStationarySamplesForAlignment(imuStreamController, baseTime);
        await Future.delayed(Duration.zero);
        expect(engine.status, FusionStatus.initialized);

        // Step 3: GPS fix (accuracy ≤ 50 m)
        engine.onGpsFix(createFakePosition(accuracy: 10.0));
        await Future.delayed(Duration.zero);
        expect(engine.status, FusionStatus.active);

        // Verify the complete status sequence
        final statuses = statusUpdates.map((u) => u.status).toList();
        expect(statuses, contains(FusionStatus.aligning));
        expect(statuses, contains(FusionStatus.initialized));
        expect(statuses, contains(FusionStatus.active));
      });

      test('error path: non-stationary → retry → error', () async {
        final statusUpdates = <FusionStatusUpdate>[];
        engine.statusUpdates.listen(statusUpdates.add);

        await engine.start();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

        // 3 non-stationary samples exhaust retries
        for (int i = 0; i < 3; i++) {
          imuStreamController.add(nonStationarySample(
            baseTime.add(Duration(milliseconds: i * 100)),
          ));
        }
        await Future.delayed(Duration.zero);

        expect(engine.status, FusionStatus.error);
        final statuses = statusUpdates.map((u) => u.status).toList();
        expect(statuses, contains(FusionStatus.aligning));
        expect(statuses, contains(FusionStatus.error));
      });

      test('error path: GPS timeout → error', () {
        fakeAsync((async) {
          final localFilter = MockDeadReckoningFilter();
          final localImuService = MockImuService();
          final localImuController = StreamController<ImuData>.broadcast();

          when(() => localImuService.startStreaming())
              .thenAnswer((_) => localImuController.stream);
          when(() => localImuService.stopStreaming())
              .thenAnswer((_) async {});
          when(() => localFilter.alignWithGravity(any()))
              .thenReturn((roll: 0.0, pitch: 0.0));

          final localEngine = FusionEngine(
            filter: localFilter,
            imuService: localImuService,
          );

          final statusUpdates = <FusionStatusUpdate>[];
          localEngine.statusUpdates.listen(statusUpdates.add);

          localEngine.start();
          async.flushMicrotasks();

          // Complete alignment
          final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
          for (int i = 0; i <= 50; i++) {
            localImuController.add(stationarySample(
              baseTime.add(Duration(milliseconds: i * 10)),
            ));
          }
          async.flushMicrotasks();

          // Timeout
          async.elapse(const Duration(seconds: 10));

          final statuses = statusUpdates.map((u) => u.status).toList();
          expect(statuses, contains(FusionStatus.aligning));
          expect(statuses, contains(FusionStatus.initialized));
          expect(statuses, contains(FusionStatus.error));

          localImuController.close();
        });
      });

      test('alignment succeeds after initial failed attempts', () async {
        await engine.start();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

        // First 2 attempts fail (non-stationary)
        imuStreamController.add(nonStationarySample(baseTime));
        imuStreamController.add(nonStationarySample(
          baseTime.add(const Duration(milliseconds: 100)),
        ));
        await Future.delayed(Duration.zero);
        expect(engine.status, FusionStatus.aligning);

        // Third attempt succeeds with stationary samples
        for (int i = 0; i <= 50; i++) {
          final timestamp =
              baseTime.add(Duration(milliseconds: 1000 + i * 10));
          imuStreamController.add(stationarySample(timestamp));
        }
        await Future.delayed(Duration.zero);

        expect(engine.status, FusionStatus.initialized);
        verify(() => mockFilter.alignWithGravity(any())).called(1);
      });
    });
  });
}
