import 'dart:async';
import 'dart:io' show Platform;

import 'package:clock/clock.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../kalman/kalman_models.dart';
import 'imu_service.dart';

/// Type alias for accelerometer stream factory (for testability).
typedef AccelerometerStreamFactory = Stream<AccelerometerEvent> Function();

/// Type alias for gyroscope stream factory (for testability).
typedef GyroscopeStreamFactory = Stream<GyroscopeEvent> Function();

/// Default implementation of [ImuService] using the `sensors_plus` plugin.
///
/// Pairs accelerometer and gyroscope events by timestamp proximity (within 5 ms)
/// and applies a platform-specific coordinate transform to produce [ImuData]
/// in the body-frame convention: X=right, Y=forward, Z=up.
///
/// Rate monitoring emits [ImuDegradedWarning] when the 500 ms sliding window
/// average sample rate drops below 50 Hz.
class DefaultImuService implements ImuService {
  /// Optional stream factories for dependency injection in tests.
  final AccelerometerStreamFactory _accelStreamFactory;
  final GyroscopeStreamFactory _gyroStreamFactory;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  final StreamController<ImuData> _imuController =
      StreamController<ImuData>.broadcast();
  final StreamController<ImuDegradedWarning> _warningController =
      StreamController<ImuDegradedWarning>.broadcast();

  /// Latest accelerometer event (waiting to be paired).
  AccelerometerEvent? _latestAccel;
  DateTime? _latestAccelTime;

  /// Latest gyroscope event (waiting to be paired).
  GyroscopeEvent? _latestGyro;
  DateTime? _latestGyroTime;

  /// Sliding window of sample timestamps for rate monitoring (last 500 ms).
  final List<DateTime> _sampleTimestamps = [];

  /// Whether a degraded warning is currently active (to avoid repeated emissions).
  bool _isDegraded = false;

  /// Timer for periodic rate checking.
  Timer? _rateCheckTimer;

  /// Maximum timestamp difference (ms) for pairing accel + gyro events.
  static const int _maxPairDeltaMs = 5;

  /// Sliding window duration for rate monitoring.
  static const Duration _rateWindowDuration = Duration(milliseconds: 500);

  /// Minimum acceptable rate (Hz) before emitting a degraded warning.
  static const double _minAcceptableRateHz = 50.0;

  /// Rate check interval.
  static const Duration _rateCheckInterval = Duration(milliseconds: 100);

  /// Creates a [DefaultImuService].
  ///
  /// Accepts optional [accelStreamFactory] and [gyroStreamFactory] for
  /// testability. When not provided, uses the default `sensors_plus` streams.
  DefaultImuService({
    AccelerometerStreamFactory? accelStreamFactory,
    GyroscopeStreamFactory? gyroStreamFactory,
  })  : _accelStreamFactory =
            (accelStreamFactory ?? () => accelerometerEventStream()),
        _gyroStreamFactory =
            (gyroStreamFactory ?? () => gyroscopeEventStream());

  @override
  Future<bool> checkAvailability() async {
    // Attempt to listen briefly to both streams to verify hardware availability.
    // sensors_plus throws or returns empty streams when hardware is unavailable.
    try {
      final accelCompleter = Completer<bool>();
      final gyroCompleter = Completer<bool>();

      final accelSub = _accelStreamFactory().listen(
        (_) {
          if (!accelCompleter.isCompleted) accelCompleter.complete(true);
        },
        onError: (_) {
          if (!accelCompleter.isCompleted) accelCompleter.complete(false);
        },
      );

      final gyroSub = _gyroStreamFactory().listen(
        (_) {
          if (!gyroCompleter.isCompleted) gyroCompleter.complete(true);
        },
        onError: (_) {
          if (!gyroCompleter.isCompleted) gyroCompleter.complete(false);
        },
      );

      // Wait up to 1 second for both sensors to deliver at least one event.
      final accelAvailable = await accelCompleter.future
          .timeout(const Duration(seconds: 1), onTimeout: () => false);
      final gyroAvailable = await gyroCompleter.future
          .timeout(const Duration(seconds: 1), onTimeout: () => false);

      await accelSub.cancel();
      await gyroSub.cancel();

      return accelAvailable && gyroAvailable;
    } catch (e) {
      return false;
    }
  }

  @override
  Stream<ImuData> startStreaming() {
    if (_accelSub != null || _gyroSub != null) {
      // Already streaming — return existing stream.
      return _imuController.stream;
    }

    try {
      _accelSub = _accelStreamFactory().listen(
        _onAccelerometerEvent,
        onError: _onSensorError,
      );

      _gyroSub = _gyroStreamFactory().listen(
        _onGyroscopeEvent,
        onError: _onSensorError,
      );
    } catch (e) {
      // Permission denied or hardware unavailable on iOS.
      throw ImuUnavailableException(
        _isIOS
            ? 'Motion sensor permission denied or hardware unavailable'
            : 'IMU hardware unavailable: $e',
      );
    }

    // Start rate monitoring timer.
    _rateCheckTimer = Timer.periodic(_rateCheckInterval, (_) {
      _checkRate();
    });

    return _imuController.stream;
  }

  @override
  Future<void> stopStreaming() async {
    _rateCheckTimer?.cancel();
    _rateCheckTimer = null;

    await _accelSub?.cancel();
    _accelSub = null;

    await _gyroSub?.cancel();
    _gyroSub = null;

    // Reset pairing state.
    _latestAccel = null;
    _latestAccelTime = null;
    _latestGyro = null;
    _latestGyroTime = null;

    // Reset rate monitoring state.
    _sampleTimestamps.clear();
    _isDegraded = false;
  }

  @override
  Stream<ImuDegradedWarning> get warnings => _warningController.stream;

  /// Disposes all resources. Call when the service is no longer needed.
  void dispose() {
    _rateCheckTimer?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _imuController.close();
    _warningController.close();
  }

  // ---------------------------------------------------------------------------
  // Private methods
  // ---------------------------------------------------------------------------

  void _onAccelerometerEvent(AccelerometerEvent event) {
    _latestAccel = event;
    _latestAccelTime = event.timestamp;
    _tryPair();
  }

  void _onGyroscopeEvent(GyroscopeEvent event) {
    _latestGyro = event;
    _latestGyroTime = event.timestamp;
    _tryPair();
  }

  /// Attempts to pair the latest accelerometer and gyroscope events.
  ///
  /// Emits an [ImuData] when both are fresh (timestamps within [_maxPairDeltaMs]).
  void _tryPair() {
    if (_latestAccel == null || _latestGyro == null) return;
    if (_latestAccelTime == null || _latestGyroTime == null) return;

    final delta =
        _latestAccelTime!.difference(_latestGyroTime!).inMilliseconds.abs();

    if (delta <= _maxPairDeltaMs) {
      final now = _latestAccelTime!.isAfter(_latestGyroTime!)
          ? _latestAccelTime!
          : _latestGyroTime!;

      // Apply coordinate transform.
      final transformed = _applyCoordinateTransform(
        _latestAccel!,
        _latestGyro!,
      );

      _imuController.add(ImuData(
        ax: transformed.ax,
        ay: transformed.ay,
        az: transformed.az,
        gx: transformed.gx,
        gy: transformed.gy,
        gz: transformed.gz,
        timestamp: now,
      ));

      // Record timestamp for rate monitoring.
      _sampleTimestamps.add(now);

      // Clear paired events so they aren't reused.
      _latestAccel = null;
      _latestAccelTime = null;
      _latestGyro = null;
      _latestGyroTime = null;
    }
  }

  /// Applies the platform-specific coordinate transform.
  ///
  /// sensors_plus convention:
  ///   - X = right side of device
  ///   - Y = top of device (forward in portrait)
  ///   - Z = out of screen (up when face-up)
  ///
  /// Body frame convention (matching DeadReckoningFilter):
  ///   - X = right
  ///   - Y = forward (top of device)
  ///   - Z = up (out of screen)
  ///
  /// For both iOS and Android with sensors_plus, the mapping is identity.
  /// This method exists as a configurable extension point for testability
  /// and future platform-specific adjustments.
  _TransformedImu _applyCoordinateTransform(
    AccelerometerEvent accel,
    GyroscopeEvent gyro,
  ) {
    if (_isIOS) {
      return _transformIOS(accel, gyro);
    } else {
      return _transformAndroid(accel, gyro);
    }
  }

  /// iOS coordinate transform (identity — sensors_plus already normalizes).
  _TransformedImu _transformIOS(
    AccelerometerEvent accel,
    GyroscopeEvent gyro,
  ) {
    return _TransformedImu(
      ax: accel.x,
      ay: accel.y,
      az: accel.z,
      gx: gyro.x,
      gy: gyro.y,
      gz: gyro.z,
    );
  }

  /// Android coordinate transform (identity — sensors_plus already normalizes).
  _TransformedImu _transformAndroid(
    AccelerometerEvent accel,
    GyroscopeEvent gyro,
  ) {
    return _TransformedImu(
      ax: accel.x,
      ay: accel.y,
      az: accel.z,
      gx: gyro.x,
      gy: gyro.y,
      gz: gyro.z,
    );
  }

  /// Checks the sample rate over the sliding window and emits warnings.
  void _checkRate() {
    final now = clock.now();
    final windowStart = now.subtract(_rateWindowDuration);

    // Remove timestamps outside the sliding window.
    _sampleTimestamps.removeWhere((t) => t.isBefore(windowStart));

    if (_sampleTimestamps.isEmpty) {
      // No samples in the window — can't compute rate yet.
      return;
    }

    // Calculate average rate over the window.
    // Rate = number of samples / window duration in seconds.
    final windowDurationSec = _rateWindowDuration.inMilliseconds / 1000.0;
    final measuredRate = _sampleTimestamps.length / windowDurationSec;

    if (measuredRate < _minAcceptableRateHz) {
      if (!_isDegraded) {
        _isDegraded = true;
        _warningController.add(ImuDegradedWarning(
          measuredRateHz: measuredRate,
          timestamp: now,
        ));
      }
    } else {
      // Rate recovered — reset degraded flag so future drops trigger a new warning.
      _isDegraded = false;
    }
  }

  /// Handles sensor stream errors (e.g., permission revoked mid-session).
  void _onSensorError(Object error) {
    if (_isIOS) {
      _imuController.addError(ImuUnavailableException(
        'Motion sensor permission denied or revoked: $error',
      ));
    } else {
      _imuController.addError(ImuUnavailableException(
        'IMU sensor error: $error',
      ));
    }
  }

  /// Returns true if running on iOS.
  bool get _isIOS {
    try {
      return Platform.isIOS;
    } catch (_) {
      // Platform not available (e.g., in tests without dart:io).
      return false;
    }
  }
}

/// Internal helper class for transformed IMU values.
class _TransformedImu {
  final double ax, ay, az;
  final double gx, gy, gz;

  const _TransformedImu({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });
}
