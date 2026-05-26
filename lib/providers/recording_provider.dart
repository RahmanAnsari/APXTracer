import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engines/post_session_pipeline.dart';
import '../engines/recording/recording_engine.dart';
import '../engines/recording/recording_messages.dart';
import '../models/session.dart';

/// The possible states of the recording lifecycle.
enum RecordingStatus {
  /// No active session. Ready to start.
  idle,

  /// A session is actively recording GPS samples.
  recording,

  /// Session has stopped and post-session pipeline is processing.
  processing,
}

/// Immutable state for the recording provider.
class RecordingState {
  /// Current recording lifecycle status.
  final RecordingStatus status;

  /// The latest live update from the recording engine (null when idle).
  final RecordingUpdate? latestUpdate;

  /// The active session ID (null when idle).
  final String? sessionId;

  /// Error message if the last operation failed (null on success).
  final String? error;

  /// The result from the post-session pipeline (null until processing completes).
  final PostSessionResult? result;

  const RecordingState({
    this.status = RecordingStatus.idle,
    this.latestUpdate,
    this.sessionId,
    this.error,
    this.result,
  });

  RecordingState copyWith({
    RecordingStatus? status,
    RecordingUpdate? latestUpdate,
    String? sessionId,
    String? error,
    PostSessionResult? result,
    bool clearLatestUpdate = false,
    bool clearSessionId = false,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return RecordingState(
      status: status ?? this.status,
      latestUpdate:
          clearLatestUpdate ? null : (latestUpdate ?? this.latestUpdate),
      sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
      error: clearError ? null : (error ?? this.error),
      result: clearResult ? null : (result ?? this.result),
    );
  }
}

/// StateNotifier that manages the recording lifecycle.
///
/// Exposes [startSession] and [stopSession] methods, and provides
/// live updates from the recording engine at 1 Hz minimum.
///
/// Wires to [IRecordingEngine] for GPS capture and [PostSessionPipeline]
/// for post-session processing (track discovery, lap detection, analytics).
///
/// Prevents duplicate concurrent sessions (requirement 1.9).
class RecordingNotifier extends StateNotifier<RecordingState> {
  final IRecordingEngine _recordingEngine;
  final PostSessionPipeline _postSessionPipeline;

  StreamSubscription<RecordingUpdate>? _updatesSubscription;

  RecordingNotifier({
    required IRecordingEngine recordingEngine,
    required PostSessionPipeline postSessionPipeline,
  })  : _recordingEngine = recordingEngine,
        _postSessionPipeline = postSessionPipeline,
        super(const RecordingState());

  /// Stream of live recording updates for UI consumption.
  ///
  /// Emits at least 1 Hz while recording (requirement 1.7).
  Stream<RecordingUpdate> get liveUpdates => _recordingEngine.updates;

  /// Starts a new recording session.
  ///
  /// Transitions state: idle → recording.
  /// Throws if GPS permission is denied or GPS fix times out.
  /// Prevents duplicate concurrent sessions (requirement 1.9).
  Future<void> startSession() async {
    // Prevent duplicate concurrent sessions.
    if (state.status != RecordingStatus.idle) {
      return;
    }

    // Clear any previous error/result.
    state = state.copyWith(
      clearError: true,
      clearResult: true,
    );

    try {
      final sessionId = await _recordingEngine.startSession();

      state = state.copyWith(
        status: RecordingStatus.recording,
        sessionId: sessionId,
        clearError: true,
      );

      // Subscribe to live updates from the recording engine.
      _updatesSubscription = _recordingEngine.updates.listen(
        (update) {
          if (state.status == RecordingStatus.recording) {
            state = state.copyWith(latestUpdate: update);
          }
        },
        onError: (Object error) {
          state = state.copyWith(error: error.toString());
        },
      );
    } on GpsPermissionDeniedException catch (e) {
      state = state.copyWith(
        status: RecordingStatus.idle,
        error: e.message,
      );
    } on GpsFixTimeoutException catch (e) {
      state = state.copyWith(
        status: RecordingStatus.idle,
        error: e.message,
      );
    } on StateError catch (e) {
      // Already recording — should not happen due to our guard, but handle gracefully.
      state = state.copyWith(error: e.message);
    }
  }

  /// Stops the active recording session and triggers post-session processing.
  ///
  /// Transitions state: recording → processing → idle.
  /// After stopping, triggers the post-session pipeline (requirement 1.5)
  /// and returns the finalized session.
  Future<Session?> stopSession() async {
    if (state.status != RecordingStatus.recording) {
      return null;
    }

    // Cancel the live updates subscription.
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;

    // Transition to processing state.
    state = state.copyWith(
      status: RecordingStatus.processing,
      clearLatestUpdate: true,
    );

    try {
      // Stop the recording engine and get the finalized session.
      final session = await _recordingEngine.stopSession();

      // Run the post-session pipeline (track discovery → lap detection → analytics).
      final result = await _postSessionPipeline.execute(session.id);

      // Transition back to idle with the result.
      state = state.copyWith(
        status: RecordingStatus.idle,
        result: result,
        clearSessionId: true,
        clearError: true,
      );

      return session;
    } catch (e) {
      // On error, transition back to idle with error info.
      state = state.copyWith(
        status: RecordingStatus.idle,
        error: e.toString(),
        clearSessionId: true,
      );
      return null;
    }
  }

  @override
  void dispose() {
    _updatesSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for the recording state notifier.
///
/// Requires [recordingEngineProvider] and [postSessionPipelineProvider]
/// to be overridden or provided in the widget tree.
final recordingProvider =
    StateNotifierProvider<RecordingNotifier, RecordingState>((ref) {
  final recordingEngine = ref.watch(recordingEngineProvider);
  final postSessionPipeline = ref.watch(postSessionPipelineProvider);

  return RecordingNotifier(
    recordingEngine: recordingEngine,
    postSessionPipeline: postSessionPipeline,
  );
});

/// Provider for the live recording updates stream.
///
/// Emits [RecordingUpdate] at 1 Hz minimum while recording (requirement 1.7).
/// Returns an empty stream when not recording.
final recordingUpdatesProvider = StreamProvider<RecordingUpdate>((ref) {
  final notifier = ref.watch(recordingProvider.notifier);
  return notifier.liveUpdates;
});

/// Provider for the recording engine instance.
///
/// Must be overridden in the ProviderScope with the actual implementation.
final recordingEngineProvider = Provider<IRecordingEngine>((ref) {
  throw UnimplementedError(
    'recordingEngineProvider must be overridden with an actual IRecordingEngine implementation',
  );
});

/// Provider for the post-session pipeline instance.
///
/// Must be overridden in the ProviderScope with the actual implementation.
final postSessionPipelineProvider = Provider<PostSessionPipeline>((ref) {
  throw UnimplementedError(
    'postSessionPipelineProvider must be overridden with an actual PostSessionPipeline implementation',
  );
});
