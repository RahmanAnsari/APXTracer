# Requirements Document

## Introduction

This feature integrates IMU (Inertial Measurement Unit) sensor fusion with the existing Extended Kalman Filter (`DeadReckoningFilter`) into ApxTracer's GPS-only recording pipeline. The integration provides high-frequency position and velocity estimates between GPS fixes, smoother telemetry data during GPS dropouts, and more accurate speed/heading readings for motorsport analytics. The system acquires raw accelerometer and gyroscope data via the `sensors_plus` Flutter plugin, feeds it through the 15-state EKF at 100 Hz, fuses GPS updates at 1–10 Hz, and outputs filtered `GpsSample`-compatible data to the existing persistence, analytics, and UI layers.

## Glossary

- **IMU_Service**: The service responsible for acquiring raw accelerometer and gyroscope data from the device hardware via the `sensors_plus` plugin and delivering it as a stream of `ImuData` objects.
- **Fusion_Engine**: The orchestration component that manages the `DeadReckoningFilter` lifecycle, coordinates IMU and GPS streams, handles initialization sequencing, and produces fused navigation output.
- **DeadReckoningFilter**: The existing 15-state Extended Kalman Filter that estimates position, velocity, attitude, and sensor biases from IMU predictions and GPS updates.
- **NavState**: The filter output containing ENU position, velocity, attitude, biases, and derived lat/lon/speed/bearing.
- **GpsSample**: The existing telemetry data model consumed by persistence, lap detection, track discovery, analytics, and export layers.
- **Recording_Engine**: The existing `RecordingEngine` that captures GPS positions, buffers them, and persists to SQLite.
- **Initialization_Phase**: The startup period (~0.5 s) during which the device must remain stationary to estimate initial roll and pitch from gravity alignment before the filter begins operation.
- **Fusion_Provider**: The Riverpod provider that exposes the Fusion_Engine state and fused telemetry stream to the UI and other providers.
- **ENU_Frame**: East-North-Up local tangent plane coordinate frame with origin at the first GPS fix.

## Requirements

### Requirement 1: IMU Data Acquisition

**User Story:** As a motorsport driver, I want the app to capture high-frequency IMU data from my device's accelerometer and gyroscope, so that the Kalman filter can produce smooth position estimates between GPS fixes.

#### Acceptance Criteria

1. WHEN a recording session starts, THE IMU_Service SHALL begin streaming accelerometer and gyroscope data at the highest available rate supported by the device hardware, targeting 100 Hz with a minimum acceptable rate of 50 Hz.
2. THE IMU_Service SHALL deliver each measurement as an `ImuData` object containing three-axis acceleration (m/s²), three-axis angular rate (rad/s), and a timestamp with microsecond precision.
3. WHEN a recording session stops, THE IMU_Service SHALL stop streaming IMU data and release hardware resources within 100 ms.
4. IF the device does not have an accelerometer or gyroscope, THEN THE IMU_Service SHALL report a sensor unavailability error to the Fusion_Engine before the session begins.
5. THE IMU_Service SHALL apply a platform-specific coordinate transform (iOS-to-body-frame and Android-to-body-frame) so that delivered measurements use the convention: X = device-right, Y = device-forward, Z = device-up (matching the DeadReckoningFilter body frame assumption).
6. IF the IMU_Service detects that the actual sample delivery rate falls below 50 Hz for more than 500 ms, THEN THE IMU_Service SHALL notify the Fusion_Engine with a degraded-rate warning indicating the current measured rate.

### Requirement 2: Filter Initialization Sequencing

**User Story:** As a motorsport driver, I want the filter to automatically calibrate itself at the start of each session, so that I get accurate telemetry without manual setup steps.

#### Acceptance Criteria

1. WHEN a recording session starts, THE Fusion_Engine SHALL collect IMU samples for a minimum of 0.5 seconds while the device is stationary (angular rate magnitude below 0.05 rad/s and acceleration magnitude within 0.5 m/s² of 9.81 m/s²) to perform gravity alignment.
2. WHEN the gravity alignment period completes, THE Fusion_Engine SHALL call `alignWithGravity` on the DeadReckoningFilter with the collected samples to estimate initial roll and pitch.
3. WHEN the first valid GPS fix arrives after gravity alignment, THE Fusion_Engine SHALL call `initWithGps` on the DeadReckoningFilter with the GPS fix and the estimated roll and pitch values.
4. WHILE the Fusion_Engine is in the Initialization_Phase, THE Fusion_Engine SHALL buffer incoming GPS fixes and forward the first valid fix (accuracy ≤ 50 m) to the filter for initialization.
5. IF no valid GPS fix arrives within 10 seconds after gravity alignment completes, THEN THE Fusion_Engine SHALL report a GPS fix timeout error, transition to the `error` status via the Fusion_Provider, and abort the session start without persisting any buffered data.
6. WHILE the Fusion_Engine is in the Initialization_Phase, THE Recording_Engine SHALL display an "Initializing sensors" status to the user via the Fusion_Provider.
7. IF the device is not stationary (angular rate magnitude ≥ 0.05 rad/s or acceleration magnitude deviates more than 0.5 m/s² from 9.81 m/s²) during the gravity alignment period, THEN THE Fusion_Engine SHALL discard collected samples, restart the 0.5-second alignment collection, and repeat up to 3 attempts before reporting an alignment failure error and aborting the session start.

### Requirement 3: Real-Time Sensor Fusion

**User Story:** As a motorsport driver, I want the app to continuously fuse IMU and GPS data during a session, so that I get smooth, high-frequency position and speed estimates even when GPS updates are delayed.

#### Acceptance Criteria

1. WHILE a recording session is active and the filter is initialized, THE Fusion_Engine SHALL forward each IMU sample to `DeadReckoningFilter.predictWithImu` within 5 ms of receipt.
2. WHILE a recording session is active and the filter is initialized, THE Fusion_Engine SHALL forward each GPS fix to `DeadReckoningFilter.updateWithGps` by converting the `Position` object to a `GpsData` instance, regardless of the fix accuracy (the filter internally rejects fixes exceeding its configured accuracy threshold).
3. WHILE a recording session is active and the filter is initialized, THE Fusion_Engine SHALL read the current `NavState` from the filter each time a GPS fix arrives (at the 1–10 Hz GPS capture rate) and produce a fused output for downstream consumption.
4. IF the IMU stream stops delivering samples for more than 200 ms, THEN THE Fusion_Engine SHALL transition to GPS-only mode by passing GPS fixes directly to the persistence layer without filter processing and updating the Fusion_Provider status to `fallback`.
5. WHEN the IMU stream resumes after a gap exceeding 500 ms, THE Fusion_Engine SHALL reinitialize the filter by calling `initWithGps` with the next valid GPS fix (accuracy ≤ 50 m) and setting initial roll and pitch to zero (level assumption), then resume normal fusion processing.
6. IF the IMU stream resumes after a gap of 200 ms to 500 ms (inclusive), THEN THE Fusion_Engine SHALL reinitialize the filter with the next valid GPS fix (accuracy ≤ 50 m) and the last known roll and pitch values, then resume normal fusion processing.

### Requirement 4: Fused Output to GpsSample Format

**User Story:** As a developer, I want the fused navigation output to be converted to the existing GpsSample format, so that all downstream consumers (lap detection, track discovery, analytics, export) work without modification.

#### Acceptance Criteria

1. THE Fusion_Engine SHALL convert each `NavState` output to a `GpsSample` with: `latitude` from `NavState.latitude`, `longitude` from `NavState.longitude`, `altitude` from `NavState.altitude`, `speed` from `NavState.groundSpeed`, `heading` from `NavState.bearingDeg` (clamped to 0–360 degrees), and `timestamp` set to the Unix epoch milliseconds of the GPS fix that triggered the filter update producing this NavState.
2. THE Fusion_Engine SHALL set `GpsSample.accuracy` to the GPS-reported horizontal accuracy value (in metres) from the most recent GPS fix used in the filter update.
3. IF the GPS-reported accuracy exceeds 50 metres, THEN THE Fusion_Engine SHALL set `GpsSample.isLowAccuracy` to true; otherwise it SHALL set `GpsSample.isLowAccuracy` to false.
4. WHEN the Fusion_Engine produces a fused GpsSample, THE Recording_Engine SHALL persist the fused sample using the same `GpsSampleRepository.batchInsert` mechanism used for raw GPS samples, associated with the current session ID.
5. THE Fusion_Engine SHALL produce exactly one fused GpsSample for each GPS fix received while the filter is in the active state, maintaining a 1:1 correspondence between incoming GPS fixes and output samples.
6. IF the NavState produces a latitude outside the range −90 to 90 degrees or a longitude outside the range −180 to 180 degrees, THEN THE Fusion_Engine SHALL discard that sample and not emit a GpsSample for that filter cycle.

### Requirement 5: Riverpod State Management Integration

**User Story:** As a developer, I want the sensor fusion state exposed through Riverpod providers, so that the UI and other features can reactively consume fused telemetry data.

#### Acceptance Criteria

1. THE Fusion_Provider SHALL expose the current fusion status as one of: `uninitialized`, `aligning`, `initialized`, `active`, `fallback`, or `error`, and WHEN the status is `error`, THE Fusion_Provider SHALL expose an accompanying error message indicating the failure reason.
2. WHILE the fusion status is `active` or `fallback`, THE Fusion_Provider SHALL expose a stream of fused `RecordingUpdate` objects (containing speed, elapsed time, GPS status, and sample count) at 1 Hz for UI consumption.
3. WHEN the fusion status changes, THE Fusion_Provider SHALL notify all listeners within one frame (16 ms).
4. WHILE the fusion status is `active` or `fallback`, THE Fusion_Provider SHALL expose the current `NavState` for consumers that need raw EKF output (attitude, biases, ENU position). IF the fusion status is `uninitialized`, `aligning`, or `initialized`, THEN THE Fusion_Provider SHALL expose a null `NavState` value.
5. WHEN the recording session stops, THE Fusion_Provider SHALL reset to the `uninitialized` status and release all stream subscriptions within 200 ms.

### Requirement 6: Recording Engine Integration

**User Story:** As a developer, I want the recording engine to use fused telemetry when available while preserving the existing GPS-only path as a fallback, so that the app remains functional on devices without IMU sensors.

#### Acceptance Criteria

1. WHEN a recording session starts and the IMU_Service reports sensor availability, THE Recording_Engine SHALL delegate position processing to the Fusion_Engine instead of directly persisting raw GPS samples.
2. WHEN a recording session starts and the IMU_Service reports sensor unavailability, THE Recording_Engine SHALL operate in GPS-only mode using the existing `DefaultGpsService` pipeline without modification.
3. WHILE the Fusion_Engine is in fallback mode (IMU unavailable or stream interrupted), THE Recording_Engine SHALL persist raw GPS samples directly, identical to the current GPS-only behavior.
4. THE Recording_Engine SHALL continue to emit `RecordingUpdate` objects (containing currentSpeedKmh derived from the active mode's latest sample, elapsed time, gpsStatus, and sampleCount) at 1 Hz regardless of whether fusion or GPS-only mode is active.
5. WHEN the recording session stops, THE Recording_Engine SHALL ensure all buffered fused samples are persisted within 500 ms before finalizing the session.
6. WHEN the Fusion_Engine transitions from active mode to fallback mode during a recording session, THE Recording_Engine SHALL begin persisting raw GPS samples starting from the next GPS fix received, with no duplicate or dropped samples at the transition boundary.
7. WHEN the Fusion_Engine transitions from fallback mode back to active mode during a recording session, THE Recording_Engine SHALL resume delegating position processing to the Fusion_Engine starting from the next fused output, with no duplicate or dropped samples at the transition boundary.

### Requirement 7: Package Dependency and Platform Configuration

**User Story:** As a developer, I want the `sensors_plus` package properly integrated into the project, so that IMU hardware access works reliably on iOS.

#### Acceptance Criteria

1. THE Application SHALL include the `sensors_plus` package as a dependency in `pubspec.yaml` with an exact version pin (e.g., `sensors_plus: 6.1.1`) compatible with the project's `sdk: ^3.12.0` environment constraint.
2. THE Application SHALL configure the iOS `Info.plist` with the `NSMotionUsageDescription` key containing a non-empty string (10–150 characters) that describes the purpose of motion data collection for telemetry recording.
3. IF the user denies motion sensor permission on iOS when the IMU_Service attempts to start streaming, THEN THE IMU_Service SHALL report a sensor unavailability error to the Fusion_Engine within 500 ms of the denial.
4. WHILE the app is in the background during an active recording session, THE IMU_Service SHALL continue delivering IMU samples to the Fusion_Engine at the target rate without interruption, consistent with the existing background location mode configured via `UIBackgroundModes`.
5. IF motion sensor permission is revoked while a recording session is active, THEN THE IMU_Service SHALL report a sensor unavailability error to the Fusion_Engine within 500 ms, causing the Fusion_Engine to transition to GPS-only fallback mode.

### Requirement 8: High-Accuracy GPS Configuration

**User Story:** As a motorsport driver, I want the GPS receiver configured for maximum navigation accuracy on both iOS and Android, so that the Kalman filter receives the best possible GPS measurements for fusion.

#### Acceptance Criteria

1. WHEN a recording session starts on iOS, THE GPS_Service SHALL configure `CLLocationManager` with `desiredAccuracy` set to `kCLLocationAccuracyBestForNavigation` and request location updates at a minimum rate of 10 Hz.
2. WHEN a recording session starts on Android, THE GPS_Service SHALL configure `LocationManager` with `PRIORITY_HIGH_ACCURACY` and a fastest update interval of 100 ms to enable GPS, Wi-Fi, and cell-tower triangulation.
3. WHEN a recording session starts, THE GPS_Service SHALL set `distanceFilter` to zero (iOS) and `smallestDisplacement` to zero (Android) so that all position updates are delivered regardless of movement distance.
4. WHEN a recording session starts on iOS, THE GPS_Service SHALL configure `activityType` to `CLActivityType.automotiveNavigation` to hint the system for motorsport-appropriate filtering and power management.
5. WHEN the recording session stops, THE GPS_Service SHALL revert location manager settings to system defaults (`kCLLocationAccuracyBest` on iOS, `PRIORITY_BALANCED_POWER_ACCURACY` on Android) and stop requesting continuous location updates within 500 ms.
6. IF the GPS_Service fails to obtain location permission or the device lacks GPS hardware, THEN THE GPS_Service SHALL report a GPS unavailability error to the Fusion_Engine before the recording session begins.

### Requirement 9: Performance and Resource Management

**User Story:** As a motorsport driver, I want the sensor fusion to run efficiently without draining my battery or causing UI jank, so that I can record full sessions without issues.

#### Acceptance Criteria

1. THE Fusion_Engine SHALL process each IMU prediction (at 100 Hz) within 2 ms wall-clock time on iPhone 12 or newer hardware, ensuring no UI frame drops attributable to filter computation.
2. WHILE a recording session is active, THE IMU_Service SHALL maintain a steady sample delivery rate with jitter below 5 ms between consecutive samples under normal operating conditions.
3. WHEN a recording session stops, THE Fusion_Engine SHALL release all sensor subscriptions, timers, and filter state within 200 ms.
4. THE Fusion_Engine SHALL not allocate persistent heap objects on each IMU prediction call beyond the `ImuData` input (reuse internal matrix buffers where possible within the DeadReckoningFilter).
5. WHILE a recording session is active, THE Fusion_Engine SHALL not increase resident memory usage by more than 5 MB above the baseline GPS-only recording memory footprint.
