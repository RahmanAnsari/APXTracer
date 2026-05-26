import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:apx_tracer/engines/fusion/default_imu_service.dart';
import 'package:apx_tracer/engines/fusion/imu_service.dart';
import 'package:apx_tracer/engines/kalman/kalman_models.dart';

void main() {
  group('DefaultImuService - Coordinate transform', () {
    late StreamController<AccelerometerEvent> accelController;
    late StreamController<GyroscopeEvent> gyroController;

    setUp(() {
      accelController = StreamController<AccelerometerEvent>.broadcast();
      gyroController = StreamController<GyroscopeEvent>.broadcast();
    });

    tearDown(() {
      accelController.close();
      gyroController.close();
    });

    DefaultImuService createService() {
      return DefaultImuService(
        accelStreamFactory: () => accelController.stream,
        gyroStreamFactory: () => gyroController.stream,
      );
    }

    test('iOS raw accel (x, y, z) is transformed to body frame (X=right, Y=forward, Z=up) correctly', () async {
      final service = createService();
      final imuDataList = <ImuData>[];

      final stream = service.startStreaming();
      final sub = stream.listen(imuDataList.add);

      final timestamp = DateTime(2024, 1, 1, 12, 0, 0);

      // Emit accel and gyro with known values.
      // sensors_plus convention matches body frame (identity transform).
      // X=right, Y=forward (top of device), Z=up (out of screen).
      accelController.add(AccelerometerEvent(1.5, 2.5, 9.81, timestamp));
      gyroController.add(GyroscopeEvent(0.1, 0.2, 0.3, timestamp));

      // Allow microtask queue to process.
      await Future<void>.delayed(Duration.zero);

      expect(imuDataList, hasLength(1));
      final imu = imuDataList.first;

      // Identity transform: output should match input.
      expect(imu.ax, 1.5);
      expect(imu.ay, 2.5);
      expect(imu.az, 9.81);
      expect(imu.gx, 0.1);
      expect(imu.gy, 0.2);
      expect(imu.gz, 0.3);

      await sub.cancel();
      await service.stopStreaming();
      service.dispose();
    });

    test('acceleration vector magnitude is preserved after transform', () async {
      final service = createService();
      final imuDataList = <ImuData>[];

      final stream = service.startStreaming();
      final sub = stream.listen(imuDataList.add);

      final timestamp = DateTime(2024, 1, 1, 12, 0, 0);

      const ax = 3.0;
      const ay = 4.0;
      const az = 5.0;
      final inputMagnitude = math.sqrt(ax * ax + ay * ay + az * az);

      accelController.add(AccelerometerEvent(ax, ay, az, timestamp));
      gyroController.add(GyroscopeEvent(0.0, 0.0, 0.0, timestamp));

      await Future<void>.delayed(Duration.zero);

      expect(imuDataList, hasLength(1));
      final imu = imuDataList.first;

      final outputMagnitude =
          math.sqrt(imu.ax * imu.ax + imu.ay * imu.ay + imu.az * imu.az);

      expect(outputMagnitude, closeTo(inputMagnitude, 1e-10));

      await sub.cancel();
      await service.stopStreaming();
      service.dispose();
    });

    test('gyroscope vector magnitude is preserved after transform', () async {
      final service = createService();
      final imuDataList = <ImuData>[];

      final stream = service.startStreaming();
      final sub = stream.listen(imuDataList.add);

      final timestamp = DateTime(2024, 1, 1, 12, 0, 0);

      const gx = 0.5;
      const gy = 0.3;
      const gz = 0.7;
      final inputMagnitude = math.sqrt(gx * gx + gy * gy + gz * gz);

      accelController.add(AccelerometerEvent(0.0, 0.0, 9.81, timestamp));
      gyroController.add(GyroscopeEvent(gx, gy, gz, timestamp));

      await Future<void>.delayed(Duration.zero);

      expect(imuDataList, hasLength(1));
      final imu = imuDataList.first;

      final outputMagnitude =
          math.sqrt(imu.gx * imu.gx + imu.gy * imu.gy + imu.gz * imu.gz);

      expect(outputMagnitude, closeTo(inputMagnitude, 1e-10));

      await sub.cancel();
      await service.stopStreaming();
      service.dispose();
    });

    test('paired ImuData has correct timestamp with microsecond precision', () async {
      final service = createService();
      final imuDataList = <ImuData>[];

      final stream = service.startStreaming();
      final sub = stream.listen(imuDataList.add);

      // Use a timestamp with microsecond precision.
      final timestamp = DateTime(2024, 6, 15, 10, 30, 45, 123, 456);

      accelController.add(AccelerometerEvent(0.0, 0.0, 9.81, timestamp));
      gyroController.add(GyroscopeEvent(0.0, 0.0, 0.0, timestamp));

      await Future<void>.delayed(Duration.zero);

      expect(imuDataList, hasLength(1));
      final imu = imuDataList.first;

      // The timestamp should preserve microsecond precision.
      expect(imu.timestamp.microsecond, timestamp.microsecond);
      expect(imu.timestamp.millisecond, timestamp.millisecond);
      expect(imu.timestamp.second, timestamp.second);
      expect(imu.timestamp, equals(timestamp));

      await sub.cancel();
      await service.stopStreaming();
      service.dispose();
    });
  });

  group('DefaultImuService - Availability and streaming lifecycle', () {
    test('checkAvailability() returns false when sensors are unavailable', () async {
      // Create stream factories that never emit (simulating unavailable sensors).
      final accelController = StreamController<AccelerometerEvent>.broadcast();
      final gyroController = StreamController<GyroscopeEvent>.broadcast();

      final service = DefaultImuService(
        accelStreamFactory: () => accelController.stream,
        gyroStreamFactory: () => gyroController.stream,
      );

      // checkAvailability waits up to 1 second for events.
      // Since we never emit, it should timeout and return false.
      final available = await service.checkAvailability();

      expect(available, false);

      await accelController.close();
      await gyroController.close();
      service.dispose();
    });

    test('checkAvailability() returns true when sensors are available', () async {
      final accelController = StreamController<AccelerometerEvent>.broadcast();
      final gyroController = StreamController<GyroscopeEvent>.broadcast();

      final service = DefaultImuService(
        accelStreamFactory: () => accelController.stream,
        gyroStreamFactory: () => gyroController.stream,
      );

      // Emit events shortly after checkAvailability is called.
      final timestamp = DateTime.now();
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        accelController.add(AccelerometerEvent(0.0, 0.0, 9.81, timestamp));
        gyroController.add(GyroscopeEvent(0.0, 0.0, 0.0, timestamp));
      });

      final available = await service.checkAvailability();

      expect(available, true);

      await accelController.close();
      await gyroController.close();
      service.dispose();
    });

    test('startStreaming() throws ImuUnavailableException when sensors unavailable', () {
      // Create a factory that throws when called (simulating permission denied).
      final service = DefaultImuService(
        accelStreamFactory: () => throw Exception('Permission denied'),
        gyroStreamFactory: () => Stream<GyroscopeEvent>.empty(),
      );

      expect(
        () => service.startStreaming(),
        throwsA(isA<ImuUnavailableException>()),
      );

      service.dispose();
    });

    test('stopStreaming() cancels subscriptions and releases resources', () async {
      final accelController = StreamController<AccelerometerEvent>.broadcast();
      final gyroController = StreamController<GyroscopeEvent>.broadcast();

      final service = DefaultImuService(
        accelStreamFactory: () => accelController.stream,
        gyroStreamFactory: () => gyroController.stream,
      );

      final imuDataList = <ImuData>[];
      final stream = service.startStreaming();
      final sub = stream.listen(imuDataList.add);

      // Emit a paired event to confirm streaming works.
      final timestamp = DateTime(2024, 1, 1, 12, 0, 0);
      accelController.add(AccelerometerEvent(1.0, 2.0, 3.0, timestamp));
      gyroController.add(GyroscopeEvent(0.1, 0.2, 0.3, timestamp));
      await Future<void>.delayed(Duration.zero);
      expect(imuDataList, hasLength(1));

      // Stop streaming.
      await service.stopStreaming();

      // Emit more events — they should NOT produce ImuData.
      final timestamp2 = DateTime(2024, 1, 1, 12, 0, 1);
      accelController.add(AccelerometerEvent(4.0, 5.0, 6.0, timestamp2));
      gyroController.add(GyroscopeEvent(0.4, 0.5, 0.6, timestamp2));
      await Future<void>.delayed(Duration.zero);

      // Should still only have the one event from before stopStreaming.
      expect(imuDataList, hasLength(1));

      await sub.cancel();
      await accelController.close();
      await gyroController.close();
      service.dispose();
    });
  });

  group('DefaultImuService - Rate monitoring and degradation detection', () {
    late StreamController<AccelerometerEvent> accelController;
    late StreamController<GyroscopeEvent> gyroController;

    setUp(() {
      accelController = StreamController<AccelerometerEvent>.broadcast();
      gyroController = StreamController<GyroscopeEvent>.broadcast();
    });

    tearDown(() {
      accelController.close();
      gyroController.close();
    });

    /// Helper to create a DefaultImuService with mock stream factories.
    DefaultImuService createService() {
      return DefaultImuService(
        accelStreamFactory: () => accelController.stream,
        gyroStreamFactory: () => gyroController.stream,
      );
    }

    /// Emits a paired accel + gyro event at the given timestamp.
    void emitPairedEvent(DateTime timestamp) {
      accelController.add(AccelerometerEvent(0.0, 0.0, 9.81, timestamp));
      gyroController.add(GyroscopeEvent(0.0, 0.0, 0.0, timestamp));
    }

    test('no warning emitted when rate stays above 50 Hz', () {
      fakeAsync((async) {
        final service = createService();
        final warnings = <ImuDegradedWarning>[];

        service.warnings.listen(warnings.add);
        service.startStreaming();

        // The rate check fires every 100ms. At the first check (100ms),
        // there will be ~10 samples in the window (rate = 20 Hz).
        // This is a startup transient. To test steady-state behavior,
        // we fill the window first, then verify no warnings after that.
        //
        // Emit at 100 Hz for 600ms to fill the 500ms window.
        for (int i = 0; i < 60; i++) {
          emitPairedEvent(clock.now());
          async.elapse(const Duration(milliseconds: 10));
        }

        // Window is now full. Clear any startup transient warnings.
        warnings.clear();

        // Continue emitting at 100 Hz for another 500ms.
        // Rate checks during this period should all see rate > 50 Hz.
        for (int i = 0; i < 50; i++) {
          emitPairedEvent(clock.now());
          async.elapse(const Duration(milliseconds: 10));
        }

        // No warnings should be emitted during steady-state high-rate operation.
        expect(warnings, isEmpty);

        service.dispose();
      });
    });

    test('ImuDegradedWarning emitted when 500ms window average drops below 50 Hz', () {
      fakeAsync((async) {
        final service = createService();
        final warnings = <ImuDegradedWarning>[];

        service.warnings.listen(warnings.add);
        service.startStreaming();

        // Emit only 10 samples in 500ms → 20 Hz (below 50 Hz threshold).
        // Use clock.now() to align timestamps with the fake clock.
        for (int i = 0; i < 10; i++) {
          emitPairedEvent(clock.now());
          async.elapse(const Duration(milliseconds: 50));
        }

        // Allow rate check timer to fire (fires every 100ms).
        async.elapse(const Duration(milliseconds: 200));

        expect(warnings, isNotEmpty);
        expect(warnings.first, isA<ImuDegradedWarning>());

        service.dispose();
      });
    });

    test('warning includes the measured rate value', () {
      fakeAsync((async) {
        final service = createService();
        final warnings = <ImuDegradedWarning>[];

        service.warnings.listen(warnings.add);
        service.startStreaming();

        // Emit 10 samples over 500ms → rate = 10 / 0.5 = 20 Hz.
        for (int i = 0; i < 10; i++) {
          emitPairedEvent(clock.now());
          async.elapse(const Duration(milliseconds: 50));
        }

        // Allow rate check timer to fire.
        async.elapse(const Duration(milliseconds: 200));

        expect(warnings, isNotEmpty);
        // The measured rate should be below 50 Hz.
        expect(warnings.first.measuredRateHz, lessThan(50.0));
        // It should be a positive number representing the actual rate.
        expect(warnings.first.measuredRateHz, greaterThan(0.0));

        service.dispose();
      });
    });

    test('warning is not emitted repeatedly for the same degradation period', () {
      fakeAsync((async) {
        final service = createService();
        final warnings = <ImuDegradedWarning>[];

        service.warnings.listen(warnings.add);
        service.startStreaming();

        // Emit a few samples to get below threshold.
        for (int i = 0; i < 5; i++) {
          emitPairedEvent(clock.now());
          async.elapse(const Duration(milliseconds: 100));
        }

        // Let multiple rate check intervals pass while still degraded.
        // Rate check fires every 100ms. Let it fire several times.
        async.elapse(const Duration(milliseconds: 1000));

        // Should only have one warning despite multiple rate checks.
        expect(warnings.length, equals(1));

        service.dispose();
      });
    });

    test('warning clears when rate recovers above 50 Hz', () {
      fakeAsync((async) {
        final service = createService();
        final warnings = <ImuDegradedWarning>[];

        service.warnings.listen(warnings.add);
        service.startStreaming();

        // Phase 1: Trigger degradation.
        // Emit a burst of samples then let the rate check detect low rate.
        for (int i = 0; i < 5; i++) {
          emitPairedEvent(clock.now());
        }
        // Wait for rate check to fire. 5 samples in 500ms window = 10 Hz → degraded.
        async.elapse(const Duration(milliseconds: 600));
        expect(warnings.length, equals(1),
            reason: 'First degradation warning should be emitted');

        // Phase 2: Recover rate above 50 Hz.
        // Emit many samples rapidly so the window fills above threshold.
        // Need > 25 samples in the 500ms window for rate > 50 Hz.
        // Emit 80 samples at 5ms intervals = 400ms. This gives 80/0.5 = 160 Hz.
        for (int i = 0; i < 80; i++) {
          emitPairedEvent(clock.now());
          async.elapse(const Duration(milliseconds: 5));
        }
        // At this point, the rate check has fired multiple times during recovery.
        // Once rate > 50 Hz, _isDegraded is set to false.
        // Let one more rate check fire to ensure recovery is detected.
        async.elapse(const Duration(milliseconds: 100));

        // Verify no additional warnings during recovery.
        // (Only the original Phase 1 warning should exist.)
        final warningsAfterRecovery = warnings.length;

        // Phase 3: Immediately drop to low rate (no gap).
        // The window still has recovery samples, so we need to wait for them
        // to age out. Emit at very low rate: 1 sample every 200ms.
        // After 500ms, old recovery samples fall out of window.
        for (int i = 0; i < 10; i++) {
          emitPairedEvent(clock.now());
          async.elapse(const Duration(milliseconds: 200));
        }

        // After 2000ms at low rate, the window should only contain recent
        // low-rate samples. Rate = samples_in_window / 0.5.
        // In the last 500ms: ~2-3 samples → rate = 4-6 Hz → degraded.
        // Since _isDegraded was reset to false during recovery, a new warning
        // should be emitted.

        // Allow final rate checks.
        async.elapse(const Duration(milliseconds: 300));

        // Should have at least 2 warnings (one from Phase 1, one from Phase 3).
        expect(warnings.length, greaterThan(warningsAfterRecovery),
            reason: 'A new degradation warning should be emitted after recovery');

        service.dispose();
      });
    });
  });
}
