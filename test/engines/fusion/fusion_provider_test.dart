import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apx_tracer/engines/fusion/fusion_engine.dart';
import 'package:apx_tracer/engines/kalman/kalman_models.dart';
import 'package:apx_tracer/engines/recording/recording_messages.dart';
import 'package:apx_tracer/providers/fusion_provider.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockFusionEngine extends Mock implements FusionEngine {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Creates a valid NavState for testing.
NavState createTestNavState({
  double px = 0.0,
  double py = 0.0,
  double pz = 0.0,
  double vx = 5.0,
  double vy = 5.0,
}) {
  return NavState(
    px: px,
    py: py,
    pz: pz,
    vx: vx,
    vy: vy,
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
    originLat: 51.5074,
    originLon: -0.1278,
    originAlt: 100.0,
  );
}

/// Creates a FusionStatusUpdate with the given status and optional error.
FusionStatusUpdate createStatusUpdate(
  FusionStatus status, {
  String? errorMessage,
}) {
  return FusionStatusUpdate(
    status: status,
    errorMessage: errorMessage,
    timestamp: DateTime(2024, 6, 15, 12, 0, 0),
  );
}

/// Creates a RecordingUpdate for testing.
RecordingUpdate createRecordingUpdate({
  double speedKmh = 60.0,
  Duration elapsed = const Duration(seconds: 30),
  int sampleCount = 30,
}) {
  return RecordingUpdate(
    currentSpeedKmh: speedKmh,
    elapsed: elapsed,
    gpsStatus: GpsStatus.active,
    sampleCount: sampleCount,
  );
}

void main() {
  late MockFusionEngine mockEngine;
  late StreamController<FusionStatusUpdate> statusController;
  late FusionNotifier notifier;

  setUp(() {
    mockEngine = MockFusionEngine();
    statusController = StreamController<FusionStatusUpdate>.broadcast();

    when(() => mockEngine.statusUpdates)
        .thenAnswer((_) => statusController.stream);

    notifier = FusionNotifier(fusionEngine: mockEngine);
  });

  tearDown(() async {
    notifier.dispose();
    await statusController.close();
  });

  group('FusionProvider state transitions', () {
    group('NavState exposure based on status', () {
      test('exposes non-null NavState when status is active', () async {
        // First set a NavState while in active status
        statusController.add(createStatusUpdate(FusionStatus.active));
        await Future.delayed(Duration.zero);

        // Update NavState while active
        notifier.updateNavState(createTestNavState());

        expect(notifier.state.status, FusionStatus.active);
        expect(notifier.state.navState, isNotNull);
      });

      test('exposes non-null NavState when status is fallback', () async {
        statusController.add(createStatusUpdate(FusionStatus.fallback));
        await Future.delayed(Duration.zero);

        notifier.updateNavState(createTestNavState());

        expect(notifier.state.status, FusionStatus.fallback);
        expect(notifier.state.navState, isNotNull);
      });

      test('exposes null NavState for uninitialized status', () async {
        // Initial state is uninitialized
        expect(notifier.state.status, FusionStatus.uninitialized);
        expect(notifier.state.navState, isNull);

        // Attempting to update NavState while uninitialized should be ignored
        notifier.updateNavState(createTestNavState());
        expect(notifier.state.navState, isNull);
      });

      test('exposes null NavState for aligning status', () async {
        statusController.add(createStatusUpdate(FusionStatus.aligning));
        await Future.delayed(Duration.zero);

        expect(notifier.state.status, FusionStatus.aligning);
        expect(notifier.state.navState, isNull);

        // Attempting to update NavState while aligning should be ignored
        notifier.updateNavState(createTestNavState());
        expect(notifier.state.navState, isNull);
      });

      test('exposes null NavState for initialized status', () async {
        statusController.add(createStatusUpdate(FusionStatus.initialized));
        await Future.delayed(Duration.zero);

        expect(notifier.state.status, FusionStatus.initialized);
        expect(notifier.state.navState, isNull);

        // Attempting to update NavState while initialized should be ignored
        notifier.updateNavState(createTestNavState());
        expect(notifier.state.navState, isNull);
      });

      test('exposes null NavState for error status', () async {
        statusController.add(createStatusUpdate(
          FusionStatus.error,
          errorMessage: 'Test error',
        ));
        await Future.delayed(Duration.zero);

        expect(notifier.state.status, FusionStatus.error);
        expect(notifier.state.navState, isNull);

        // Attempting to update NavState while in error should be ignored
        notifier.updateNavState(createTestNavState());
        expect(notifier.state.navState, isNull);
      });

      test('NavState is cleared when transitioning from active to error', () async {
        // Set active with NavState
        statusController.add(createStatusUpdate(FusionStatus.active));
        await Future.delayed(Duration.zero);
        notifier.updateNavState(createTestNavState());
        expect(notifier.state.navState, isNotNull);

        // Transition to error — NavState should be cleared
        statusController.add(createStatusUpdate(
          FusionStatus.error,
          errorMessage: 'IMU lost',
        ));
        await Future.delayed(Duration.zero);

        expect(notifier.state.status, FusionStatus.error);
        expect(notifier.state.navState, isNull);
      });

      test('NavState is preserved when transitioning from active to fallback', () async {
        // Set active with NavState
        statusController.add(createStatusUpdate(FusionStatus.active));
        await Future.delayed(Duration.zero);
        notifier.updateNavState(createTestNavState());
        expect(notifier.state.navState, isNotNull);

        // Transition to fallback — NavState should be preserved
        statusController.add(createStatusUpdate(FusionStatus.fallback));
        await Future.delayed(Duration.zero);

        expect(notifier.state.status, FusionStatus.fallback);
        expect(notifier.state.navState, isNotNull);
      });
    });

    group('Status change propagation', () {
      test('status changes are propagated to listeners within one frame (16 ms)', () {
        fakeAsync((async) {
          final localEngine = MockFusionEngine();
          final localStatusController =
              StreamController<FusionStatusUpdate>.broadcast();

          when(() => localEngine.statusUpdates)
              .thenAnswer((_) => localStatusController.stream);

          final localNotifier = FusionNotifier(fusionEngine: localEngine);

          final stateChanges = <FusionState>[];
          localNotifier.addListener(stateChanges.add);

          // Emit a status update
          localStatusController.add(createStatusUpdate(FusionStatus.aligning));
          async.flushMicrotasks();

          // Should be propagated within 16 ms
          async.elapse(const Duration(milliseconds: 16));

          expect(stateChanges.isNotEmpty, isTrue);
          expect(stateChanges.last.status, FusionStatus.aligning);

          localNotifier.dispose();
          localStatusController.close();
        });
      });

      test('multiple status changes are all propagated in order', () async {
        final stateChanges = <FusionState>[];
        notifier.addListener(stateChanges.add);

        statusController.add(createStatusUpdate(FusionStatus.aligning));
        await Future.delayed(Duration.zero);

        statusController.add(createStatusUpdate(FusionStatus.initialized));
        await Future.delayed(Duration.zero);

        statusController.add(createStatusUpdate(FusionStatus.active));
        await Future.delayed(Duration.zero);

        // Initial state + 3 changes
        expect(stateChanges.length, greaterThanOrEqualTo(3));
        final statuses = stateChanges.map((s) => s.status).toList();
        expect(statuses, contains(FusionStatus.aligning));
        expect(statuses, contains(FusionStatus.initialized));
        expect(statuses, contains(FusionStatus.active));
      });
    });

    group('Error status with error message', () {
      test('error status includes accompanying error message', () async {
        const errorMsg = 'Alignment failed: device not stationary';
        statusController.add(createStatusUpdate(
          FusionStatus.error,
          errorMessage: errorMsg,
        ));
        await Future.delayed(Duration.zero);

        expect(notifier.state.status, FusionStatus.error);
        expect(notifier.state.errorMessage, errorMsg);
      });

      test('error message is null for non-error statuses', () async {
        statusController.add(createStatusUpdate(FusionStatus.active));
        await Future.delayed(Duration.zero);

        expect(notifier.state.status, FusionStatus.active);
        expect(notifier.state.errorMessage, isNull);
      });

      test('error message is updated when a new error occurs', () async {
        statusController.add(createStatusUpdate(
          FusionStatus.error,
          errorMessage: 'First error',
        ));
        await Future.delayed(Duration.zero);
        expect(notifier.state.errorMessage, 'First error');

        // Simulate recovery and new error
        statusController.add(createStatusUpdate(FusionStatus.aligning));
        await Future.delayed(Duration.zero);

        statusController.add(createStatusUpdate(
          FusionStatus.error,
          errorMessage: 'GPS fix timeout',
        ));
        await Future.delayed(Duration.zero);
        expect(notifier.state.errorMessage, 'GPS fix timeout');
      });
    });

    group('Session stop resets state', () {
      test('stop() resets status to uninitialized', () async {
        // Set active state
        statusController.add(createStatusUpdate(FusionStatus.active));
        await Future.delayed(Duration.zero);
        notifier.updateNavState(createTestNavState());
        expect(notifier.state.status, FusionStatus.active);

        // Stop the session
        await notifier.stop();

        expect(notifier.state.status, FusionStatus.uninitialized);
      });

      test('stop() clears NavState', () async {
        statusController.add(createStatusUpdate(FusionStatus.active));
        await Future.delayed(Duration.zero);
        notifier.updateNavState(createTestNavState());
        expect(notifier.state.navState, isNotNull);

        await notifier.stop();

        expect(notifier.state.navState, isNull);
      });

      test('stop() clears error message', () async {
        statusController.add(createStatusUpdate(
          FusionStatus.error,
          errorMessage: 'Some error',
        ));
        await Future.delayed(Duration.zero);
        expect(notifier.state.errorMessage, isNotNull);

        await notifier.stop();

        expect(notifier.state.errorMessage, isNull);
      });

      test('stop() releases subscriptions (no further updates after stop)', () async {
        statusController.add(createStatusUpdate(FusionStatus.active));
        await Future.delayed(Duration.zero);
        expect(notifier.state.status, FusionStatus.active);

        await notifier.stop();
        expect(notifier.state.status, FusionStatus.uninitialized);

        // Emit another status update after stop — should be ignored
        statusController.add(createStatusUpdate(FusionStatus.aligning));
        await Future.delayed(Duration.zero);

        // State should remain uninitialized since subscription was cancelled
        expect(notifier.state.status, FusionStatus.uninitialized);
      });

      test('stop() clears latestUpdate', () async {
        statusController.add(createStatusUpdate(FusionStatus.active));
        await Future.delayed(Duration.zero);
        notifier.updateLatestUpdate(createRecordingUpdate());
        expect(notifier.state.latestUpdate, isNotNull);

        await notifier.stop();

        expect(notifier.state.latestUpdate, isNull);
      });
    });

    group('RecordingUpdate stream at 1 Hz', () {
      test('RecordingUpdate is exposed when status is active', () async {
        statusController.add(createStatusUpdate(FusionStatus.active));
        await Future.delayed(Duration.zero);

        final update = createRecordingUpdate(
          speedKmh: 80.0,
          elapsed: const Duration(seconds: 10),
          sampleCount: 10,
        );
        notifier.updateLatestUpdate(update);

        expect(notifier.state.latestUpdate, isNotNull);
        expect(notifier.state.latestUpdate!.currentSpeedKmh, 80.0);
        expect(notifier.state.latestUpdate!.sampleCount, 10);
      });

      test('RecordingUpdate is exposed when status is fallback', () async {
        statusController.add(createStatusUpdate(FusionStatus.fallback));
        await Future.delayed(Duration.zero);

        final update = createRecordingUpdate(
          speedKmh: 45.0,
          elapsed: const Duration(seconds: 20),
          sampleCount: 20,
        );
        notifier.updateLatestUpdate(update);

        expect(notifier.state.latestUpdate, isNotNull);
        expect(notifier.state.latestUpdate!.currentSpeedKmh, 45.0);
      });

      test('RecordingUpdate emits at 1 Hz when active', () {
        fakeAsync((async) {
          final localEngine = MockFusionEngine();
          final localStatusController =
              StreamController<FusionStatusUpdate>.broadcast();

          when(() => localEngine.statusUpdates)
              .thenAnswer((_) => localStatusController.stream);

          final localNotifier = FusionNotifier(fusionEngine: localEngine);

          // Transition to active
          localStatusController.add(createStatusUpdate(FusionStatus.active));
          async.flushMicrotasks();

          // Simulate 1 Hz updates over 3 seconds
          final updates = <RecordingUpdate>[];
          localNotifier.addListener((state) {
            if (state.latestUpdate != null) {
              updates.add(state.latestUpdate!);
            }
          });

          for (int i = 1; i <= 3; i++) {
            async.elapse(const Duration(seconds: 1));
            localNotifier.updateLatestUpdate(createRecordingUpdate(
              speedKmh: 60.0 + i,
              elapsed: Duration(seconds: i),
              sampleCount: i * 10,
            ));
            async.flushMicrotasks();
          }

          // Should have received 3 updates (one per second)
          expect(updates.length, 3);
          expect(updates[0].currentSpeedKmh, 61.0);
          expect(updates[1].currentSpeedKmh, 62.0);
          expect(updates[2].currentSpeedKmh, 63.0);

          localNotifier.dispose();
          localStatusController.close();
        });
      });

      test('RecordingUpdate emits at 1 Hz when in fallback', () {
        fakeAsync((async) {
          final localEngine = MockFusionEngine();
          final localStatusController =
              StreamController<FusionStatusUpdate>.broadcast();

          when(() => localEngine.statusUpdates)
              .thenAnswer((_) => localStatusController.stream);

          final localNotifier = FusionNotifier(fusionEngine: localEngine);

          // Transition to fallback
          localStatusController
              .add(createStatusUpdate(FusionStatus.fallback));
          async.flushMicrotasks();

          // Simulate 1 Hz updates over 2 seconds
          final updates = <RecordingUpdate>[];
          localNotifier.addListener((state) {
            if (state.latestUpdate != null) {
              updates.add(state.latestUpdate!);
            }
          });

          for (int i = 1; i <= 2; i++) {
            async.elapse(const Duration(seconds: 1));
            localNotifier.updateLatestUpdate(createRecordingUpdate(
              speedKmh: 50.0 + i,
              elapsed: Duration(seconds: i),
              sampleCount: i * 5,
            ));
            async.flushMicrotasks();
          }

          expect(updates.length, 2);
          expect(updates[0].currentSpeedKmh, 51.0);
          expect(updates[1].currentSpeedKmh, 52.0);

          localNotifier.dispose();
          localStatusController.close();
        });
      });
    });
  });
}
