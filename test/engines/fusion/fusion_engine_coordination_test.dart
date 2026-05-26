import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:geolocator/geolocator.dart';

import 'package:apx_tracer/engines/kalman/dead_reckoning_filter.dart';
import 'package:apx_tracer/engines/kalman/kalman_models.dart';
import 'package:apx_tracer/engines/fusion/fusion_engine.dart';
import 'package:apx_tracer/engines/fusion/imu_service.dart';
import 'package:apx_tracer/models/gps_sample.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockDeadReckoningFilter extends Mock implements DeadReckoningFilter {}

class MockImuService extends Mock implements ImuService {}

// ─── Fakes for mocktail registerFallbackValue ────────────────────────────────

class FakeImuData extends Fake implements ImuData {}

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

/// Creates a valid Position with sensible defaults.
Position _createPosition({
  double latitude = 37.7749,
  double longitude = -122.4194,
  double altitude = 10.0,
  double speed = 5.0,
  double heading = 90.0,
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

/// Returns a valid NavState with coordinates at (37.7749, -122.4194).
NavState _validNavState() {
  return const NavState(
    px: 0.0,
    py: 0.0,
    pz: 0.0,
    vx: 3.54,
    vy: 3.54,
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
    originLat: 37.7749,
    originLon: -122.4194,
    originAlt: 10.0,
  );
}

/// Returns an invalid NavState with latitude > 90.
NavState _invalidNavState() {
  return const NavState(
    px: 100000.0, // large ENU offset → latitude > 90
    py: 100000.0,
    pz: 0.0,
    vx: 0.0,
    vy: 0.0,
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
    originLat: 89.5, // near pole, so small ENU offset → lat > 90
    originLon: -122.4194,
    originAlt: 10.0,
  );
}

void main() {
  late MockDeadReckoningFilter mockFilter;
  late MockImuService mockImuService;
  late StreamController<ImuData> imuStreamController;
  late FusionEngine engine;

  setUpAll(() {
    registerFallbackValue(FakeImuData());
    registerFallbackValue(FakeGpsData());
    registerFallbackValue(<ImuData>[]);
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
            initialPitch: any(named: 'initialPitch')))
        .thenReturn(null);
    when(() => mockFilter.predictWithImu(any())).thenReturn(null);
    when(() => mockFilter.updateWithGps(any())).thenReturn(null);
    when(() => mockFilter.isInitialized).thenReturn(true);
    when(() => mockFilter.state).thenReturn(_validNavState());

    engine = FusionEngine(
      filter: mockFilter,
      imuService: mockImuService,
    );
  });

  tearDown(() async {
    await imuStreamController.close();
  });

  /// Helper to bring the engine to `active` state.
  /// Sends stationary samples for 0.5s, then a valid GPS fix.
  Future<void> bringToActiveState() async {
    await engine.start();

    // Send stationary samples spanning 0.5 seconds
    final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
    for (int i = 0; i <= 50; i++) {
      final timestamp = baseTime.add(Duration(milliseconds: i * 10));
      imuStreamController.add(_stationarySample(timestamp));
    }
    await Future.delayed(Duration.zero);

    // Should now be in `initialized` state
    expect(engine.status, FusionStatus.initialized);

    // Send a valid GPS fix to transition to `active`
    engine.onGpsFix(_createPosition());
    await Future.delayed(Duration.zero);

    expect(engine.status, FusionStatus.active);
  }

  group('FusionEngine IMU/GPS coordination (task 5.7)', () {
    group('IMU forwarding to filter.predictWithImu', () {
      test('each IMU sample is forwarded to filter.predictWithImu when active',
          () async {
        await bringToActiveState();

        // Send 5 IMU samples while active
        final baseTime = DateTime(2024, 1, 1, 0, 0, 1);
        for (int i = 0; i < 5; i++) {
          final timestamp = baseTime.add(Duration(milliseconds: i * 10));
          final sample = ImuData(
            ax: 0.1 * i,
            ay: 0.2 * i,
            az: 9.81,
            gx: 0.01 * i,
            gy: 0.0,
            gz: 0.0,
            timestamp: timestamp,
          );
          imuStreamController.add(sample);
        }
        await Future.delayed(Duration.zero);

        // predictWithImu should have been called for each sample
        // (plus the alignment samples that were sent before active state,
        //  but those were in aligning state so predictWithImu was NOT called)
        verify(() => mockFilter.predictWithImu(any())).called(5);
      });
    });

    group('GPS fix produces fused GpsSample (1:1 correspondence)', () {
      test(
          'each GPS fix produces exactly one fused GpsSample on fusedSamples stream',
          () async {
        await bringToActiveState();

        final emittedSamples = <GpsSample>[];
        engine.fusedSamples.listen(emittedSamples.add);

        // Send 3 GPS fixes
        for (int i = 0; i < 3; i++) {
          engine.onGpsFix(_createPosition(
            timestamp: DateTime(2024, 1, 1, 0, 0, i + 1),
          ));
        }
        await Future.delayed(Duration.zero);

        // Should have exactly 3 fused samples (1:1 correspondence)
        expect(emittedSamples.length, 3);
      });

      test('N GPS fixes produce exactly N fused samples', () async {
        await bringToActiveState();

        final emittedSamples = <GpsSample>[];
        engine.fusedSamples.listen(emittedSamples.add);

        const n = 10;
        for (int i = 0; i < n; i++) {
          engine.onGpsFix(_createPosition(
            timestamp: DateTime(2024, 1, 1, 0, 0, i + 1),
          ));
        }
        await Future.delayed(Duration.zero);

        expect(emittedSamples.length, n);
      });
    });

    group('GPS fix conversion and filter update', () {
      test(
          'GPS fix is converted to GpsData and passed to filter.updateWithGps',
          () async {
        await bringToActiveState();

        // Reset interaction count from initialization
        clearInteractions(mockFilter);
        when(() => mockFilter.isInitialized).thenReturn(true);
        when(() => mockFilter.state).thenReturn(_validNavState());
        when(() => mockFilter.updateWithGps(any())).thenReturn(null);
        when(() => mockFilter.predictWithImu(any())).thenReturn(null);

        final position = _createPosition(
          latitude: 37.7750,
          longitude: -122.4195,
          altitude: 15.0,
          speed: 10.0,
          heading: 45.0,
          accuracy: 3.0,
          timestamp: DateTime(2024, 6, 15, 12, 30, 0),
        );

        engine.onGpsFix(position);
        await Future.delayed(Duration.zero);

        // Verify updateWithGps was called with a GpsData
        final captured =
            verify(() => mockFilter.updateWithGps(captureAny())).captured;
        expect(captured.length, 1);
        final gpsData = captured.first as GpsData;
        expect(gpsData.latitude, 37.7750);
        expect(gpsData.longitude, -122.4195);
        expect(gpsData.altitude, 15.0);
        expect(gpsData.speed, 10.0);
        expect(gpsData.heading, 45.0);
        expect(gpsData.accuracy, 3.0);
      });
    });

    group('NavState read after GPS update and conversion', () {
      test(
          'NavState is read after GPS update and converted via navStateToGpsSample',
          () async {
        await bringToActiveState();

        final emittedSamples = <GpsSample>[];
        engine.fusedSamples.listen(emittedSamples.add);

        final position = _createPosition(
          accuracy: 8.0,
          timestamp: DateTime(2024, 6, 15, 12, 30, 0),
        );

        engine.onGpsFix(position);
        await Future.delayed(Duration.zero);

        // Verify filter.state was accessed (NavState read)
        verify(() => mockFilter.state).called(greaterThan(0));

        // Verify the emitted sample matches the NavState conversion
        expect(emittedSamples.length, 1);
        final sample = emittedSamples.first;
        // NavState at origin (px=0, py=0) → lat = originLat, lon = originLon
        expect(sample.latitude, closeTo(37.7749, 0.001));
        expect(sample.longitude, closeTo(-122.4194, 0.001));
        expect(sample.accuracy, 8.0);
        expect(sample.isLowAccuracy, false);
        expect(sample.timestamp,
            DateTime(2024, 6, 15, 12, 30, 0).millisecondsSinceEpoch);
      });
    });

    group('Invalid NavState handling', () {
      test(
          'invalid NavState (out-of-range coordinates) results in no sample emitted',
          () async {
        await bringToActiveState();

        // Now mock filter.state to return an invalid NavState
        when(() => mockFilter.state).thenReturn(_invalidNavState());

        final emittedSamples = <GpsSample>[];
        engine.fusedSamples.listen(emittedSamples.add);

        engine.onGpsFix(_createPosition(
          timestamp: DateTime(2024, 1, 1, 0, 0, 1),
        ));
        await Future.delayed(Duration.zero);

        // No sample should be emitted for invalid coordinates
        expect(emittedSamples.length, 0);
      });

      test(
          'mix of valid and invalid NavStates emits only for valid ones',
          () async {
        await bringToActiveState();

        final emittedSamples = <GpsSample>[];
        engine.fusedSamples.listen(emittedSamples.add);

        // First fix: valid NavState
        when(() => mockFilter.state).thenReturn(_validNavState());
        engine.onGpsFix(_createPosition(
          timestamp: DateTime(2024, 1, 1, 0, 0, 1),
        ));
        await Future.delayed(Duration.zero);

        // Second fix: invalid NavState
        when(() => mockFilter.state).thenReturn(_invalidNavState());
        engine.onGpsFix(_createPosition(
          timestamp: DateTime(2024, 1, 1, 0, 0, 2),
        ));
        await Future.delayed(Duration.zero);

        // Third fix: valid NavState again
        when(() => mockFilter.state).thenReturn(_validNavState());
        engine.onGpsFix(_createPosition(
          timestamp: DateTime(2024, 1, 1, 0, 0, 3),
        ));
        await Future.delayed(Duration.zero);

        // Only 2 samples emitted (first and third)
        expect(emittedSamples.length, 2);
      });
    });

    group('IMU samples before initialization are ignored', () {
      test(
          'predictWithImu is NOT called when status is aligning',
          () async {
        await engine.start();
        expect(engine.status, FusionStatus.aligning);

        // Send IMU samples while in aligning state
        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        for (int i = 0; i < 5; i++) {
          final timestamp = baseTime.add(Duration(milliseconds: i * 10));
          imuStreamController.add(ImuData(
            ax: 1.0,
            ay: 2.0,
            az: 9.81,
            gx: 0.0,
            gy: 0.0,
            gz: 0.0,
            timestamp: timestamp,
          ));
        }
        await Future.delayed(Duration.zero);

        // predictWithImu should NOT have been called during aligning
        verifyNever(() => mockFilter.predictWithImu(any()));
      });

      test(
          'predictWithImu is NOT called when status is initialized',
          () async {
        await engine.start();

        // Bring to initialized state (send stationary samples for 0.5s)
        final baseTime = DateTime(2024, 1, 1, 0, 0, 0);
        for (int i = 0; i <= 50; i++) {
          final timestamp = baseTime.add(Duration(milliseconds: i * 10));
          imuStreamController.add(_stationarySample(timestamp));
        }
        await Future.delayed(Duration.zero);
        expect(engine.status, FusionStatus.initialized);

        // Now send more IMU samples while in initialized state
        for (int i = 0; i < 5; i++) {
          final timestamp =
              baseTime.add(Duration(milliseconds: 600 + i * 10));
          imuStreamController.add(ImuData(
            ax: 0.5,
            ay: 0.5,
            az: 9.81,
            gx: 0.0,
            gy: 0.0,
            gz: 0.0,
            timestamp: timestamp,
          ));
        }
        await Future.delayed(Duration.zero);

        // predictWithImu should NOT have been called in initialized state
        verifyNever(() => mockFilter.predictWithImu(any()));
      });

      test(
          'predictWithImu IS called once engine transitions to active',
          () async {
        await bringToActiveState();

        // Reset interactions to only count from now
        clearInteractions(mockFilter);
        when(() => mockFilter.isInitialized).thenReturn(true);
        when(() => mockFilter.state).thenReturn(_validNavState());
        when(() => mockFilter.predictWithImu(any())).thenReturn(null);

        // Send IMU samples while active
        final baseTime = DateTime(2024, 1, 1, 0, 0, 1);
        for (int i = 0; i < 3; i++) {
          final timestamp = baseTime.add(Duration(milliseconds: i * 10));
          imuStreamController.add(_stationarySample(timestamp));
        }
        await Future.delayed(Duration.zero);

        // predictWithImu should now be called
        verify(() => mockFilter.predictWithImu(any())).called(3);
      });
    });
  });
}
