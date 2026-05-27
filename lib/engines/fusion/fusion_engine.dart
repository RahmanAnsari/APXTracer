import 'dart:async';
import 'dart:math' as math;

import 'package:apx_tracer/engines/kalman/dead_reckoning_filter.dart';
import 'package:apx_tracer/engines/kalman/kalman_models.dart';
import 'package:apx_tracer/engines/fusion/imu_service.dart';
import 'package:apx_tracer/engines/fusion/nav_state_converter.dart';
import 'package:apx_tracer/models/gps_sample.dart';
import 'package:geolocator/geolocator.dart';

/// Lifecycle states of the FusionEngine.
enum FusionStatus {
  /// Not started, no resources allocated.
  uninitialized,

  /// Collecting stationary IMU samples for gravity alignment.
  aligning,

  /// Gravity alignment done, waiting for first valid GPS fix.
  initialized,

  /// Filter running, producing fused output.
  active,

  /// IMU stream interrupted; passing GPS directly to persistence.
  fallback,

  /// Unrecoverable error (alignment failure, GPS timeout, etc.).
  error,
}

/// Emitted by FusionEngine when its status changes.
class FusionStatusUpdate {
  final FusionStatus status;
  final String? errorMessage;
  final DateTime timestamp;

  const FusionStatusUpdate({
    required this.status,
    this.errorMessage,
    required this.timestamp,
  });
}

/// Orchestrates the DeadReckoningFilter lifecycle, coordinates IMU and GPS
/// streams, handles initialization sequencing, and produces fused output.
class FusionEngine {
  final DeadReckoningFilter _filter;
  final ImuService _imuService;

  FusionStatus _status = FusionStatus.uninitialized;

  // Initialization state
  final List<ImuData> _alignmentSamples = [];
  int _alignmentAttempts = 0;
  static const int maxAlignmentAttempts = 3;
  static const Duration alignmentDuration = Duration(milliseconds: 500);

  // GPS initialization timeout
  Timer? _gpsTimeoutTimer;
  static const Duration gpsFixTimeout = Duration(seconds: 10);

  // Fallback detection
  DateTime? _lastImuTimestamp;
  static const Duration imuGapFallback = Duration(milliseconds: 200);
  static const Duration imuGapReinit = Duration(milliseconds: 500);
  Timer? _imuWatchdogTimer;

  // Last known attitude for short-gap recovery
  double _lastRoll = 0.0;
  double _lastPitch = 0.0;

  // Recovery state
  bool _pendingRecovery = false;
  double _recoveryRoll = 0.0;
  double _recoveryPitch = 0.0;

  // IMU-driven continuous emit — produces dead-reckoned samples at ~10 Hz
  // regardless of GPS state. Throttled so we don't flood at raw IMU rate.
  DateTime? _lastImuEmitAt;
  static const Duration _imuEmitInterval = Duration(milliseconds: 100);

  // Last known GPS accuracy, used to mark dead-reckoned samples as low-accuracy.
  double _lastGpsAccuracy = 0.0;

  // Output streams
  final StreamController<GpsSample> _fusedSampleController =
      StreamController<GpsSample>.broadcast();
  final StreamController<FusionStatusUpdate> _statusController =
      StreamController<FusionStatusUpdate>.broadcast();

  // Subscriptions
  StreamSubscription<ImuData>? _imuSubscription;

  FusionEngine({
    required DeadReckoningFilter filter,
    required ImuService imuService,
  })  : _filter = filter,
        _imuService = imuService;

  /// Current fusion status.
  FusionStatus get status => _status;

  /// Stream of fused GpsSample output for RecordingEngine consumption.
  Stream<GpsSample> get fusedSamples => _fusedSampleController.stream;

  /// Stream of status change events for provider consumption.
  Stream<FusionStatusUpdate> get statusUpdates => _statusController.stream;

  /// Starts the fusion pipeline. Called by RecordingEngine at session start.
  ///
  /// Begins the gravity alignment phase by subscribing to the IMU stream
  /// and collecting stationary samples.
  Future<void> start() async {
    if (_status != FusionStatus.uninitialized) return;

    _alignmentSamples.clear();
    _alignmentAttempts = 0;

    _setStatus(FusionStatus.aligning);

    // Subscribe to IMU stream for alignment sample collection.
    // Full alignment logic (stationarity detection, retry, GPS init)
    // will be implemented in tasks 5.2–5.3.
    final imuStream = _imuService.startStreaming();
    _imuSubscription = imuStream.listen(_onImuData);
  }

  /// Stops the fusion pipeline. Called by RecordingEngine at session stop.
  ///
  /// Releases subscriptions and timers, resets state so [start] can be
  /// called again for a new session. Does NOT close stream controllers —
  /// those are reused across sessions and only closed by [dispose].
  Future<void> stop() async {
    _gpsTimeoutTimer?.cancel();
    _gpsTimeoutTimer = null;

    _imuWatchdogTimer?.cancel();
    _imuWatchdogTimer = null;

    await _imuSubscription?.cancel();
    _imuSubscription = null;

    await _imuService.stopStreaming();

    _alignmentSamples.clear();
    _lastImuTimestamp = null;
    _pendingRecovery = false;

    _lastImuEmitAt = null;
    _lastGpsAccuracy = 0.0;

    _setStatus(FusionStatus.uninitialized);
  }

  /// Permanently releases all resources. Call only when the engine will
  /// no longer be used (e.g., provider disposal).
  Future<void> dispose() async {
    await stop();
    await _fusedSampleController.close();
    await _statusController.close();
  }

  // ─── Internal handlers (skeletons for subsequent tasks) ────────────────────

  /// Handles incoming IMU data from ImuService.
  void _onImuData(ImuData data) {
    if (_status == FusionStatus.aligning) {
      _lastImuTimestamp = data.timestamp;
      _handleAlignmentSample(data);
      return;
    }

    if (_status == FusionStatus.active) {
      // Reset the watchdog timer on each IMU sample in active state
      _resetImuWatchdog();

      // Track last known attitude for short-gap recovery
      if (_filter.isInitialized) {
        final navState = _filter.state;
        _lastRoll = navState.roll;
        _lastPitch = navState.pitch;
      }

      _filter.predictWithImu(data);
      _lastImuTimestamp = data.timestamp;

      // Emit the predicted position at ~10 Hz regardless of GPS state.
      // This guarantees samples are always produced — GPS present or absent.
      // When GPS is present, _handleFusedGpsFix also emits a GPS-corrected
      // sample, giving slightly higher temporal density around each GPS fix.
      if (_filter.isInitialized) {
        final now = DateTime.now();
        if (_lastImuEmitAt == null ||
            now.difference(_lastImuEmitAt!) >= _imuEmitInterval) {
          _lastImuEmitAt = now;
          final sample = navStateToGpsSample(
            navState: _filter.state,
            // Dead-reckoned samples get a high accuracy value (> 50 m) so
            // isLowAccuracy is true, signalling downstream they are IMU-only.
            gpsAccuracy: _lastGpsAccuracy > 0
                ? math.max(_lastGpsAccuracy * 2, 100.0)
                : 100.0,
            timestampMs: now.millisecondsSinceEpoch,
          );
          if (sample != null) {
            _fusedSampleController.add(sample);
          }
        }
      }

      return;
    }

    if (_status == FusionStatus.fallback) {
      _handleImuRecovery(data);
      return;
    }
  }

  /// Handles incoming GPS fix from GpsService.
  ///
  /// Behavior depends on the current status:
  /// - `initialized`: GPS initialization phase — forward first valid fix to filter
  /// - `active`: fused output (placeholder for task 5.4)
  /// - `fallback`: GPS-only mode (placeholder for task 5.5)
  void onGpsFix(Position position) {
    switch (_status) {
      case FusionStatus.initialized:
        _handleGpsInitialization(position);
        break;
      case FusionStatus.active:
        _handleFusedGpsFix(position);
        break;
      case FusionStatus.fallback:
        _handleFallbackGpsFix(position);
        break;
      default:
        // Ignore GPS fixes in other states (uninitialized, aligning, error)
        break;
    }
  }

  /// Handles a GPS fix during the initialization phase.
  ///
  /// Discards fixes with accuracy > 50 m. Forwards the first valid fix
  /// (accuracy ≤ 50 m) to the filter's `initWithGps` and transitions to `active`.
  void _handleGpsInitialization(Position position) {
    if (position.accuracy > 50.0) {
      // Discard inaccurate fix
      return;
    }

    // Convert Position to GpsData for the filter
    final gpsData = positionToGpsData(position);

    // Initialize the filter with the first valid GPS fix
    _filter.initWithGps(
      gpsData,
      initialRoll: _lastRoll,
      initialPitch: _lastPitch,
    );

    // Cancel the GPS timeout timer
    _gpsTimeoutTimer?.cancel();
    _gpsTimeoutTimer = null;

    // Transition to active state
    _setStatus(FusionStatus.active);
  }

  /// Handles a GPS fix during the active state.
  ///
  /// Converts Position to GpsData, updates the filter, reads NavState,
  /// converts to GpsSample, and emits on the fusedSamples stream.
  /// Ensures exactly one fused GpsSample per GPS fix (1:1 correspondence)
  /// when coordinates are valid.
  void _handleFusedGpsFix(Position position) {
    // Convert Position to GpsData for the filter
    final gpsData = positionToGpsData(position);

    // Update the filter with the GPS fix
    _filter.updateWithGps(gpsData);

    // Read the current NavState from the filter
    final navState = _filter.state;

    // Cache accuracy for dead-reckoned samples produced from the IMU path.
    _lastGpsAccuracy = position.accuracy > 0 ? position.accuracy : 100.0;

    // Convert NavState to GpsSample
    final sample = navStateToGpsSample(
      navState: navState,
      gpsAccuracy: _lastGpsAccuracy,
      timestampMs: position.timestamp.millisecondsSinceEpoch,
    );

    // Emit the GPS-corrected sample if coordinates are valid.
    if (sample != null) {
      _fusedSampleController.add(sample);
      // Advance the IMU emit clock so the next IMU sample is emitted
      // ~100 ms after this GPS-corrected one, avoiding back-to-back duplicates.
      _lastImuEmitAt = DateTime.now();
    }
  }

  // Stationarity thresholds for alignment
  static const double _maxGyroRate = 0.05; // rad/s
  static const double _gravityNominal = 9.81; // m/s²
  static const double _accelTolerance = 0.5; // m/s²

  /// Processes an IMU sample during the alignment phase.
  ///
  /// Checks stationarity, collects samples for 0.5s, and transitions
  /// to `initialized` on success or `error` after 3 failed attempts.
  void _handleAlignmentSample(ImuData data) {
    // Check stationarity: angular rate magnitude < 0.05 rad/s
    final gyroMagnitude = math.sqrt(
      data.gx * data.gx + data.gy * data.gy + data.gz * data.gz,
    );
    // Check stationarity: accel magnitude within 0.5 m/s² of 9.81
    final accelMagnitude = math.sqrt(
      data.ax * data.ax + data.ay * data.ay + data.az * data.az,
    );

    final isStationary = gyroMagnitude < _maxGyroRate &&
        (accelMagnitude - _gravityNominal).abs() < _accelTolerance;

    if (!isStationary) {
      // Non-stationary: discard collected samples and retry
      _alignmentSamples.clear();
      _alignmentAttempts++;

      if (_alignmentAttempts >= maxAlignmentAttempts) {
        _setStatus(
          FusionStatus.error,
          errorMessage: 'Alignment failed: device not stationary',
        );
        return;
      }
      // Restart collection on next stationary sample
      return;
    }

    // Sample is stationary — collect it
    _alignmentSamples.add(data);

    // Check if we have collected 0.5 seconds of stationary samples
    if (_alignmentSamples.length >= 2) {
      final firstTimestamp = _alignmentSamples.first.timestamp;
      final lastTimestamp = _alignmentSamples.last.timestamp;
      final elapsed = lastTimestamp.difference(firstTimestamp);

      if (elapsed >= alignmentDuration) {
        // Successful alignment collection — call alignWithGravity
        final attitude = _filter.alignWithGravity(_alignmentSamples);
        _lastRoll = attitude.roll;
        _lastPitch = attitude.pitch;
        _setStatus(FusionStatus.initialized);
      }
    }
  }

  // ─── Private helpers ───────────────────────────────────────────────────────

  /// Handles a GPS fix during fallback state.
  ///
  /// If a pending recovery is set (IMU has resumed), reinitializes the filter
  /// with the GPS fix and transitions back to active. Otherwise, does nothing
  /// (RecordingEngine will persist raw GPS directly).
  void _handleFallbackGpsFix(Position position) {
    if (!_pendingRecovery) {
      // No recovery pending — GPS fix is handled by the caller's raw path
      return;
    }

    // Only reinitialize with a valid GPS fix (accuracy ≤ 50 m)
    if (position.accuracy > 50.0) {
      return;
    }

    // Reinitialize the filter with recovery attitude
    final gpsData = positionToGpsData(position);
    _filter.initWithGps(
      gpsData,
      initialRoll: _recoveryRoll,
      initialPitch: _recoveryPitch,
    );

    // Clear recovery state
    _pendingRecovery = false;
    _recoveryRoll = 0.0;
    _recoveryPitch = 0.0;

    // Transition back to active state
    _setStatus(FusionStatus.active);
  }

  /// Handles IMU data arriving while in fallback state.
  ///
  /// Calculates the gap duration and sets recovery parameters:
  /// - Short gap (200–500 ms): recover with last known roll/pitch
  /// - Long gap (> 500 ms): recover with zero roll/pitch
  void _handleImuRecovery(ImuData data) {
    if (_lastImuTimestamp != null) {
      final gap = data.timestamp.difference(_lastImuTimestamp!);

      if (gap <= imuGapReinit) {
        // Short gap (200–500 ms): use last known attitude
        _pendingRecovery = true;
        _recoveryRoll = _lastRoll;
        _recoveryPitch = _lastPitch;
      } else {
        // Long gap (> 500 ms): use zero attitude (level assumption)
        _pendingRecovery = true;
        _recoveryRoll = 0.0;
        _recoveryPitch = 0.0;
      }
    } else {
      // No previous timestamp — treat as long gap
      _pendingRecovery = true;
      _recoveryRoll = 0.0;
      _recoveryPitch = 0.0;
    }

    _lastImuTimestamp = data.timestamp;
  }

  /// Resets the IMU watchdog timer. Called on each IMU sample in active state.
  void _resetImuWatchdog() {
    _imuWatchdogTimer?.cancel();
    _imuWatchdogTimer = Timer(imuGapFallback, _onImuWatchdogFired);
  }

  /// Called when the IMU watchdog fires (200 ms without IMU data in active state).
  void _onImuWatchdogFired() {
    if (_status == FusionStatus.active) {
      _setStatus(FusionStatus.fallback);
    }
  }

  void _setStatus(FusionStatus newStatus, {String? errorMessage}) {
    final oldStatus = _status;
    _status = newStatus;
    _statusController.add(FusionStatusUpdate(
      status: newStatus,
      errorMessage: errorMessage,
      timestamp: DateTime.now(),
    ));

    // Watchdog management: cancel when leaving active state
    if (oldStatus == FusionStatus.active && newStatus != FusionStatus.active) {
      _imuWatchdogTimer?.cancel();
      _imuWatchdogTimer = null;
    }

    // Start watchdog when entering active state
    if (newStatus == FusionStatus.active) {
      _resetImuWatchdog();
    }

    // Start GPS fix timeout timer when entering initialized state
    if (newStatus == FusionStatus.initialized) {
      _gpsTimeoutTimer?.cancel();
      _gpsTimeoutTimer = Timer(gpsFixTimeout, () {
        _setStatus(
          FusionStatus.error,
          errorMessage: 'GPS fix timeout',
        );
      });
    }
  }
}
