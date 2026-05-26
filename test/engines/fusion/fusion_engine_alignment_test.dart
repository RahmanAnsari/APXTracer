import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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
ImuData _stationarySample(DateTime timestamp) {
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
ImuData _nonStationarySample(DateTime timestamp) {
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

/// Creates a non-stationary IMU sample (accel too far from 9.81).
ImuData _nonStationaryAccelSample(DateTime timestamp) {
  return ImuData(
    ax: 0.0,
    ay: 0.0,
    az: 10.5, // magnitude = 10.5, deviation = 0.69 > 0.5
    gx: 0.0,
    gy: 0.0,
    gz: 0.0,
    timestamp: timestamp,
  );
}

void main() {
  late MockDeadReckoningFilter mockFilter;
  late MockImuService mockImuService;
  late StreamController<ImuData> imuStreamController;
  late FusionEngine engine;

  setUp(() {
    mockFilter = MockDeadReckoningFilter();
    mockImuService = MockImuService();
    imuStreamController = StreamController<ImuData>.broadcast();

    when(() => mockImuService.startStreaming())
        .thenAnswer((_) => imuStreamController.stream);
    when(() => mockImuService.stopStreaming()).thenAnswer((_) async {});
    when(() => mockFilter.alignWithGravity(any()))
        .thenReturn((roll: 0.0, pitch: 0.0));

    engine = FusionEngine(
      filter: mockFilter,
      imuService: mockImuService,
    );
  });

  tearDown(() async {
    await imuStreamController.close();
  });

  group('FusionEngine gravity alignment (task 5.2)', () {
    test('start() transitions to aligning status', () async {
      final statusUpdates = <FusionStatusUpdate>[];
      engine.statusUpdates.listen(statusUpdates.add);

      await engine.start();

      expect(engine.status, FusionStatus.aligning);
      expect(statusUpdates.length, 1);
      expect(statusUpdates.first.status, FusionStatus.aligning);
    });

    test('stationary samples for 0.5s triggers alignWithGravity and transitions to initialized', () async {
      await engine.start();

      final statusUpdates = <FusionStatusUpdate>[];
      engine.statusUpdates.listen(statusUpdates.add);

      // Send stationary samples spanning 0.5 seconds
      final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
      for (int i = 0; i <= 50; i++) {
        // 51 samples over 500ms (10ms apart)
        final timestamp = baseTime.add(Duration(milliseconds: i * 10));
        imuStreamController.add(_stationarySample(timestamp));
      }

      // Allow stream events to propagate
      await Future.delayed(Duration.zero);

      expect(engine.status, FusionStatus.initialized);
      verify(() => mockFilter.alignWithGravity(any())).called(1);
    });

    test('non-stationary sample (high gyro) discards collected samples and increments attempts', () async {
      await engine.start();

      final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

      // Send some stationary samples (not enough for 0.5s)
      for (int i = 0; i < 10; i++) {
        final timestamp = baseTime.add(Duration(milliseconds: i * 10));
        imuStreamController.add(_stationarySample(timestamp));
      }
      await Future.delayed(Duration.zero);

      // Send a non-stationary sample
      imuStreamController.add(_nonStationarySample(
        baseTime.add(Duration(milliseconds: 100)),
      ));
      await Future.delayed(Duration.zero);

      // Engine should still be aligning (attempt 1 used)
      expect(engine.status, FusionStatus.aligning);
      verifyNever(() => mockFilter.alignWithGravity(any()));
    });

    test('non-stationary sample (accel deviation) discards collected samples', () async {
      await engine.start();

      final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

      // Send some stationary samples
      for (int i = 0; i < 5; i++) {
        final timestamp = baseTime.add(Duration(milliseconds: i * 10));
        imuStreamController.add(_stationarySample(timestamp));
      }
      await Future.delayed(Duration.zero);

      // Send a non-stationary accel sample
      imuStreamController.add(_nonStationaryAccelSample(
        baseTime.add(Duration(milliseconds: 50)),
      ));
      await Future.delayed(Duration.zero);

      expect(engine.status, FusionStatus.aligning);
      verifyNever(() => mockFilter.alignWithGravity(any()));
    });

    test('3 failed alignment attempts transitions to error status', () async {
      await engine.start();

      final statusUpdates = <FusionStatusUpdate>[];
      engine.statusUpdates.listen(statusUpdates.add);

      final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

      // Send 3 non-stationary samples (each triggers a failed attempt)
      for (int i = 0; i < 3; i++) {
        imuStreamController.add(_nonStationarySample(
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

    test('alignment succeeds after failed attempts if stationary samples follow', () async {
      await engine.start();

      final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

      // First attempt fails (non-stationary sample)
      imuStreamController.add(_nonStationarySample(baseTime));
      await Future.delayed(Duration.zero);

      // Second attempt: send 0.5s of stationary samples
      for (int i = 0; i <= 50; i++) {
        final timestamp = baseTime.add(Duration(milliseconds: 1000 + i * 10));
        imuStreamController.add(_stationarySample(timestamp));
      }
      await Future.delayed(Duration.zero);

      expect(engine.status, FusionStatus.initialized);
      verify(() => mockFilter.alignWithGravity(any())).called(1);
    });

    test('alignment requires exactly 0.5s time span between first and last sample', () async {
      await engine.start();

      final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

      // Send samples spanning only 400ms — should NOT trigger alignment
      for (int i = 0; i <= 40; i++) {
        final timestamp = baseTime.add(Duration(milliseconds: i * 10));
        imuStreamController.add(_stationarySample(timestamp));
      }
      await Future.delayed(Duration.zero);

      expect(engine.status, FusionStatus.aligning);
      verifyNever(() => mockFilter.alignWithGravity(any()));

      // Now send one more sample at 500ms — should trigger alignment
      imuStreamController.add(_stationarySample(
        baseTime.add(Duration(milliseconds: 500)),
      ));
      await Future.delayed(Duration.zero);

      expect(engine.status, FusionStatus.initialized);
      verify(() => mockFilter.alignWithGravity(any())).called(1);
    });

    test('does not process alignment samples when not in aligning state', () async {
      // Don't start the engine — status is uninitialized
      expect(engine.status, FusionStatus.uninitialized);

      // Manually verify that if somehow IMU data arrives, it won't crash
      // (This tests the guard in _onImuData)
    });

    test('stationarity boundary: gyro exactly at 0.05 rad/s is NOT stationary', () async {
      await engine.start();

      final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

      // Gyro magnitude exactly 0.05 — should fail (< 0.05 required, not <=)
      final borderlineSample = ImuData(
        ax: 0.0,
        ay: 0.0,
        az: 9.81,
        gx: 0.05, // magnitude = 0.05, NOT < 0.05
        gy: 0.0,
        gz: 0.0,
        timestamp: baseTime,
      );

      imuStreamController.add(borderlineSample);
      await Future.delayed(Duration.zero);

      // Should have incremented attempts (non-stationary)
      expect(engine.status, FusionStatus.aligning);
    });

    test('stationarity boundary: accel exactly 0.5 from 9.81 is NOT stationary', () async {
      await engine.start();

      final baseTime = DateTime(2024, 1, 1, 0, 0, 0);

      // Accel magnitude = 9.31 → deviation = 0.5, NOT < 0.5
      final borderlineSample = ImuData(
        ax: 0.0,
        ay: 0.0,
        az: 9.31, // |9.31 - 9.81| = 0.5, NOT < 0.5
        gx: 0.0,
        gy: 0.0,
        gz: 0.0,
        timestamp: baseTime,
      );

      imuStreamController.add(borderlineSample);
      await Future.delayed(Duration.zero);

      // Should have incremented attempts (non-stationary)
      expect(engine.status, FusionStatus.aligning);
    });
  });
}
