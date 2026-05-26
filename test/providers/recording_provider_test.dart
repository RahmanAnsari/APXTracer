import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:apx_tracer/engines/post_session_pipeline.dart';
import 'package:apx_tracer/engines/recording/recording_engine.dart';
import 'package:apx_tracer/engines/recording/recording_messages.dart';
import 'package:apx_tracer/models/session.dart';
import 'package:apx_tracer/models/session_analytics.dart';
import 'package:apx_tracer/providers/recording_provider.dart';

// --- Mocks ---

class MockRecordingEngine extends Mock implements IRecordingEngine {}

class MockPostSessionPipeline extends Mock implements PostSessionPipeline {}

void main() {
  late MockRecordingEngine mockEngine;
  late MockPostSessionPipeline mockPipeline;
  late RecordingNotifier notifier;

  setUp(() {
    mockEngine = MockRecordingEngine();
    mockPipeline = MockPostSessionPipeline();

    // Default: updates stream returns an empty stream
    when(() => mockEngine.updates).thenAnswer((_) => const Stream.empty());

    notifier = RecordingNotifier(
      recordingEngine: mockEngine,
      postSessionPipeline: mockPipeline,
    );
  });

  tearDown(() {
    notifier.dispose();
  });

  group('RecordingNotifier', () {
    group('startSession', () {
      test('transitions state from idle to recording', () async {
        when(() => mockEngine.startSession())
            .thenAnswer((_) async => 'session-1');
        when(() => mockEngine.updates)
            .thenAnswer((_) => const Stream.empty());

        expect(notifier.state.status, equals(RecordingStatus.idle));

        await notifier.startSession();

        expect(notifier.state.status, equals(RecordingStatus.recording));
        expect(notifier.state.sessionId, equals('session-1'));
      });

      test('is rejected when already recording (requirement 1.9)', () async {
        when(() => mockEngine.startSession())
            .thenAnswer((_) async => 'session-1');
        when(() => mockEngine.updates)
            .thenAnswer((_) => const Stream.empty());

        // Start first session
        await notifier.startSession();
        expect(notifier.state.status, equals(RecordingStatus.recording));

        // Attempt to start a second session — should be silently rejected
        await notifier.startSession();

        // State should still be recording with the original session
        expect(notifier.state.status, equals(RecordingStatus.recording));
        expect(notifier.state.sessionId, equals('session-1'));

        // startSession on the engine should only have been called once
        verify(() => mockEngine.startSession()).called(1);
      });

      test('captures GPS permission denied error in state', () async {
        when(() => mockEngine.startSession()).thenThrow(
          const GpsPermissionDeniedException('Location permission denied'),
        );

        await notifier.startSession();

        expect(notifier.state.status, equals(RecordingStatus.idle));
        expect(notifier.state.error, contains('Location permission denied'));
      });

      test('captures GPS fix timeout error in state', () async {
        when(() => mockEngine.startSession()).thenThrow(
          const GpsFixTimeoutException(
            message: 'Could not acquire GPS fix within 10 seconds',
          ),
        );

        await notifier.startSession();

        expect(notifier.state.status, equals(RecordingStatus.idle));
        expect(notifier.state.error, contains('GPS fix'));
      });
    });

    group('stopSession', () {
      test('transitions state from recording to processing to idle', () async {
        // Setup: start a session first
        when(() => mockEngine.startSession())
            .thenAnswer((_) async => 'session-1');
        when(() => mockEngine.updates)
            .thenAnswer((_) => const Stream.empty());

        await notifier.startSession();
        expect(notifier.state.status, equals(RecordingStatus.recording));

        // Setup stop: engine returns a session, pipeline returns a result
        final session = Session(
          id: 'session-1',
          startTime: 1700000000000,
          endTime: 1700000060000,
          durationMs: 60000,
        );
        when(() => mockEngine.stopSession()).thenAnswer((_) async => session);

        final pipelineResult = PostSessionResult(
          laps: [],
          analytics: const SessionAnalytics(
            sessionId: 'session-1',
            durationSeconds: 60.0,
            distanceKm: 1.5,
            totalLaps: 0,
            averageSpeedKmh: 90.0,
            maxSpeedKmh: 120.0,
            speedTraceKmh: [90.0, 100.0, 110.0],
          ),
        );
        when(() => mockPipeline.execute('session-1'))
            .thenAnswer((_) async => pipelineResult);

        // Track state transitions
        final states = <RecordingStatus>[];
        notifier.addListener((state) {
          states.add(state.status);
        });

        // Stop the session
        final result = await notifier.stopSession();

        expect(result, isNotNull);
        expect(result!.id, equals('session-1'));

        // Verify the final state is idle
        expect(notifier.state.status, equals(RecordingStatus.idle));
        expect(notifier.state.result, equals(pipelineResult));

        // Verify processing state was reached
        expect(states, contains(RecordingStatus.processing));
      });

      test('returns null when not recording', () async {
        expect(notifier.state.status, equals(RecordingStatus.idle));

        final result = await notifier.stopSession();

        expect(result, isNull);
        verifyNever(() => mockEngine.stopSession());
      });

      test('captures error and transitions to idle on failure', () async {
        // Start a session
        when(() => mockEngine.startSession())
            .thenAnswer((_) async => 'session-1');
        when(() => mockEngine.updates)
            .thenAnswer((_) => const Stream.empty());
        await notifier.startSession();

        // Stop fails
        when(() => mockEngine.stopSession())
            .thenThrow(Exception('Engine error'));

        final result = await notifier.stopSession();

        expect(result, isNull);
        expect(notifier.state.status, equals(RecordingStatus.idle));
        expect(notifier.state.error, isNotNull);
      });
    });

    group('live updates', () {
      test('updates latestUpdate from engine stream', () async {
        final controller = StreamController<RecordingUpdate>.broadcast();

        when(() => mockEngine.startSession())
            .thenAnswer((_) async => 'session-1');
        when(() => mockEngine.updates).thenAnswer((_) => controller.stream);

        await notifier.startSession();

        const update = RecordingUpdate(
          currentSpeedKmh: 85.0,
          elapsed: Duration(seconds: 30),
          gpsStatus: GpsStatus.active,
          sampleCount: 300,
        );

        controller.add(update);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(notifier.state.latestUpdate, isNotNull);
        expect(notifier.state.latestUpdate!.currentSpeedKmh, equals(85.0));
        expect(notifier.state.latestUpdate!.sampleCount, equals(300));

        await controller.close();
      });
    });
  });
}
