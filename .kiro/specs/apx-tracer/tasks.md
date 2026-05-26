# Implementation Plan: APXTracer

## Overview

This plan implements APXTracer as a Flutter/Dart application with local-only GPS telemetry recording, automatic track discovery, lap detection, sector analysis, session analytics, and export capabilities. The implementation follows a bottom-up approach: data layer first, then engines, then state management, then UI, and finally integration wiring.

## Tasks

- [x] 1. Set up project structure, dependencies, and data layer
  - [x] 1.1 Configure project dependencies and directory structure
    - Add dependencies to `pubspec.yaml`: `sqflite_sqlcipher`, `flutter_secure_storage`, `geolocator`, `riverpod`/`flutter_riverpod`, `go_router`, `flutter_map`, `fl_chart`, `google_sign_in`, `googleapis`, `share_plus`, `uuid`, `path_provider`
    - Add dev dependencies: `flutter_test`, `mockito`, `build_runner`, `mocktail`
    - Create directory structure: `lib/engines/`, `lib/data/`, `lib/models/`, `lib/providers/`, `lib/screens/`, `lib/services/`, `lib/utils/`, `test/engines/`, `test/data/`, `test/providers/`, `test/services/`, `test/utils/`, `test/integration/`
    - _Requirements: 11.1, 11.5, 10.1_

  - [x] 1.2 Implement data models (Dart classes)
    - Create `lib/models/gps_sample.dart` with `GpsSample` class including all fields (timestamp, latitude, longitude, altitude, speed, heading, accuracy, isLowAccuracy)
    - Create `lib/models/session.dart` with `Session` class
    - Create `lib/models/track.dart` with `Track` class including polyline, sector fractions, and start/finish point
    - Create `lib/models/lap.dart` with `Lap` class including sector times and isBestLap flag
    - Create `lib/models/session_analytics.dart` with `SessionAnalytics` class
    - Add `toMap()` and `fromMap()` factory constructors for database serialization on each model
    - _Requirements: 2.1, 2.3, 2.4, 2.5, 2.6, 4.3, 4.4, 5.1, 6.1_

  - [x] 1.3 Implement database helper with encrypted storage
    - Create `lib/data/database_helper.dart` with SQLCipher-encrypted sqflite initialization
    - Use `flutter_secure_storage` to store/retrieve the encryption key
    - Implement `CREATE TABLE` statements for `sessions`, `gps_samples`, `tracks`, `laps`, `session_analytics` with indexes
    - Implement database migration strategy for future schema changes
    - _Requirements: 10.1, 10.2, 11.5_

  - [x] 1.4 Implement repository classes
    - Create `lib/data/session_repository.dart` with CRUD operations for sessions (insert, getById, getAll ordered by start_time DESC, delete)
    - Create `lib/data/gps_sample_repository.dart` with batch insert, getBySessionId (ordered by timestamp), count operations
    - Create `lib/data/track_repository.dart` with CRUD, findNearby (Haversine within 50m), getAll ordered by last_driven DESC
    - Create `lib/data/lap_repository.dart` with insert, getBySessionId, delete operations
    - Create `lib/data/analytics_repository.dart` with insert, getBySessionId, delete operations
    - All repositories use transactions for atomic writes
    - _Requirements: 1.2, 1.5, 2.7, 2.8, 3.3, 3.4, 7.1, 8.1, 10.3_

  - [x] 1.5 Write unit tests for data models and repositories
    - Test `toMap()`/`fromMap()` round-trip for all models
    - Test repository CRUD operations with mocked database
    - Test batch insert preserves order and count
    - Test transaction rollback on failure
    - Test track ordering by last_driven descending
    - Test session ordering by start_time descending
    - _Requirements: 2.1, 2.7, 7.1, 8.1_

- [x] 2. Implement utility functions
  - [x] 2.1 Implement Haversine distance calculation
    - Create `lib/utils/haversine.dart` with `double haversineDistance(double lat1, double lng1, double lat2, double lng2)` returning meters
    - _Requirements: 3.1, 3.3, 6.1_

  - [x] 2.2 Implement polyline utilities
    - Create `lib/utils/polyline_utils.dart` with:
      - `double polylineLength(List<LatLng> points)` — total distance along polyline
      - `LatLng pointAtFraction(List<LatLng> points, double fraction)` — interpolated point at given fraction of total length
      - `double fractionAtPoint(List<LatLng> points, LatLng point)` — find closest fraction for a point
    - _Requirements: 5.1, 5.2_

  - [x] 2.3 Implement time and speed formatting utilities
    - Create `lib/utils/time_formatter.dart` with formatLapTime (mm:ss.SSS), formatDuration (mm:ss), formatSpeed (km/h)
    - Create `lib/utils/speed_converter.dart` with m/s to km/h conversion
    - _Requirements: 5.4, 6.1, 6.2, 8.2_

  - [x] 2.4 Write unit tests for utility functions
    - Test Haversine with known coordinate pairs
    - Test polyline length calculation
    - Test point interpolation at 0, 0.333, 0.666, 1.0 fractions
    - Test time formatting edge cases (zero, large values)
    - Test speed conversion accuracy
    - _Requirements: 3.1, 5.1, 6.1, 6.2_

- [x] 3. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Implement Recording Engine
  - [x] 4.1 Implement GPS isolate communication layer
    - Create `lib/engines/recording/recording_messages.dart` with sealed class hierarchy: `StartRecording`, `StopRecording`, `GpsSampleBatch`, `RecordingError`
    - Create `lib/engines/recording/gps_isolate.dart` with the isolate entry point that initializes Geolocator at 10 Hz and sends `GpsSampleBatch` messages via `SendPort`
    - Handle GPS permission checks and fix timeout (10s) before spawning isolate
    - _Requirements: 1.1, 1.4, 2.2, 12.1_

  - [x] 4.2 Implement Recording Engine main class
    - Create `lib/engines/recording/recording_engine.dart` implementing `IRecordingEngine`
    - Implement `startSession()`: check permissions, acquire GPS fix (10s timeout), spawn isolate, create session record in DB, return session ID
    - Implement `stopSession()`: send stop signal to isolate, await final batch, persist session metadata (end_time, duration_ms), return finalized Session
    - Implement `updates` stream: emit `RecordingUpdate` at 1 Hz with current speed, elapsed time, GPS status, sample count
    - Implement batch persistence: buffer samples and write to DB in batches for efficiency
    - Prevent duplicate concurrent sessions via `isRecording` guard
    - Handle signal loss: mark gap, resume on restore without data loss
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 2.8, 12.3_

  - [x] 4.3 Write unit tests for Recording Engine
    - Test startSession returns session ID within expected time (mock Geolocator)
    - Test GPS samples stored sequentially with zero loss (mock stream + DB)
    - Test recording continues without internet (mock offline connectivity)
    - Test stopSession persists all data (mock DB transaction)
    - Test signal loss resumes without data loss (mock Geolocator with gap)
    - Test UI updates stream at 1 Hz minimum
    - Test permission denied throws GpsPermissionDeniedException
    - Test prevents duplicate concurrent sessions
    - Test GPS fix timeout after 10s throws GpsFixTimeoutException
    - Test captures at 10 Hz rate
    - Test low-accuracy flagged when accuracy > 50m
    - Test low-accuracy sample still persisted
    - _Requirements: 1.1, 1.2, 1.3, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 2.2, 2.8, 2.9_

- [x] 5. Implement Track Discovery Engine
  - [x] 5.1 Implement closed-loop detection and track matching
    - Create `lib/engines/track_discovery/track_discovery_engine.dart` implementing `ITrackDiscoveryEngine`
    - Implement `discoverTrack()`:
      - Calculate Haversine distance between first and last GPS sample
      - If distance ≤ 50m AND sample count ≥ 20, detect closed loop
      - Generate track polyline from GPS path
      - Query existing tracks for match within 50m of start/finish
      - If match found, associate session with existing track and increment session_count
      - If no match, create new track in Track_Library
      - If no closed loop, return null (session stored without track)
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [x] 5.2 Implement sector splitting
    - Implement `computeSectors()` in track discovery engine:
      - Calculate total polyline length
      - Place sector boundaries at 1/3 and 2/3 cumulative distance
      - Return `SectorBoundary` objects with polyline fraction and interpolated LatLng point
    - _Requirements: 5.1_

  - [x] 5.3 Write unit tests for Track Discovery Engine
    - Test detects closed loop when last sample within 50m of first
    - Test no detection when distance > 50m
    - Test no detection when < 20 samples
    - Test generates polyline from GPS path
    - Test matches existing track within 50m
    - Test creates new track when no match exists
    - Test session stored without track when no loop
    - Test sectors placed at 1/3 and 2/3 distance
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 5.1_

- [x] 6. Implement Lap Detection Engine
  - [x] 6.1 Implement start/finish crossing detection and sector time calculation
    - Create `lib/engines/lap_detection/lap_detection_engine.dart` implementing `ILapDetectionEngine`
    - Implement `detectLaps()`:
      - Find GPS samples within 15m tolerance of start/finish point
      - Detect crossings using closest-approach method between consecutive samples
      - Filter false detections: discard laps with time < 10 seconds
      - Assign sequential lap numbers starting from 1
      - Exclude incomplete partial laps (before first full crossing, after last)
      - Identify best lap (minimum lap time)
    - Implement `computeSectorTimes()`:
      - For each lap, find GPS samples that straddle each sector boundary
      - Use linear interpolation to compute exact crossing timestamp
      - Return null for sectors where no straddling pair exists (GPS gap)
      - Identify best sector times (minimum non-null per sector)
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 5.2, 5.3, 5.6_

  - [x] 6.2 Write unit tests for Lap Detection Engine
    - Test detects crossings within 15m of start/finish
    - Test assigns sequential lap numbers from 1
    - Test calculates lap time as timestamp difference
    - Test discards laps < 10 seconds
    - Test identifies best lap (minimum time)
    - Test excludes incomplete partial laps
    - Test sector times via linear interpolation
    - Test sector time null when no straddling pair
    - Test best sector time is minimum non-null
    - _Requirements: 4.2, 4.3, 4.4, 4.5, 4.6, 5.2, 5.3, 5.6_

- [x] 7. Implement Analytics Engine
  - [x] 7.1 Implement session analytics computation
    - Create `lib/engines/analytics/analytics_engine.dart` implementing `IAnalyticsEngine`
    - Implement `computeAnalytics()`:
      - Duration: (endTime - startTime) / 1000 in seconds
      - Distance: sum of Haversine distances between consecutive samples, converted to km (2 decimal places)
      - Total laps: count of detected laps
      - Best lap time: minimum lap_time_ms (null if no laps)
      - Average lap time: mean of all lap_time_ms (null if no laps)
      - Average speed: distance / duration in km/h (1 decimal place)
      - Max speed: maximum sample speed converted to km/h (1 decimal place)
      - Speed trace: list of speed values in km/h, one per sample
      - Best sector times: minimum non-null sector time per sector
    - Persist computed analytics to `session_analytics` table
    - _Requirements: 6.1, 6.2, 6.3, 6.6, 6.7_

  - [x] 7.2 Write unit tests for Analytics Engine
    - Test calculates duration correctly
    - Test distance via Haversine sum (2 decimal km)
    - Test total laps from detected laps
    - Test best lap time is minimum
    - Test average lap time computed correctly
    - Test average speed = distance / duration (1 decimal)
    - Test max speed = max sample speed in km/h
    - Test speed trace has one entry per sample
    - Test zero laps: total=0, best/avg omitted (null)
    - Test all computation works without internet (mocked offline)
    - _Requirements: 6.1, 6.2, 6.3, 6.6, 6.7_

- [x] 8. Checkpoint - Ensure all engine tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Implement Export Engine and Google Drive Service
  - [x] 9.1 Implement CSV and JSON export generation
    - Create `lib/engines/export/export_engine.dart` implementing `IExportEngine`
    - Implement `exportCsv()`: generate CSV with header "timestamp,latitude,longitude,speed" and one row per sample in chronological order, write to temp file, return path
    - Implement `exportJson()`: generate JSON with root object containing "samples" array, each element with timestamp, latitude, longitude, speed fields in chronological order, write to temp file, return path
    - Implement `shareFile()`: use `share_plus` to present platform share sheet
    - Disable export for sessions with 0 samples
    - Handle insufficient storage and data read errors gracefully
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.8_

  - [x] 9.2 Implement Google Drive service
    - Create `lib/services/google_drive_service.dart` implementing `IGoogleDriveService`
    - Implement `authenticate()`: use `google_sign_in` for OAuth, request Drive file scope
    - Implement `uploadFile()`: use `googleapis` Drive API to upload file, return file ID
    - Implement `isAuthenticated` getter
    - Implement `uploadToGoogleDrive()` in export engine: authenticate, upload, handle errors with fallback to share sheet
    - _Requirements: 9.5, 9.6, 9.7_

  - [x] 9.3 Write unit tests for Export Engine and Google Drive Service
    - Test CSV has correct header row
    - Test CSV rows match sample count and order
    - Test JSON has "samples" array with correct fields
    - Test JSON preserves chronological order
    - Test export available for sessions with ≥1 sample
    - Test export disabled for empty sessions
    - Test export works without internet
    - Test Google Drive auth success uploads file
    - Test Google Drive auth failure shows error + fallback
    - Test Google Drive upload failure shows error + fallback
    - Test insufficient storage shows error, preserves data
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.6, 9.7, 9.8_

- [x] 10. Implement post-session processing pipeline
  - [x] 10.1 Create post-session pipeline coordinator
    - Create `lib/engines/post_session_pipeline.dart` that orchestrates: Track Discovery → Lap Detection → Sector Times → Analytics
    - Accept session ID, load GPS samples from DB
    - Run track discovery; if track found, run lap detection and sector computation
    - Run analytics computation with all results
    - Persist all results (track, laps, analytics) atomically in a transaction
    - _Requirements: 1.5, 3.1, 4.1, 5.1, 6.1_

  - [x] 10.2 Write unit tests for post-session pipeline
    - Test full pipeline executes in correct order
    - Test pipeline handles no-track scenario (skips lap detection)
    - Test pipeline persists all results atomically
    - Test pipeline handles errors gracefully without data loss
    - _Requirements: 1.5, 3.5, 6.6_

- [x] 11. Implement Riverpod state management providers
  - [x] 11.1 Implement recording provider
    - Create `lib/providers/recording_provider.dart` with `StateNotifierProvider` or `AsyncNotifierProvider`
    - Expose: startSession(), stopSession(), recording state (idle/recording/processing), live updates stream
    - Wire to RecordingEngine and PostSessionPipeline
    - _Requirements: 1.1, 1.5, 1.7, 1.9_

  - [x] 11.2 Implement session and analytics providers
    - Create `lib/providers/session_provider.dart`: list all sessions (reverse chronological), get session detail with analytics
    - Create `lib/providers/analytics_provider.dart`: get analytics for a session, speed trace data
    - _Requirements: 6.5, 8.1, 8.2, 8.3_

  - [x] 11.3 Implement track provider
    - Create `lib/providers/track_provider.dart`: list all tracks (ordered by last_driven DESC), rename track, get track detail with sessions
    - Validate track name (1-50 chars), reject invalid names with error
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

  - [x] 11.4 Implement export provider
    - Create `lib/providers/export_provider.dart`: trigger CSV/JSON export, upload to Google Drive, share via platform sheet
    - Manage export state (idle/exporting/success/error)
    - _Requirements: 9.1, 9.2, 9.5, 9.6, 9.7_

  - [x] 11.5 Write unit tests for providers
    - Test recording provider state transitions (idle → recording → processing → idle)
    - Test session provider returns sessions in reverse chronological order
    - Test track provider validates name length (1-50 chars)
    - Test track provider rejects empty/too-long names
    - Test export provider handles success and error states
    - _Requirements: 1.1, 1.9, 7.2, 7.3, 8.1, 9.1_

- [x] 12. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 13. Implement UI screens and routing
  - [x] 13.1 Set up go_router and app shell
    - Create `lib/app.dart` with MaterialApp.router and GoRouter configuration
    - Define routes: `/` (Home), `/recording` (Recording), `/session/:id/summary` (Summary), `/sessions` (History), `/session/:id` (Detail), `/tracks` (Track Library), `/settings` (Settings)
    - Create `lib/screens/` directory with placeholder screen widgets
    - _Requirements: 8.4, 11.1_

  - [x] 13.2 Implement Home screen
    - Create `lib/screens/home_screen.dart` with dashboard layout
    - Display quick-start recording button (large, prominent)
    - Show recent session summary (last session metrics)
    - Navigation to Session History and Track Library
    - _Requirements: 1.1_

  - [x] 13.3 Implement Recording screen
    - Create `lib/screens/recording_screen.dart` with live telemetry display
    - Display: current speed (km/h), elapsed time, GPS status indicator, sample count
    - Start Session button: check permissions, handle errors (no permission, no GPS fix)
    - Stop Session button: finalize session, navigate to summary
    - Disable Start button while recording (prevent duplicates)
    - Update display at minimum 1 Hz from recording provider stream
    - _Requirements: 1.1, 1.7, 1.8, 1.9, 1.10_

  - [x] 13.4 Implement Session Summary screen
    - Create `lib/screens/session_summary_screen.dart`
    - Display: duration, distance (km), total laps, best lap time, average lap time, average speed, max speed
    - Display racing line on flutter_map (GPS path as polyline)
    - Display speed graph using fl_chart (speed trace over time)
    - Handle zero-laps case: show total=0, omit best/avg lap time
    - Show within 2 seconds of analytics computation completing
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_

  - [x] 13.5 Implement Session History screen
    - Create `lib/screens/session_history_screen.dart`
    - List all sessions in reverse chronological order
    - Display per session: date, duration (mm:ss), best lap time (mm:ss.SSS), total laps, distance (km, 1 decimal), top speed (km/h, 1 decimal)
    - Tap session → navigate to Session Detail
    - Empty state message when no sessions exist
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.6_

  - [x] 13.6 Implement Session Detail screen
    - Create `lib/screens/session_detail_screen.dart`
    - Display track visualization on flutter_map (GPS path polyline)
    - Display speed graph using fl_chart
    - Display lap list with lap number, lap time, sector times (formatted mm:ss.SSS)
    - Visually indicate best lap and best sector times
    - Export button → present export options (CSV/JSON, Google Drive, Share)
    - Handle no-track/no-laps case: show GPS path + "no laps detected" message
    - _Requirements: 5.4, 8.4, 8.5, 9.5_

  - [x] 13.7 Implement Track Library screen
    - Create `lib/screens/track_library_screen.dart`
    - List all tracks ordered by last driven date descending
    - Display per track: name (editable), session count, last driven date
    - Inline edit for track name with validation (1-50 chars)
    - Show validation error for empty or >50 char names
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

  - [x] 13.8 Implement Settings screen with data management
    - Create `lib/screens/settings_screen.dart`
    - Include "Delete All Data" option with confirmation dialog
    - Implement atomic deletion of all telemetry data (sessions, samples, tracks, laps, analytics)
    - _Requirements: 10.3_

- [x] 14. Wire everything together and final integration
  - [x] 14.1 Wire recording flow end-to-end
    - Connect Home → Recording screen → start/stop → post-session pipeline → Session Summary
    - Ensure GPS isolate spawns correctly and samples flow through to DB
    - Ensure post-session pipeline triggers automatically on stop
    - Ensure navigation to Session Summary after processing completes
    - _Requirements: 1.1, 1.5, 6.5_

  - [x] 14.2 Wire session browsing and detail flow
    - Connect Session History → Session Detail with full data loading
    - Connect Track Library → track detail with associated sessions
    - Ensure all data loads from local DB (offline-capable)
    - _Requirements: 8.3, 8.4, 11.1, 11.2, 11.3_

  - [x] 14.3 Wire export flow
    - Connect Session Detail export button → format selection → Google Drive or Share
    - Handle auth flow for Google Drive
    - Handle errors with fallback to share sheet
    - _Requirements: 9.5, 9.6, 9.7_

  - [x] 14.4 Write integration tests for recording flow
    - Test full session recording flow with mocked GPS
    - Test post-session pipeline produces correct track, laps, analytics
    - Test navigation flow from start to summary
    - _Requirements: 1.1, 1.5, 3.1, 4.1, 6.1_

- [x] 15. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- No property-based tests are used; all testing is mock-based with mockito/mocktail
- Unit tests validate specific examples and edge cases with mocked dependencies
- The Recording Engine uses a background Dart isolate for 10 Hz GPS capture without UI blocking
- All database operations use SQLCipher encryption via `sqflite_sqlcipher`
- The post-session pipeline (Track Discovery → Lap Detection → Analytics) runs automatically after session stop

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3"] },
    { "id": 2, "tasks": ["1.4", "2.1", "2.2", "2.3"] },
    { "id": 3, "tasks": ["1.5", "2.4"] },
    { "id": 4, "tasks": ["4.1", "5.1", "5.2"] },
    { "id": 5, "tasks": ["4.2", "6.1", "7.1"] },
    { "id": 6, "tasks": ["4.3", "5.3", "6.2", "7.2", "9.1"] },
    { "id": 7, "tasks": ["9.2", "9.3", "10.1"] },
    { "id": 8, "tasks": ["10.2", "11.1", "11.2", "11.3", "11.4"] },
    { "id": 9, "tasks": ["11.5", "13.1"] },
    { "id": 10, "tasks": ["13.2", "13.3", "13.4", "13.5", "13.6", "13.7", "13.8"] },
    { "id": 11, "tasks": ["14.1", "14.2", "14.3"] },
    { "id": 12, "tasks": ["14.4"] }
  ]
}
```
