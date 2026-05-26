# Implementation Plan: IMU Kalman Sensor Fusion

## Overview

This plan implements IMU sensor fusion into ApxTracer's recording pipeline. The implementation proceeds bottom-up: package setup → pure conversion functions → IMU service → fusion engine orchestration → provider integration → recording engine modifications → tests. Each step builds on the previous, ensuring no orphaned code.

## Tasks

- [x] 1. Package dependency and platform configuration
  - [x] 1.1 Add sensors_plus dependency to pubspec.yaml
    - Add `sensors_plus: 6.1.1` to dependencies section
    - _Requirements: 7.1_

  - [x] 1.2 Configure iOS Info.plist with motion usage description
    - Add `NSMotionUsageDescription` key with value: "ApxTracer uses motion sensors to provide high-frequency telemetry and smooth position tracking during recording sessions."
    - _Requirements: 7.2_

- [x] 2. Core data models and pure conversion functions
  - [x] 2.1 Create nav_state_converter.dart with navStateToGpsSample pure function
    - Create `lib/engines/fusion/nav_state_converter.dart`
    - Implement `GpsSample? navStateToGpsSample({required NavState navState, required double gpsAccuracy, required int timestampMs})`
    - Include coordinate range validation (lat [-90,90], lon [-180,180]) returning null for invalid
    - Set `isLowAccuracy` based on `gpsAccuracy > 50.0`
    - Clamp heading to [0, 360]
    - _Requirements: 4.1, 4.2, 4.3, 4.6_

  - [x] 2.2 Write unit tests for navStateToGpsSample
    - Create `test/engines/fusion/nav_state_converter_test.dart`
    - Test valid NavState produces correct GpsSample with all fields mapped (latitude, longitude, altitude, speed, heading, accuracy, isLowAccuracy)
    - Test heading is clamped to [0, 360] range
    - Test `isLowAccuracy` is true when accuracy > 50 m, false otherwise
    - Test out-of-range latitude (< -90 or > 90) returns null
    - Test out-of-range longitude (< -180 or > 180) returns null
    - Test boundary values (lat exactly ±90, lon exactly ±180) return valid GpsSample
    - Test timestamp is passed through correctly
    - Use `mocktail` for any mocking needs
    - _Requirements: 4.1, 4.2, 4.3, 4.6_

  - [x] 2.3 Create positionToGpsData conversion function in nav_state_converter.dart
    - Implement `GpsData positionToGpsData(Position position)` in the same file
    - Map latitude, longitude, altitude directly
    - Map speed (null if < 0), heading (null if < 0), accuracy (default 100.0 if ≤ 0)
    - _Requirements: 3.2_

  - [x] 2.4 Write unit tests for positionToGpsData
    - Create `test/engines/fusion/position_to_gps_data_test.dart`
    - Test valid Position maps all fields correctly to GpsData
    - Test speed is null when Position.speed < 0
    - Test heading is null when Position.heading < 0
    - Test accuracy defaults to 100.0 when Position.accuracy ≤ 0
    - Test latitude, longitude, altitude are preserved exactly
    - Test timestamp is preserved
    - Use `mocktail` for any mocking needs
    - _Requirements: 3.2_

- [x] 3. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. IMU Service layer
  - [x] 4.1 Create ImuService abstract interface and supporting types
    - Create `lib/engines/fusion/imu_service.dart`
    - Define `abstract class ImuService` with: `checkAvailability()`, `startStreaming()`, `stopStreaming()`, `warnings` stream
    - Define `ImuDegradedWarning` class with `measuredRateHz` and `timestamp`
    - Define `ImuUnavailableException` class
    - _Requirements: 1.1, 1.3, 1.4, 1.6_

  - [x] 4.2 Create DefaultImuService implementation with coordinate transforms
    - Create `lib/engines/fusion/default_imu_service.dart`
    - Implement `DefaultImuService` using `sensors_plus` plugin streams
    - Pair accelerometer and gyroscope events by timestamp proximity into `ImuData`
    - Apply platform-specific coordinate transform (iOS/Android → body frame: X=right, Y=forward, Z=up)
    - Implement rate monitoring: emit `ImuDegradedWarning` when 500 ms sliding window average < 50 Hz
    - Handle permission denial on iOS (report `ImuUnavailableException`)
    - _Requirements: 1.1, 1.2, 1.3, 1.5, 1.6, 7.3, 7.4, 7.5_

  - [x] 4.3 Write unit tests for DefaultImuService coordinate transform
    - Create `test/engines/fusion/default_imu_service_test.dart`
    - Mock `sensors_plus` accelerometer and gyroscope streams using `mocktail`
    - Test that iOS raw accel (x, y, z) is transformed to body frame (X=right, Y=forward, Z=up) correctly
    - Test that acceleration vector magnitude is preserved after transform (sqrt(ax²+ay²+az²) unchanged)
    - Test that gyroscope vector magnitude is preserved after transform
    - Test that paired ImuData has correct timestamp with microsecond precision
    - Test that `checkAvailability()` returns false when sensors are unavailable
    - Test that `startStreaming()` throws `ImuUnavailableException` when sensors unavailable
    - Test that `stopStreaming()` cancels subscriptions and releases resources
    - _Requirements: 1.2, 1.3, 1.4, 1.5_

  - [x] 4.4 Write unit tests for rate monitoring and degradation detection
    - In `test/engines/fusion/default_imu_service_test.dart`
    - Mock sensor streams delivering samples at various rates
    - Test that no warning is emitted when rate stays above 50 Hz
    - Test that `ImuDegradedWarning` is emitted when 500 ms sliding window average drops below 50 Hz
    - Test that warning includes the measured rate value
    - Test that warning is not emitted repeatedly for the same degradation period
    - Test that warning clears when rate recovers above 50 Hz
    - _Requirements: 1.6_

- [x] 5. FusionEngine orchestration
  - [x] 5.1 Create FusionEngine with status enum and status update model
    - Create `lib/engines/fusion/fusion_engine.dart`
    - Define `FusionStatus` enum: `uninitialized`, `aligning`, `initialized`, `active`, `fallback`, `error`
    - Define `FusionStatusUpdate` class with status, errorMessage, timestamp
    - Implement `FusionEngine` class skeleton with constructor accepting `DeadReckoningFilter` and `ImuService`
    - Implement `start()` and `stop()` lifecycle methods
    - Implement `fusedSamples` stream and `statusUpdates` stream
    - _Requirements: 2.1, 2.6, 3.4, 5.1_

  - [x] 5.2 Implement gravity alignment and initialization sequencing in FusionEngine
    - Implement stationarity detection (angular rate < 0.05 rad/s AND accel magnitude within 0.5 m/s² of 9.81)
    - Implement 0.5s sample collection with up to 3 retry attempts
    - Call `alignWithGravity` on filter after successful collection
    - Transition through `aligning` → `initialized` states
    - Report alignment failure error after 3 failed attempts
    - _Requirements: 2.1, 2.2, 2.7_

  - [x] 5.3 Implement GPS fix filtering and filter initialization in FusionEngine
    - Buffer GPS fixes during initialization phase
    - Forward first fix with accuracy ≤ 50 m to `initWithGps`
    - Discard fixes with accuracy > 50 m
    - Implement 10-second GPS fix timeout with error reporting
    - Transition to `active` state after successful initialization
    - _Requirements: 2.3, 2.4, 2.5_

  - [x] 5.4 Implement IMU/GPS coordination and fused output in FusionEngine
    - Implement `onImuData(ImuData)` → forward to `filter.predictWithImu`
    - Implement `onGpsFix(Position)` → convert to GpsData, call `filter.updateWithGps`, read NavState, convert to GpsSample via `navStateToGpsSample`, emit on `fusedSamples` stream
    - Ensure exactly one fused GpsSample per GPS fix (1:1 correspondence)
    - _Requirements: 3.1, 3.2, 3.3, 4.1, 4.5_

  - [x] 5.5 Implement IMU gap detection and fallback logic in FusionEngine
    - Implement IMU watchdog timer (200 ms threshold → transition to `fallback`)
    - Implement short-gap recovery (200–500 ms): reinitialize with last known roll/pitch
    - Implement long-gap recovery (> 500 ms): reinitialize with zero roll/pitch
    - Handle transition boundaries (no duplicate/dropped samples)
    - _Requirements: 3.4, 3.5, 3.6, 6.6, 6.7_

  - [x] 5.6 Write unit tests for FusionEngine initialization sequencing
    - Create `test/engines/fusion/fusion_engine_test.dart`
    - Mock `ImuService` and `DeadReckoningFilter` using `mocktail`
    - Test that `start()` transitions status to `aligning` and begins collecting IMU samples
    - Test stationarity detection: stationary samples (gyro < 0.05 rad/s, accel within 0.5 m/s² of 9.81) pass alignment
    - Test stationarity detection: non-stationary samples trigger retry (up to 3 attempts)
    - Test alignment failure after 3 failed attempts transitions to `error` status
    - Test that `alignWithGravity` is called with collected samples after successful alignment
    - Test that first GPS fix with accuracy ≤ 50 m triggers `initWithGps` and transitions to `active`
    - Test that GPS fixes with accuracy > 50 m are discarded during initialization
    - Test that GPS fix timeout (10s) transitions to `error` status
    - Test that status updates are emitted on the `statusUpdates` stream for each transition
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.7_

  - [x] 5.7 Write unit tests for FusionEngine IMU/GPS coordination
    - In `test/engines/fusion/fusion_engine_test.dart`
    - Test that each IMU sample is forwarded to `filter.predictWithImu` when active
    - Test that each GPS fix produces exactly one fused GpsSample on `fusedSamples` stream (1:1 correspondence)
    - Test that GPS fix is converted to GpsData and passed to `filter.updateWithGps`
    - Test that NavState is read after GPS update and converted via `navStateToGpsSample`
    - Test that invalid NavState (out-of-range coordinates) results in no sample emitted for that fix
    - Test that IMU samples received before initialization are ignored
    - _Requirements: 3.1, 3.2, 3.3, 4.1, 4.5, 4.6_

  - [x] 5.8 Write unit tests for FusionEngine fallback and recovery
    - In `test/engines/fusion/fusion_engine_test.dart`
    - Test that IMU gap > 200 ms triggers transition to `fallback` status
    - Test that IMU gap ≤ 200 ms does NOT trigger fallback
    - Test that GPS fixes during fallback are NOT processed through the filter
    - Test short-gap recovery (200–500 ms): filter reinitialized with last known roll/pitch
    - Test long-gap recovery (> 500 ms): filter reinitialized with zero roll/pitch
    - Test transition boundary: no duplicate samples when switching active → fallback
    - Test transition boundary: no dropped samples when switching fallback → active
    - Test that total fused samples equals total GPS fixes across transitions in a session
    - Test `stop()` releases all subscriptions and timers within 200 ms
    - _Requirements: 3.4, 3.5, 3.6, 6.6, 6.7_

- [x] 6. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. FusionProvider and RecordingEngine integration
  - [x] 7.1 Create FusionProvider with StateNotifier
    - Create `lib/providers/fusion_provider.dart`
    - Implement `FusionState` immutable class with status, errorMessage, navState, latestUpdate
    - Implement `FusionNotifier extends StateNotifier<FusionState>`
    - Subscribe to `FusionEngine.statusUpdates` and update state
    - Expose non-null NavState only when status is `active` or `fallback`
    - Define `fusionProvider`, `fusionEngineProvider`, `imuServiceProvider` providers
    - Reset to `uninitialized` on session stop
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [x] 7.2 Write unit tests for FusionProvider state transitions
    - Create `test/engines/fusion/fusion_provider_test.dart`
    - Mock `FusionEngine` using `mocktail`
    - Test that FusionProvider exposes non-null NavState only when status is `active` or `fallback`
    - Test that FusionProvider exposes null NavState for `uninitialized`, `aligning`, `initialized`, `error` statuses
    - Test that status changes are propagated to listeners within one frame (16 ms)
    - Test that error status includes accompanying error message
    - Test that session stop resets status to `uninitialized` and releases subscriptions
    - Test that `RecordingUpdate` stream emits at 1 Hz when status is `active` or `fallback`
    - _Requirements: 5.1, 5.3, 5.4, 5.5_

  - [x] 7.3 Modify RecordingEngine to support FusionEngine delegation
    - Add optional `FusionEngine?` constructor parameter to `RecordingEngine`
    - In `startSession()`: check IMU availability, call `FusionEngine.start()` if available
    - Subscribe to `FusionEngine.fusedSamples` stream → feed into `_sampleBuffer`
    - Subscribe to `FusionEngine.statusUpdates` → handle active/fallback transitions
    - Modify `_onPositionReceived()`: route through `FusionEngine.onGpsFix()` when fusion active
    - In `stopSession()`: call `FusionEngine.stop()`, cancel fusion subscriptions
    - Preserve existing GPS-only path when `_fusionEngine` is null
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7_

  - [x] 7.4 Update RecordingProvider to wire FusionEngine dependency
    - Modify `recordingEngineProvider` to accept optional `FusionEngine` from `fusionEngineProvider`
    - Ensure `RecordingNotifier` still works when fusion is unavailable
    - _Requirements: 6.2_

  - [x] 7.5 Write unit tests for RecordingEngine fusion delegation
    - Create `test/engines/fusion/recording_engine_fusion_test.dart`
    - Mock `FusionEngine`, `ImuService`, `GpsService`, `SessionRepository`, `GpsSampleRepository` using `mocktail`
    - Test that `startSession()` delegates to FusionEngine when IMU is available
    - Test that `startSession()` uses GPS-only path when IMU is unavailable (FusionEngine is null)
    - Test that GPS positions are routed through `FusionEngine.onGpsFix()` when fusion is active
    - Test that GPS positions are persisted directly when fusion is in fallback mode
    - Test transition from active → fallback: next GPS fix persisted directly, no duplicates
    - Test transition from fallback → active: next fused sample persisted, no duplicates
    - Test that `RecordingUpdate` is emitted at 1 Hz regardless of fusion/GPS-only mode
    - Test that `stopSession()` calls `FusionEngine.stop()` and persists all buffered samples
    - Test that all buffered fused samples are persisted within 500 ms on stop
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7_

- [x] 8. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- All tests use `mocktail` for mocking (already in dev_dependencies)
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- The `DeadReckoningFilter` and `kalman_models.dart` are existing and unchanged — this implementation wraps them
- All new files go in `lib/engines/fusion/` and `lib/providers/fusion_provider.dart`
- Test files go in `test/engines/fusion/`

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["2.1", "2.3", "4.1"] },
    { "id": 2, "tasks": ["2.2", "2.4", "4.2"] },
    { "id": 3, "tasks": ["4.3", "4.4", "5.1"] },
    { "id": 4, "tasks": ["5.2", "5.3"] },
    { "id": 5, "tasks": ["5.4", "5.5"] },
    { "id": 6, "tasks": ["5.6", "5.7", "5.8"] },
    { "id": 7, "tasks": ["7.1", "7.3"] },
    { "id": 8, "tasks": ["7.2", "7.4", "7.5"] }
  ]
}
```
