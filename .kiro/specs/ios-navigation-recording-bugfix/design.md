# Design Document: iOS Navigation & Recording Bugfix

## Overview

This bugfix addresses three related issues in the APXTracer Flutter app on iOS:
1. No back navigation from sub-pages (Recording, Session History, Track Library, Settings)
2. Start Session button not working (GPS isolate ReceivePort issue)
3. GPS Idle indicator always showing "Idle" (consequence of #2)

## Root Cause Analysis

### Bug 1: Navigation Stack Replacement

**File**: `lib/screens/home_screen.dart`

The Home screen uses `context.go()` for all navigation to sub-pages. In go_router, `go()` replaces the entire navigation stack with the new route, meaning the Home page is removed from the stack. When the user arrives at the Recording screen (or any other sub-page), there is no previous route in the stack, so the system back button and AppBar back arrow have nowhere to navigate.

**Fix**: Replace `context.go()` with `context.push()` for navigation from Home to sub-pages. `push()` adds the destination on top of the current stack, preserving the back button. The `context.go()` call for navigating to Session Summary after stopping a recording should remain as `go()` since that's an intentional stack replacement (the user shouldn't go "back" to the recording screen after stopping).

### Bug 2: ReceivePort Single-Subscription Stream Cancelled

**File**: `lib/engines/recording/gps_isolate.dart` — `spawnGpsIsolate()` function

The `spawnGpsIsolate()` function:
1. Creates a `ReceivePort`
2. Spawns the isolate, passing the ReceivePort's SendPort
3. Sets up a `StreamSubscription` on the ReceivePort to listen for the isolate's SendPort (first message)
4. Awaits the SendPort via a `Completer`
5. **Cancels the subscription** with `await subscription.cancel()`
6. Returns the ReceivePort to the caller

The problem: `ReceivePort` is a **single-subscription stream**. Once you call `listen()` on it and then `cancel()` the subscription, you cannot call `listen()` again on the same ReceivePort. When the RecordingEngine later tries to set up its own listener (`_receivePort!.listen(_onIsolateMessage)`), it fails silently or throws because the stream has already been listened to and cancelled.

**Fix**: Instead of using a temporary subscription that gets cancelled, use a `StreamController` as a relay. The approach:
1. Create the ReceivePort
2. Set up a single permanent listener that forwards messages to a StreamController
3. Use a Completer to extract the first message (SendPort) 
4. Return both the ReceivePort and a way for the caller to receive subsequent messages

Alternative simpler fix: Don't cancel the subscription. Instead, restructure so the recording engine's message handler is passed into `spawnGpsIsolate()`, or return a broadcast stream that the caller can listen to.

**Chosen approach**: The simplest fix is to NOT set up a listener in `spawnGpsIsolate()` at all. Instead, use `receivePort.first` or a Completer with `receivePort.listen` but DON'T cancel it — instead, pause it and let the caller resume or re-listen. 

Actually, the cleanest fix: Use a `Completer` with the ReceivePort cast to a Stream, and use `await receivePort.first` to get the SendPort. But `ReceivePort.first` also cancels the subscription after receiving the first element.

**Final chosen approach**: Create a new ReceivePort specifically for the handshake, separate from the data ReceivePort. The isolate sends its SendPort to the handshake port, and then the recording engine listens on a separate data ReceivePort that the isolate uses for sending GpsSampleBatch messages. 

Actually, the simplest correct fix: Don't cancel the subscription. Instead, keep the subscription active and have it forward messages. The recording engine will set up its own handling by replacing the listener callback. We can achieve this by:
1. Listening on the ReceivePort with a handler that first completes the Completer (for the SendPort), then does nothing for subsequent messages
2. NOT cancelling the subscription
3. The caller (RecordingEngine) will cancel this subscription and set up its own

Wait — you CAN'T listen twice on a single-subscription stream. The correct fix is:

**Use a broadcast StreamController as a relay**:
```dart
final receivePort = ReceivePort();
final controller = StreamController<dynamic>.broadcast();
receivePort.listen(controller.add);
// Now use controller.stream which is broadcast and can be listened to multiple times
final commandPort = await controller.stream.first; // Gets SendPort
// Return controller.stream for the caller to listen to
```

This way the ReceivePort has exactly one listener (forwarding to the controller), and the caller gets a broadcast stream they can listen to freely.

### Bug 3: GPS Idle Indicator

This is a direct consequence of Bug 2. The `_GpsStatusIndicator` widget shows "GPS Idle" when `isRecording` is `false`. Since the recording never actually starts successfully (no GPS samples arrive, the engine may error out or the state never transitions), the indicator stays idle. Once Bug 2 is fixed, the recording will start, `RecordingUpdate` messages will flow, and the GPS status will transition to "active".

## Changes Required

### File 1: `lib/screens/home_screen.dart`

| Line | Current | Fixed |
|------|---------|-------|
| Navigation to recording | `context.go('/recording')` | `context.push('/recording')` |
| Navigation to sessions | `context.go('/sessions')` | `context.push('/sessions')` |
| Navigation to tracks | `context.go('/tracks')` | `context.push('/tracks')` |
| Navigation to settings | `context.go('/settings')` | `context.push('/settings')` |

### File 2: `lib/engines/recording/gps_isolate.dart`

Replace the `spawnGpsIsolate()` function's subscription handling:

**Before**:
```dart
final completer = Completer<SendPort>();
late final StreamSubscription subscription;
subscription = receivePort.listen((message) {
  if (message is SendPort && !completer.isCompleted) {
    completer.complete(message);
  }
});
final commandPort = await completer.future;
await subscription.cancel();
```

**After**:
```dart
final controller = StreamController<dynamic>.broadcast();
receivePort.listen(controller.add);
final commandPort = await controller.stream.first as SendPort;
```

And return the broadcast stream for the caller to use instead of the raw ReceivePort.

### File 3: `lib/engines/recording/recording_engine.dart`

Update `startSession()` to use the broadcast stream from the updated `spawnGpsIsolate()` return type.

### File 4: `lib/engines/recording/gps_service.dart`

Update the `spawnGpsIsolate()` return type to include the broadcast stream.

## Testing Strategy

1. **Navigation test**: Verify that after navigating from Home to Recording/Sessions/Tracks, `GoRouter.of(context).canPop()` returns `true`
2. **Recording engine test**: Verify that after `spawnGpsIsolate()` returns, the caller can listen on the returned stream and receive `GpsSampleBatch` messages sent by the isolate
3. **GPS status test**: Verify that when recording starts and samples arrive, the `RecordingUpdate.gpsStatus` transitions from `acquiring` to `active`
