# Bugfix Requirements Document

## Introduction

The APXTracer Flutter app has three related bugs on iOS that prevent core functionality from working correctly. Navigation from the Home screen to sub-pages (Recording, Session History, Track Library, Settings) uses `context.go()` which replaces the navigation stack, preventing back navigation. Additionally, the GPS recording isolate's `spawnGpsIsolate()` function cancels the ReceivePort subscription after extracting the SendPort, which prevents the recording engine from receiving subsequent messages (GpsSampleBatch). This causes the "Start Session" button to appear non-functional and the GPS status indicator to remain stuck on "GPS Idle".

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN a user navigates from the Home screen to the Recording screen, Session History, Track Library, or Settings THEN the system replaces the entire navigation stack using `context.go()`, removing the Home page and preventing back navigation

1.2 WHEN a user taps "Start Session" on the Recording screen THEN the system spawns the GPS isolate and cancels the ReceivePort subscription after receiving the SendPort, making the ReceivePort unable to deliver subsequent GpsSampleBatch messages to the recording engine

1.3 WHEN a recording session is started THEN the system never receives GpsSampleBatch messages from the GPS isolate because the ReceivePort's single-subscription stream was cancelled in `spawnGpsIsolate()`, so the UI never transitions from "GPS Idle" to "GPS Active"

### Expected Behavior (Correct)

2.1 WHEN a user navigates from the Home screen to any sub-page (Recording, Sessions, Tracks, Settings) THEN the system SHALL use `context.push()` to add the destination to the navigation stack, preserving the back button and allowing the user to return to the Home screen

2.2 WHEN a user taps "Start Session" THEN the system SHALL spawn the GPS isolate and return a ReceivePort that can still receive subsequent messages (GpsSampleBatch, RecordingError) after the initial SendPort handshake completes

2.3 WHEN a recording session is active and the GPS isolate sends GpsSampleBatch messages THEN the system SHALL receive those messages via the recording engine's listener on the ReceivePort, updating the UI with live telemetry and transitioning the GPS status indicator to "GPS Active"

### Unchanged Behavior (Regression Prevention)

3.1 WHEN a user navigates from a sub-page to a deeper page (e.g., Session History to Session Detail, or Recording to Session Summary after stopping) THEN the system SHALL CONTINUE TO use `context.go()` for those transitions where stack replacement is intentional

3.2 WHEN the GPS isolate is spawned THEN the system SHALL CONTINUE TO correctly extract the isolate's SendPort from the first message on the ReceivePort before sending commands

3.3 WHEN a recording session is stopped THEN the system SHALL CONTINUE TO properly clean up the isolate, cancel subscriptions, close the ReceivePort, and persist all buffered samples

3.4 WHEN the recording engine sends a StartRecording command to the GPS isolate THEN the system SHALL CONTINUE TO begin GPS capture at the configured Hz rate

3.5 WHEN mouse/touch interactions occur on the Home screen buttons (Start Recording, Session History, Track Library) THEN the system SHALL CONTINUE TO trigger navigation as before
