# Tasks: iOS Navigation & Recording Bugfix

## Overview

Fix three related bugs: no back navigation from sub-pages, Start Session button not working due to ReceivePort stream cancellation, and GPS Idle indicator stuck.

## Tasks

- [x] 1. Fix navigation from Home screen to use push instead of go
  - Replace `context.go('/recording')` with `context.push('/recording')` in `lib/screens/home_screen.dart`
  - Replace `context.go('/sessions')` with `context.push('/sessions')` in `lib/screens/home_screen.dart`
  - Replace `context.go('/tracks')` with `context.push('/tracks')` in `lib/screens/home_screen.dart`
  - Replace `context.go('/settings')` with `context.push('/settings')` in `lib/screens/home_screen.dart`
  - Keep `context.go()` in recording_screen.dart for post-session navigation to summary (intentional stack replacement)
  - Verify the app compiles without errors
  - _Validates: Bugfix 2.1, Regression 3.1, 3.5_

- [x] 2. Fix GPS isolate ReceivePort to support subsequent listeners
  - [x] 2.1 Update `spawnGpsIsolate()` in `lib/engines/recording/gps_isolate.dart` to use a broadcast StreamController relay instead of cancelling the subscription
    - Create a `StreamController<dynamic>.broadcast()` that relays messages from the ReceivePort
    - Set up a single permanent listener on the ReceivePort that forwards to the StreamController
    - Extract the SendPort from the broadcast stream's first message
    - Update the return type to include the broadcast `Stream<dynamic>` instead of the raw ReceivePort
    - _Validates: Bugfix 2.2, Regression 3.2, 3.4_

  - [x] 2.2 Update `GpsService` interface and `DefaultGpsService` to match the new return type
    - Update `lib/engines/recording/gps_service.dart` abstract method signature to return the broadcast stream
    - Update `lib/engines/recording/default_gps_service.dart` to match
    - _Validates: Bugfix 2.2_

  - [x] 2.3 Update `RecordingEngine` to use the broadcast stream for isolate messages
    - In `lib/engines/recording/recording_engine.dart`, update `startSession()` to listen on the broadcast stream instead of the raw ReceivePort
    - Update `stopSession()` cleanup to close the StreamController if needed
    - Ensure the recording engine properly receives `GpsSampleBatch` and `RecordingError` messages
    - _Validates: Bugfix 2.2, 2.3, Regression 3.3_

- [x] 3. Verify fixes compile and existing tests pass
  - Run `flutter analyze` to check for compile errors
  - Run `flutter test` to verify existing tests still pass
  - _Validates: Regression 3.1, 3.2, 3.3, 3.4, 3.5_

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1", "2.1"] },
    { "id": 1, "tasks": ["2.2"] },
    { "id": 2, "tasks": ["2.3"] },
    { "id": 3, "tasks": ["3"] }
  ]
}
```
