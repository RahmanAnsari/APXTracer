# Requirements Document

## Introduction

APXTracer is a personal motorsport telemetry application for iOS and Android (Flutter/Dart) that records GPS telemetry during driving sessions and automatically generates track maps, lap timing, speed analytics, and session insights. The application targets karting drivers, amateur racers, and motorsport enthusiasts who want telemetry without dedicated hardware. All data is stored locally on-device using sqflite. All telemetry remains private to the user with no community features in V1.

## Glossary

- **APXTracer**: The mobile telemetry application being specified
- **Session**: A continuous recording period from start to stop during a driving activity
- **GPS_Sample**: A single telemetry data point containing timestamp, coordinates, and optional motion data
- **Track**: A geographic circuit layout auto-generated from GPS path data representing a closed driving loop
- **Lap**: A single completed circuit of a Track within a Session
- **Lap_Time**: The elapsed duration in milliseconds for completing one Lap
- **Track_Library**: The user's collection of auto-generated and named Tracks
- **Session_History**: The chronological list of all recorded Sessions
- **Recording_Engine**: The component responsible for capturing GPS samples during a Session
- **Analytics_Engine**: The component responsible for computing session metrics from raw GPS data
- **Track_Discovery_Engine**: The component responsible for detecting closed loops and generating Track geometry
- **Lap_Detection_Engine**: The component responsible for identifying individual Laps within a Session
- **Export_Engine**: The component responsible for generating CSV and JSON telemetry files

## Requirements

### Requirement 1: Session Recording

**User Story:** As a karting driver, I want to start and stop recording sessions with a single action, so that I can capture telemetry without distraction while driving.

#### Acceptance Criteria

1. WHEN the user taps the Start Session button, THE Recording_Engine SHALL begin capturing GPS_Samples within 1 second at a minimum rate of 1 sample per second
2. WHILE a Session is active, THE Recording_Engine SHALL store all GPS_Samples to the local database sequentially with zero sample loss
3. WHILE a Session is active, THE Recording_Engine SHALL continue recording without an internet connection
4. WHILE a Session is active, THE Recording_Engine SHALL operate without blocking the application UI thread
5. WHEN the user taps the Stop Session button, THE Recording_Engine SHALL finalize the Session within 3 seconds by persisting all captured GPS_Samples, session start time, session end time, and total duration to the local database
6. IF GPS signal is temporarily lost during a Session, THEN THE Recording_Engine SHALL resume capturing GPS_Samples when signal is restored without data loss for the periods where signal was available
7. WHILE a Session is active, THE APXTracer SHALL update the displayed GPS status, current speed, and elapsed time on the Recording screen at least once per second
8. IF the user taps the Start Session button and GPS permission has not been granted, THEN THE APXTracer SHALL display an error message indicating that location permission is required and SHALL NOT start a Session
9. WHILE a Session is active, THE APXTracer SHALL disable the Start Session button to prevent duplicate concurrent Sessions
10. IF the user taps the Start Session button and the device cannot acquire a GPS fix within 10 seconds, THEN THE APXTracer SHALL display an error message indicating that GPS signal is unavailable and SHALL NOT start a Session

### Requirement 2: GPS Data Collection

**User Story:** As a driver, I want accurate GPS telemetry captured during my sessions, so that I can analyze my driving performance.

#### Acceptance Criteria

1. THE Recording_Engine SHALL capture each GPS_Sample with a timestamp (Unix epoch in milliseconds), latitude, and longitude
2. THE Recording_Engine SHALL capture GPS_Samples at a rate of 10 Hz (10 samples per second) for motorsport-grade telemetry resolution
3. WHERE the device sensor provides altitude data, THE Recording_Engine SHALL include altitude in meters in the GPS_Sample
4. WHERE the device sensor provides speed data, THE Recording_Engine SHALL include speed in meters per second in the GPS_Sample
5. WHERE the device sensor provides heading data, THE Recording_Engine SHALL include heading in degrees (0-360) in the GPS_Sample
6. WHERE the device sensor provides accuracy data, THE Recording_Engine SHALL include horizontal accuracy in meters in the GPS_Sample
7. THE Recording_Engine SHALL store GPS_Samples in chronological order preserving the original timestamps
8. THE Recording_Engine SHALL persist every captured GPS_Sample to the local database with zero telemetry loss during a Session
9. IF the device sensor reports a GPS_Sample with an accuracy value exceeding 50 meters, THEN THE Recording_Engine SHALL flag that sample as low-accuracy but SHALL still persist it to the local database

### Requirement 3: Track Discovery

**User Story:** As a driver, I want the application to automatically generate a track map from my driving path, so that I can see the circuit layout without manual configuration.

#### Acceptance Criteria

1. WHEN a Session is stopped, THE Track_Discovery_Engine SHALL analyze the GPS path and detect a closed-loop circuit when the final GPS_Sample is within 50 meters of the first GPS_Sample
2. WHEN a closed loop is detected and the GPS path contains at least 20 GPS_Samples, THE Track_Discovery_Engine SHALL generate a Track geometry polyline from the GPS path
3. WHEN a new Track is generated and an existing Track in the Track_Library has a start/finish point within 50 meters, THE Track_Discovery_Engine SHALL associate the Session with the existing Track instead of creating a duplicate
4. WHEN a new Track is generated and no matching Track exists in the Track_Library, THE Track_Discovery_Engine SHALL store the Track in the user's Track_Library
5. IF no closed loop is detected in the GPS path, THEN THE Track_Discovery_Engine SHALL store the Session without an associated Track

### Requirement 4: Lap Detection

**User Story:** As a racer, I want automatic lap detection and timing, so that I can compare my performance across laps without manual timing.

#### Acceptance Criteria

1. WHEN a Session contains a detected Track with a closed loop, THE Lap_Detection_Engine SHALL define the start/finish line as the point where the GPS path first crosses the detected closed loop boundary
2. WHEN a Session contains a detected Track with a closed loop, THE Lap_Detection_Engine SHALL identify individual Laps by detecting crossings of the start/finish line within a tolerance radius of 15 meters to account for GPS inaccuracy
3. WHEN Laps are detected, THE Lap_Detection_Engine SHALL assign sequential lap numbers starting from 1, excluding any incomplete partial lap before the first full crossing and after the last full crossing
4. WHEN Laps are detected, THE Lap_Detection_Engine SHALL calculate the Lap_Time in milliseconds for each Lap using the GPS timestamps of consecutive start/finish line crossings
5. IF a detected crossing produces a Lap_Time of less than 10 seconds, THEN THE Lap_Detection_Engine SHALL discard that crossing as a false detection caused by GPS noise
6. WHEN Laps are detected, THE Lap_Detection_Engine SHALL identify the Lap with the shortest Lap_Time as the best lap

### Requirement 5: Sector Splitting and Analysis

**User Story:** As a racer, I want the track automatically split into 3 sectors after discovery, so that I can analyze my performance at a sector level and identify where I'm gaining or losing time.

#### Acceptance Criteria

1. WHEN a Track is discovered and stored in the Track_Library, THE Track_Discovery_Engine SHALL automatically divide the Track into 3 sectors by placing sector boundaries at exactly 1/3 and 2/3 of the total track polyline distance, measured along the polyline from the start/finish point
2. WHEN sectors are defined for a Track, THE Lap_Detection_Engine SHALL calculate sector times in milliseconds for each sector within each detected Lap by detecting the GPS path crossing each sector boundary using linear interpolation between consecutive GPS_Samples that straddle the boundary point
3. WHEN sector times are calculated, THE Analytics_Engine SHALL identify the best sector time for each sector as the shortest sector time recorded across all Laps in the Session
4. WHEN analytics computation completes, THE APXTracer SHALL display sector times for each Lap in the Session Detail screen formatted as minutes, seconds, and milliseconds, and SHALL visually indicate the best sector time for each sector
5. THE Analytics_Engine SHALL compute all sector metrics from locally stored data without requiring an internet connection
6. IF the Lap_Detection_Engine cannot determine a sector crossing for a given sector within a Lap due to GPS signal loss or insufficient GPS_Samples in that segment, THEN THE Lap_Detection_Engine SHALL mark that sector time as unavailable for that Lap and SHALL exclude it from best sector time comparison

### Requirement 6: Session Analytics

**User Story:** As a driver, I want to see performance metrics immediately after a session, so that I can understand my driving without manual calculations.

#### Acceptance Criteria

1. WHEN a Session is stopped and processing completes, THE Analytics_Engine SHALL calculate session duration in seconds, distance travelled in kilometres to two decimal places, total laps completed, best lap time in milliseconds, and average lap time in milliseconds
2. WHEN a Session is stopped and processing completes, THE Analytics_Engine SHALL calculate average speed in km/h and maximum speed in km/h, each to one decimal place
3. WHEN a Session is stopped and processing completes, THE Analytics_Engine SHALL generate a speed trace as a time-series of speed values in km/h, one entry per GPS_Sample
4. WHEN a Session is stopped and processing completes, THE Analytics_Engine SHALL generate a racing line visualization by rendering the GPS path as a polyline on a map
5. WHEN analytics computation completes, THE APXTracer SHALL display the Session Summary screen with all computed metrics within 2 seconds of computation finishing
6. IF a Session contains zero detected Laps, THEN THE Analytics_Engine SHALL report total laps as zero and omit best lap time and average lap time from the Session Summary
7. THE Analytics_Engine SHALL compute all metrics from locally stored data without requiring an internet connection

### Requirement 7: Track Library

**User Story:** As a regular driver, I want to manage my collection of tracks, so that I can organize and revisit circuits I have driven.

#### Acceptance Criteria

1. THE APXTracer SHALL display all auto-generated Tracks in the Track_Library screen ordered by last driven date descending
2. WHEN the user edits a Track name, THE APXTracer SHALL accept a name between 1 and 50 characters and persist the updated name to the local database
3. IF the user submits an empty Track name or a name exceeding 50 characters, THEN THE APXTracer SHALL reject the edit, retain the previous name, and display a validation error message indicating the allowed length
4. THE APXTracer SHALL display the session count and last driven date for each Track in the Track_Library
5. THE APXTracer SHALL keep all Tracks private and stored locally on the device

### Requirement 8: Session History

**User Story:** As a driver, I want to browse my past sessions with key metrics, so that I can track my progress over time.

#### Acceptance Criteria

1. THE APXTracer SHALL display all recorded Sessions in the Session_History screen in reverse chronological order, showing the most recent Session first
2. THE APXTracer SHALL display date, duration (in minutes and seconds), best lap time (in minutes, seconds, and milliseconds), total laps, distance (in kilometres to one decimal place), and top speed (in km/h to one decimal place) for each Session in the Session_History
3. THE APXTracer SHALL make Session_History available offline from locally stored data
4. WHEN the user selects a Session from Session_History, THE APXTracer SHALL display the Session Detail screen with track visualization, speed graph, lap list, and export option
5. IF a Session has no detected Track or Laps, THEN THE APXTracer SHALL display the Session Detail screen with the GPS path visualization and speed graph, and shall indicate that no laps were detected in place of the lap list
6. IF no recorded Sessions exist, THEN THE APXTracer SHALL display an empty state message on the Session_History screen indicating that no sessions have been recorded

### Requirement 9: Telemetry Export

**User Story:** As a data-oriented driver, I want to export my raw telemetry data to Google Drive or share it locally, so that I can perform custom analysis in external tools and back up my data.

#### Acceptance Criteria

1. WHEN the user requests a CSV export for a Session, THE Export_Engine SHALL generate a CSV file with a header row of "timestamp,latitude,longitude,speed" followed by one data row per GPS_Sample in chronological order
2. WHEN the user requests a JSON export for a Session, THE Export_Engine SHALL generate a JSON file with a root object containing a "samples" array where each element represents one GPS_Sample with its timestamp, latitude, longitude, and speed fields in chronological order
3. THE Export_Engine SHALL make export functionality available for every recorded Session that contains at least one GPS_Sample
4. THE Export_Engine SHALL generate export files from locally stored data without requiring an internet connection
5. WHEN the user selects the export option, THE APXTracer SHALL present export destination choices including Google Drive and the platform share sheet
6. WHEN the user selects Google Drive as the export destination, THE Export_Engine SHALL authenticate with the user's Google account and upload the generated file to the user's Google Drive
7. IF Google Drive authentication fails or upload fails, THEN THE Export_Engine SHALL display an error message indicating the failure reason and offer the platform share sheet as a fallback
8. IF the Export_Engine fails to generate an export file due to insufficient storage or a data read error, THEN THE Export_Engine SHALL display an error message indicating the failure reason without losing the original Session data

### Requirement 10: Data Privacy and Security

**User Story:** As a privacy-conscious user, I want my telemetry data to remain private and secure, so that no unauthorized party can access my driving data.

#### Acceptance Criteria

1. THE APXTracer SHALL store all local telemetry data in encrypted storage on the device such that telemetry data is not readable by other applications or by accessing the device filesystem without user authentication
2. THE APXTracer SHALL not expose any telemetry data to other users or public endpoints
3. WHEN the user requests deletion of their data, THE APXTracer SHALL remove all telemetry data from local storage within a single operation

### Requirement 11: Local-Only Operation

**User Story:** As a driver, I want all application functionality to work entirely on-device without requiring internet, so that I can record and review sessions anywhere.

#### Acceptance Criteria

1. THE APXTracer SHALL provide full Session recording functionality without an internet connection
2. THE APXTracer SHALL provide full Session analytics and visualization without an internet connection
3. THE APXTracer SHALL provide full Session_History browsing without an internet connection
4. THE APXTracer SHALL provide full telemetry export functionality without an internet connection
5. THE APXTracer SHALL not require any network connectivity for any core functionality

### Requirement 12: Performance and Battery

**User Story:** As a karting driver, I want the application to perform efficiently during long sessions, so that recording does not drain my battery or degrade the experience.

#### Acceptance Criteria

1. WHILE a Session is active, THE Recording_Engine SHALL capture GPS_Samples on a background isolate while maintaining UI frame rendering at a minimum of 60 frames per second and responding to user input within 16 milliseconds
2. THE APXTracer SHALL support continuous Session recording for a minimum duration of 60 minutes without memory growth exceeding 50 MB above the baseline at Session start, without frame rate dropping below 60 frames per second, and without application crash or forced restart
3. THE Recording_Engine SHALL persist every captured GPS_Sample to the local database with zero telemetry loss for the entire duration of a Session
4. WHILE a Session is active, THE APXTracer SHALL consume no more than 15% of total device battery capacity per 60 minutes of continuous recording
5. IF available device memory falls below 50 MB during a Session, THEN THE Recording_Engine SHALL continue persisting GPS_Samples to the local database without data loss and SHALL display a warning indicating low memory to the user
