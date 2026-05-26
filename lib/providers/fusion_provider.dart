import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engines/fusion/default_imu_service.dart';
import '../engines/fusion/fusion_engine.dart';
import '../engines/fusion/imu_service.dart';
import '../engines/kalman/dead_reckoning_filter.dart';
import '../engines/kalman/kalman_models.dart';
import '../engines/recording/recording_messages.dart';

/// Immutable state exposed by the FusionProvider.
class FusionState {
  /// Current fusion lifecycle status.
  final FusionStatus status;

  /// Error message when status is [FusionStatus.error].
  final String? errorMessage;

  /// Current NavState from the filter. Non-null only when status is
  /// [FusionStatus.active] or [FusionStatus.fallback].
  final NavState? navState;

  /// Latest recording update for UI consumption.
  final RecordingUpdate? latestUpdate;

  const FusionState({
    this.status = FusionStatus.uninitialized,
    this.errorMessage,
    this.navState,
    this.latestUpdate,
  });

  FusionState copyWith({
    FusionStatus? status,
    String? errorMessage,
    NavState? navState,
    RecordingUpdate? latestUpdate,
    bool clearErrorMessage = false,
    bool clearNavState = false,
    bool clearLatestUpdate = false,
  }) {
    return FusionState(
      status: status ?? this.status,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      navState: clearNavState ? null : (navState ?? this.navState),
      latestUpdate:
          clearLatestUpdate ? null : (latestUpdate ?? this.latestUpdate),
    );
  }
}

/// StateNotifier managing fusion lifecycle state for UI consumption.
///
/// Subscribes to [FusionEngine.statusUpdates] and exposes the current
/// fusion state including status, NavState, and error information.
///
/// NavState is only exposed (non-null) when status is `active` or `fallback`.
/// On session stop, resets to `uninitialized` and releases subscriptions.
class FusionNotifier extends StateNotifier<FusionState> {
  final FusionEngine _fusionEngine;
  StreamSubscription<FusionStatusUpdate>? _statusSub;

  FusionNotifier({required FusionEngine fusionEngine})
      : _fusionEngine = fusionEngine,
        super(const FusionState()) {
    _statusSub = _fusionEngine.statusUpdates.listen(_onStatusUpdate);
  }

  /// Handles status updates from the FusionEngine.
  void _onStatusUpdate(FusionStatusUpdate update) {
    final newStatus = update.status;

    // Only expose NavState when status is active or fallback
    NavState? navState;
    if (newStatus == FusionStatus.active || newStatus == FusionStatus.fallback) {
      navState = state.navState;
    }

    state = FusionState(
      status: newStatus,
      errorMessage: update.errorMessage,
      navState: navState,
      latestUpdate: state.latestUpdate,
    );
  }

  /// Updates the exposed NavState. Should only be called when the engine
  /// is in `active` or `fallback` status.
  void updateNavState(NavState navState) {
    if (state.status == FusionStatus.active ||
        state.status == FusionStatus.fallback) {
      state = state.copyWith(navState: navState);
    }
  }

  /// Updates the latest recording update for UI consumption.
  void updateLatestUpdate(RecordingUpdate update) {
    state = state.copyWith(latestUpdate: update);
  }

  /// Stops the fusion session and resets state to uninitialized.
  ///
  /// Cancels the status subscription and clears all state.
  Future<void> stop() async {
    await _statusSub?.cancel();
    _statusSub = null;

    state = const FusionState(
      status: FusionStatus.uninitialized,
    );
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }
}

/// Provider for the IMU service instance.
///
/// Provides [DefaultImuService] for hardware IMU access.
final imuServiceProvider = Provider<ImuService>((ref) {
  return DefaultImuService();
});

/// Provider for the FusionEngine instance.
///
/// Depends on [imuServiceProvider] for IMU data and creates a
/// [DeadReckoningFilter] with default configuration.
final fusionEngineProvider = Provider<FusionEngine>((ref) {
  final imuService = ref.watch(imuServiceProvider);
  final filter = DeadReckoningFilter();

  return FusionEngine(
    filter: filter,
    imuService: imuService,
  );
});

/// Provider for the fusion state notifier.
///
/// Exposes [FusionState] reactively for UI consumption.
/// Depends on [fusionEngineProvider] for the underlying engine.
final fusionProvider =
    StateNotifierProvider<FusionNotifier, FusionState>((ref) {
  final fusionEngine = ref.watch(fusionEngineProvider);

  return FusionNotifier(fusionEngine: fusionEngine);
});
