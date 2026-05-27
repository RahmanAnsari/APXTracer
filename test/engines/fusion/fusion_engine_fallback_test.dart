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

class FakeGpsData extends Fake implements GpsData {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Creates a stationary IMU sample (low gyro, accel ≈ 9.81 m/s²).
ImuData _stationarySample(DateTime timestamp) {
  return ImuData(
    ax: 0.0,
    ay: 0.0,
    az: 9.81,
    gx: 0.0,
    gy: 0.0,
    gz: 0.0,
    timestamp: timestamp,
  );
}

/// Creates a valid GPS Position with accuracy ≤ 50m.
Position _validPosition(DateTime timestamp) {
  return Position(
    latitude: 51.5074,
    longitude: -0.1278,
    altitude: 10.0,
    accuracy: 5.0,
    altitudeAccuracy: 5.0,
    heading: 90.0,
    headingAccuracy: 5.0,
    speed: 10.0,
    speedAccuracy: 1.0,
    timestamp: timestamp,
  );
}

/// A valid NavState that produces coordinates within valid ranges.
const _validNavState = NavState(
  px: 10.0,
  py: 20.0,
  pz: 5.0,
  vx: 5.0,
  vy: 3.0,
  vz: 0.0,
  roll: 0.1,
  pitch: 0.2,
  yaw: 0.5,
  biasAx: 0.0,
  biasAy: 0.0,
  biasAz: 0.0,
  biasGx: 0.0,
  biasGy: 0.0,
  biasGz: 0.0,
  originLat: 51.5074,
  originLon: -0.1278,
  originAlt: 10.0,
);

void main() {
  late MockDeadReckoningFilter mockFilter;
  late MockImuService mockImuService;
  late StreamController<ImuData> imuStreamController;
  late FusionEngine engine;

  setUpAll(() {
    registerFallbackValue(FakeGpsData());
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
        .thenReturn((roll: 0.1, pitch: 0.2));
    when(() => mockFilter.initWithGps(any(),
            initialRoll: any(named: 'initialRoll'),
            initialPitch: any(named: 'initialPitch')))
        .thenReturn(null);
    when(() => mockFilter.predictWithImu(any())).thenReturn(null);
    when(() => mockFilter.updateWithGps(any())).thenReturn(null);
    when(() => mockFilter.state).thenReturn(_validNavState);
    when(() => mockFilter.isInitialized).thenReturn(true);

    engine = FusionEngine(
      filter: mockFilter,
      imuService: mockImuService,
    );
  });

  tearDown(() async {
    await imuStreamController.close();
  });

  group('FusionEngine fallback detection (Requirements 3.4, 3.5)', () {
    test('IMU gap > 200ms triggers transition to fallback status', () {
      fakeAsync((async) {
        engine = FusionEngine(
          filter: mockFilter,
          imuService: mockImuService,
        );

        // Start and bring to active
        engine.start();
        async.flushMicrotasks();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        for (int i = 0; i <= 50; i++) {
          final timestamp = baseTime.add(Duration(milliseconds: i * 10));
          imuStreamController.add(_stationarySample(timestamp));
        }
        async.flushMicrotasks();

        // Send GPS fix to transition to active
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 600))));
        async.flushMicrotasks();
        expect(engine.status, FusionStatus.active);

        // Send one IMU sample to start the watchdog
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 700))));
        async.flushMicrotasks();
        expect(engine.status, FusionStatus.active);

        // Advance time by 201ms without sending IMU data
        async.elapse(Duration(milliseconds: 201));

        expect(engine.status, FusionStatus.fallback);
      });
    });

    test('IMU gap ≤ 200ms does NOT trigger fallback', () {
      fakeAsync((async) {
        engine = FusionEngine(
          filter: mockFilter,
          imuService: mockImuService,
        );

        engine.start();
        async.flushMicrotasks();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        for (int i = 0; i <= 50; i++) {
          final timestamp = baseTime.add(Duration(milliseconds: i * 10));
          imuStreamController.add(_stationarySample(timestamp));
        }
        async.flushMicrotasks();

        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 600))));
        async.flushMicrotasks();
        expect(engine.status, FusionStatus.active);

        // Send IMU sample
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 700))));
        async.flushMicrotasks();

        // Advance 199ms — should still be active
        async.elapse(Duration(milliseconds: 199));

        expect(engine.status, FusionStatus.active);
      });
    });
  });

  group('FusionEngine fallback GPS behavior (Requirement 3.4)', () {
    test('GPS fixes during fallback (no pending recovery) are NOT processed through filter', () {
      fakeAsync((async) {
        engine = FusionEngine(
          filter: mockFilter,
          imuService: mockImuService,
        );

        engine.start();
        async.flushMicrotasks();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        for (int i = 0; i <= 50; i++) {
          final timestamp = baseTime.add(Duration(milliseconds: i * 10));
          imuStreamController.add(_stationarySample(timestamp));
        }
        async.flushMicrotasks();

        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 600))));
        async.flushMicrotasks();
        expect(engine.status, FusionStatus.active);

        // Send IMU to start watchdog, then let it expire
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 700))));
        async.flushMicrotasks();
        async.elapse(Duration(milliseconds: 201));
        expect(engine.status, FusionStatus.fallback);

        // Reset mock call counts
        clearInteractions(mockFilter);
        when(() => mockFilter.state).thenReturn(_validNavState);
        when(() => mockFilter.isInitialized).thenReturn(true);

        // Send GPS fix during fallback — should NOT call updateWithGps
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 1000))));
        async.flushMicrotasks();

        verifyNever(() => mockFilter.updateWithGps(any()));
      });
    });

    test('no fused sample emitted on fusedSamples stream during fallback', () {
      fakeAsync((async) {
        engine = FusionEngine(
          filter: mockFilter,
          imuService: mockImuService,
        );

        final fusedSamples = <dynamic>[];
        engine.fusedSamples.listen(fusedSamples.add);

        engine.start();
        async.flushMicrotasks();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        for (int i = 0; i <= 50; i++) {
          final timestamp = baseTime.add(Duration(milliseconds: i * 10));
          imuStreamController.add(_stationarySample(timestamp));
        }
        async.flushMicrotasks();

        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 600))));
        async.flushMicrotasks();

        // Send IMU to start watchdog, then let it expire
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 700))));
        async.flushMicrotasks();
        async.elapse(Duration(milliseconds: 201));
        expect(engine.status, FusionStatus.fallback);

        // Clear any samples emitted during active phase
        fusedSamples.clear();

        // Send GPS fix during fallback — no fused sample should be emitted
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 1000))));
        async.flushMicrotasks();

        expect(fusedSamples, isEmpty);
      });
    });
  });

  group('FusionEngine short-gap recovery (Requirement 3.6)', () {
    test('short gap (200-500ms): filter reinitialized with last known roll/pitch', () {
      fakeAsync((async) {
        engine = FusionEngine(
          filter: mockFilter,
          imuService: mockImuService,
        );

        engine.start();
        async.flushMicrotasks();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        for (int i = 0; i <= 50; i++) {
          final timestamp = baseTime.add(Duration(milliseconds: i * 10));
          imuStreamController.add(_stationarySample(timestamp));
        }
        async.flushMicrotasks();

        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 600))));
        async.flushMicrotasks();
        expect(engine.status, FusionStatus.active);

        // Send IMU sample at T=700ms (this sets _lastImuTimestamp)
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 700))));
        async.flushMicrotasks();

        // Let watchdog expire → fallback
        async.elapse(Duration(milliseconds: 201));
        expect(engine.status, FusionStatus.fallback);

        // Clear interactions to track recovery calls
        clearInteractions(mockFilter);
        when(() => mockFilter.initWithGps(any(),
                initialRoll: any(named: 'initialRoll'),
                initialPitch: any(named: 'initialPitch')))
            .thenReturn(null);
        when(() => mockFilter.state).thenReturn(_validNavState);
        when(() => mockFilter.isInitialized).thenReturn(true);

        // Send IMU at T+300ms gap (700 + 300 = 1000ms) — short gap recovery
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 1000))));
        async.flushMicrotasks();

        // Send GPS fix to complete recovery
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 1100))));
        async.flushMicrotasks();

        // Verify initWithGps called with last known roll/pitch (0.1, 0.2)
        verify(() => mockFilter.initWithGps(
              any(),
              initialRoll: 0.1,
              initialPitch: 0.2,
            )).called(1);
        expect(engine.status, FusionStatus.active);
      });
    });
  });

  group('FusionEngine long-gap recovery (Requirement 3.5)', () {
    test('long gap (> 500ms): filter reinitialized with zero roll/pitch', () {
      fakeAsync((async) {
        engine = FusionEngine(
          filter: mockFilter,
          imuService: mockImuService,
        );

        engine.start();
        async.flushMicrotasks();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        for (int i = 0; i <= 50; i++) {
          final timestamp = baseTime.add(Duration(milliseconds: i * 10));
          imuStreamController.add(_stationarySample(timestamp));
        }
        async.flushMicrotasks();

        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 600))));
        async.flushMicrotasks();
        expect(engine.status, FusionStatus.active);

        // Send IMU sample at T=700ms
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 700))));
        async.flushMicrotasks();

        // Let watchdog expire → fallback
        async.elapse(Duration(milliseconds: 201));
        expect(engine.status, FusionStatus.fallback);

        // Clear interactions
        clearInteractions(mockFilter);
        when(() => mockFilter.initWithGps(any(),
                initialRoll: any(named: 'initialRoll'),
                initialPitch: any(named: 'initialPitch')))
            .thenReturn(null);
        when(() => mockFilter.state).thenReturn(_validNavState);
        when(() => mockFilter.isInitialized).thenReturn(true);

        // Send IMU at T+600ms gap (700 + 600 = 1300ms) — long gap
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 1300))));
        async.flushMicrotasks();

        // Send GPS fix to complete recovery
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 1400))));
        async.flushMicrotasks();

        // Verify initWithGps called with zero roll/pitch
        verify(() => mockFilter.initWithGps(
              any(),
              initialRoll: 0.0,
              initialPitch: 0.0,
            )).called(1);
        expect(engine.status, FusionStatus.active);
      });
    });
  });

  group('FusionEngine transition boundaries (Requirements 6.6, 6.7)', () {
    test('no duplicate samples when switching active → fallback', () {
      fakeAsync((async) {
        engine = FusionEngine(
          filter: mockFilter,
          imuService: mockImuService,
        );

        final fusedSamples = <dynamic>[];
        engine.fusedSamples.listen(fusedSamples.add);

        engine.start();
        async.flushMicrotasks();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        for (int i = 0; i <= 50; i++) {
          final timestamp = baseTime.add(Duration(milliseconds: i * 10));
          imuStreamController.add(_stationarySample(timestamp));
        }
        async.flushMicrotasks();

        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 600))));
        async.flushMicrotasks();
        expect(engine.status, FusionStatus.active);

        // Send IMU to start watchdog
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 700))));
        async.flushMicrotasks();

        // Send GPS fix while active — should produce 1 fused sample
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 800))));
        async.flushMicrotasks();

        final samplesBeforeFallback = fusedSamples.length;

        // Transition to fallback
        async.elapse(Duration(milliseconds: 201));
        expect(engine.status, FusionStatus.fallback);
        async.flushMicrotasks();

        // No extra samples should have been emitted at the boundary
        expect(fusedSamples.length, samplesBeforeFallback);
      });
    });

    test('no dropped samples when switching fallback → active', () {
      fakeAsync((async) {
        engine = FusionEngine(
          filter: mockFilter,
          imuService: mockImuService,
        );

        final fusedSamples = <dynamic>[];
        engine.fusedSamples.listen(fusedSamples.add);

        engine.start();
        async.flushMicrotasks();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        for (int i = 0; i <= 50; i++) {
          final timestamp = baseTime.add(Duration(milliseconds: i * 10));
          imuStreamController.add(_stationarySample(timestamp));
        }
        async.flushMicrotasks();

        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 600))));
        async.flushMicrotasks();
        expect(engine.status, FusionStatus.active);

        // Send IMU to start watchdog
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 700))));
        async.flushMicrotasks();

        // Transition to fallback
        async.elapse(Duration(milliseconds: 201));
        expect(engine.status, FusionStatus.fallback);

        // Recover: send IMU with short gap, then GPS fix
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 1000))));
        async.flushMicrotasks();

        // Clear samples to count only post-recovery
        fusedSamples.clear();

        // GPS fix triggers recovery → active
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 1100))));
        async.flushMicrotasks();
        expect(engine.status, FusionStatus.active);

        // Send another IMU to keep watchdog alive
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 1200))));
        async.flushMicrotasks();

        // Send GPS fix in active state — should produce a fused sample
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 1300))));
        async.flushMicrotasks();

        // Should have exactly 1 fused sample from the post-recovery GPS fix
        expect(fusedSamples.length, 1);
      });
    });

    test('total fused samples equals GPS fixes during active periods across transitions', () {
      fakeAsync((async) {
        engine = FusionEngine(
          filter: mockFilter,
          imuService: mockImuService,
        );

        final fusedSamples = <dynamic>[];
        engine.fusedSamples.listen(fusedSamples.add);

        engine.start();
        async.flushMicrotasks();

        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        for (int i = 0; i <= 50; i++) {
          final timestamp = baseTime.add(Duration(milliseconds: i * 10));
          imuStreamController.add(_stationarySample(timestamp));
        }
        async.flushMicrotasks();

        // GPS fix #1: transitions to active (init fix, no fused sample)
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 600))));
        async.flushMicrotasks();
        expect(engine.status, FusionStatus.active);

        // Send IMU to keep watchdog alive
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 700))));
        async.flushMicrotasks();

        // GPS fix #2: active → produces fused sample
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 800))));
        async.flushMicrotasks();

        // GPS fix #3: active → produces fused sample
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 850))));
        async.flushMicrotasks();
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 900))));
        async.flushMicrotasks();

        final activeGpsCount1 = 2; // fixes #2 and #3

        // Transition to fallback
        async.elapse(Duration(milliseconds: 201));
        expect(engine.status, FusionStatus.fallback);

        // GPS fix #4: fallback → no fused sample
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 1200))));
        async.flushMicrotasks();

        // GPS fix #5: fallback → no fused sample
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 1300))));
        async.flushMicrotasks();

        // Recover: send IMU with short gap
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 1200))));
        async.flushMicrotasks();

        // GPS fix #6: triggers recovery → active (recovery fix, not fused)
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 1400))));
        async.flushMicrotasks();
        expect(engine.status, FusionStatus.active);

        // Send IMU to keep watchdog alive
        imuStreamController.add(_stationarySample(
            baseTime.add(Duration(milliseconds: 1500))));
        async.flushMicrotasks();

        // GPS fix #7: active → produces fused sample
        engine.onGpsFix(_validPosition(
            baseTime.add(Duration(milliseconds: 1600))));
        async.flushMicrotasks();

        final activeGpsCount2 = 1; // fix #7
        // After async.elapse(201ms), _lastImuEmitAt is still at the fake time
        // of fix #3. The IMU at t=1500ms arrives 201ms later (> 100ms interval),
        // so the IMU-driven emit fires once before GPS fix #7.
        final imuDrivenEmits = 1;

        // Total = GPS fused during active periods + IMU-driven dead-reckoned emits
        expect(fusedSamples.length,
            activeGpsCount1 + activeGpsCount2 + imuDrivenEmits);
      });
    });
  });

  group('FusionEngine stop() (Requirement 9.3)', () {
    test('stop() releases all subscriptions and transitions to uninitialized', () async {
      await engine.start();
      await Future.delayed(Duration.zero);

      final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
      for (int i = 0; i <= 50; i++) {
        final timestamp = baseTime.add(Duration(milliseconds: i * 10));
        imuStreamController.add(_stationarySample(timestamp));
      }
      await Future.delayed(Duration.zero);

      engine.onGpsFix(_validPosition(
          baseTime.add(Duration(milliseconds: 600))));
      await Future.delayed(Duration.zero);
      expect(engine.status, FusionStatus.active);

      // Call stop
      await engine.stop();

      expect(engine.status, FusionStatus.uninitialized);
      verify(() => mockImuService.stopStreaming()).called(1);
    });
  });
}
